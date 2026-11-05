import type { Metadata } from "next";
import Link from "next/link";
import { Toc } from "@/components/guide/doc";
import { ContactEmail } from "@/components/site/placeholder";
import { APPLE_EULA, GOVERNING_LAW, LEGAL_UPDATED, OWNER, PRICE, formatDay } from "@/lib/site-info";

export const metadata: Metadata = { title: "Terms of Use", description: "The terms for using the Pythilo app for iPhone and iPad, the pythilo.com website, its lessons, playground and shared rooms." };

export default function TermsPage() {
  return <>
    <header>
      <span className="label">Legal</span>
      <h1>Terms of Use</h1>
      <p>These terms cover the Pythilo app for iPhone and iPad and the website at pythilo.com, including its lessons, playground, shared rooms and the Pythilo MCP bridge. Please read them; they are written to be read.</p>
      <p className="updated">Last updated {formatDay(LEGAL_UPDATED)}</p>
    </header>
    <Toc items={[["agreement", "Agreement"], ["app-licence", "The app and Apple's licence"], ["beta", "Beta software"], ["price", "Price and payment"], ["services", "The website and rooms"], ["your-content", "Your code and content"], ["running-code", "Code you run"], ["third-party", "Third-party services and software"], ["acceptable-use", "Acceptable use"], ["ip", "Our rights"], ["learning", "Lessons are for learning"], ["warranty", "No warranty"], ["liability", "Limitation of liability"], ["ending", "Suspension and ending"], ["changes", "Changes"], ["law", "Governing law and disputes"], ["contact", "Contact"]]} />

    <h2 id="agreement">1. Agreement</h2>
    <p>Pythilo is made by {OWNER} (&ldquo;we&rdquo;, &ldquo;us&rdquo;). By downloading or using the app, or by using the website, you agree to these Terms of Use and to our <Link href="/legal/privacy/">Privacy Policy</Link> and <Link href="/legal/acceptable-use/">Acceptable Use Policy</Link>. If you do not agree, do not use Pythilo. If you use Pythilo for an organisation, you accept these terms for it and confirm you may do so.</p>

    <h2 id="app-licence">2. The app and Apple&apos;s licence</h2>
    <p>The app is licensed, not sold, to you. Your licence to use the app is Apple&apos;s <a href={APPLE_EULA} target="_blank" rel="noreferrer">Licensed Application End User License Agreement</a> (the &ldquo;Standard EULA&rdquo;), between you and us. These terms add to the Standard EULA; where the two conflict about your licence to use the app, the Standard EULA wins.</p>
    <p>As the Standard EULA says, Apple is not a party to these terms, is not responsible for the app or its content, and has no obligation to provide support for it. Apple and its subsidiaries are third-party beneficiaries of the Standard EULA and may enforce it against you.</p>

    <h2 id="beta">3. Beta software</h2>
    <p>Pythilo is in beta and offered through Apple&apos;s TestFlight. Apple&apos;s TestFlight terms also apply while you test it. Beta builds are pre-release: they may contain bugs, change or remove features, lose data, and stop working when a build expires. Keep copies of work that matters, for example by committing and pushing it with Git or copying it out with the Files app. Feedback you send us may be used to improve Pythilo without obligation to you.</p>

    <h2 id="price">4. Price and payment</h2>
    <p>Pythilo is free while it is in beta. The planned App Store price is {PRICE}, as a one-time purchase for the full app, with local pricing and taxes shown by Apple. Any purchase will be made through the App Store and handled by Apple under its terms, including refunds. We will state any price on the <Link href="/pricing/">Pricing</Link> page and in the App Store before you pay. The website is free.</p>

    <h2 id="services">5. The website and shared rooms</h2>
    <p>The website, its in-browser lessons and playground, the room relay and the Pythilo MCP bridge are offered free of charge, as they are, and may change or stop at any time. Rooms are temporary by design: they last only as long as the owner chose, at most 24 hours, are kept only in the relay&apos;s memory, and end if the relay restarts. Do not use rooms to store anything; keep your own copy. We may limit how many rooms, participants and how much data a room or a network may use, and we may end rooms that break these terms.</p>

    <h2 id="your-content">6. Your code and content</h2>
    <p>Your code, files and other content are yours. We do not claim any rights in them. Content in the app stays on your device; content in a room is encrypted so that we cannot read it, and we need no licence to it beyond carrying the encrypted data to the people you share it with. When you share a room, you decide who gets the link and what they may do; you are responsible for having the right to share what you share, and for what you let others do on your device.</p>

    <h2 id="running-code">7. Code you run</h2>
    <p>Pythilo runs code you write, install or receive. You are responsible for the code you run and its effects, including code installed with pip or npm, code from Git repositories, code from rooms, and code an AI client writes or runs with your permission. All projects in the app share one Python process; switching projects is not a security boundary. Only run code you trust, and review what others ask to run on your device before you allow it.</p>

    <h2 id="third-party">8. Third-party services and software</h2>
    <p>Some features connect to services we do not run, such as the Python Package Index, the npm registry, Git hosts and AI clients. Your use of them is governed by their terms, and we are not responsible for them, their content or their availability. Pythilo includes open-source software, which is licensed under its own terms; see <Link href="/legal/licenses/">Open-source licences</Link>. Nothing in these terms limits your rights under those licences.</p>

    <h2 id="acceptable-use">9. Acceptable use</h2>
    <p>You must follow our <Link href="/legal/acceptable-use/">Acceptable Use Policy</Link>, which covers shared rooms, the relay and the website. In short: nothing illegal, no malware or harmful code aimed at others, no abuse of people, and no attacks on, or misuse of, the service.</p>

    <h2 id="ip">10. Our rights</h2>
    <p>The app, the website, the course and lesson content, the labs, the design and the Pythilo name and logo belong to {OWNER}, apart from the open-source components, which belong to their authors. The app&apos;s source code is public to read, but no licence is granted to use, copy, modify or distribute it except as the law allows. You may use the lessons to learn, and quote short parts with attribution; do not copy or republish the courses as a whole or in substantial part. These terms do not give you any right to use our name or logo.</p>

    <h2 id="learning">11. Lessons are for learning</h2>
    <p>Lessons, examples, checks and labs are educational. We work to make them correct, but they may contain mistakes and are not professional advice. Timings in the labs are measurements on your device, not guarantees about an algorithm. Check anything before you rely on it in production.</p>

    <h2 id="warranty">12. No warranty</h2>
    <p>To the fullest extent the law allows, Pythilo, the website and all services are provided &ldquo;as is&rdquo; and &ldquo;as available&rdquo;, without warranties of any kind, express or implied, including fitness for a particular purpose, accuracy and non-infringement, and without any promise that they will be uninterrupted, secure or free of errors. If the app fails to conform to any warranty that applies by law, you may notify Apple as described in the Standard EULA.</p>

    <h2 id="liability">13. Limitation of liability</h2>
    <p>To the fullest extent the law allows, we are not liable for indirect, incidental, special, consequential or punitive damages, or for loss of data, code, profits or business, arising from your use of, or inability to use, Pythilo, the website or any service, including from code you run and content others share with you. Where liability cannot be excluded, our total liability is limited to the amount you paid us for the app in the twelve months before the claim.</p>
    <p>Nothing in these terms limits liability that cannot be limited by law, such as for death or personal injury caused by negligence, or for fraud, and nothing affects the rights you have as a consumer under the mandatory laws of the country where you live.</p>

    <h2 id="ending">14. Suspension and ending</h2>
    <p>You can stop using Pythilo at any time by deleting the app and leaving the website. We may end rooms, limit access to the relay or website, or stop offering a service, in particular if you break these terms or to protect others. Sections 6 to 13 and 16 continue to apply after you stop.</p>

    <h2 id="changes">15. Changes</h2>
    <p>We may update these terms as Pythilo changes. We will post the new terms here with a new date before they take effect. If a change materially reduces your rights, we will also say so in the app or on the website. If you keep using Pythilo after the change, the new terms apply; if you do not agree, stop using it.</p>

    <h2 id="law">16. Governing law and disputes</h2>
    <p>{GOVERNING_LAW ? <>These terms are governed by the laws of {GOVERNING_LAW}, without regard to its conflict-of-laws rules. </> : null}If you are a consumer, you keep the protection of the mandatory laws of the country where you live and may also bring proceedings there. Before going to court, please contact us so we can try to resolve the issue informally.</p>
    <p>If any part of these terms is found unenforceable, the rest stays in effect. These terms, the Standard EULA and the policies they link to are the whole agreement between you and us about Pythilo.</p>

    <h2 id="contact">17. Contact</h2>
    <p>{OWNER}. Contact: <ContactEmail />. See <Link href="/support/">Support</Link> for help with the app.</p>
  </>;
}
