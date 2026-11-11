"""Several jobs at once: one per terminal tab, on lanes that share the interpreter.

Lane 0 is Python's main thread, where Run, the debugger, lessons and labs run. Lanes 1
to 3 are threads the app starts for terminal tabs, so a command can run while another
tab's program, such as a web server, keeps going.

Everything a program can change for the whole process is shared: the working folder,
the environment, sys.path and imported modules. This module keeps each job's output,
input, stop request, exit handlers and imported modules apart, so a job that ends
cleans up after itself without pulling the floor from under the others. Isolation is
still a clean-up, not a boundary.
"""

import signal
import sys
import threading
import time

import _pythilo

_lock = threading.RLock()
# lane -> the running job's record
_jobs = {}
# module name -> lane whose thread first imported it
_ledger = {}
_cancel = {lane: threading.Event() for lane in range(4)}
_real_sleep = time.sleep
_real_start = threading.Thread.start
_real_signal = signal.signal
_real_getsignal = signal.getsignal
# (lane, signal number) -> handler a lane's program installed
_lane_handlers = {}
_installed = False


class Job:
    __slots__ = ("lane", "id", "ident", "root", "modules", "path", "environ", "cwd", "argv", "main", "filters", "in_body")

    def __init__(self, lane, job_id, root):
        self.lane = lane
        self.id = job_id
        self.ident = threading.get_ident()
        self.root = root
        self.modules = set()
        self.path = []
        self.environ = {}
        self.cwd = ""
        self.argv = []
        self.main = None
        self.filters = []
        self.in_body = False


def current_lane():
    """The lane whose job started the calling thread. 0 for the main thread's jobs."""
    return getattr(threading.current_thread(), "_pythilo_lane", 0)


def begin(lane, job_id, root):
    record = Job(lane, job_id, root)
    with _lock:
        _jobs[lane] = record
        _cancel[lane].clear()
    if lane:
        threading.current_thread()._pythilo_lane = lane
    return record


def end(lane):
    with _lock:
        _jobs.pop(lane, None)
        for key in [key for key in _lane_handlers if key[0] == lane]:
            del _lane_handlers[key]


def serialized():
    return _lock


def others_running(lane):
    with _lock:
        return any(other != lane for other in _jobs)


def running_roots(except_lane):
    with _lock:
        return [job.root for other, job in _jobs.items() if other != except_lane and job.root]


def imported_by(lane):
    with _lock:
        return {name for name, owner in _ledger.items() if owner == lane}


def owned_new_modules(lane, before):
    """Modules imported since `before` that no other lane imported.

    An import hook placed ahead of the ledger (pytest's assertion rewriting does
    this) leaves a module unrecorded; such a module belongs to the job that ends.
    """
    with _lock:
        return {name for name in set(sys.modules) - before if _ledger.get(name, lane) == lane}


def forget_imports(names):
    with _lock:
        for name in names:
            _ledger.pop(name, None)


def cancelled(lane=None):
    return _cancel[current_lane() if lane is None else lane].is_set()


def interrupt(lane):
    """Called by the app on its own thread to stop a lane's job."""
    with _lock:
        job = _jobs.get(lane)
        _cancel[lane].set()
        deliver = job is not None and job.in_body
        ident = job.ident if job is not None else None
    # Wake a read of the lane's stdin: the program sees the end of its input.
    try:
        import os

        os.write(_pythilo.lane_input_fd(lane), b"\x04")
    except OSError:
        pass
    if deliver and ident is not None:
        _set_async_exception(ident, KeyboardInterrupt)


def clear_pending():
    """Drops a stop that arrived after the job's own code had finished."""
    _set_async_exception(threading.get_ident(), None)


def _set_async_exception(ident, exception):
    try:
        import ctypes

        # None clears a pending exception.
        value = None if exception is None else ctypes.py_object(exception)
        ctypes.pythonapi.PyThreadState_SetAsyncExc(ctypes.c_ulong(ident), value)
    except Exception:
        pass


def shielded(function, *args):
    """Runs clean-up to the end even if a late stop request lands in the middle."""
    for _ in range(5):
        try:
            return function(*args)
        except KeyboardInterrupt:
            continue
    return function(*args)


class _ImportLedger:
    """A finder that finds nothing; it only notes which lane imported each module."""

    @staticmethod
    def find_spec(fullname, path=None, target=None):
        # Asked only when the module is not imported yet, so the latest asker owns it.
        _ledger[fullname] = current_lane()
        return None

    @staticmethod
    def invalidate_caches():
        pass


def _lane_sleep(seconds):
    lane = current_lane()
    if not lane:
        return _real_sleep(seconds)
    # Signals reach only the main thread, so a lane's sleep wakes for Stop on its own.
    if seconds < 0:
        raise ValueError("sleep length must be non-negative")
    deadline = time.monotonic() + seconds
    event = _cancel[lane]
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        if event.wait(min(remaining, 0.1)):
            raise KeyboardInterrupt


def _start_in_lane(self):
    # A thread belongs to the lane of the code that started it, so its output and
    # imports go to the same tab.
    if not hasattr(self, "_pythilo_lane"):
        self._pythilo_lane = current_lane()
    return _real_start(self)


def _signal_in_lane(signalnum, handler):
    # Only the main thread may set handlers. On a desktop each terminal is its own
    # process, so a program in a lane (unittest, Django's test runner) may set one
    # too: it is kept for that lane. Stop still reaches the lane as KeyboardInterrupt.
    lane = current_lane()
    if not lane or threading.current_thread() is threading.main_thread():
        return _real_signal(signalnum, handler)
    previous = _lane_handlers.get((lane, signalnum))
    if previous is None:
        previous = _real_getsignal(signalnum)
    _lane_handlers[(lane, signalnum)] = handler
    return previous


def _getsignal_in_lane(signalnum):
    lane = current_lane()
    if lane and (lane, signalnum) in _lane_handlers:
        return _lane_handlers[(lane, signalnum)]
    return _real_getsignal(signalnum)


def install():
    global _installed
    if _installed:
        return
    _installed = True
    sys.meta_path.insert(0, _ImportLedger)
    time.sleep = _lane_sleep
    threading.Thread.start = _start_in_lane
    signal.signal = _signal_in_lane
    signal.getsignal = _getsignal_in_lane
