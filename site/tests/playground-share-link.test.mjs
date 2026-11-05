import { test } from "node:test";
import assert from "node:assert/strict";
import { deflateRawSync, inflateRawSync } from "node:zlib";
import { appShareLink, decodeSharePayload, encodeSharePayload, parseShareLink, sharePayloadFromHash, sharePayloadJSON, shareLink, SHARE_LINK_LIMITS } from "../lib/playground-share-link.ts";
import { newPlaygroundDocument } from "../lib/playground-document.ts";

const project = () => ({ schemaVersion: 1, name: "Café demo ☕", entryFile: "app/main.py", files: {
  "app/main.py": "from app.util import twice\nprint(twice('héllo 👋'))\n",
  "app/util.py": "def twice(text):\n    return text * 2\n",
  "app/__init__.py": "",
  "README.md": "# Demo\n\nQuotes \" and backslashes \\ and tabs\t survive.\n",
  "data/rows.csv": "a,b\n1,2\n",
} });
const raw = payload => JSON.parse(inflateRawSync(Buffer.from(payload, "base64url")).toString("utf8"));
const encodeRaw = value => deflateRawSync(Buffer.from(JSON.stringify(value), "utf8")).toString("base64url");

test("a share link round-trips every file, the name and the entry file", () => {
  const source = project(), link = shareLink(source, "https://pythilo.com");
  assert.match(link, /^https:\/\/pythilo\.com\/playground\/#code=[A-Za-z0-9_-]+$/);
  const opened = parseShareLink(new URL(link));
  assert.deepEqual({ ...opened.files }, source.files);
  assert.equal(opened.name, source.name);
  assert.equal(opened.entryFile, "app/main.py");
  assert.equal(opened.schemaVersion, 1);
});

test("the payload is plain raw DEFLATE of the documented JSON, so any zlib decodes it", () => {
  const payload = encodeSharePayload(project()), json = raw(payload);
  assert.deepEqual(Object.keys(json), ["v", "name", "main", "files"]);
  assert.equal(json.v, 1);
  assert.equal(json.main, "app/main.py");
  assert.deepEqual(Object.keys(json.files), Object.keys(project().files).sort(), "files are written in sorted order, so equal projects give equal links");
  assert.equal(payload.includes("="), false, "no padding");
  assert.equal(sharePayloadJSON(project()), JSON.stringify(json));
  assert.equal(encodeSharePayload(project()), payload, "deterministic");
});

test("links written by another client decode: padding, standard base64 and line breaks are accepted", () => {
  const value = { v: 1, name: "from swift", main: "main.py", files: { "main.py": "print('hi')\n" } };
  const urlSafe = encodeRaw(value), standard = Buffer.from(urlSafe, "base64url").toString("base64");
  for (const payload of [urlSafe, standard, standard.replace(/(.{10})/g, "$1\n")]) assert.equal(decodeSharePayload(payload).files["main.py"], "print('hi')\n");
});

test("missing name and main fall back to sensible defaults", () => {
  const opened = decodeSharePayload(encodeRaw({ v: 1, files: { "b.py": "", "a.py": "print(1)" } }));
  assert.equal(opened.name, "shared-project");
  assert.equal(opened.entryFile, "a.py");
  assert.equal(decodeSharePayload(encodeRaw({ v: 1, files: { "z.py": "", "main.py": "" } })).entryFile, "main.py");
});

test("damaged, future, oversized and unsafe links are refused with a reason", () => {
  const good = encodeSharePayload(newPlaygroundDocument());
  assert.throws(() => decodeSharePayload(good.slice(0, good.length - 6)), /cut short|damaged/);
  assert.throws(() => decodeSharePayload("not base64!"), /damaged/);
  assert.throws(() => decodeSharePayload(encodeRaw({ v: 2, files: { "main.py": "" } })), /newer Pythilo/);
  assert.throws(() => decodeSharePayload(encodeRaw([1, 2])), /damaged/);
  assert.throws(() => decodeSharePayload(encodeRaw({ v: 1, files: { "../etc/passwd.py": "" } })), /Unsupported source path/);
  assert.throws(() => decodeSharePayload(encodeRaw({ v: 1, files: { "notes.txt": "" } })), /entry file/);
  const bomb = deflateRawSync(Buffer.alloc(SHARE_LINK_LIMITS.inflatedBytes + 10, 32)).toString("base64url");
  assert.ok(bomb.length < 5000, "a tiny link");
  assert.throws(() => decodeSharePayload(bomb), /more than a Playground/);
});

test("a project too large for a link is refused when encoding", () => {
  const files = {};
  // Random text does not compress; 15 files of 8 KiB stay inside the project limit.
  for (let i = 0; i < 15; i++) files[`f${i}.py`] = "#" + Array.from(crypto.getRandomValues(new Uint8Array(6000)), byte => String.fromCharCode(0x21 + byte % 90)).join("");
  assert.throws(() => encodeSharePayload({ schemaVersion: 1, name: "big", entryFile: "f0.py", files }), /too large for a link/);
});

test("only playground URLs with a code fragment are share links", () => {
  const payload = encodeSharePayload(newPlaygroundDocument());
  assert.equal(parseShareLink(new URL("https://pythilo.com/playground/")), null);
  assert.equal(parseShareLink(new URL("https://pythilo.com/learn/#code=" + payload)), null);
  assert.equal(parseShareLink(new URL("https://pythilo.com/playground/room/abc/#code=" + payload)), null);
  assert.ok(parseShareLink(new URL("https://pythilo.com/playground#code=" + payload)));
  assert.ok(parseShareLink(new URL("http://127.0.0.1:3103/playground/#file=main.py&code=" + payload)));
  const app = appShareLink(newPlaygroundDocument());
  assert.match(app, /^pythilo:\/\/playground\/#code=/);
  assert.equal(parseShareLink(new URL(app)).entryFile, "main.py");
  assert.equal(sharePayloadFromHash("#a=1&code=xyz&b=2"), "xyz");
  assert.equal(sharePayloadFromHash("#key=1"), null);
});

test("the starter project makes a short link", () => {
  assert.ok(shareLink(newPlaygroundDocument(), "https://pythilo.com").length < 250);
});
