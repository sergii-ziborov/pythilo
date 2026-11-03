import Link from "next/link";

export const APP_URL = process.env.NEXT_PUBLIC_APP_STORE_URL || "/#app";

export function BrandMark({ size = 30 }: { size?: number }) {
  return <span aria-hidden="true" className="brand-mark" style={size !== 30 ? { width: size, height: size, fontSize: Math.round(size * .43) } : undefined}>py</span>;
}

export function SiteHeader({ current }: { current?: "learn" | "playground" | "ai" }) {
  return <header className="site-header">
    <nav aria-label="Site">
      <Link href="/" className="brand"><BrandMark />Pythilo</Link>
      <span className="site-nav-links">
        <Link href="/learn/" aria-current={current === "learn" ? "page" : undefined}>Learn</Link>
        <Link href="/playground/" aria-current={current === "playground" ? "page" : undefined}>Playground</Link>
        <Link href="/ai/" aria-current={current === "ai" ? "page" : undefined}>Connect AI</Link>
      </span>
      <a href={APP_URL} className="pill-button">Get the iPhone app</a>
    </nav>
  </header>;
}

export function SiteFooter() {
  return <footer className="site-footer">
    <span>Pythilo</span>
    <span>Python in this browser runs on <a href="https://pyodide.org" target="_blank" rel="noreferrer">Pyodide</a> (MPL 2.0).</span>
    <span>Rooms are end-to-end encrypted and held in memory until they close.</span>
  </footer>;
}
