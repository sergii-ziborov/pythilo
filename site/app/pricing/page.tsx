import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader, APP_URL } from "@/components/site-header";
import { PRICE, RELEASED, formatDay } from "@/lib/site-info";
import "../site.css";

export const metadata: Metadata = { title: "Pricing", description: `Pythilo for iPhone and iPad costs ${PRICE} on the App Store, paid once: no subscription, no in-app purchases, no account. The website's lessons, labs and playground are free.` };

export default function PricingPage() {
  return <>
    <SiteHeader current="pricing" />
    <main className="page" style={{ gap: 48 }}>
      <section className="section-intro center" style={{ maxWidth: 820 }}>
        <span className="label">Pricing</span>
        <h1 style={{ margin: 0, fontSize: "clamp(36px, 5vw, 56px)", lineHeight: 1.08, fontWeight: 820, letterSpacing: "-.02em" }}>One price, paid once</h1>
        <p>Pythilo is on the App Store. You buy the whole app once, and everything in it is yours to use: no subscription, no in-app purchases and no account to make.</p>
      </section>

      <section className="card-grid two" aria-label="Plans">
        <div className="price-card featured" id="app">
          <span className="label" style={{ color: "var(--ok)" }}>On the App Store</span>
          <h2>Pythilo for iPhone and iPad</h2>
          <div className="price">{PRICE} <small>once</small></div>
          <ul className="ticks">
            <li>The whole app: projects, editor, terminal with tabs, debugger, Git, notebooks</li>
            <li>NumPy, PyTorch, Django, Flask, FastAPI and more, running on the device</li>
            <li>Every course, lab and interview task, offline once downloaded</li>
            <li>Shared rooms and AI clients</li>
            <li>One purchase covers your iPhone and your iPad</li>
          </ul>
          <div className="button-row"><a href={APP_URL} className="big-button primary">Get it on the App Store</a></div>
          <p className="muted" style={{ margin: 0, fontSize: 14.5, lineHeight: "21px" }}>The price is for the United States. Apple shows it in your currency, with any taxes, before you pay. Released on {formatDay(RELEASED)} in 175 countries and regions.</p>
        </div>
        <div className="price-card">
          <span className="label">On the web</span>
          <h2>Lessons, labs and playground</h2>
          <div className="price">Free</div>
          <ul className="ticks">
            <li>The same lessons, running in your browser on Pyodide</li>
            <li>Labs that trace your own code, the playground and shared rooms</li>
            <li>No account, no ads</li>
          </ul>
          <div className="button-row"><Link href="/learn/" className="big-button run">Start learning</Link><Link href="/playground/" className="big-button">Playground</Link></div>
        </div>
      </section>

      <section className="band" aria-labelledby="included">
        <div>
          <h2 id="included">What the price includes</h2>
          <p>Everything. There is one version of Pythilo and nothing inside it is locked: every course and Lab and every bundled package. Courses, Lab topics and Python packages download from this website at no extra cost, and updates arrive through the App Store like those of any other app.</p>
        </div>
      </section>

      <section aria-labelledby="faq" style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 820 }}>
        <h2 id="faq" style={{ margin: 0, fontSize: 28 }}>Questions</h2>
        <div className="faq">
          <details><summary>Is there a subscription, an in-app purchase or an account?</summary><div><p>No. You pay once on the App Store. The app has no in-app purchases, shows no ads and has no account, and neither does this website. A GitHub account is optional, for cloning your own repositories.</p></div></details>
          <details><summary>Can I try it before I buy?</summary><div><p>The app has no free trial. The <Link href="/learn/">lessons</Link>, many of the <Link href="/labs/">Labs</Link> and the <Link href="/playground/">playground</Link> run free in your browser, and the <Link href="/guide/">guide</Link> shows every screen of the app. What only the app does, such as Django, PyTorch, the debugger and Git, is described in <Link href="/guide/limits/">What runs on iOS</Link>.</p></div></details>
          <details><summary>Can I get a refund?</summary><div><p>Apple handles the payment and refunds. Open <a href="https://reportaproblem.apple.com" target="_blank" rel="noreferrer">reportaproblem.apple.com</a>, sign in, choose Pythilo and ask for a refund. Apple decides the request under its own terms.</p></div></details>
          <details><summary>Does one purchase cover both my iPhone and iPad?</summary><div><p>Yes. Pythilo is one app for iPhone and iPad. Buy it once and install it on the devices signed in to your Apple Account. Apple&apos;s Family Sharing also lets a family group share purchased apps.</p></div></details>
          <details><summary>I tested the beta. What happens to my projects?</summary><div><p>Your projects are ordinary folders on your device, visible in the Files app, and they stay there. Installing the App Store version over a TestFlight build keeps the app&apos;s data, so the same projects open. Keep a copy of anything important all the same, for example by pushing it with Git.</p></div></details>
          <details><summary>Do I need a network connection?</summary><div><p>Not to work. Python and its compiled packages are in the app. Courses, Lab topics and package APIs download when you choose them, and then run offline. The network is used only for those downloads, pip, npm, Git remotes and shared rooms.</p></div></details>
          <details><summary>Which devices does it run on?</summary><div><p>iPhone and iPad with iOS 18 or later, including the folding iPhone.</p></div></details>
        </div>
      </section>
      <p className="muted" style={{ margin: 0, fontSize: 14 }}>Purchases are covered by the <Link href="/legal/terms/#price">Terms of Use</Link>. Help with a purchase is on the <Link href="/support/#app">Support</Link> page.</p>
    </main>
    <SiteFooter />
  </>;
}
