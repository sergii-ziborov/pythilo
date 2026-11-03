import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { aiClients, setupCommand, type AIClient } from "@/lib/playground-handoff";

export const metadata: Metadata = { title: "Connect an AI client", description: "Let Claude Code, Claude Desktop or Codex join a Pythilo room through the Pythilo MCP bridge." };

export default function ConnectAIPage() {
  return <>
    <SiteHeader current="ai" />
    <main className="page">
      <article className="prose">
        <h1>Connect an AI client</h1>
        <p>The Pythilo MCP bridge lets an AI client you run yourself join a room as a participant. It reads and edits the room&apos;s files like any other participant, and it can ask a device in the room to run code. That device asks its owner every time; the relay never runs code.</p>
        <h2>1 · Add Pythilo once</h2>
        {(Object.keys(aiClients) as AIClient[]).map(client => <div key={client}><p><strong>{aiClients[client]}</strong></p><pre><code>{setupCommand(client)}</code></pre></div>)}
        <p>The <code>pythilo</code> package is not on npm yet. Until it is, build <code>sdk/</code> in a checkout of the repository and point the client at it:</p>
        <pre><code>{setupCommand("claude-code", "<path>")}</code></pre>
        <p>Creating a room from the client needs the relay origin in <code>PYTHILO_RELAY</code>. Joining needs nothing more: a room link carries its origin.</p>
        <h2>2 · Hand it a room</h2>
        <p>Open the <Link href="/playground/">playground</Link>, choose <strong>Connect AI</strong> and copy the message. It holds the room link with its key, so paste it only into the client you mean. Choose <strong>Only read</strong> to hand over a link that cannot edit.</p>
        <h2>3 · Running code</h2>
        <p>The client lists the devices that can run Python in the room: a browser with the room open, or the Pythilo app on an iPhone or iPad. When it asks one to check, run or test, that device shows the request and its owner allows it once or for up to ten minutes. Each result says where it ran, on which Python and for which revision of the source.</p>
      </article>
    </main>
    <SiteFooter />
  </>;
}
