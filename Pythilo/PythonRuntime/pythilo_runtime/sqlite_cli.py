"""sqlite3 in the terminal: the SQLite shell's usual options and dot commands,
on Python's sqlite3 module, so Django's db.sqlite3 can be opened and queried."""

import csv
import io
import json
import os
import sqlite3
import sys
import time

USAGE = """usage: sqlite3 [options] [FILE] [SQL]
  sqlite3 db.sqlite3                  open an interactive shell (.help lists dot commands)
  sqlite3 db.sqlite3 "select * from t" run SQL and print the result
  sqlite3 db.sqlite3 < script.sql     run a script
options: -header -noheader -csv -json -line -list -column -box -table -markdown -tabs
         -separator S -nullvalue S -readonly -cmd COMMAND -bail -version -help
"""

DOT_HELP = """.tables [PATTERN]       list tables
.schema [TABLE]         show CREATE statements
.indexes [TABLE]        list indexes
.headers on|off         show column names
.mode MODE              list csv json line column box table markdown tabs
.separator SEP          separator for list mode
.nullvalue TEXT         text shown for NULL
.read FILE              run SQL from a file
.import [--csv] FILE TABLE  load a CSV file into a table (created if missing)
.dump [TABLE]           print SQL that recreates the database
.output [FILE]          send results to a file, or back to the screen
.once FILE              send the next result to a file
.open FILE              open another database
.databases              list attached databases
.timer on|off           show how long each statement took
.changes on|off         show how many rows changed
.show                   show the current settings
.quit  .exit            leave
"""


