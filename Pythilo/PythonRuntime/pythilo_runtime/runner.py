"""Runs one job at a time and puts the interpreter back afterwards.

All jobs share one interpreter, because iOS gives an app one process and native
extensions cannot be unloaded. Isolation between runs is therefore a clean-up,
not a boundary: it stops one project's modules, paths and settings from leaking
into the next run, but it is not a sandbox and is never described as one.
"""

import atexit
import gc
import logging
import os
import signal
import sys
import threading
import time
import traceback
import types
import warnings
from importlib.machinery import ExtensionFileLoader

from . import emit_json, lanes, streams

_baseline_modules = set()
# The analysis thread can be inside these during a reset, whatever a run did.
_editor_tools = {"pythilo_runtime", "pyflakes", "jedi", "parso"}
_stdlib_root = ""
_baseline_path = []
_baseline_environment = {}
_baseline_filters = []
_baseline_cwd = ""
_process_register = atexit.register
_process_unregister = atexit.unregister
# lane -> (project root, callbacks registered by that job's own code)
_job_exits = {}


def capture_baseline():
    global _baseline_modules, _stdlib_root, _baseline_path, _baseline_environment, _baseline_filters, _baseline_cwd
    from . import analysis, debugger, labs, lessons, notebook, packages, shell  # noqa: F401

    _stdlib_root = os.path.dirname(os.__file__)
    _baseline_modules = set(sys.modules)
    _baseline_path = list(sys.path)
    _baseline_environment = dict(os.environ)
    _baseline_filters = list(warnings.filters)
    _baseline_cwd = os.getcwd()


def _origin(module):
    spec = getattr(module, "__spec__", None)
    return getattr(spec, "origin", None) or getattr(module, "__file__", None)


def _sticky_packages():
    """Packages holding a native extension. Those cannot be imported twice."""
    sticky = set()
    for name, module in list(sys.modules.items()):
        loader = getattr(getattr(module, "__spec__", None), "loader", None)
        if isinstance(loader, ExtensionFileLoader):
            sticky.add(name.partition(".")[0])
    return sticky


def _purge_modules(only=None):
    """Forgets modules a run imported, so the next run reads the files again.

    `only` limits it to those names: while another tab's program runs, a job removes
    just what its own lane imported and leaves the other program's modules alone.
    """
    sticky = _sticky_packages()
    purged = []
    for name, module in list(sys.modules.items()):
        if only is not None and name not in only:
            continue
        top = name.partition(".")[0]
        if name in _baseline_modules or top in sticky or top in _editor_tools:
            continue
        origin = _origin(module)
        if origin in ("built-in", "frozen"):
            continue
        if isinstance(origin, str) and origin.startswith(_stdlib_root) and "site-packages" not in origin:
            continue
        del sys.modules[name]
        purged.append(name)
    lanes.forget_imports(purged)


def _leftover_threads(lane=0):
    current = threading.current_thread()
    # A dummy thread stands for a native thread the app started, such as another
    # lane, not one the program left running. Threads belong to the lane that started them.
    return [
        thread.name
        for thread in threading.enumerate()
        if thread is not current
        and thread is not threading.main_thread()
        and thread.is_alive()
        and not isinstance(thread, threading._DummyThread)
        and getattr(thread, "_pythilo_lane", 0) == lane
    ]


def _owns_exit_registration(frame, root):
    # The immediate registration site owns the callback. In particular,
    # weakref.finalize registers its PROCESS exit hook from the stdlib; running
    # that hook after a job destroys live PyTorch operator registrations.
    origin = frame.f_globals.get("__file__") or frame.f_code.co_filename
    if origin.startswith("<frozen "):
        return False
    if not os.path.isabs(origin):
        return True  # REPL, notebook and lab source use virtual filenames.
    try:
        return os.path.commonpath((os.path.realpath(origin), root)) == root
    except ValueError:
        return False


def _register_job_exit(callback, *args, **kwargs):
    if not callable(callback):
        raise TypeError("the first argument must be callable")
    entry = _job_exits.get(lanes.current_lane())
    if entry is not None and _owns_exit_registration(sys._getframe(1), entry[0]):
        entry[1].append((callback, args, kwargs))
        return callback
    return _process_register(callback, *args, **kwargs)


