"use client";

import { useMemo, useState, type ReactNode } from "react";
import type { PlaygroundDocument } from "@/lib/playground-document";
import { appShareLink, shareLink, SHARE_LINK_LIMITS } from "@/lib/playground-share-link";
import { playgroundLink, type CreatedPlayground, type PlaygroundLink } from "@/lib/playground-session";
import { Icon } from "./icons";

export const lifetimes: [number, string][] = [[3600, "1 hour"], [14400, "4 hours"], [43200, "12 hours"], [86400, "24 hours"]];

type Props = {
  source: PlaygroundDocument;
  /** The live room this page is in, if any. */
  link: PlaygroundLink | null; created: CreatedPlayground | null;
  expired: boolean; closes: string; expiresAt: number | null;
  lifetime: number; setLifetime: (seconds: number) => void; sharing: boolean;
  onStartRoom: () => Promise<unknown>;
  onOpenRoomInApp: () => void;
  onEndRoom: () => void;
  onCopyToLocal: () => void;
  onDownload: () => void;
  displayName: string; namePlaceholder: string; onRename: (name: string) => void;
  /** The room's "run code here for others" panel. */
  permissions: ReactNode;
  onClose: () => void;
};

const canNativeShare = () => typeof navigator !== "undefined" && typeof navigator.share === "function" && matchMedia("(pointer: coarse)").matches;
const isAppleMobile = () => typeof navigator !== "undefined" && (/iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1));