class Shell:
    def __init__(self, path, readonly=False):
        self.path = path
        self.mode = "list"
        self.headers = False
        self.separator = "|"
        self.nullvalue = ""
        self.timer = False
        self.changes = False
        self.bail = False
        self.output = None
        self.once = False
        self.failed = False
        self.connection = None
        self.open(path, readonly)

    def open(self, path, readonly=False):
        if self.connection is not None:
            self.connection.close()
        self.path = path
        if path in ("", ":memory:"):
            self.connection = sqlite3.connect(":memory:")
        elif readonly:
            self.connection = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
        else:
            self.connection = sqlite3.connect(path)
        self.connection.isolation_level = None  # autocommit, as the sqlite3 shell does

    @property
    def out(self):
        return self.output or sys.stdout

    # ------------------------------------------------------------ running SQL

    def run_sql(self, text):
        """Runs every complete statement in text. Returns False after an error."""
        ok = True
        for statement in split_statements(text):
            started = time.perf_counter()
            try:
                cursor = self.connection.execute(statement)
                if cursor.description:
                    columns = [d[0] for d in cursor.description]
                    self.show(columns, cursor.fetchall())
                elif self.changes:
                    print(f"changes: {self.connection.total_changes}", file=self.out)
            except sqlite3.Error as error:
                print(f"Error: {error}", file=sys.stderr)
                ok = False
                self.failed = True
                if self.bail:
                    return False
            if self.timer:
                print(f"Run Time: real {time.perf_counter() - started:.3f}", file=self.out)
            self.finish_once()
        return ok

    def finish_once(self):
        if self.once and self.output is not None:
            self.output.close()
            self.output = None
            self.once = False

    def cell(self, value):
        if value is None:
            return self.nullvalue
        if isinstance(value, bytes):
            return value.hex()
        return str(value)

    def show(self, columns, rows):
        out = self.out
        mode = self.mode
        if mode == "json":
            data = [{c: (v.hex() if isinstance(v, bytes) else v) for c, v in zip(columns, row)} for row in rows]
            if data:
                out.write(json.dumps(data, ensure_ascii=False, indent=None).replace("},{", "},\n{") + "\n")
            return
        if mode == "csv":
            writer = csv.writer(out, lineterminator="\n")
            if self.headers:
                writer.writerow(columns)
            for row in rows:
                writer.writerow([self.cell(v) for v in row])
            return
        if mode == "line":
            width = max((len(c) for c in columns), default=0)
            for index, row in enumerate(rows):
                if index:
                    out.write("\n")
                for column, value in zip(columns, row):
                    out.write(f"{column:>{width}} = {self.cell(value)}\n")
            return
        if mode in ("list", "tabs"):
            separator = "\t" if mode == "tabs" else self.separator
            if self.headers:
                out.write(separator.join(columns) + "\n")
            for row in rows:
                out.write(separator.join(self.cell(v) for v in row) + "\n")
            return
        cells = [[self.cell(v) for v in row] for row in rows]
        widths = [max([len(c)] + [len(r[i]) for r in cells]) for i, c in enumerate(columns)]
        numeric = [all(isinstance(row[i], (int, float)) or row[i] is None for row in rows) and rows for i in range(len(columns))]

        def line(values):
            return [v.rjust(w) if numeric[i] else v.ljust(w) for i, (v, w) in enumerate(zip(values, widths))]

        if mode == "column":
            if self.headers or True:
                out.write("  ".join(line(columns)).rstrip() + "\n")
                out.write("  ".join("-" * w for w in widths) + "\n")
            for row in cells:
                out.write("  ".join(line(row)).rstrip() + "\n")
        elif mode == "markdown":
            out.write("| " + " | ".join(line(columns)) + " |\n")
            out.write("|" + "|".join(("-" * (w + 1) + ":") if numeric[i] else ("-" * (w + 2)) for i, w in enumerate(widths)) + "|\n")
            for row in cells:
                out.write("| " + " | ".join(line(row)) + " |\n")
        else:  # box and table
            box = mode == "box"
            h, v = ("─", "│") if box else ("-", "|")
            corners = ("┌┬┐", "├┼┤", "└┴┘") if box else ("+++", "+++", "+++")

            def rule(chars):
                left, middle, right = chars
                return left + middle.join(h * (w + 2) for w in widths) + right + "\n"

            out.write(rule(corners[0]))
            out.write(v + v.join(f" {c} " for c in line(columns)) + v + "\n")
            out.write(rule(corners[1]))
            for row in cells:
                out.write(v + v.join(f" {c} " for c in line(row)) + v + "\n")
            out.write(rule(corners[2]))

    # ------------------------------------------------------------ dot commands

    def dot(self, line):
        """Runs a dot command. Returns False when the shell should stop."""
        words = split_words(line)
        command, args = words[0], words[1:]
        if command in (".quit", ".exit", ".q"):
            return False
        if command == ".help":
            self.out.write(DOT_HELP)
        elif command in (".tables", ".table"):
            pattern = args[0] if args else "%"
            names = [r[0] for r in self.connection.execute(
                "select name from sqlite_schema where type in ('table','view') and name not like 'sqlite_%' and name like ? order by name", (pattern,))]
            self.columns_out(names)
        elif command == ".schema":
            query = "select sql from sqlite_schema where sql is not null and name not like 'sqlite_%'"
            params = ()
            if args:
                query += " and (name like ? or tbl_name like ?)"
                params = (args[0], args[0])
            for (sql,) in self.connection.execute(query + " order by type desc, name", params):
                self.out.write(sql + ";\n")
        elif command in (".indexes", ".indices"):
            query = "select name from sqlite_schema where type='index'"
            params = ()
            if args:
                query += " and tbl_name like ?"
                params = (args[0],)
            self.columns_out([r[0] for r in self.connection.execute(query + " order by name", params)])
        elif command == ".headers":
            self.headers = on_off(args)
        elif command == ".mode":
            if not args:
                print(f"current output mode: {self.mode}", file=self.out)
            elif args[0] in ("list", "csv", "json", "line", "column", "box", "table", "markdown", "tabs"):
                self.mode = args[0]
                if args[0] in ("column", "box", "table", "markdown"):
                    self.headers = True
            else:
                print(f"Error: mode should be one of: list csv json line column box table markdown tabs", file=sys.stderr)
        elif command == ".separator":
            if args:
                self.separator = args[0].encode().decode("unicode_escape")
        elif command == ".nullvalue":
            self.nullvalue = args[0] if args else ""
        elif command == ".timer":
            self.timer = on_off(args)
        elif command == ".changes":
            self.changes = on_off(args)
        elif command == ".bail":
            self.bail = on_off(args)
        elif command == ".read":
            if not args:
                print("Error: .read needs a file", file=sys.stderr)
            else:
                with open(args[0], encoding="utf-8") as handle:
                    self.run_script(handle.read())
        elif command == ".import":
            self.import_csv([a for a in args if not a.startswith("--")])
        elif command == ".dump":
            for line in self.connection.iterdump():
                if args and not mentions(line, args[0]):
                    continue
                self.out.write(line + "\n")
        elif command in (".output", ".once"):
            if self.output is not None:
                self.output.close()
                self.output = None
            if args and args[0] != "stdout":
                self.output = open(args[0], "w", encoding="utf-8")
                self.once = command == ".once"
        elif command == ".open":
            if not args:
                print("Error: .open needs a file", file=sys.stderr)
            else:
                self.open(args[-1], readonly="--readonly" in args)
        elif command == ".databases":
            for _, name, path in self.connection.execute("pragma database_list"):
                print(f"{name}: {path or '(in memory)'}", file=self.out)
        elif command == ".show":
            for key, value in (("headers", "on" if self.headers else "off"), ("mode", self.mode), ("nullvalue", repr(self.nullvalue)),
                               ("separator", repr(self.separator)), ("timer", "on" if self.timer else "off"), ("filename", self.path or ":memory:")):
                print(f"{key:>10}: {value}", file=self.out)
        elif command in (".width", ".prompt", ".echo", ".print"):
            if command == ".print":
                print(" ".join(args), file=self.out)
        else:
            print(f"Error: unknown command {command}. .help lists the dot commands.", file=sys.stderr)
        return True

    def columns_out(self, names):
        if not names:
            return
        width = max(len(n) for n in names) + 2
        per_line = max(1, 40 // width)
        for index in range(0, len(names), per_line):
            self.out.write("".join(n.ljust(width) for n in names[index:index + per_line]).rstrip() + "\n")

    def import_csv(self, args):
        if len(args) != 2:
            print("Error: .import FILE TABLE", file=sys.stderr)
            return
        path, table = args
        with open(path, newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))
        if not rows:
            return
        exists = self.connection.execute("select 1 from sqlite_schema where type='table' and name=?", (table,)).fetchone()
        quoted = '"' + table.replace('"', '""') + '"'
        if not exists:
            header, rows = rows[0], rows[1:]
            columns = ", ".join('"' + c.replace('"', '""') + '" TEXT' for c in header)
            self.connection.execute(f"create table {quoted} ({columns})")
        width = len(self.connection.execute(f"select * from {quoted} limit 0").description)
        placeholders = ", ".join("?" * width)
        self.connection.execute("begin")
        self.connection.executemany(f"insert into {quoted} values ({placeholders})", [(r + [None] * width)[:width] for r in rows])
        self.connection.execute("commit")

    def run_script(self, text):
        """Runs SQL and dot commands from a script. Returns False to stop."""
        pending = ""
        for line in text.splitlines():
            if not pending and line.strip().startswith("."):
                if not self.dot(line.strip()):
                    return False
                continue
            pending += line + "\n"
            if sqlite3.complete_statement(pending):
                if not self.run_sql(pending) and self.bail:
                    return False
                pending = ""
        if pending.strip():
            self.run_sql(pending)
        return True

    def interact(self):
        print(f"SQLite version {sqlite3.sqlite_version}. Enter .help for usage hints; .quit leaves.")
        if self.path in ("", ":memory:"):
            print("Connected to a transient in-memory database. Use .open FILE to open a database file.")
        pending = ""
        while True:
            try:
                line = input("   ...> " if pending else "sqlite> ")
            except EOFError:
                print()
                break
            except KeyboardInterrupt:
                pending = ""
                print()
                continue
            if not pending and line.strip().startswith("."):
                if not self.dot(line.strip()):
                    break
                continue
            pending += line + "\n"
            if sqlite3.complete_statement(pending):
                self.run_sql(pending)
                pending = ""

    def close(self):
        if self.output is not None:
            self.output.close()
        self.connection.close()


