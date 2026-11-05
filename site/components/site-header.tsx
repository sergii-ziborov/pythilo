import Link from "next/link";
import { OWNER } from "@/lib/site-info";

export const APP_URL = process.env.NEXT_PUBLIC_APP_STORE_URL || "/pricing/#beta";

export function BrandMark({ size = 30 }: { size?: number }) {
  return <span aria-hidden="true" className="brand-mark" style={size !== 30 ? { width: size, height: size, fontSize: Math.round(size * .43) } : undefined}>py</span>;
}

type Section = "learn" | "playground" | "ai" | "guide" | "pricing" | "blog" | "legal";

const NAV: { href: string; label: string; id: Section }[] = [
  { href: "/guide/", label: "Guide", id: "guide" },
  { href: "/learn/", label: "Learn", id: "learn" },
  { href: "/playground/", label: "Playground", id: "playground" },
  { href: "/pricing/", label: "Pricing", id: "pricing" },
  { href: "/blog/", label: "Blog", id: "blog" },
];

export function SiteHeader({ current }: { current?: Section }) {
  const links = NAV.map(item => <Link key={item.id} href={item.href} aria-current={current === item.id ? "page" : undefined}>{item.label}</Link>);
  return <>
    <a href="#main" className="skip-link">Skip to content</a>
    <header className="site-header">
      <nav aria-label="Site">
        <Link href="/" className="brand"><BrandMark />Pythilo</Link>
        <span className="site-nav-links">{links}</span>
        <a href={APP_URL} className="pill-button primary site-cta">Get the app</a>
        <details className="site-menu">
          <summary aria-label="Menu"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" /></svg></summary>
          <div className="site-menu-panel">
            {links}
            <Link href="/ai/" aria-current={current === "ai" ? "page" : undefined}>Connect AI</Link>
            <a href={APP_URL} className="pill-button primary">Get the app</a>
          </div>
        </details>
      </nav>
    </header>
    {/* The skip link lands here, right after the header, on every page that uses it. */}
    <div id="main" tabIndex={-1} className="skip-target" />
  </>;
}

const FOOTER: { title: string; links: [string, string][] }[] = [
  { title: "App", links: [["/", "Overview"], ["/guide/", "Guide"], ["/pricing/", "Pricing"], ["/support/", "Support"]] },
  { title: "On the web", links: [["/learn/", "Lessons"], ["/playground/", "Playground"], ["/ai/", "Connect AI"], ["/blog/", "Blog"]] },
  { title: "Legal", links: [["/legal/terms/", "Terms of Use"], ["/legal/privacy/", "Privacy Policy"], ["/legal/acceptable-use/", "Acceptable use"], ["/legal/licenses/", "Open-source licences"]] },
];

export function SiteFooter() {
  return <footer className="site-footer">
    <div className="site-footer-inner">
      <div className="site-footer-brand">
        <Link href="/" className="brand"><BrandMark size={26} />Pythilo</Link>
        <p>Real Python on iPhone and iPad. No account, no analytics, no ads.</p>
        <p>Python in this browser runs on <a href="https://pyodide.org" target="_blank" rel="noreferrer">Pyodide</a> (MPL 2.0). Rooms are end-to-end encrypted and held in memory until they close.</p>
      </div>
      {FOOTER.map(group => <nav key={group.title} aria-label={group.title} className="site-footer-col">
        <h2>{group.title}</h2>
        <ul role="list">{group.links.map(([href, label]) => <li key={href}><Link href={href}>{label}</Link></li>)}</ul>
      </nav>)}
    </div>
    <div className="site-footer-base">© 2026 {OWNER}. iPhone and iPad are trademarks of Apple Inc. Python is a trademark of the Python Software Foundation.</div>
  </footer>;
}