/** Two ways to share: a link that carries a copy of the code, and a live room. */
export function ShareDialog(props: Props) {
  const { source, link, created, expired, closes, expiresAt, lifetime, setLifetime, sharing, onStartRoom, onOpenRoomInApp, onEndRoom, onCopyToLocal, onDownload, displayName, namePlaceholder, onRename, permissions, onClose } = props;
  const [status, setStatus] = useState(""), [roomStatus, setRoomStatus] = useState("");
  const code = useMemo(() => {
    try { return { url: shareLink(source, location.origin), app: appShareLink(source), error: "" }; }
    catch (error) { return { url: "", app: "", error: error instanceof Error ? error.message : String(error) }; }
  }, [source]);
  const fileCount = Object.keys(source.files).length;
  const copy = (text: string, done: string, set = setStatus) => void navigator.clipboard.writeText(text).then(() => set(done), () => set("Select the link and copy it."));
  const roomURL = link ? playgroundLink(link) : "";
  const viewURL = created ? playgroundLink({ ...created, access: created.view, mode: "view" }) : "";

  return <div className="pg-share">
    <div className="dialog-heading"><h2 id="dialog-title">Share</h2><button type="button" className="icon-button" aria-label="Close" onClick={onClose}><Icon name="close" /></button></div>

    <section className="pg-share-section" aria-labelledby="pg-share-copy">
      <div className="pg-share-title"><Icon name="link" /><h3 id="pg-share-copy">Link to this code</h3></div>
      <p className="field-note">Anyone who opens it gets their own copy of {fileCount === 1 ? "this file" : `these ${fileCount} files`}, as they are now. The code travels inside the link, so nothing is uploaded and it never expires.</p>
      {code.error ? <p className="field-problem" role="alert">{code.error}</p> : <>
        <div className="pg-link-row">
          <input className="pg-link-field" readOnly value={code.url} aria-label="Link to this code" onFocus={event => event.target.select()} spellCheck={false} />
          <button type="button" className="pill-button primary" onClick={() => copy(code.url, "Link copied.")}><Icon name="copy" />Copy link</button>
        </div>
        <div className="pg-share-actions">
          {canNativeShare() ? <button type="button" className="pill-button" onClick={() => void navigator.share({ title: source.name, url: code.url }).catch(() => {})}><Icon name="share" />Share…</button> : null}
          <a className="pill-button" href={code.app} onClick={() => setTimeout(() => { if (document.visibilityState === "visible") setStatus(isAppleMobile() ? "If Pythilo did not open, install it from the App Store, then try again." : "Open this on an iPhone or iPad with Pythilo installed."); }, 1500)}><Icon name="phone" />Open in the Pythilo app</a>
        </div>
        <p className="field-note">{code.url.length.toLocaleString()} characters{code.url.length > SHARE_LINK_LIMITS.comfortableChars ? " · long links can break in some chat and mail apps; a live room or a ZIP is safer." : ""}</p>
      </>}
      {status ? <p className="field-note pg-share-status" role="status">{status}</p> : null}
    </section>

    <section className="pg-share-section" aria-labelledby="pg-share-room">
      <div className="pg-share-title"><Icon name="people" /><h3 id="pg-share-room">{link ? "Live room" : "Edit together"}</h3>{link ? <span className={expired ? "pg-chip pg-chip-stop" : "pg-chip pg-chip-live"}>{expired ? "Closed" : "Live"}</span> : null}</div>
      {!link ? <>
        <p className="field-note">A live room syncs every keystroke between up to four people, AI clients or the Pythilo app on iPhone, which can also run the code. It is end-to-end encrypted: the key is in the link, and the relay only holds ciphertext.</p>
        <fieldset className="field"><legend>Closes after</legend><div className="chip-row" role="radiogroup" aria-label="Closes after">{lifetimes.map(([seconds, label]) => <button key={seconds} type="button" role="radio" aria-checked={lifetime === seconds} onClick={() => setLifetime(seconds)}>{label}</button>)}</div></fieldset>
        <div className="pg-share-actions"><button type="button" className="pill-button" disabled={sharing || expired} onClick={() => { setRoomStatus(""); void onStartRoom().catch(error => setRoomStatus(error instanceof Error ? error.message : String(error))); }}><Icon name="people" />{sharing ? "Encrypting…" : "Start a live room"}</button></div>
      </> : <>
        <p className="field-note">{expired ? "This room has closed. Your code is still here: download it or copy it to a local draft." : <>Anyone with the room link can edit with you. It {closes}{expiresAt ? ` (${new Date(expiresAt).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })})` : ""}; opening it does not renew it.</>}</p>
        {!expired ? <>
          <div className="pg-link-row">
            <input className="pg-link-field" readOnly value={roomURL} aria-label={link.mode === "view" ? "View-only room link" : "Room link"} onFocus={event => event.target.select()} spellCheck={false} />
            <button type="button" className="pill-button primary" onClick={() => copy(roomURL, "Room link copied.", setRoomStatus)}><Icon name="copy" />Copy</button>
          </div>
          {viewURL ? <div className="pg-link-row">
            <input className="pg-link-field" readOnly value={viewURL} aria-label="View-only room link" onFocus={event => event.target.select()} spellCheck={false} />
            <button type="button" className="pill-button" onClick={() => copy(viewURL, "View-only link copied.", setRoomStatus)}><Icon name="copy" />View-only</button>
          </div> : null}
          <div className="pg-share-actions"><button type="button" className="pill-button" onClick={onOpenRoomInApp}><Icon name="phone" />Open room in the Pythilo app</button></div>
          <label className="field">Your name in this room<input value={displayName} maxLength={30} placeholder={namePlaceholder} onChange={event => onRename(event.target.value)} /></label>
          {permissions}
        </> : null}
        <div className="pg-share-actions">
          <button type="button" className="pill-button" onClick={onDownload}><Icon name="download" />Download ZIP</button>
          <button type="button" className="pill-button" onClick={onCopyToLocal}>Copy to a local draft</button>
          {created && !expired ? <button type="button" className="pill-button danger" onClick={onEndRoom}><Icon name="end" />End room for everyone</button> : null}
        </div>
      </>}
      {roomStatus ? <p className="field-note pg-share-status" role="status">{roomStatus}</p> : null}
    </section>
  </div>;
}
