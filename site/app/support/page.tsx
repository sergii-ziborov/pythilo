import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { Note } from "@/components/guide/doc";
import { DocNav } from "@/components/site/doc-nav";
import { ContactEmail } from "@/components/site/placeholder";
import { LEGAL_PAGES } from "@/lib/legal";
import { OWNER } from "@/lib/site-info";
import "../site.css";

export const metadata: Metadata = { title: "Support and contact", description: "Get help with Pythilo for iPhone and iPad, report a bug, send beta feedback, or contact us about privacy and abuse." };

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

        <h2 id="beta">Beta access and feedback</h2>
        <p>The beta is currently available to invited TestFlight testers. There is no public signup link yet. To request an invitation, use the contact options below. No payment is required during the beta.</p>
        <p>While Pythilo is on TestFlight, the quickest way to report a bug is TestFlight itself: take a screenshot in Pythilo and tap <strong>Share Beta Feedback</strong>, or open the TestFlight app, choose Pythilo and tap <strong>Send Beta Feedback</strong>. Crashes you allow TestFlight to send arrive with the build and device, which helps a lot.</p>

        <h2 id="contact">Contact</h2>
        <p>Email: <ContactEmail />. Please include your device, iOS version, Pythilo&apos;s build number (from TestFlight), and what you did and saw. For privacy requests, use <a href="mailto:privacy@pythilo.com">privacy@pythilo.com</a>. Do not send room links unless you want us to be able to read the room.</p>
        <p>You can also <a href="https://github.com/sergii-ziborov/pythilo/issues/new">open a public issue on GitHub</a> for bugs and feature requests. Keep personal information, room keys and security reports out of public issues.</p>

        <h2 id="security">Security and abuse</h2>
        <p>To report a security problem in the app, the website or the relay, or misuse of a room, write to <a href="mailto:security@pythilo.com">security@pythilo.com</a>, or send private feedback through TestFlight. Please give us a reasonable time to fix a vulnerability before you publish it. See the <Link href="/legal/acceptable-use/">Acceptable Use Policy</Link>.</p>

        <Note title="Legal">The <Link href="/legal/terms/">Terms of Use</Link>, <Link href="/legal/privacy/">Privacy Policy</Link> and <Link href="/legal/licenses/">open-source licences</Link> cover the app and this website.</Note>
      </main>
    </div>
    <SiteFooter />
  </>;
}
