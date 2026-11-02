#!/usr/bin/env python3
"""Checks every course in Pythilo/Resources/Courses against its lesson contract.

Each lesson's starter and solution run in their own python3 subprocess, in their
own temporary directory, with a 10 second timeout. The source runs once in a
fresh namespace with stdout captured, then each check runs in that namespace with
the captured text in `_stdout`.

Nothing is installed. A lesson that imports a module python3 cannot find here is
reported as skipped and counted apart from the lessons that really ran. To run
those too, put a python3 that has them first on PATH.
"""

import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COURSES_DIR = ROOT / "Pythilo" / "Resources" / "Courses"
TIMEOUT_SECONDS = 10

# File stem -> (course id, kind, number of lessons)
EXPECTED_COURSES = {
    "1-foundations": ("foundations", "path", 10),
    "2-deeper": ("deeper", "path", 9),
    "3-tools": ("tools", "path", 5),
    "4-web": ("web", "path", 5),
    "5-data": ("data", "path", 4),
    "6-ai": ("ai", "path", 3),
    "7-interview": ("interview", "interview", 20),
}
INTERVIEW_LEVELS = {"Easy": 7, "Medium": 9, "Hard": 4}
REQUIRED_TEXT_FIELDS = ("id", "title", "body", "task", "starter", "solution", "explanation")
ALLOWED_LESSON_FIELDS = set(REQUIRED_TEXT_FIELDS) | {"level", "minutes", "checks", "hints"}
FORBIDDEN_IMPORTS = {"multiprocessing", "socket", "subprocess"}
BODY_WORDS = (60, 180)
BODY_CODE_BLOCKS = (1, 2)
BODY_CODE_WIDTH = 44

FORBIDDEN_WORDS = re.compile(r"\b(rust|crabrix)\b", re.IGNORECASE)
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")
INLINE_CODE = re.compile(r"`[^`\n]*`")
UNSUPPORTED_MARKDOWN = (
    (re.compile(r"^#{3,}\s"), "heading deeper than ##"),
    (re.compile(r"^\s*\d+[.)]\s"), "numbered list"),
    (re.compile(r"^\s*\+\s"), "+ bullet"),
    (re.compile(r"^\s*>"), "block quote"),
    (re.compile(r"^\s*\|"), "table"),
    (re.compile(r"^\s*(---+|===+)\s*$"), "horizontal rule"),
    (re.compile(r"^\s+-\s"), "nested bullet"),
    (re.compile(r"\*"), "asterisk outside inline code"),
    (re.compile(r"\[[^\]]*\]\([^)]*\)"), "link"),
    (re.compile(r"<[a-zA-Z/][^>]*>"), "raw HTML"),
)

HARNESS = r"""
import contextlib, io, json, sys, types

job_path, result_path = sys.argv[1:3]
with open(job_path, encoding="utf-8") as handle:
    job = json.load(handle)


def describe(error):
    text = str(error).strip().splitlines()
    detail = f": {text[0][:200]}" if text else ""
    return type(error).__name__ + detail


module = types.ModuleType("__main__")
sys.modules["__main__"] = module
namespace = module.__dict__
captured = io.StringIO()
result = {"file_error": None, "checks": []}
try:
    code = compile(job["source"], "<lesson>", "exec")
    with contextlib.redirect_stdout(captured):
        exec(code, namespace)
except BaseException as error:
    result["file_error"] = describe(error)

namespace["_stdout"] = captured.getvalue()
for check in job["checks"]:
    if result["file_error"] is not None:
        result["checks"].append({"name": check["name"], "error": "file did not run"})
        continue
    try:
        code = compile(check["code"], "<check>", "exec")
        with contextlib.redirect_stdout(io.StringIO()):
            exec(code, namespace)
        result["checks"].append({"name": check["name"], "error": None})
    except BaseException as error:
        result["checks"].append({"name": check["name"], "error": describe(error)})

with open(result_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle)
"""

PROBE = """
import importlib.util, json, sys
names = json.loads(sys.argv[1])
missing = [
    name for name in names
    if name not in sys.stdlib_module_names and importlib.util.find_spec(name) is None
]
print(json.dumps(missing))
"""


def is_text(value):
    return isinstance(value, str) and value.strip() != ""


def compile_strict(source, label):
    """Returns an error message, or None. SyntaxWarnings count as errors."""
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            compile(source, label, "exec")
    except (SyntaxError, ValueError, Warning) as error:
        return f"{type(error).__name__}: {error}"
    return None


def parse_or_none(source):
    try:
        return ast.parse(source)
    except (SyntaxError, ValueError):
        return None


