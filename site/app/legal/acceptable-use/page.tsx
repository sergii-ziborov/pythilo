import type { Metadata } from "next";
import Link from "next/link";
import { ContactEmail } from "@/components/site/placeholder";
import { LEGAL_UPDATED, formatDay } from "@/lib/site-info";

export const metadata: Metadata = { title: "Acceptable Use Policy", description: "Rules for Pythilo's shared rooms, the room relay, the playground and the website." };

export default function AcceptableUsePage() {
  return <>
    <header>
      <span className="label">Legal</span>
      <h1>Acceptable Use Policy</h1>
      <p>Shared rooms let people edit a project together and, with permission, run code on each other&apos;s devices. That only works if everyone plays fair. These rules apply to rooms, the relay, the playground, the Pythilo MCP bridge and the rest of the website, and are part of the <Link href="/legal/terms/">Terms of Use</Link>.</p>
      <p className="updated">Last updated {formatDay(LEGAL_UPDATED)}</p>
    </header>

    <h2 id="content">Do not share</h2>
    <ul>
      <li>Anything illegal where you or the other participants are, or anything that infringes someone else&apos;s copyright, trade secrets or other rights.</li>
      <li>Malware, or code meant to damage, spy on, or take control of a device, its data or its network, including code that tries to read files outside the shared project or to steal credentials.</li>
      <li>Other people&apos;s personal data, passwords, API keys or tokens without their permission. Remove secrets from a project before you share it.</li>
      <li>Content that harasses, threatens, or sexually exploits anyone, or that promotes violence or hatred.</li>
    </ul>

    <h2 id="running">Running code on someone else&apos;s device</h2>
    <ul>
      <li>Ask to run only code you would be comfortable running yourself, and say what it does.</li>
      <li>Do not try to trick someone into allowing a run, or hide what a run does.</li>
      <li>Do not use another person&apos;s device for work they did not agree to, such as mining, scanning networks or sending traffic to third parties.</li>
    </ul>

    <h2 id="service">Do not misuse the service</h2>
    <ul>
      <li>Do not attack, overload, probe or scan the relay or website, or try to get around its limits, for example by spreading load across many addresses.</li>
      <li>Do not use rooms as file storage, a content delivery network, or a channel for anything other than working on code together.</li>
      <li>Do not access rooms you were not given a link to, or try to break their encryption.</li>
      <li>Do not impersonate other people, or Pythilo.</li>
      <li>Do not use automated clients against the relay other than the Pythilo app, the website and the Pythilo MCP bridge, except reasonable use of your own AI client through the bridge.</li>
    </ul>

    <h2 id="safety">Staying safe</h2>
    <ul>
      <li>A room link is the key to the room. Send it only to the people you mean, never post it publicly, and end the room when you are done.</li>
      <li>Keep <strong>Ask each time</strong> for running code unless you trust everyone in the room, and read a request before you allow it.</li>
      <li>Use <strong>Only view</strong> links when people only need to look.</li>
    </ul>

    <h2 id="enforcement">What we can do</h2>
    <p>Rooms are end-to-end encrypted, so we cannot see what is in them and do not monitor them. We act on what we can see and on reports: we may end rooms, limit or block access to the relay from a network, and, where the law requires it, cooperate with authorities with the little data we hold (see the <Link href="/legal/privacy/">Privacy Policy</Link>).</p>

    <h2 id="report">Report abuse</h2>
    <p>If someone uses a room or the site against these rules, or you found a security problem, write to <ContactEmail />. Include the room link only if you are comfortable sharing its contents with us; without it we cannot read the room.</p>
  </>;
}
