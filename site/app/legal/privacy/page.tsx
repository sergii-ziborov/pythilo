import type { Metadata } from "next";
import Link from "next/link";
import { Table, Toc } from "@/components/guide/doc";
import { ContactEmail } from "@/components/site/placeholder";
import { LEGAL_UPDATED, LOG_RETENTION, OWNER, formatDay } from "@/lib/site-info";

export const metadata: Metadata = { title: "Privacy Policy", description: "How the Pythilo app for iPhone and iPad and the pythilo.com website handle your data: no account, no analytics, no ads, and end-to-end encrypted rooms." };

export default function PrivacyPage() {
  return <>
    <header>
      <span className="label">Legal</span>
      <h1>Privacy Policy</h1>
      <p>Pythilo has no account, no analytics, no advertising and no tracking, in the app or on this website. Your projects stay on your device. This policy explains, in detail, the few cases where data leaves it.</p>
      <p className="updated">Last updated {formatDay(LEGAL_UPDATED)}</p>
    </header>
    <Toc items={[["who", "Who we are"], ["summary", "Summary"], ["app-device", "App: on your device"], ["app-network", "App: when it uses the network"], ["rooms", "Shared rooms and the relay"], ["mcp", "AI clients on your network"], ["permissions", "App permissions"], ["apple", "Apple, TestFlight and the App Store"], ["website", "The website"], ["browser-storage", "Website: storage in your browser"], ["logs", "Website: server logs"], ["bases", "Legal bases"], ["sharing", "Who we share data with"], ["retention", "How long we keep data"], ["rights", "Your rights"], ["children", "Children"], ["security", "Security"], ["changes", "Changes"], ["contact", "Contact"]]} />

    <h2 id="who">Who we are</h2>
    <p>Pythilo, the app for iPhone and iPad, and the website at pythilo.com are made and run by {OWNER} (&ldquo;we&rdquo;, &ldquo;us&rdquo;). For the few personal data described here, we are the controller. You can reach us at <ContactEmail />.</p>

    <h2 id="summary">Summary</h2>
    <ul>
      <li><strong>No account, no analytics, no ads, no tracking.</strong> Neither the app nor the website contains analytics, advertising, crash-reporting or tracking code, and neither sets cookies.</li>
      <li><strong>Your code stays on your device.</strong> Pythilo runs Python on the device. Your projects, lesson progress and settings are stored there and never sent to us.</li>
      <li><strong>The network is used when you ask for it</strong>: installing packages, Git, code you run yourself, shared rooms and connecting an AI client.</li>
      <li><strong>Shared rooms are end-to-end encrypted.</strong> Our relay sees encrypted text and the technical data needed to deliver it, keeps it in memory only, and forgets it when the room closes.</li>
      <li><strong>The website&apos;s web server keeps standard access logs</strong> for its pages (not for rooms), to run and protect the site.</li>
    </ul>

    <h2 id="app-device">App: data on your device</h2>
    <p>The app stores the following on your device only. We do not receive any of it.</p>
    <Table head={["What", "Where it is kept"]} rows={[
      ["Your projects, including files from rooms you joined and packages you installed", "The app's Documents folder, visible in the Files app"],
      ["Lesson progress, your code for each lesson, and your lab code", "The app's private storage"],
      ["Settings, including the Git name and email and the room name you enter", "The app's private storage"],
      ["Git access tokens for HTTPS remotes", "The iOS Keychain, on this device only, available only while it is unlocked, not synced"],
      ["Temporary files for running code and rooms", "The app's caches, deleted when no longer needed"],
    ]} />
    <p>If you back up your device with iCloud or a computer, the backup includes the app&apos;s data under Apple&apos;s or your own backup terms. Deleting the app deletes its data from the device. Pythilo does not use iCloud or any server of its own to store your data.</p>

    <h2 id="app-network">App: when it uses the network</h2>
    <p>Installed courses, Lab topics, packages and training assets work offline. Pythilo uses the network for the actions below, started by you, including dependency downloads only after you explicitly tap Download. The service receives ordinary connection information such as your IP address and the requested resource, plus what the action needs, and handles it under its own privacy policy.</p>
    <Table head={["You…", "The app contacts", "What is sent"]} rows={[
      ["download a course, Lab topic, Python package pack or training dataset", "pythilo.com", "Requests for the selected archive. Your project code, lesson drafts and progress are not uploaded"],
      ["explicitly download pretrained-transformer model weights", "Hugging Face (huggingface.co and its model-delivery CDN)", "Requests for the pinned public BERT weight file. Project code, training results and dataset rows stay on your device"],
      [<>install a Python package (<code>pip</code>, the Packages screen)</>, "The Python Package Index (pypi.org and files.pythonhosted.org), or an index you name", "Requests for the packages and their metadata"],
      [<>install a JavaScript package (<code>npm install</code>)</>, "The npm registry (registry.npmjs.org)", "Requests for the packages and their metadata"],
      ["clone, fetch, pull or push with Git", "The Git server whose address you entered", "Repository data, your commits (which carry the Git name and email you set), and, for private repositories, the username and token you saved for that host"],
      ["run your own code or use the terminal to fetch something", "Whatever your code or command contacts", "Whatever your code or command sends"],
      ["open your local site in the web preview", "Your server on this device; the page may load resources from the internet (for example, FastAPI's /docs loads Swagger UI from a CDN)", "Ordinary web requests made by the page"],
      ["share a project as a link", "Nothing: the files are packed into the link itself, after the #, which browsers do not send to servers. Whoever you send the link to can read the files", "Nothing, until you send the link to someone"],
      ["create or join a shared room", "Our relay at pythilo.com", <>Encrypted room data. See <a href="#rooms">Shared rooms</a></>],
      ["connect an AI client", "Nothing on the internet; the client on your computer connects to the device over your local network", <>See <a href="#mcp">AI clients</a></>],
    ]} />

    <h2 id="rooms">Shared rooms and the relay</h2>
    <p>A shared room lets you work on a project with other people, browsers or AI clients. Room data passes through our relay, which is part of the pythilo.com website.</p>
    <h3>What is end-to-end encrypted</h3>
    <p>File names and contents, edits, your display name, cursors and selections, which devices can run code, run requests and their results (output, errors, timings, and the device and Python version they ran on) are encrypted on your device with AES-256-GCM before they are sent. The key is in the part of the room link after <code>#</code>, which browsers and the app never send to a server. We cannot read this data.</p>
    <h3>What the relay does see</h3>
    <ul>
      <li>The room&apos;s random id, when it was created and when it expires, and the size and timing of encrypted messages.</li>
      <li>Random ids for each connection and message, how many participants are connected, and access tokens (we store only their hashes).</li>
      <li>Your IP address, used while a request is handled. To limit abuse, the relay keeps a keyed hash of the IP address for as long as a room you created lasts, and a hash of it for about a minute to count how many rooms it creates. These stay in memory.</li>
    </ul>
    <h3>How long</h3>
    <p>Rooms are held in the relay&apos;s memory only, never written to disk, and deleted when the owner ends them or their time runs out (between one and 24 hours, as the owner chose). A restart of the server deletes every room.</p>
    <h3>What other participants see</h3>
    <p>Everyone in a room can decrypt it. They see the files, your edits and cursor, your display name (the room name from Settings, else the first word of your Git name, else the device&apos;s name), your device model and Python version if your device can run code, and the results of code your device ran for them. Joining copies the room&apos;s files to each participant&apos;s device, where they stay after the room ends. Share links only with people you trust.</p>

    <h2 id="mcp">AI clients on your network</h2>
    <p>When you connect an AI client (such as Claude Code or Codex) from the Playground tab, the app runs a small server on your device that the client on your computer reaches over your local network. Nothing passes through our servers. While sharing is on, the client can, within the permissions you set, read the shared project&apos;s files and problems, edit them, run them, install packages and use Git; it receives your project name, device model, Python version, file contents, run output, Git status and diff, and the remote&apos;s address. It never receives your Git tokens.</p>
    <p>The connection uses a fresh token each time and ends when you stop sharing. It is unencrypted HTTP on your local network, so use it on networks you trust. <strong>The AI client and its provider handle what they receive under their own terms and privacy policies</strong>, which may include sending your code to the provider&apos;s servers.</p>

    <h2 id="permissions">App permissions</h2>
    <p>Pythilo asks for one permission: <strong>Local Network</strong>, used to let an AI client on your network connect to the device and to open local web servers. It does not ask for, or use, your location, contacts, photos, camera, microphone, health data or advertising identifier.</p>

    <h2 id="apple">Apple, TestFlight and the App Store</h2>
    <p>Pythilo is distributed by Apple. Apple processes your data under its own privacy policy when you download apps, buy them, or use TestFlight. If you take part in the TestFlight beta, Apple shares with us what TestFlight provides to developers, such as the name and email address you were invited with (for invited testers), the build and device you use, crash reports and usage sessions, and any feedback and screenshots you choose to send. If you allow your device to share analytics with app developers, Apple may also give us aggregated usage and crash data. We use this only to fix and improve Pythilo.</p>

    <h2 id="website">The website</h2>
    <p>pythilo.com offers lessons, interactive labs and a playground that run Python in your browser with Pyodide, the room relay, the guide and this information. It has no account, no cookies, no analytics, no advertising, and loads no fonts, scripts or images from other sites: everything, including Pyodide, is served from pythilo.com. Python you run on the site runs in your browser, not on our server; like any program it can make its own network requests.</p>
    <p>The site is served from a server we rent from Hetzner Online GmbH. Its domain&apos;s DNS is hosted by Vercel Inc. Support, privacy and security emails are forwarded by Forward Email to our Gmail inbox; Forward Email and Google process messages you choose to send under their own policies.</p>

    <h2 id="browser-storage">Website: storage in your browser</h2>
    <p>The site saves the following in your browser&apos;s own storage so your work survives a reload. It is not sent to us, and you can delete it at any time by clearing this site&apos;s data in your browser.</p>
    <Table head={["Storage", "What"]} rows={[
      ["Local storage", "Lesson and lab progress and your code for each lesson or lab; your playground display name; whether to keep playground drafts"],
      ["IndexedDB", "Up to 32 playground drafts (source code, name, date). Room keys and permissions are never written here"],
      ["Session storage (until the tab closes)", "Owner and view tokens for rooms you created, and which folders you opened"],
    ]} />
    <p>A room link contains its key. In a browser, the full link sits in the address bar and your history; anyone who gets it can join the room until it ends.</p>

    <h2 id="logs">Website: server logs</h2>
    <p>The web server records a standard access log for page and file requests: your IP address, the date and time, the page path requested, the response status and size, request duration and your browser&apos;s user-agent string. Query strings and referring pages are not stored. Requests to the room relay and to room pages are <strong>not</strong> written to the access log. An error log records problems with requests, which can include the IP address. We use logs only to keep the site running and secure, and we do not combine them with other data. Logs are kept for {LOG_RETENTION}.</p>

    <h2 id="bases">Legal bases</h2>
    <p>Where the EU or UK General Data Protection Regulation applies, we process the data described here because it is necessary to provide what you ask for (delivering rooms you create or join, Article 6(1)(b)), and for our legitimate interests in running a secure and reliable service and preventing abuse (server logs and rate limits, Article 6(1)(f)). Data shared with us through TestFlight is processed for our legitimate interest in fixing and improving the app.</p>

    <h2 id="sharing">Who we share data with</h2>
    <p>We do not sell or rent personal data, and we do not share it for advertising. Our hosting provider (Hetzner Online GmbH) and DNS provider (Vercel Inc.) process the technical data needed to run the website and relay. If you email us, Forward Email delivers the message to our Gmail inbox, operated by Google; do not include secrets or private room links unless needed for your request. We may disclose information if the law requires it, and only what we hold, which for rooms is encrypted text we cannot read.</p>

    <h2 id="retention">How long we keep data</h2>
    <ul>
      <li>Room data: in memory until the room ends, at most 24 hours.</li>
      <li>IP-based abuse limits: in memory for the lifetime of the room, or about a minute.</li>
      <li>Server logs: see <a href="#logs">Server logs</a>.</li>
      <li>TestFlight information: for as long as Apple makes it available to us.</li>
    </ul>

    <h2 id="rights">Your rights</h2>
    <p>Depending on where you live, you may have the right to access, correct or delete personal data about you, to object to or restrict its processing, to data portability, and to complain to a data protection authority. Most of the data described here never reaches us, and what does (server logs, rate-limit hashes) does not identify you by name. To make a request, contact us at <ContactEmail />. Data stored on your device or in your browser is under your control: delete it in the app, in the Files app, by deleting the app, or by clearing the site&apos;s data in your browser.</p>

    <h2 id="children">Children</h2>
    <p>Pythilo is a tool for learning and writing code and is not directed at young children. Because neither the app nor the website collects personal data for us, we do not knowingly collect personal data from children. If you are below the age at which you can consent to online services in your country, use Pythilo with a parent&apos;s or guardian&apos;s permission, and do not join rooms with people you do not know.</p>

    <h2 id="security">Security</h2>
    <p>The website and relay are served only over HTTPS. Rooms are end-to-end encrypted, access tokens are stored as hashes, and the relay keeps nothing on disk. Git tokens stay in the iOS Keychain. Code you run in Pythilo runs with the app&apos;s access to your projects; only run code you trust (see <Link href="/guide/limits/">What runs on iOS</Link>).</p>

    <h2 id="changes">Changes to this policy</h2>
    <p>If the app or website starts handling data differently, we will update this policy before the change takes effect and change the date at the top.</p>

    <h2 id="contact">Contact</h2>
    <p>Questions or requests about privacy: <ContactEmail />. See also the <Link href="/legal/terms/">Terms of Use</Link> and <Link href="/support/">Support</Link>.</p>
  </>;
}
