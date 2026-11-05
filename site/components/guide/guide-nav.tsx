"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { guidePages } from "@/lib/guide";

function Links() {
  const pathname = usePathname();
  const groups = [...new Set(guidePages.map(page => page.group))];
  return <nav className="doc-nav" aria-label="Guide">
    <Link href="/guide/" aria-current={pathname === "/guide/" || pathname === "/guide" ? "page" : undefined}>Overview</Link>
    {groups.map(group => <div key={group} style={{ display: "contents" }}>
      <p className="doc-nav-title" style={{ marginTop: 16 }}>{group}</p>
      {guidePages.filter(page => page.group === group).map(page => {
        const href = `/guide/${page.slug}/`;
        return <Link key={page.slug} href={href} aria-current={pathname === href || pathname === href.slice(0, -1) ? "page" : undefined}>{page.title}</Link>;
      })}
    </div>)}
  </nav>;
}

export function GuideNav() {
  return <aside className="doc-aside">
    <Links />
    <details className="doc-nav-mobile"><summary>Guide contents</summary><Links /></details>
  </aside>;
}
