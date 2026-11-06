// Prepares generated, uncommitted inputs of the site:
// - public/pyodide/: Pyodide core copied from node_modules, plus the few package
//   wheels lessons and tests need, fetched once from the Pyodide CDN and checked
//   against the SHA-256 in pyodide-lock.json. The trimmed lock lists only those.
// - content/: courses and the app's lesson checker, read from ../Pythilo.
// - public/pyodide/python-worker.mjs: the Python worker, bundled as a module.
// `--content-only` skips copying and fetching (for tests and type checks).
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = join(dirname(fileURLToPath(import.meta.url)), '..');
const repository = join(site, '..');
const contentOnly = process.argv.includes('--content-only');
const pyodideModule = join(site, 'node_modules', 'pyodide');
const publicPyodide = join(site, 'public', 'pyodide');
const content = join(site, 'content');
const coursesDirectory = join(repository, 'Pythilo', 'Resources', 'Courses');
const checkerFile = join(repository, 'Pythilo', 'PythonRuntime', 'pythilo_runtime', 'lessons.py');
// Lessons import numpy; `test` runs pytest. pyflakes is used by `check` when Pyodide ships it.
const WANTED = ['numpy', 'pytest', 'pyflakes', 'pydantic', 'fastapi', 'httpx'];
const CORE = ['pyodide.mjs', 'pyodide.asm.mjs', 'pyodide.asm.wasm', 'python_stdlib.zip'];

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const version = JSON.parse(readFileSync(join(pyodideModule, 'package.json'), 'utf8')).version;
const lock = JSON.parse(readFileSync(join(pyodideModule, 'pyodide-lock.json'), 'utf8'));
// This Pyodide release names the wheel pydantic-core but spells its dependency
// pydantic_core. Normalize that spelling without changing wheel hashes.
for (const item of Object.values(lock.packages)) {
  item.depends = item.depends.map(name => lock.packages[name] ? name :
    lock.packages[name.replaceAll('_', '-')] ? name.replaceAll('_', '-') : name);
}
mkdirSync(content, { recursive: true });

function closure(names) {
  const seen = new Set(), stack = names.filter(name => lock.packages[name]);
  while (stack.length) {
    const name = stack.pop();
    if (seen.has(name)) continue;
    seen.add(name); stack.push(...lock.packages[name].depends);
  }
  return [...seen].sort();
}