def _unregister_job_exit(callback):
    entry = _job_exits.get(lanes.current_lane())
    if entry is not None:
        entry[1][:] = [item for item in entry[1] if item[0] != callback]
    _process_unregister(callback)


def _begin_exit_handlers(job, lane=0):
    root = job.get("root") or os.path.dirname(job.get("path") or "") or os.getcwd()
    _job_exits[lane] = (os.path.realpath(root), [])
    atexit.register = _register_job_exit
    atexit.unregister = _unregister_job_exit


def _run_exit_handlers(lane=0):
    entry = _job_exits.get(lane)
    try:
        # Only callbacks registered by the running project's code belong to
        # its lifetime. Imported bundled libraries retain process callbacks.
        for callback, args, kwargs in reversed((entry[1] if entry else [])[:]):
            try:
                callback(*args, **kwargs)
            except BaseException as error:
                print_exception(error)
    finally:
        _job_exits.pop(lane, None)
        if not _job_exits:
            atexit.register = _process_register
            atexit.unregister = _process_unregister


def restore_interpreter(record=None):
    """Undo what a run changed, except for files, which belong to the user.

    While another lane's program is still running, the process-wide state it relies
    on (folder, environment, sys.path, logging, signals) stays as it is; only the
    modules this job imported are forgotten. The last job to end resets everything.
    """
    sys.settrace(None)
    sys.setprofile(None)
    if record is not None and lanes.others_running(record.lane):
        if "asyncio" in sys.modules:
            try:
                sys.modules["asyncio"].set_event_loop(None)
            except Exception:
                pass
        _purge_modules(only=lanes.owned_new_modules(record.lane, record.modules))
        return
    threading.settrace(None)
    threading.setprofile(None)
    streams.reset()
    logging.shutdown()
    logging.root.handlers.clear()
    logging.root.setLevel(logging.WARNING)
    logging.Logger.manager.loggerDict.clear()
    warnings.filters[:] = _baseline_filters
    sys.path[:] = _baseline_path
    sys.argv[:] = [""]
    sys.modules.pop("__main__", None)
    sys.modules["__main__"] = types.ModuleType("__main__")
    os.environ.clear()
    os.environ.update(_baseline_environment)
    os.chdir(_baseline_cwd)
    if threading.current_thread() is threading.main_thread():
        signal.signal(signal.SIGINT, signal.default_int_handler)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
    if "asyncio" in sys.modules:
        try:
            sys.modules["asyncio"].set_event_loop(None)
        except Exception:
            pass
    _purge_modules()
    gc.collect()


def describe_exception(error):
    frames = []
    for frame in traceback.extract_tb(error.__traceback__):
        if "/pythilo_runtime/" in frame.filename:
            continue
        frames.append({"file": frame.filename, "line": frame.lineno or 0, "name": frame.name})
    line = 0
    file = None
    if isinstance(error, SyntaxError):
        file = error.filename
        line = error.lineno or 0
    elif frames:
        file = frames[-1]["file"]
        line = frames[-1]["line"]
    return {
        "type": type(error).__name__,
        "message": str(error),
        "file": file,
        "line": line,
        "frames": frames,
    }


def print_exception(error):
    """Print a traceback without the runtime's own frames."""
    tb = error.__traceback__
    while tb is not None and "/pythilo_runtime/" in tb.tb_frame.f_code.co_filename:
        tb = tb.tb_next
    traceback.print_exception(type(error), error, tb, file=sys.stderr)


def exit_code(error):
    code = error.code
    if code is None:
        return 0
    if isinstance(code, int):
        return code
    print(code, file=sys.stderr)
    return 1


def project_environment(job):
    """Puts the project's own files and packages first on the import path."""
    root = job.get("root")

    def first(path):
        # Another tab's job may have put it there already.
        while path in sys.path:
            sys.path.remove(path)
        sys.path.insert(0, path)

    for package_path in reversed(job.get("packagePaths") or []):
        if os.path.isdir(package_path):
            first(package_path)
    if root:
        site = os.path.join(root, ".pythilo", "site-packages")
        if os.path.isdir(site):
            first(site)
    os.environ.update(job.get("env") or {})
    os.environ["PYTHILO_PROJECT"] = root or ""
    cwd = job.get("cwd") or root
    if cwd:
        os.chdir(cwd)


