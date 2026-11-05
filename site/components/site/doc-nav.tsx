"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/** A side navigation for a set of document pages, collapsed into a disclosure on small screens. */
export function DocNav({ title, items }: { title: string; items: [string, string][] }) {
  const pathname = usePathname();
  const current = (href: string) => pathname === href || pathname === href.replace(/\/$/, "") ? "page" : undefined;
  const links = <nav className="doc-nav" aria-label={title}><p className="doc-nav-title">{title}</p>{items.map(([href, label]) => <Link key={href} href={href} aria-current={current(href)}>{label}</Link>)}</nav>;
  return <aside className="doc-aside">{links}<details className="doc-nav-mobile"><summary>{title}</summary>{links}</details></aside>;
}