async function fetchWheel(file, expected) {
  const target = join(publicPyodide, file);
  if (existsSync(target) && sha256(readFileSync(target)) === expected) return true;
  const url = `https://cdn.jsdelivr.net/pyodide/v${version}/full/${file}`;
  try {
    const response = await fetch(url, { redirect: 'error' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (sha256(bytes) !== expected) throw new Error('SHA-256 mismatch');
    writeFileSync(target, bytes);
    return true;
  } catch (error) {
    console.warn(`Could not fetch ${file} (${error.message}). Lessons that need it will say so.`);
    return false;
  }
}

// Self-hosted packages, from the trimmed lock written by a full run.
let hosted = [];
if (!contentOnly) {
  mkdirSync(publicPyodide, { recursive: true });
  for (const file of CORE) {
    const from = join(pyodideModule, file), to = join(publicPyodide, file);
    if (!existsSync(to) || statSync(to).size !== statSync(from).size || sha256(readFileSync(to)) !== sha256(readFileSync(from))) copyFileSync(from, to);
  }
  const wanted = closure(WANTED);
  for (const name of wanted) if (await fetchWheel(lock.packages[name].file_name, lock.packages[name].sha256)) hosted.push(name);
  // A package is usable only with everything it depends on.
  hosted = hosted.filter(name => closure([name]).every(dependency => hosted.includes(dependency)));
  const keep = new Set([...CORE, 'pyodide-lock.json', 'python-worker.mjs', ...hosted.map(name => lock.packages[name].file_name)]);
  for (const file of readdirSync(publicPyodide)) if (!keep.has(file)) rmSync(join(publicPyodide, file), { recursive: true, force: true });
  writeFileSync(join(publicPyodide, 'pyodide-lock.json'), JSON.stringify({ ...lock, packages: Object.fromEntries(hosted.map(name => [name, lock.packages[name]])) }));
} else if (existsSync(join(publicPyodide, 'pyodide-lock.json'))) {
  hosted = Object.keys(JSON.parse(readFileSync(join(publicPyodide, 'pyodide-lock.json'), 'utf8')).packages);
} else hosted = closure(WANTED);

// The standard library of this exact Pyodide build, cached per version.
const runtimeFile = join(content, 'runtime.json');
let stdlib;
try {
  const cached = JSON.parse(readFileSync(runtimeFile, 'utf8'));
  if (cached.pyodide === version && Array.isArray(cached.stdlib)) stdlib = cached.stdlib;
} catch {}
if (!stdlib) {
  const { loadPyodide } = await import(join(pyodideModule, 'pyodide.mjs'));
  const pyodide = await loadPyodide({ indexURL: pyodideModule + '/' });
  stdlib = JSON.parse(pyodide.runPython('import json, sys; json.dumps(sorted(sys.stdlib_module_names))'));
}
const packages = Object.fromEntries(hosted.map(name => [name, lock.packages[name].version]));
const importable = new Set([...stdlib, ...hosted.flatMap(name => lock.packages[name].imports)]);
// The package catalog is cached for a day. Its URL must change when wheels are
// added, even when the Pyodide version itself stays the same.
const lockBytes = existsSync(join(publicPyodide, 'pyodide-lock.json'))
  ? readFileSync(join(publicPyodide, 'pyodide-lock.json'))
  : JSON.stringify({ ...lock, packages: Object.fromEntries(hosted.map(name => [name, lock.packages[name]])) });
const lockFile = `/pyodide/pyodide-lock.json?v=${sha256(lockBytes).slice(0, 16)}`;
writeFileSync(runtimeFile, JSON.stringify({ pyodide: version, python: lock.info.python, lockFile, packages, imports: hosted.flatMap(name => lock.packages[name].imports).sort(), checker: hosted.includes('pyflakes') ? 'pyflakes' : 'compile', stdlib }, null, 1) + '\n');

// Top-level names a lesson imports, from its starter, solution and checks.
function imports(text) {
  const names = new Set();
  for (const line of text.split('\n')) {
    const from = line.match(/^\s*from\s+([A-Za-z_]\w*)[\w.]*\s+import\b/);
    if (from) { names.add(from[1]); continue; }
    const plain = line.match(/^\s*import\s+(.+)$/);
    if (plain) for (const part of plain[1].split(',')) { const name = part.trim().match(/^([A-Za-z_]\w*)/); if (name) names.add(name[1]); }
  }
  return [...names].sort();
}

// `# Title`, then the part before the first `## ` is the idea; each `## ` is a section.
function sections(body, title) {
  const lines = body.replace(/\r\n/g, '\n').split('\n');
  if (/^# /.test(lines[0] ?? '')) lines.shift();
  const result = [{ title, chip: 'Idea', markdown: [] }];
  for (const line of lines) {
    const heading = line.match(/^## (.+)$/);
    if (heading) result.push({ title: heading[1].trim(), chip: heading[1].trim(), markdown: [] });
    else result.at(-1).markdown.push(line);
  }
  return result.map(section => ({ ...section, markdown: section.markdown.join('\n').trim() })).filter((section, index) => index === 0 || section.markdown);
}

if (!existsSync(coursesDirectory)) throw new Error(`Course files not found in ${coursesDirectory}.`);
const courses = readdirSync(coursesDirectory).filter(file => /^\d+-.+\.json$/.test(file)).sort((a, b) => parseInt(a) - parseInt(b)).map(file => {
  const course = JSON.parse(readFileSync(join(coursesDirectory, file), 'utf8'));
  for (const field of ['id', 'title', 'summary', 'kind']) if (typeof course[field] !== 'string') throw new Error(`${file}: missing ${field}.`);
  return { id: course.id, title: course.title, summary: course.summary, kind: course.kind, order: parseInt(file), lessons: course.lessons.map(lesson => {
    for (const field of ['id', 'title', 'body', 'task', 'starter', 'solution']) if (typeof lesson[field] !== 'string') throw new Error(`${file}/${lesson.id}: missing ${field}.`);
    const source = [lesson.starter, lesson.solution, ...lesson.checks.map(check => check.code)].join('\n');
    const used = imports(source);
    // Pyodide imports threading but cannot start a thread, so those lessons run only in the app.
    const threads = /\b(threading|concurrent\.futures|to_thread|ThreadPoolExecutor)\b/.test(source) ? ['threads'] : [];
    return {
      id: lesson.id, title: lesson.title, ...(lesson.level ? { level: lesson.level } : {}), ...(lesson.minutes ? { minutes: lesson.minutes } : {}),
      sections: sections(lesson.body, lesson.title), task: lesson.task, starter: lesson.starter, solution: lesson.solution,
      checks: lesson.checks.map(check => ({ name: check.name, code: check.code })), hints: lesson.hints ?? [], explanation: lesson.explanation ?? '',
      imports: used, packages: used.filter(name => hosted.some(item => lock.packages[item].imports.includes(name))), missing: [...used.filter(name => !importable.has(name)), ...threads],
    };
  }) };
});
writeFileSync(join(content, 'courses.json'), JSON.stringify({ pyodide: version, python: lock.info.python, courses }) + '\n');
const checker = readFileSync(checkerFile, 'utf8');
writeFileSync(join(content, 'lessons-checker.json'), JSON.stringify({ source: checker, sha256: sha256(checker) }) + '\n');

// The new browser labs use the exact tracing engine and files bundled by iOS.
const labRoot = join(repository, 'Pythilo', 'PythonRuntime', 'pythilo_runtime');
const labCatalog = JSON.parse(readFileSync(join(labRoot, 'labcode', 'catalog-expansion.json'), 'utf8'));
writeFileSync(join(content, 'labs.json'), JSON.stringify({
  labs: labCatalog.map(lab => ({ ...lab,
    starter: readFileSync(join(labRoot, 'labcode', `${lab.id}.practice.starter.py`), 'utf8'),
    answer: readFileSync(join(labRoot, 'labcode', `${lab.id}.practice.answer.py`), 'utf8'),
  })),
  sources: Object.fromEntries(['labs_engine.py', 'labs_extended.py', 'labs_intelligence.py', 'labs_senior.py', 'labs_projects.py'].map(file => [file, readFileSync(join(labRoot, file), 'utf8')])),
}) + '\n');

// Pyodide runs only in a module worker, and the app's bundler starts workers as
// classic scripts. The worker is therefore bundled here, beside Pyodide.
const workerFile = join(content, 'worker.json');
if (!contentOnly) {
  const { build } = await import('esbuild');
  const result = await build({ entryPoints: [join(site, 'workers', 'python.worker.ts')], bundle: true, format: 'esm', target: 'es2022', minify: true, write: false, outfile: 'python-worker.mjs', logLevel: 'error' });
  const bytes = result.outputFiles[0].contents;
  writeFileSync(join(publicPyodide, 'python-worker.mjs'), bytes);
  writeFileSync(workerFile, JSON.stringify({ url: `/pyodide/python-worker.mjs?v=${sha256(bytes).slice(0, 12)}` }) + '\n');
} else if (!existsSync(workerFile)) writeFileSync(workerFile, JSON.stringify({ url: '/pyodide/python-worker.mjs' }) + '\n');
console.log(`Pyodide ${version} · Python ${lock.info.python} · packages ${hosted.join(', ') || 'none'} · ${courses.length} courses, ${courses.reduce((n, course) => n + course.lessons.length, 0)} lessons${contentOnly ? ' (content only)' : ''}`);
