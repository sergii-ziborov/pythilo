import Link from "next/link";
import { guidePages } from "@/lib/guide";

/** Title block for a guide page. */
export function GuideHeader({ slug, children }: { slug: string; children?: React.ReactNode }) {
  const page = guidePages.find(item => item.slug === slug)!;
  return <header>
    <span className="label">Guide · {page.group}</span>
    <h1>{page.title}</h1>
    <p>{children ?? page.summary}</p>
  </header>;
}

/** An "on this page" list. Items are [anchor id, label]. */
export function Toc({ items }: { items: [string, string][] }) {
  return <nav className="doc-toc" aria-label="On this page"><strong>On this page</strong><ol>{items.map(([id, label]) => <li key={id}><a href={`#${id}`}>{label}</a></li>)}</ol></nav>;
}

export function Pager({ slug }: { slug: string }) {
  const index = guidePages.findIndex(page => page.slug === slug);
  const previous = guidePages[index - 1], next = guidePages[index + 1];
  return <nav className="doc-pager" aria-label="Previous and next">
    {previous ? <Link href={`/guide/${previous.slug}/`} rel="prev"><span>Previous</span>{previous.title}</Link> : <Link href="/guide/"><span>Back to</span>Guide overview</Link>}
    {next ? <Link href={`/guide/${next.slug}/`} rel="next" className="next"><span>Next</span>{next.title}</Link> : null}
  </nav>;
}

export function Table({ head, rows }: { head: string[]; rows: React.ReactNode[][] }) {
  return <div className="table-wrap"><table><thead><tr>{head.map(cell => <th key={cell} scope="col">{cell}</th>)}</tr></thead>
    <tbody>{rows.map((row, index) => <tr key={index}>{row.map((cell, column) => <td key={column}>{cell}</td>)}</tr>)}</tbody></table></div>;
}

export function Note({ title, warn = false, children }: { title?: string; warn?: boolean; children: React.ReactNode }) {
  return <div className={`callout${warn ? " warn" : ""}`} role="note">{title ? <span className="callout-title">{title}</span> : null}{children}</div>;
}
