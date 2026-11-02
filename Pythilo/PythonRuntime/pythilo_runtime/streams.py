"""sys.stdout, sys.stderr and sys.stdin, wired to the app."""

import io
import os
import sys
import threading

import _pythilo

# Marks the end of input in the stdin pipe, as Ctrl-D does in a terminal.
END_OF_INPUT = b"\x04"


class _BinaryOutput(io.RawIOBase):
    def __init__(self, kind):
        self._kind = kind

    def writable(self):
        return True

    def write(self, data):
        _pythilo.emit(self._kind, bytes(data).decode("utf-8", "backslashreplace"))
        return len(data)


class OutputStream(io.TextIOBase):
    encoding = "utf-8"
    errors = "backslashreplace"

    def __init__(self, kind, name):
        self._kind = kind
        self._name = name
        self.buffer = _BinaryOutput(kind)

    @property
    def name(self):
        return self._name

    def writable(self):
        return True

    def isatty(self):
        return False

    def write(self, text):
        if not isinstance(text, str):
            raise TypeError(f"write() argument must be str, not {type(text).__name__}")
        if text:
            _pythilo.emit(self._kind, text)
        return len(text)

    def flush(self):
        pass


class InputStream(io.TextIOBase):
    """Reads from a pipe, so a real SIGINT interrupts a program waiting for input."""

    encoding = "utf-8"
    errors = "strict"

    def __init__(self):
        self._fd = _pythilo.input_fd()
        self._pending = b""
        self._lock = threading.Lock()

    @property
    def name(self):
        return "<stdin>"

    def readable(self):
        return True

    def isatty(self):
        return False

    def fileno(self):
        return self._fd

    def _read_more(self):
        chunk = os.read(self._fd, 65536)
        if not chunk:
            return False
        self._pending += chunk
        return True

    def readline(self, size=-1):
        with self._lock:
            _pythilo.emit("input_wait", "")
            try:
                while True:
                    marker = self._pending.find(END_OF_INPUT)
                    newline = self._pending.find(b"\n")
                    if marker != -1 and (newline == -1 or marker < newline):
                        line, self._pending = self._pending[:marker], self._pending[marker + 1 :]
                        return line.decode("utf-8", "replace")
                    if newline != -1:
                        line, self._pending = self._pending[: newline + 1], self._pending[newline + 1 :]
                        return line.decode("utf-8", "replace")
                    if not self._read_more():
                        return ""
            finally:
                _pythilo.emit("input_done", "")

    def read(self, size=-1):
        lines = []
        while True:
            line = self.readline()
            if not line:
                break
            lines.append(line)
            if size is not None and 0 <= size <= sum(map(len, lines)):
                break
        return "".join(lines)

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if not line:
            raise StopIteration
        return line

    def discard_pending(self):
        """Forget anything typed for an earlier run."""
        self._pending = b""
        os.set_blocking(self._fd, False)
        try:
            while True:
                try:
                    if not os.read(self._fd, 65536):
                        break
                except BlockingIOError:
                    break
        finally:
            os.set_blocking(self._fd, True)


stdout = None
stderr = None
stdin = None


def install():
    global stdout, stderr, stdin
    stdout = OutputStream("stdout", "<stdout>")
    stderr = OutputStream("stderr", "<stderr>")
    stdin = InputStream()
    reset()


def reset():
    sys.stdout = sys.__stdout__ = stdout
    sys.stderr = sys.__stderr__ = stderr
    sys.stdin = sys.__stdin__ = stdin