def on_off(args):
    return bool(args) and args[0].lower() in ("on", "1", "yes", "true")


def mentions(line, table):
    lowered = line.lower()
    name = table.lower()
    return any(token in lowered for token in (f'"{name}"', f" {name} ", f" {name}(", f"table {name}", f"into {name}")) or not line.upper().startswith(("CREATE", "INSERT"))


def split_words(line):
    import shlex

    try:
        return shlex.split(line)
    except ValueError:
        return line.split()


def split_statements(text):
    statements = []
    pending = ""
    for piece in text.split(";"):
        pending += piece + ";"
        if sqlite3.complete_statement(pending):
            if pending.strip(" \n\t;"):
                statements.append(pending)
            pending = ""
    if pending.strip(" \n\t;"):
        statements.append(pending)
    return statements


def main(args):
    from .bash import piped

    options = {"mode": None, "headers": None, "separator": None, "nullvalue": None, "readonly": False, "cmds": [], "bail": False}
    positional = []
    iterator = iter(args)
    for arg in iterator:
        name = arg.lstrip("-")
        if not arg.startswith("-"):
            positional.append(arg)
        elif name in ("help", "h"):
            sys.stdout.write(USAGE)
            return 0
        elif name == "version":
            print(sqlite3.sqlite_version)
            return 0
        elif name == "header":
            options["headers"] = True
        elif name == "noheader":
            options["headers"] = False
        elif name in ("csv", "json", "line", "list", "column", "box", "table", "markdown", "tabs"):
            options["mode"] = name
        elif name == "separator":
            options["separator"] = next(iterator, "|")
        elif name == "nullvalue":
            options["nullvalue"] = next(iterator, "")
        elif name == "readonly":
            options["readonly"] = True
        elif name == "bail":
            options["bail"] = True
        elif name == "cmd":
            options["cmds"].append(next(iterator, ""))
        elif name in ("batch", "interactive", "echo"):
            continue
        else:
            print(f"sqlite3: option {arg} is not supported here. sqlite3 -help lists what works.", file=sys.stderr)
            return 1
    path = positional[0] if positional else ""
    sql = " ".join(positional[1:])
    if path and not os.path.exists(path) and options["readonly"]:
        print(f"sqlite3: {path}: no such file", file=sys.stderr)
        return 1
    shell = Shell(path, readonly=options["readonly"])
    interactive = not sql and not piped()
    if interactive:
        shell.mode, shell.headers = "box", True
    for key in ("mode", "headers", "separator", "nullvalue"):
        if options[key] is not None:
            setattr(shell, key, options[key])
    if options["mode"] in ("column", "box", "table", "markdown") and options["headers"] is None:
        shell.headers = True
    shell.bail = options["bail"]
    status = 0
    try:
        for command in options["cmds"]:
            if command.startswith("."):
                shell.dot(command)
            else:
                shell.run_sql(command)
        if sql:
            shell.run_script(sql if sql.rstrip().endswith(";") or sql.lstrip().startswith(".") else sql + ";")
            status = 1 if shell.failed else 0
        elif not interactive:
            shell.run_script(sys.stdin.read())
            status = 1 if shell.failed else 0
        else:
            shell.interact()
    finally:
        shell.close()
    return status
