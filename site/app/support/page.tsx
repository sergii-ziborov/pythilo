import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { Note } from "@/components/guide/doc";
import { DocNav } from "@/components/site/doc-nav";
import { ContactEmail } from "@/components/site/placeholder";
import { LEGAL_PAGES } from "@/lib/legal";
import { APP_STORE_URL, OWNER, PRICE } from "@/lib/site-info";
import "../site.css";

export const metadata: Metadata = { title: "Support and contact", description: "Get help with Pythilo for iPhone and iPad, report a bug, ask about a purchase, or contact us about privacy and abuse." };

export default function SupportPage() {
  return <>
    <SiteHeader />
    <div className="doc-layout">
      <DocNav title="Legal" items={LEGAL_PAGES} />
      <main className="doc">
        <header>
          <span className="label">Support</span>
          <h1>Support and contact</h1>
          <p>Pythilo is made by one person, {OWNER}. Every message is read.</p>
        </header>

        <h2 id="first">Before you write</h2>
        <ul>
          <li>The <Link href="/guide/">guide</Link> describes every screen, and <Link href="/guide/limits/">What runs on iOS</Link> what iOS does not allow, such as compiled packages Pythilo does not bundle, subprocesses and Node.</li>
          <li>A run that will not stop: your files are already saved. Close Pythilo from the app switcher and open it again.</li>
          <li>pip says a package cannot be installed: it probably needs compiled code. See <Link href="/guide/packages/#pip">pip</Link>.</li>
          <li>An AI client cannot connect: the computer must be on the same network, and Pythilo needs the Local Network permission (Settings › Privacy &amp; Security › Local Network on the device).</li>
        </ul>

        <h2 id="app">Getting the app, purchases and refunds</h2>
        <p>Pythilo is <a href={APP_STORE_URL}>on the App Store</a> for iPhone and iPad, for {PRICE} paid once. Updates arrive through the App Store like those of any other app. Apple takes the payment, so questions about a charge and refund requests go to Apple: open <a href="https://reportaproblem.apple.com" target="_blank" rel="noreferrer">reportaproblem.apple.com</a>, sign in and choose the purchase. We never see your payment details. See <Link href="/pricing/">Pricing</Link>.</p>

        <h2 id="beta">Reporting a bug</h2>
        <p>In the app, <strong>Settings › About</strong> shows the version and build. <strong>Email support</strong> there starts a message with the version in its subject, and <strong>Report a bug</strong> opens a new issue on GitHub. A screenshot and the steps that led to the problem help the most.</p>
        <p>New builds are tried on Apple&apos;s TestFlight before they reach the App Store. If you test one, the quickest report is TestFlight itself: take a screenshot in Pythilo and tap <strong>Share Beta Feedback</strong>, or open the TestFlight app, choose Pythilo and tap <strong>Send Beta Feedback</strong>.</p>

        <h2 id="contact">Contact</h2>
        <p>Email: <ContactEmail />. Please include your device, iOS version, Pythilo&apos;s version and build (from Settings › About), and what you did and saw. For privacy requests, use <a href="mailto:privacy@pythilo.com">privacy@pythilo.com</a>. Do not send room links unless you want us to be able to read the room.</p>
        <p>You can also <a href="https://github.com/sergii-ziborov/pythilo/issues/new">open a public issue on GitHub</a> for bugs and feature requests. Keep personal information, room keys and security reports out of public issues.</p>

        <h2 id="security">Security and abuse</h2>
        <p>To report a security problem in the app, the website or the relay, or misuse of a room, write to <a href="mailto:security@pythilo.com">security@pythilo.com</a>, Please give us a reasonable time to fix a vulnerability before you publish it. See the <Link href="/legal/acceptable-use/">Acceptable Use Policy</Link>.</p>

        <Note title="Legal">The <Link href="/legal/terms/">Terms of Use</Link>, <Link href="/legal/privacy/">Privacy Policy</Link> and <Link href="/legal/licenses/">open-source licences</Link> cover the app and this website.</Note>
      </main>
    </div>
    <SiteFooter />
  </>;
}