def imported_modules(source):
    tree = parse_or_none(source)
    names = set()
    if tree is None:
        return names
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name.partition(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.add(node.module.partition(".")[0])
    return names


def lesson_sources(lesson):
    sources = [lesson.get("starter"), lesson.get("solution")]
    for check in lesson.get("checks") or []:
        if isinstance(check, dict):
            sources.append(check.get("code"))
    return [source for source in sources if isinstance(source, str)]


def markdown_problems(text):
    problems = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            if in_fence:
                if line.strip() != "```":
                    problems.append(f"bad closing fence {line!r}")
                in_fence = False
            else:
                if line.strip() != "```python":
                    problems.append(f"fence must be ```python, got {line!r}")
                in_fence = True
            continue
        if in_fence:
            continue
        plain = INLINE_CODE.sub("", line)
        for pattern, label in UNSUPPORTED_MARKDOWN:
            if pattern.search(plain):
                problems.append(f"{label} in {line.strip()[:40]!r}")
    if in_fence:
        problems.append("unclosed code fence")
    return problems


def body_stats(body):
    prose = []
    blocks = []
    current = None
    for line in body.splitlines():
        if line.startswith("```"):
            if current is None:
                current = []
            else:
                blocks.append(current)
                current = None
        elif current is not None:
            current.append(line)
        else:
            prose.append(line)
    words = [word for word in " ".join(prose).split() if word not in ("#", "##", "-")]
    return len(words), blocks


def static_problems(lesson, kind):
    """Everything that can be judged without running code."""
    problems = []
    notes = []
    for field in REQUIRED_TEXT_FIELDS:
        if not is_text(lesson.get(field)):
            problems.append(f"missing or empty field '{field}'")
    unknown = set(lesson) - ALLOWED_LESSON_FIELDS
    if unknown:
        problems.append(f"unknown fields {sorted(unknown)}")

    if kind == "interview":
        if lesson.get("level") not in INTERVIEW_LEVELS:
            problems.append(f"bad level {lesson.get('level')!r}")
        minutes = lesson.get("minutes")
        if not isinstance(minutes, int) or isinstance(minutes, bool) or minutes <= 0:
            problems.append(f"bad minutes {minutes!r}")
    else:
        for field in ("level", "minutes"):
            if field in lesson:
                problems.append(f"'{field}' is for interview lessons only")

    checks = lesson.get("checks")
    if not isinstance(checks, list) or not 3 <= len(checks) <= 6:
        problems.append("needs 3 to 6 checks")
        checks = checks if isinstance(checks, list) else []
    for index, check in enumerate(checks):
        if not isinstance(check, dict) or not is_text(check.get("name")) or not is_text(check.get("code")):
            problems.append(f"check {index + 1} needs a name and code")
            continue
        error = compile_strict(check["code"], "<check>")
        if error:
            problems.append(f"check '{check['name']}' does not compile: {error}")
            continue
        tree = ast.parse(check["code"])
        if not any(isinstance(node, ast.Assert) for node in ast.walk(tree)):
            problems.append(f"check '{check['name']}' has no assert")
        if imported_modules(check["code"]) & {"time", "datetime"}:
            problems.append(f"check '{check['name']}' depends on the clock")

    hints = lesson.get("hints")
    if not isinstance(hints, list) or len(hints) != 3 or not all(is_text(hint) for hint in hints):
        problems.append("needs exactly 3 hints")

    for field in ("starter", "solution"):
        source = lesson.get(field)
        if not isinstance(source, str):
            continue
        error = compile_strict(source, f"<{field}>")
        if error:
            problems.append(f"{field} does not compile: {error}")
    if lesson.get("starter") == lesson.get("solution"):
        problems.append("starter and solution are identical")

    for source in lesson_sources(lesson):
        tree = parse_or_none(source)
        if tree is None:
            continue
        banned = imported_modules(source) & FORBIDDEN_IMPORTS
        if banned:
            problems.append(f"imports {sorted(banned)}, unavailable on iOS")
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "input":
                problems.append("uses input()")
                break

    if is_text(lesson.get("body")):
        words, blocks = body_stats(lesson["body"])
        if not BODY_WORDS[0] <= words <= BODY_WORDS[1]:
            problems.append(f"body has {words} words, wants {BODY_WORDS[0]} to {BODY_WORDS[1]}")
        if not BODY_CODE_BLOCKS[0] <= len(blocks) <= BODY_CODE_BLOCKS[1]:
            problems.append(f"body has {len(blocks)} code blocks, wants 1 or 2")
        for block in blocks:
            for line in block:
                if len(line) > BODY_CODE_WIDTH:
                    notes.append(f"body code line over {BODY_CODE_WIDTH} chars: {line.strip()!r}")
    for field in ("body", "explanation"):
        if is_text(lesson.get(field)):
            for problem in markdown_problems(lesson[field]):
                problems.append(f"{field}: {problem}")

    everything = json.dumps(lesson, ensure_ascii=False)
    if FORBIDDEN_WORDS.search(everything):
        problems.append("mentions a forbidden word")
    if EMOJI.search(everything):
        problems.append("contains an emoji")
    return problems, notes


def run_source(python, source, checks):
    """Runs one file and its checks. Returns (file_error, check results) or raises."""
    root = Path(tempfile.mkdtemp(prefix="pythilo-lesson-"))
    try:
        work = root / "work"
        work.mkdir()
        job_path = root / "job.json"
        result_path = root / "result.json"
        job_path.write_text(json.dumps({"source": source, "checks": checks}), encoding="utf-8")
        environment = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUTF8": "1"}
        completed = subprocess.run(
            [python, "-P", "-c", HARNESS, str(job_path), str(result_path)],
            cwd=work,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT_SECONDS,
        )
        if not result_path.exists():
            detail = completed.stderr.decode("utf-8", "replace").strip().splitlines()
            raise RuntimeError(f"no result, exit {completed.returncode}: {detail[-1] if detail else ''}")
        result = json.loads(result_path.read_text(encoding="utf-8"))
        return result["file_error"], result["checks"]
    finally:
        shutil.rmtree(root, ignore_errors=True)


def runtime_problems(python, lesson):
    problems = []
    checks = lesson["checks"]

    try:
        file_error, results = run_source(python, lesson["solution"], checks)
    except subprocess.TimeoutExpired:
        problems.append(f"solution timed out after {TIMEOUT_SECONDS}s")
    except RuntimeError as error:
        problems.append(f"solution crashed: {error}")
    else:
        if file_error:
            problems.append(f"solution raised at top level: {file_error}")
        else:
            for item in results:
                if item["error"]:
                    problems.append(f"solution fails check '{item['name']}': {item['error']}")

    try:
        file_error, results = run_source(python, lesson["starter"], checks)
    except subprocess.TimeoutExpired:
        problems.append(f"starter timed out after {TIMEOUT_SECONDS}s")
    except RuntimeError as error:
        problems.append(f"starter crashed: {error}")
    else:
        if file_error:
            problems.append(f"starter raised at top level: {file_error}")
        elif all(item["error"] is None for item in results):
            problems.append("starter passes every check")
    return problems


def missing_modules(python, names):
    completed = subprocess.run(
        [python, "-c", PROBE, json.dumps(sorted(names))],
        capture_output=True,
        text=True,
        check=True,
    )
    return set(json.loads(completed.stdout))


def main():
    python = shutil.which("python3")
    if python is None:
        print("FAIL python3 not found on PATH")
        print("Summary: 0 lessons, 0 verified, 0 skipped, 1 failures")
        return 1

    failures = []

    def fail(where, message):
        failures.append(message)
        print(f"FAIL {where}: {message}")

    courses = []
    for path in sorted(COURSES_DIR.glob("*.json")) if COURSES_DIR.is_dir() else []:
        expected = EXPECTED_COURSES.get(path.stem)
        if expected is None:
            fail(path.name, "unexpected course file")
            continue
        try:
            course = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            fail(path.name, f"cannot read JSON: {error}")
            continue
        if not isinstance(course, dict):
            fail(path.name, "top level is not an object")
            continue
        courses.append((path.stem, course))

    found = {stem for stem, _ in courses}
    for stem in EXPECTED_COURSES:
        if stem not in found and not (COURSES_DIR / f"{stem}.json").exists():
            fail(stem, "course file is missing")

    wanted_modules = set()
    for _, course in courses:
        for lesson in course.get("lessons") or []:
            if isinstance(lesson, dict):
                for source in lesson_sources(lesson):
                    wanted_modules |= imported_modules(source)
    absent = missing_modules(python, wanted_modules)

    seen_ids = {}
    verified = skipped = total = 0
    notes = []
    for stem, course in courses:
        course_id, kind, count = EXPECTED_COURSES[stem]
        if course.get("id") != course_id:
            fail(stem, f"id should be {course_id!r}")
        if course.get("kind") != kind:
            fail(stem, f"kind should be {kind!r}")
        for field in ("title", "summary"):
            if not is_text(course.get(field)):
                fail(stem, f"missing course field '{field}'")
        lessons = course.get("lessons")
        if not isinstance(lessons, list):
            fail(stem, "lessons is not a list")
            continue
        if len(lessons) != count:
            fail(stem, f"has {len(lessons)} lessons, wants {count}")
        if kind == "interview":
            for level, wanted in INTERVIEW_LEVELS.items():
                have = sum(1 for lesson in lessons if isinstance(lesson, dict) and lesson.get("level") == level)
                if have != wanted:
                    fail(stem, f"has {have} {level} lessons, wants {wanted}")

        for index, lesson in enumerate(lessons):
            total += 1
            where = f"{course_id}/{lesson.get('id', index) if isinstance(lesson, dict) else index}"
            if not isinstance(lesson, dict):
                fail(where, "lesson is not an object")
                continue
            before = len(failures)
            lesson_id = lesson.get("id")
            if lesson_id in seen_ids:
                fail(where, f"id already used in {seen_ids[lesson_id]}")
            else:
                seen_ids[lesson_id] = course_id

            problems, lesson_notes = static_problems(lesson, kind)
            notes += [f"note {where}: {note}" for note in lesson_notes]
            for problem in problems:
                fail(where, problem)
            if problems:
                continue

            need = sorted(set().union(*map(imported_modules, lesson_sources(lesson))) & absent)
            if need:
                skipped += 1
                print(f"SKIP {where}: skipped: {', '.join(need)} not installed here")
                continue

            for problem in runtime_problems(python, lesson):
                fail(where, problem)
            if len(failures) == before:
                verified += 1

    for note in notes:
        print(note)
    print(f"Summary: {total} lessons, {verified} verified, {skipped} skipped, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
