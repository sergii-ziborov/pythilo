import type { Metadata } from "next";
import Link from "next/link";
import { OWNER } from "@/lib/site-info";

export const metadata: Metadata = { title: "Legal", description: "Terms of Use, Privacy Policy, Acceptable Use Policy and open-source licences for Pythilo and pythilo.com." };

const PAGES: [string, string, string][] = [
  ["/legal/terms/", "Terms of Use", "The agreement for the app and the website, with Apple's Standard EULA for the app licence."],
  ["/legal/privacy/", "Privacy Policy", "No account, no analytics, no ads. What leaves your device, and when."],
  ["/legal/acceptable-use/", "Acceptable Use Policy", "Rules for shared rooms, running code for others, and the relay."],
  ["/legal/licenses/", "Open-source licences", "CPython, PyTorch, libgit2, Pyodide and everything else Pythilo builds on."],
  ["/support/", "Support and contact", "Help with the app, reporting a problem, and how to reach us."],
];

export default function LegalIndex() {
  return <>
    <header>
      <span className="label">Legal</span>
      <h1>Legal</h1>
      <p>Pythilo for iPhone and iPad and the website at pythilo.com are made by {OWNER}. These pages cover both.</p>
    </header>
    <div className="card-grid two">
      {PAGES.map(([href, title, text]) => <Link key={href} href={href} className="card"><h3>{title}</h3><p>{text}</p></Link>)}
    </div>
  </>;
}
