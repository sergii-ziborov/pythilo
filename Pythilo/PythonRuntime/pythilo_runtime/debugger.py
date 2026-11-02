"""A source debugger built on bdb. Only the thread that runs the program is traced."""

import bdb
import os
import reprlib
import sys

import _pythilo

from . import emit_json, runner

_formatter = reprlib.Repr()
_formatter.maxstring = 240
_formatter.maxother = 240
_formatter.maxlist = 30
_formatter.maxdict = 30
_formatter.maxtuple = 30
_formatter.maxset = 30
_formatter.maxlevel = 3

MAXIMUM_VARIABLES = 200


def _describe_value(value):
    try:
        text = _formatter.repr(value)
    except BaseException as error:
        text = f"<repr failed: {type(error).__name__}>"
    return {"type": type(value).__name__, "value": text}


def _variables(namespace):
    result = []
    for name, value in list(namespace.items())[:MAXIMUM_VARIABLES]:
        if name.startswith("__") and name.endswith("__"):
            continue
        if isinstance(value, type(sys)):
            continue
        result.append({"name": name, **_describe_value(value)})
    return result


class ProjectDebugger(bdb.Bdb):
    def __init__(self, breakpoints):
        super().__init__(skip=["pythilo_runtime", "pythilo_runtime.*", "bdb", "importlib.*"])
        self._fd = _pythilo.debug_fd()
        self._pending = b""
        self._wanted = {os.path.realpath(path): set(lines) for path, lines in breakpoints.items()}
        self._started = False
        for path, lines in self._wanted.items():
            for line in lines:
                self.set_break(path, line)

    def _read_command(self):
        while b"\n" not in self._pending:
            chunk = os.read(self._fd, 4096)
            if not chunk:
                return "quit"
            self._pending += chunk
        line, _, self._pending = self._pending.partition(b"\n")
        return line.decode("utf-8", "replace").strip()

    def discard_commands(self):
        self._pending = b""
        os.set_blocking(self._fd, False)
        try:
            while True:
                try:
                    if not os.read(self._fd, 4096):
                        break
                except BlockingIOError:
                    break
        finally:
            os.set_blocking(self._fd, True)

    def _frames(self, frame):
        stack, _ = self.get_stack(frame, None)
        frames = []
        for entry, line in reversed(stack):
            filename = entry.f_code.co_filename
            if filename.startswith("<") or "/pythilo_runtime/" in filename or filename.endswith("/bdb.py"):
                continue
            frames.append(
                {
                    "file": filename,
                    "line": line,
                    "name": entry.f_code.co_name,
                    "locals": _variables(entry.f_locals),
                }
            )
        return frames

    def _pause(self, frame, reason):
        frames = self._frames(frame)
        emit_json(
            "debug_pause",
            {"reason": reason, "file": frame.f_code.co_filename, "line": frame.f_lineno, "frames": frames},
        )
        while True:
            command = self._read_command()
            if command.startswith("eval "):
                self._evaluate(command[5:], frame)
                continue
            break
        emit_json("debug_resume", {})
        if command == "next":
            self.set_next(frame)
        elif command == "step":
            self.set_step()
        elif command == "return":
            self.set_return(frame)
        elif command == "quit":
            self.set_quit()
        else:
            self.set_continue()

    def _evaluate(self, expression, frame):
        try:
            result = _describe_value(eval(expression, frame.f_globals, frame.f_locals))
            emit_json("debug_eval", {"expression": expression, **result})
        except BaseException as error:
            emit_json("debug_eval", {"expression": expression, "error": f"{type(error).__name__}: {error}"})

    def user_call(self, frame, argument_list):
        pass

    def user_line(self, frame):
        filename = frame.f_code.co_filename
        if filename.startswith("<") or "/pythilo_runtime/" in filename:
            self.set_step()
            return
        if not self._started:
            # Stepping starts at the first line of the program, but the program
            # only stops there if the user asked to.
            self._started = True
            if self.break_here(frame):
                self._pause(frame, "breakpoint")
            elif not self._wanted:
                self._pause(frame, "entry")
            else:
                self.set_continue()
            return
        self._pause(frame, "breakpoint" if self.break_here(frame) else "step")

    def user_exception(self, frame, exc_info):
        pass


def run(path, args, breakpoints):
    code, module = runner.prepare_script(path, args)
    debugger = ProjectDebugger(breakpoints)
    debugger.discard_commands()
    try:
        debugger.run(code, module.__dict__)
    except bdb.BdbQuit:
        raise KeyboardInterrupt from None
    finally:
        debugger.quitting = True
        sys.settrace(None)
