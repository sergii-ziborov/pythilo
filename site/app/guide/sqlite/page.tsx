import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager } from "@/components/guide/doc";
import { Placeholder } from "@/components/site/placeholder";

export const metadata: Metadata = { title: "SQLite", description: "Working with SQLite databases in Pythilo." };

export default function Page() {
  return <>
    <GuideHeader slug="sqlite" />
    <p>Python&apos;s own <code>sqlite3</code> module works in every project today, and Django uses SQLite for its database. Database files (<code>.sqlite3</code>, <code>.sqlite</code>, <code>.db</code>) show a database icon in the file tree.</p>
    <Note warn title="Coming in the next build">
      <p>A <code>sqlite3</code> terminal command and a SQLite browser for database files are being added to the app. This page will describe them once that build ships.</p>
      <p><Placeholder>SQLite: the sqlite3 terminal command, the database browser, and how to open a database from the file tree</Placeholder></p>
    </Note>
    <p>Until then, see <Link href="/guide/terminal/">The terminal</Link> and <Link href="/guide/web-servers/#migrations">Django migrations</Link>.</p>
    <Pager slug="sqlite" />
  </>;
}
