import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { Placeholder } from "@/components/site/placeholder";
import { PRICE } from "@/lib/site-info";
import "../site.css";

export const metadata: Metadata = { title: "Pricing", description: "Pythilo is free while in beta on TestFlight. The website's lessons and playground are free." };

export default function PricingPage() {
  return <>
    <SiteHeader current="pricing" />
    <main className="page" style={{ gap: 48 }}>
      <section className="section-intro center" style={{ maxWidth: 820 }}>
        <span className="label">Pricing</span>
        <h1 style={{ margin: 0, fontSize: "clamp(36px, 5vw, 56px)", lineHeight: 1.08, fontWeight: 820, letterSpacing: "-.02em" }}>Free while in beta</h1>
        <p>Pythilo is in beta on TestFlight. Everything in the app is available, and there is nothing to pay and no account to make.</p>
      </section>

      <section className="card-grid two" aria-label="Plans">
        <div className="price-card featured" id="beta">
          <span className="label" style={{ color: "var(--ok)" }}>Now</span>
          <h2>Pythilo beta for iPhone and iPad</h2>
          <div className="price">Free <small>during the beta</small></div>
          <ul className="ticks">
            <li>The whole app: projects, editor, terminal, debugger, Git, notebooks</li>
            <li>NumPy, PyTorch, Django, Flask, FastAPI and more, bundled</li>
            <li>Every course, lab and interview task</li>
            <li>Shared rooms and AI clients</li>
          </ul>
          <p className="muted" style={{ margin: 0, fontSize: 14.5, lineHeight: "21px" }}>The beta is on Apple&apos;s TestFlight. Testers are invited; the public App Store release is still to come. Builds expire after a while and are replaced by newer ones.</p>
        </div>
        <div className="price-card">
          <span className="label">On the web</span>
          <h2>Lessons and playground</h2>
          <div className="price">Free</div>
          <ul className="ticks">
            <li>The same lessons, running in your browser on Pyodide</li>
            <li>The playground and shared rooms</li>
            <li>No account, no ads</li>
          </ul>
          <div className="button-row"><Link href="/learn/" className="big-button run">Start learning</Link><Link href="/playground/" className="big-button">Playground</Link></div>
        </div>
      </section>

      <section className="band" aria-labelledby="release">
        <div>
          <h2 id="release">After the beta</h2>
          <p>{PRICE ?? <>The price for the App Store release has not been decided yet. <Placeholder>App Store price and model</Placeholder></>} It will be shown here and on the App Store before you pay anything, and any purchase goes through Apple.</p>
        </div>
      </section>

      <section aria-labelledby="faq" style={{ display: "flex", flexDirection: "column", gap: 16, maxWidth: 820 }}>
        <h2 id="faq" style={{ margin: 0, fontSize: 28 }}>Questions</h2>
        <div className="faq">
          <details><summary>How do I join the beta?</summary><div><p>Pythilo is tested through Apple&apos;s TestFlight. Testers install TestFlight from the App Store and open their invitation. If you would like to test, <Link href="/support/">get in touch</Link>.</p></div></details>
          <details><summary>Will my projects survive when the app leaves beta?</summary><div><p>Your projects are ordinary folders on your device, visible in the Files app. Keep a copy of anything important, for example by pushing it with Git, as beta builds can have bugs.</p></div></details>
          <details><summary>Is there a subscription or an account?</summary><div><p>There is no account at all, in the app or on the website. How the App Store release will be priced has not been decided.</p></div></details>
          <details><summary>Do I need a network connection?</summary><div><p>No. Python, the bundled packages, the courses and the labs all work offline. The network is used only when you install packages, use a Git remote, or share a room.</p></div></details>
          <details><summary>Which devices does it run on?</summary><div><p>iPhone and iPad with iOS 18 or later, including the folding iPhone.</p></div></details>
        </div>
      </section>
      <p className="muted" style={{ margin: 0, fontSize: 14 }}>Purchases, when there are any, are covered by the <Link href="/legal/terms/#price">Terms of Use</Link>.</p>
    </main>
    <SiteFooter />
  </>;
}