def run_job(job, lane=0):
    job_id = job.get("id", "")
    kind = job.get("kind")
    started = time.monotonic()
    outcome = {"id": job_id, "status": "finished", "code": 0, "error": None, "cwd": None, "lane": lane}
    record = lanes.begin(lane, job_id, job.get("root"))
    record.modules = set(sys.modules)
    emit_json("run_start", {"id": job_id, "kind": kind, "lane": lane})
    try:
        streams.stdin.discard_pending(lane)
        # A stop that arrived after the previous run ended must not end this one.
        time.sleep(0)
        project_environment(job)
        _begin_exit_handlers(job, lane)
        record.in_body = True
        try:
            outcome.update(_perform(job) or {})
        finally:
            record.in_body = False
    except KeyboardInterrupt:
        outcome.update(status="cancelled", code=130)
    except SystemExit as error:
        code = exit_code(error)
        outcome.update(status="finished" if code == 0 else "failed", code=code)
    except BaseException as error:
        print_exception(error)
        outcome.update(status="failed", code=1, error=describe_exception(error))
    finally:
        record.in_body = False
        lanes.shielded(_finish, record, outcome, started)


def _finish(record, outcome, started):
    lane = record.lane
    if lane:
        lanes.clear_pending()
    outcome["cwd"] = _current_directory()
    try:
        _run_exit_handlers(lane)
    except BaseException as error:
        print_exception(error)
    outcome["threads"] = _leftover_threads(lane)
    # Deciding and resetting happen under the lanes lock, so of two jobs ending at once
    # exactly the last one resets the interpreter, and no job starts halfway through.
    with lanes.serialized():
        try:
            restore_interpreter(record)
        except BaseException as error:
            print(f"Pythilo could not fully reset Python: {error}", file=sys.stderr)
            outcome["recovery"] = str(error)
        lanes.end(lane)
    outcome["duration"] = time.monotonic() - started
    emit_json("run_end", outcome)


def _current_directory():
    try:
        return os.getcwd()
    except OSError:
        return None


def _perform(job):
    kind = job.get("kind")
    if kind == "script":
        run_script(job["path"], job.get("args") or [])
    elif kind == "debug":
        from . import debugger

        debugger.run(job["path"], job.get("args") or [], job.get("breakpoints") or {})
    elif kind == "shell":
        from . import shell

        return shell.run_line(job["line"], job.get("root"))
    elif kind == "repl":
        from . import shell

        shell.repl()
    elif kind == "notebook":
        from . import notebook

        notebook.run_cell(job)
    elif kind == "lesson_check":
        from . import lessons

        lessons.check(job)
    elif kind == "lab_trace":
        from . import labs

        labs.trace_sort(job)
    elif kind == "lab_measure":
        from . import labs

        labs.scale_sort(job)
    elif kind in ("lab_graph_trace", "lab_graph_measure"):
        from . import labs_graph

        (labs_graph.trace if kind == "lab_graph_trace" else labs_graph.scale)(job)
    elif kind in ("lab_hash", "lab_hash_scale"):
        from . import labs_hashing

        (labs_hashing.run if kind == "lab_hash" else labs_hashing.scale)(job)
    elif kind in ("lab_dp_trace", "lab_dp_measure"):
        from . import labs_dp

        (labs_dp.trace if kind == "lab_dp_trace" else labs_dp.scale)(job)
    elif kind in ("lab_run", "lab_scale"):
        from . import labs_engine

        (labs_engine.run if kind == "lab_run" else labs_engine.run_scale)(job)
    elif kind == "notebook_reset":
        from . import notebook

        notebook.reset(job.get("path"))
    else:
        raise ValueError(f"Unknown job kind: {kind}")
    return None


def main_module_for(path):
    module = types.ModuleType("__main__")
    module.__file__ = path
    module.__builtins__ = __builtins__
    module.__cached__ = None
    sys.modules["__main__"] = module
    return module


def prepare_script(path, args):
    path = os.path.abspath(path)
    with open(path, "rb") as handle:
        source = handle.read()
    code = compile(source, path, "exec", dont_inherit=True)
    sys.argv[:] = [path, *args]
    sys.path.insert(0, os.path.dirname(path))
    return code, main_module_for(path)


def run_script(path, args):
    code, module = prepare_script(path, args)
    exec(code, module.__dict__)

