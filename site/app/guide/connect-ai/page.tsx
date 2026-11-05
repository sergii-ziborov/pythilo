import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";

export const metadata: Metadata = { title: "Connect an AI client", description: "Let Claude Code, Codex or any MCP client work on one Pythilo project over your local network, with separate permissions for reading, editing, running, installing and committing." };

export default function Page() {
  return <>
    <GuideHeader slug="connect-ai" />
    <Toc items={[["two-ways", "Two ways to connect"], ["local", "On your network"], ["permissions", "What it may do"], ["requests", "Requests and activity"], ["stop", "Stop sharing"], ["room", "Through a room"], ["good-to-know", "Good to know"]]} />

    <h2 id="two-ways">Two ways to connect</h2>
    <ul>
      <li><strong>On your network</strong>: the AI client on your computer talks straight to Pythilo on your iPhone or iPad over the local network. No account, no cloud service, no relay.</li>
      <li><strong>Through a room</strong>: the client joins a <Link href="/guide/rooms/">shared room</Link> with the Pythilo MCP bridge, from anywhere.</li>
    </ul>

    <h2 id="local">On your network</h2>
    <p>Open <span className="ui">Playground</span> › <span className="ui">Manage connection</span> on the <span className="ui">AI client over MCP</span> card, or <span className="ui">⋯</span> › <span className="ui">Share with an AI client or person</span> › <span className="ui">Connect an AI client</span> in a project, and tap <span className="ui">Connect</span> beside the project to share. Pythilo starts a Model Context Protocol server on the device and shows the command to run on your computer, which must be on the same network:</p>
    <Table head={["Client", "What to do"]} rows={[
      [<strong key="c">Claude Code</strong>, <>Tap <span className="ui">Copy command</span> and run it. It looks like <code>claude mcp add --transport http pythilo http://192.168.1.20:18765/mcp --header &quot;Authorization: Bearer …&quot;</code></>],
      [<strong key="c">Codex</strong>, <>Run the copied <code>codex mcp add pythilo --url … --bearer-token-env-var PYTHILO_TOKEN</code> and set <code>PYTHILO_TOKEN</code> to the token shown.</>],
      [<strong key="c">Any other MCP client</strong>, "Streamable HTTP at the address shown, with the same bearer token."],
    ]} />
    <p>The first time, iOS asks whether Pythilo may find and connect to devices on your local network. Allow it, or the computer cannot reach the phone.</p>

    <h2 id="permissions">What it may do</h2>
    <p>Each permission is <span className="ui">Allowed</span>, <span className="ui">Ask each time</span> or <span className="ui">Not allowed</span>:</p>
    <Table head={["Permission", "Default"]} rows={[
      ["Read project files", "Allowed"], ["Edit files", "Allowed"], ["Run, test, debug", "Ask each time"], ["Install packages", "Ask each time"], ["Git commit", "Ask each time"], ["Git push", "Not allowed"],
    ]} />
    <p>The client sees one project only, and not its <code>.git</code>, <code>.pythilo</code> or <code>__pycache__</code> folders. Every write checks that the file has not changed underneath it. Your Git tokens are never shown to it; a permitted push uses them on the device.</p>

    <h2 id="requests">Requests and activity</h2>
    <p>When a permission is set to ask, a card says what the client wants to do, with <span className="ui">Deny</span> and <span className="ui">Allow once</span>. A request nobody answers is denied after two minutes. <span className="ui">Recent</span> lists what the client did.</p>

    <h2 id="stop">Stop sharing</h2>
    <p><span className="ui">Stop sharing</span> ends the connection and throws the token away; the next share makes a new one. Sharing another project, or closing Pythilo, also ends it. Keep Pythilo open while the client works: iOS pauses it in the background.</p>

    <h2 id="room">Through a room</h2>
    <p>For a client that is not on your network, share the project as a room and use <span className="ui">Connect AI</span> in the room. The client then needs the Pythilo MCP bridge; <Link href="/ai/">Connect AI</Link> on this site explains the setup. In a room, the client is a participant like any other and asks your device to run code under the room&apos;s rules.</p>

    <h2 id="good-to-know">Good to know</h2>
    <Note warn title="Your network, your client">
      <p>The local connection is plain HTTP on your network, protected by a token that changes every time you share. Use it on networks you trust, such as your home, not on public Wi-Fi.</p>
      <p>What the AI client does with your code is up to it and its provider&apos;s terms: Pythilo sends the project to the client you connect, and nowhere else.</p>
    </Note>
    <Pager slug="connect-ai" />
  </>;
}
