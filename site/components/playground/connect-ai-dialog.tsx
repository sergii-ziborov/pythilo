"use client";

import { useState } from "react";
import { playgroundLink, type CreatedPlayground, type PlaygroundLink } from "@/lib/playground-session";
import { aiClients, aiHandoffText, maskedLink, setupCommand, type AIClient } from "@/lib/playground-handoff";

type Props = {
  link: PlaygroundLink | null; created: CreatedPlayground | null; projectName: string; sharing: boolean;
  share: () => Promise<PlaygroundLink>; lifetime: number; setLifetime: (seconds: number) => void; onClose: () => void;
};

export function ConnectAIDialog({ link, created, projectName, sharing, share, lifetime, setLifetime, onClose }: Props) {
  const [client, setClient] = useState<AIClient>("claude-code"), [mode, setMode] = useState<"edit" | "view">(link?.mode === "view" ? "view" : "edit");
  const [checkout, setCheckout] = useState(false), [path, setPath] = useState("~/dev/pythilo"), [status, setStatus] = useState("");
  const canView = !link || link.mode === "view" || !!created;
  const command = setupCommand(client, checkout ? path.trim() || "~/dev/pythilo" : undefined);
  const access = (room: PlaygroundLink) => mode === "view" && room.mode !== "view" ? (created?.view ?? (room as Partial<CreatedPlayground>).view) : room.access;
  const preview = link ? maskedLink(playgroundLink({ ...link, mode })) : `${typeof location === "undefined" ? "" : location.origin}/playground/room/[ROOM]/#key=[KEY]&access=[ACCESS]&mode=${mode}`;
  const copy = async (text: string, done: string) => { try { await navigator.clipboard.writeText(text); setStatus(done); } catch { setStatus("Select and copy the text above."); } };
  const copyMessage = async () => {
    setStatus("");
    try {
      const room = await share(), token = access(room);
      if (!token) { setStatus("Only the room's creator has its read-only link. Hand off with edit access, or ask them."); return; }
      await copy(aiHandoffText(playgroundLink({ ...room, access: token, mode }), mode, room.expiresAt), "Message copied. It holds the room's key, so paste it only into the client you mean.");
    } catch (error) { setStatus(error instanceof Error ? error.message : String(error)); }
  };

  return <div className="connect">
    <div className="dialog-heading">
      <div><h2 id="dialog-title">Connect an AI client to this room</h2><p>It sees {projectName || "this project"} and nothing else, until the room closes or you end it.</p></div>
      <button type="button" className="icon-button" aria-label="Close" onClick={onClose}><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg></button>
    </div>
    <div role="radiogroup" aria-label="Client" className="segmented">
      {(Object.keys(aiClients) as AIClient[]).map(key => <button key={key} type="button" role="radio" aria-checked={client === key} onClick={() => setClient(key)}>{aiClients[key]}</button>)}
    </div>
    <section className="connect-step">
      <div className="label">1 · Add Pythilo once</div>
      <pre>{command}</pre>
      <label className="check-row"><input type="checkbox" checked={checkout} onChange={event => setCheckout(event.target.checked)} />From a checkout</label>
      {checkout ? <label className="field">Folder that holds <code>sdk/</code><input value={path} onChange={event => setPath(event.target.value)} spellCheck={false} autoCapitalize="off" /></label> : null}
      <p className="field-note">{checkout ? "Run npm ci --ignore-scripts and npm run build in sdk/. Use the absolute folder path. Node.js 22 or newer is required." : <>Requires Node.js 22 or newer. Downloads the official Pythilo bridge from pythilo.com.</>}{client === "claude-desktop" ? " Add this to claude_desktop_config.json and restart Claude Desktop." : ""}</p>
    </section>
    <section className="connect-step">
      <div className="label">2 · Paste this into the chat</div>
      <pre className="connect-message">{`Join my Pythilo room with pythilo_connect:\n${preview}`}</pre>
      <div role="radiogroup" aria-label="What the client may do" className="chip-row">
        <button type="button" role="radio" aria-checked={mode === "edit"} disabled={link?.mode === "view"} onClick={() => setMode("edit")}>It may edit</button>
        <button type="button" role="radio" aria-checked={mode === "view"} disabled={!canView} onClick={() => setMode("view")}>Only read</button>
      </div>
      {!link ? <label className="field inline">This creates a room that closes after<select value={lifetime} onChange={event => setLifetime(Number(event.target.value))}><option value={3600}>1 hour</option><option value={14400}>4 hours</option><option value={43200}>12 hours</option><option value={86400}>24 hours</option></select></label> : null}
    </section>
    <section className="connect-note">The link is the key: anyone holding it can {mode === "edit" ? "edit" : "read"} until the room closes. Running code is never part of it. The client asks a device in the room, and that device asks its owner.</section>
    {status ? <p className="field-note" role="status">{status}</p> : null}
    <div className="dialog-actions">
      <button type="button" className="pill-button" onClick={() => void copy(command, "Command copied.")}>Copy command</button>
      <button type="button" className="pill-button primary" disabled={sharing} onClick={() => void copyMessage()}>{link ? "Copy message" : sharing ? "Creating room…" : "Create room and copy message"}</button>
    </div>
  </div>;
}
