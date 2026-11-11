"""sys.stdout, sys.stderr and sys.stdin, wired to the app.

Jobs run on lanes (see lanes.py) that share these objects. Output carries its lane, so
each terminal tab shows only its own program. A shell redirect or pipe is kept per lane
(`redirect`), not by replacing sys.stdout, so one tab's `> file` or `| grep` never
catches another tab's server log.
"""

import io
import os
import sys
import threading

import _pythilo

# Marks the end of input in the stdin pipe, as Ctrl-D does in a terminal.
END_OF_INPUT = b"\x04"

# lane -> (stdin, stdout, stderr) targets, any of them None for "not redirected"
_redirects = {}


def _lane():
    return getattr(threading.current_thread(), "_pythilo_lane", 0)


def _event(kind):
    lane = _lane()
    return f"{kind}@{lane}" if lane else kind


def redirect(lane, targets):
    """Sets or clears (targets=None) the lane's redirected streams. Returns the previous ones."""
    previous = _redirects.get(lane)
    if targets is None or not any(target is not None for target in targets):
        _redirects.pop(lane, None)
    else:
        _redirects[lane] = tuple(targets)
    return previous


def redirected(lane=None):
    return _redirects.get(_lane() if lane is None else lane)


def _target(index):
    targets = _redirects.get(_lane())
    return targets[index] if targets else None


class _BinaryOutput(io.RawIOBase):
    def __init__(self, kind):
        self._kind = kind

    def writable(self):
        return True

    def write(self, data):
        _pythilo.emit(_event(self._kind), bytes(data).decode("utf-8", "backslashreplace"))
        return len(data)


class OutputStream(io.TextIOBase):
    encoding = "utf-8"
    errors = "backslashreplace"

    def __init__(self, kind, name, index):
        self._kind = kind
        self._name = name
        self._index = index
        self._buffer = _BinaryOutput(kind)

    def _redirect(self):
        target = _target(self._index)
        return target if target is not None and target is not self else None

    @property
    def name(self):
        target = self._redirect()
        return getattr(target, "name", self._name) if target is not None else self._name

    @property
    def buffer(self):
        target = self._redirect()
        return target.buffer if target is not None else self._buffer

    def writable(self):
        return True

    def isatty(self):
        target = self._redirect()
        return target.isatty() if target is not None else False

    def fileno(self):
        target = self._redirect()
        if target is not None:
            return target.fileno()
        raise io.UnsupportedOperation("fileno")

    def write(self, text):
        target = self._redirect()
        if target is not None:
            return target.write(text)
        if not isinstance(text, str):
            raise TypeError(f"write() argument must be str, not {type(text).__name__}")
        if text:
            _pythilo.emit(_event(self._kind), text)
        return len(text)

    def flush(self):
        target = self._redirect()
        if target is not None:
            target.flush()


class _LaneInput:
    __slots__ = ("fd", "pending", "lock")

    def __init__(self, fd):
        self.fd = fd
        self.pending = b""
        self.lock = threading.Lock()


class InputStream(io.TextIOBase):
    """Reads from a pipe, so a real SIGINT interrupts a program waiting for input.

    Each lane reads its own pipe, so typing in one tab never feeds another tab's program.
    """

    encoding = "utf-8"
    errors = "strict"

    def __init__(self):
        self._lanes = {0: _LaneInput(_pythilo.input_fd())}
        self._guard = threading.Lock()

    def _state(self, lane=None):
        lane = _lane() if lane is None else lane
        state = self._lanes.get(lane)
        if state is None:
            with self._guard:
                state = self._lanes.get(lane)
                if state is None:
                    state = self._lanes[lane] = _LaneInput(_pythilo.lane_input_fd(lane))
        return state

    def _redirect(self):
        target = _target(0)
        return target if target is not None and target is not self else None

    @property
    def name(self):
        target = self._redirect()
        return getattr(target, "name", "<stdin>") if target is not None else "<stdin>"

    @property
    def piped(self):
        """True when this lane's stdin is a pipe or a file, not the person at the keyboard."""
        target = self._redirect()
        if target is None:
            return False
        return getattr(target, "piped", False) or isinstance(target, io.TextIOWrapper)

    def readable(self):
        return True

    def isatty(self):
        return False

    def fileno(self):
        target = self._redirect()
        if target is not None:
            return target.fileno()
        return self._state().fd

    def _read_more(self, state):
        chunk = os.read(state.fd, 65536)
        if not chunk:
            return False
        state.pending += chunk
        return True

    def readline(self, size=-1):
        target = self._redirect()
        if target is not None:
            return target.readline(size)
        state = self._state()
        with state.lock:
            _pythilo.emit(_event("input_wait"), "")
            try:
                while True:
                    marker = state.pending.find(END_OF_INPUT)
                    newline = state.pending.find(b"\n")
                    if marker != -1 and (newline == -1 or marker < newline):
                        line, state.pending = state.pending[:marker], state.pending[marker + 1 :]
                        return line.decode("utf-8", "replace")
                    if newline != -1:
                        line, state.pending = state.pending[: newline + 1], state.pending[newline + 1 :]
                        return line.decode("utf-8", "replace")
                    if not self._read_more(state):
                        return ""
            finally:
                _pythilo.emit(_event("input_done"), "")

    def read(self, size=-1):
        target = self._redirect()
        if target is not None:
            return target.read(size)
        lines = []
        while True:
            line = self.readline()
            if not line:
                break
            lines.append(line)
            if size is not None and 0 <= size <= sum(map(len, lines)):
                break
        return "".join(lines)

    def readlines(self, hint=-1):
        target = self._redirect()
        if target is not None:
            return target.readlines(hint)
        return list(iter(self.readline, ""))

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if not line:
            raise StopIteration
        return line

    def discard_pending(self, lane=None):
        """Forget anything typed for an earlier run on this lane."""
        state = self._state(lane)
        state.pending = b""
        os.set_blocking(state.fd, False)
        try:
            while True:
                try:
                    if not os.read(state.fd, 65536):
                        break
                except BlockingIOError:
                    break
        finally:
            os.set_blocking(state.fd, True)


stdout = None
stderr = None
stdin = None


def install():
    global stdout, stderr, stdin
    stdout = OutputStream("stdout", "<stdout>", 1)
    stderr = OutputStream("stderr", "<stderr>", 2)
    stdin = InputStream()
    reset()


def reset():
    sys.stdout = sys.__stdout__ = stdout
    sys.stderr = sys.__stderr__ = stderr
    sys.stdin = sys.__stdin__ = stdin
