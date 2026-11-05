import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";

export const metadata: Metadata = { title: "SQLite", description: "Browse and edit SQLite databases in Pythilo on iPhone and iPad, and use the sqlite3 command in the terminal, with Django's db.sqlite3 or any other database." };

export default function Page() {
  return <>
    <GuideHeader slug="sqlite">Browse and edit SQLite databases with a tap, or use the sqlite3 shell in the terminal. Django&apos;s <code>db.sqlite3</code> works the same as any other database.</GuideHeader>
    <Toc items={[["browser", "The database browser"], ["data", "Data: rows, filter and editing"], ["schema", "Schema"], ["sql", "SQL"], ["terminal", "sqlite3 in the terminal"], ["dot", "Dot commands"], ["python", "From Python"]]} />

    <h2 id="browser">The database browser</h2>
    <p>Tap a database in the file tree and it opens in the database browser instead of the editor. Pythilo recognises a SQLite file by its contents, so <code>db.sqlite3</code>, <code>app.db</code> or a database with any other name all open there. At the top, pick a table (each shows its row count) and one of three views: <span className="ui">Data</span>, <span className="ui">Schema</span> and <span className="ui">SQL</span>. The <span className="ui">Database actions</span> menu has <span className="ui">Reload</span>, <span className="ui">Open in the terminal</span> (which runs <code>sqlite3</code> on the file) and <span className="ui">Share file</span>.</p>
    <p>A new Django project has no tables until you migrate. The browser says so: create one in the SQL tab, or run <code>python manage.py migrate</code>.</p>

    <h2 id="data">Data: rows, filter and editing</h2>
    <ul>
      <li>Rows show in a grid, 100 at a time; <span className="ui">Show … more</span> loads the next ones.</li>
      <li><span className="ui">Filter rows</span> keeps the rows where any column contains what you type.</li>
      <li>Tap a row to edit it: change values, set a column to <code>NULL</code> with its switch, then <span className="ui">Save</span>, or <span className="ui">Delete row</span>.</li>
      <li><span className="ui">Add row</span> opens the same form for a new row. Primary-key columns start as <code>NULL</code>, so SQLite fills them in.</li>
    </ul>
    <p>Edits are written to the file straight away. Commit the database with Git first if you may want to undo. Views, and tables created <code>WITHOUT ROWID</code>, are shown read-only.</p>

    <h2 id="schema">Schema</h2>
    <p>Each column with its type, a key for the primary key, and <code>NOT NULL</code> where it applies, followed by the table&apos;s <span className="ui">CREATE statement</span>.</p>

    <h2 id="sql">SQL</h2>
    <p>Write any SQL and tap <span className="ui">Run</span>. A query shows its rows (up to the first 1000) and how many there were; any other statement says how many rows it changed.</p>

    <h2 id="terminal">sqlite3 in the terminal</h2>
    <p>The <code>sqlite3</code> command works like the SQLite shell on a computer, built on Python&apos;s <code>sqlite3</code> module:</p>
    <pre><code>{`sqlite3 db.sqlite3                      # interactive shell; .quit leaves
sqlite3 db.sqlite3 "select count(*) from notes_note"
sqlite3 -box db.sqlite3 "select * from notes_note limit 5"
sqlite3 db.sqlite3 < schema.sql         # run a script`}</code></pre>
    <p>Options: <code>-header</code>, <code>-noheader</code>, the output modes <code>-csv</code>, <code>-json</code>, <code>-line</code>, <code>-list</code>, <code>-column</code>, <code>-box</code>, <code>-table</code>, <code>-markdown</code> and <code>-tabs</code>, plus <code>-separator</code>, <code>-nullvalue</code>, <code>-readonly</code>, <code>-cmd</code>, <code>-bail</code> and <code>-version</code>. It works in pipes and with redirects, like any other command.</p>

    <h2 id="dot">Dot commands</h2>
    <Table head={["Command", "Does"]} rows={[
      [<><code>.tables</code>, <code>.schema</code>, <code>.indexes</code></>, "List tables, show CREATE statements, list indexes"],
      [<><code>.headers on|off</code>, <code>.mode MODE</code></>, "Column names; list, csv, json, line, column, box, table, markdown or tabs output"],
      [<><code>.separator</code>, <code>.nullvalue</code></>, "The separator for list mode, and the text shown for NULL"],
      [<><code>.read FILE</code>, <code>.import FILE TABLE</code></>, "Run SQL from a file; load a CSV file into a table, creating it if missing"],
      [<><code>.dump</code>, <code>.output FILE</code>, <code>.once FILE</code></>, "SQL that recreates the database; send results to a file"],
      [<><code>.open FILE</code>, <code>.databases</code></>, "Open another database; list attached ones"],
      [<><code>.timer</code>, <code>.changes</code>, <code>.show</code></>, "Time statements, count changed rows, show the settings"],
      [<><code>.help</code>, <code>.quit</code></>, "Help, and leave"],
    ]} />

    <h2 id="python">From Python</h2>
    <p>Python&apos;s own <code>sqlite3</code> module works in every project, and Django uses SQLite for its database out of the box. <code>python manage.py dbshell</code> is not available, because it starts an external program; use <code>sqlite3 db.sqlite3</code> instead.</p>
    <Note>Database files are left out of <Link href="/guide/rooms/#what">shared rooms</Link>: a room carries source and text files only.</Note>
    <Pager slug="sqlite" />
  </>;
}
