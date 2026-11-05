// End-to-end check of the Playground in a real headless browser. Not part of `pnpm test`
// (it needs a running site and Playwright, which is not a dependency of this package):
//
//   pnpm dev                                    # or any running site
//   PLAYWRIGHT_MODULE=/path/to/node_modules/playwright/index.mjs \
//   PLAYGROUND_ORIGIN=http://127.0.0.1:3212 SHOTS=../build/shots node tests/e2e/playground-e2e.mjs
//
// The relay refuses requests whose Origin differs from SITE_ORIGIN, so run the site
// with SITE_ORIGIN set to the origin used here for the room steps to pass.
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zipSync, strToU8 } from "fflate";

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? "playwright");
const ORIGIN = process.env.PLAYGROUND_ORIGIN ?? "http://127.0.0.1:3212";
const SHOTS = process.env.SHOTS;
if (SHOTS) mkdirSync(SHOTS, { recursive: true });
const browser = await chromium.launch();
const problems = [];
let step = "";
let current = null;
const check = async (name, work) => {
  step = name; const started = Date.now();
  try { await work(); }
  catch (error) { if (current && SHOTS) await current.screenshot({ path: join(SHOTS, "playground-failure.png") }).catch(() => {}); console.log(`not ok - ${name}`); throw error; }
  console.log(`ok - ${name} (${Date.now() - started} ms)`);
};
const shot = async (page, name) => { if (SHOTS) await page.screenshot({ path: join(SHOTS, `playground-${name}.png`) }); };

async function open(viewport, url = "/playground/", options = {}) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 2, ...options });
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: ORIGIN }).catch(() => {});
  const page = await context.newPage();
  page.on("pageerror", error => problems.push(`${step}: page error ${error.message}`));
  page.on("console", entry => { if (entry.type() === "error" && !/favicon|DevTools/.test(entry.text())) problems.push(`${step}: console ${entry.text()}`); });
  page.on("dialog", dialog => dialog.accept());
  current = page;
  await page.goto(ORIGIN + url);
  await page.waitForSelector(".cm-content", { timeout: 60_000 });
  return page;
}
const tree = page => page.locator(".pg-file-list .pg-tree-row:not(.pg-tree-editing) .pg-tree-name").allInnerTexts();
const row = (page, name) => page.locator(".pg-tree-row", { has: page.locator(".pg-tree-name", { hasText: new RegExp(`^${name.replace(".", "\\.")}$`) }) });
const editorText = page => page.locator(".cm-content").evaluate(element => element.cmView?.view?.state.doc.toString() ?? Array.from(element.querySelectorAll(".cm-line"), line => line.textContent).join("\n"));
const output = page => page.locator(".pg-output").innerText();
async function setCode(page, text) {
  await page.locator(".cm-content").click();
  await page.keyboard.press("ControlOrMeta+a"); await page.keyboard.press("Delete");
  await page.keyboard.insertText(text);
}
async function runAndWait(page, trigger) {
  await (trigger ?? (() => page.locator(".pg-header .pg-run-button").click()))();
  await page.waitForSelector(".pg-run-button.stop", { timeout: 5000 }).catch(() => {});
  await page.waitForFunction(() => !document.querySelector(".pg-run-button.stop"), null, { timeout: 120_000 });
}

const desk = await open({ width: 1440, height: 900 });
await check("starts with main.py as the main file", async () => {
  assert.deepEqual(await tree(desk), ["main.py"]);
  assert.equal(await desk.locator(".pg-entry-mark").count(), 1);
  await shot(desk, "desktop-start");
});
await check("new file from the toolbar is named inline and opens with the cursor in it", async () => {
  await desk.getByRole("button", { name: "New file", exact: true }).click();
  const field = desk.getByRole("textbox", { name: "New file name" });
  await field.fill("helpers");
  await desk.locator(".pg-tree-problem").waitFor();
  assert.match(await desk.locator(".pg-tree-problem").innerText(), /extension/);
  await field.fill("helpers.py"); await field.press("Enter");
  await desk.waitForFunction(() => document.activeElement?.classList.contains("cm-content"));
  await desk.keyboard.insertText("def double(x):\n    return x * 2\n");
  assert.deepEqual(await tree(desk), ["helpers.py", "main.py"]);
  assert.equal(await desk.locator(".pg-path-file").innerText(), "helpers.py");
});
await check("a taken name and Escape leave the project unchanged", async () => {
  await desk.keyboard.press("Alt+N");
  const field = desk.getByRole("textbox", { name: "New file name" });
  await field.fill("main.py");
  assert.match(await desk.locator(".pg-tree-problem").innerText(), /already exists/);
  await field.press("Escape");
  assert.deepEqual(await tree(desk), ["helpers.py", "main.py"]);
});
await check("new folder appears empty, then holds its first file", async () => {
  await desk.getByRole("button", { name: "New folder", exact: true }).click();
  await desk.getByRole("textbox", { name: "New folder name" }).fill("pkg");
  await desk.getByRole("textbox", { name: "New folder name" }).press("Enter");
  const field = desk.getByRole("textbox", { name: "New file name" });
  await field.waitFor();
  assert.equal(await row(desk, "pkg").getAttribute("aria-expanded"), "true");
  await field.fill("util.py"); await field.press("Enter");
  await desk.keyboard.insertText("VALUE = 7\n");
  assert.deepEqual(await tree(desk), ["pkg", "util.py", "helpers.py", "main.py"]);
});
await check("F2 renames inline and Undo puts the name back", async () => {
  await row(desk, "util.py").click(); await row(desk, "util.py").focus();
  await desk.keyboard.press("F2");
  const field = desk.getByRole("textbox", { name: "New name" });
  assert.equal(await field.inputValue(), "util.py");
  await field.fill("tools.py"); await field.press("Enter");
  assert.deepEqual(await tree(desk), ["pkg", "tools.py", "helpers.py", "main.py"]);
  await desk.locator(".pg-toast", { hasText: "Renamed pkg/util.py" }).getByRole("button", { name: "Undo" }).click();
  assert.deepEqual(await tree(desk), ["pkg", "util.py", "helpers.py", "main.py"]);
});
await check("Move to… from the context menu, and drag and drop into a folder", async () => {
  await row(desk, "util.py").click({ button: "right" });
  await desk.getByRole("menuitem", { name: "Move to…" }).click();
  await desk.getByRole("menuitem", { name: "Project root" }).click();
  assert.deepEqual(await tree(desk), ["helpers.py", "main.py", "util.py"]);
  // The folder is gone with its last file; make it again and drag two files in.
  await desk.getByRole("button", { name: "New folder", exact: true }).click();
  await desk.getByRole("textbox", { name: "New folder name" }).fill("pkg"); await desk.getByRole("textbox", { name: "New folder name" }).press("Enter");
  await desk.getByRole("textbox", { name: "New file name" }).press("Escape");
  await row(desk, "util.py").dragTo(row(desk, "pkg"));
  await row(desk, "helpers.py").dragTo(row(desk, "pkg"));
  assert.deepEqual(await tree(desk), ["pkg", "helpers.py", "util.py", "main.py"]);
  await shot(desk, "desktop-tree");
});
await check("imports across folders run, input() reads a line, and output shows", async () => {
  await row(desk, "main.py").click();
  await setCode(desk, "from pkg.helpers import double\nfrom pkg.util import VALUE\nname = input('Name? ')\nprint('Hi', name, double(VALUE))\n");
  await desk.locator(".pg-header .pg-run-button").click();
  await desk.locator("#program-input").waitFor({ timeout: 90_000 });
  await desk.locator("#program-input").fill("Ann"); await desk.locator("#program-input").press("Enter");
  await desk.waitForFunction(() => !document.querySelector(".pg-run-button.stop"), null, { timeout: 60_000 });
  assert.match(await output(desk), /Hi Ann 14/);
  await shot(desk, "desktop-run");
});
await check("a traceback names the file and line, and opens it", async () => {
  await row(desk, "util.py").click();
  await setCode(desk, "VALUE = 1 / 0\n");
  await runAndWait(desk, () => desk.keyboard.press("ControlOrMeta+Enter"));
  assert.match(await output(desk), /ZeroDivisionError/);
  await row(desk, "main.py").click();
  await desk.locator(".diagnostics button", { hasText: "pkg/util.py:1" }).click();
  assert.equal(await desk.locator(".pg-path-file").innerText(), "util.py");
  await setCode(desk, "VALUE = 7\n");
});
await check("packages: NumPy loads, and a missing package explains itself", async () => {
  await row(desk, "main.py").click();
  await setCode(desk, "import numpy as np\nprint(int(np.arange(5).sum()))\n");
  await runAndWait(desk);
  assert.match(await output(desk), /^10$/m);
  await setCode(desk, "import requests\n");
  await runAndWait(desk);
  assert.match(await output(desk), /requests is not available/);
});
await check("Stop ends an endless loop and Clear empties the output", async () => {
  await setCode(desk, "while True:\n    pass\n");
  await desk.locator(".pg-header .pg-run-button").click();
  await desk.locator(".pg-header .pg-run-button.stop").waitFor();
  await desk.waitForTimeout(800);
  await desk.locator(".pg-header .pg-run-button.stop").click();
  await desk.waitForFunction(() => !document.querySelector(".pg-run-button.stop"), null, { timeout: 10_000 });
  assert.match(await output(desk), /Stopped/);
  await desk.getByRole("button", { name: "Clear output" }).click();
  assert.match(await output(desk), /Press Run/);
  await setCode(desk, "from pkg.helpers import double\nprint(double(21))\n");
});
await check("deleting asks nothing and Undo restores, even the main file", async () => {
  await row(desk, "main.py").click({ button: "right" });
  await desk.getByRole("menuitem", { name: "Delete" }).click();
  assert.deepEqual(await tree(desk), ["pkg", "helpers.py", "util.py"]);
  assert.match(await desk.locator(".pg-toast").last().innerText(), /pkg\/helpers\.py is now the main file/);
  await desk.locator(".pg-toast", { hasText: "Deleted main.py" }).getByRole("button", { name: "Undo" }).click();
  assert.deepEqual(await tree(desk), ["pkg", "helpers.py", "util.py", "main.py"]);
  assert.equal(await desk.locator(".pg-header .pg-run-file").innerText(), "main.py");
});
await check("uploading text files and a ZIP adds them; binary files are skipped", async () => {
  const folder = join(tmpdir(), `pythilo-upload-${Date.now()}`); mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "notes.md"), "# Notes\n");
  writeFileSync(join(folder, "image.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0, 0xff, 0xfe]));
  writeFileSync(join(folder, "project.zip"), zipSync({ "demo-main/data/rows.csv": strToU8("a,b\n1,2\n"), "demo-main/test_rows.py": strToU8("def test_rows():\n    assert open('data/rows.csv').read().startswith('a,b')\n") }));
  const chooser = desk.waitForEvent("filechooser");
  await desk.getByRole("button", { name: "Upload files" }).click();
  await (await chooser).setFiles([join(folder, "notes.md"), join(folder, "image.png"), join(folder, "project.zip")]);
  await desk.locator(".pg-toast", { hasText: "Added" }).waitFor();
  assert.match(await desk.locator(".pg-toast", { hasText: "Added" }).innerText(), /Skipped image\.png/);
  assert.deepEqual(await tree(desk), ["data", "pkg", "helpers.py", "util.py", "main.py", "notes.md", "test_rows.py"]);
  await row(desk, "data").click();
  assert.deepEqual((await tree(desk)).slice(0, 2), ["data", "rows.csv"]);
  await runAndWait(desk, () => desk.getByRole("button", { name: "Test", exact: true }).click());
  assert.match(await output(desk), /1 passed/);
});
await check("Ctrl/Cmd+S saves to Drafts, which lists it", async () => {
  await desk.locator(".cm-content").click();
  await desk.keyboard.press("ControlOrMeta+s");
  await desk.locator(".pg-toast", { hasText: "Saved to Drafts" }).waitFor();
  await desk.getByRole("button", { name: "More options" }).click();
  await desk.getByRole("menuitem", { name: "Drafts…" }).click();
  assert.match(await desk.locator("dialog .draft-list").innerText(), /hello-pythilo \(open\)/);
  await desk.keyboard.press("Escape");
});
await check("? opens the shortcuts", async () => {
  await desk.locator(".pg-statusbar").click();
  await desk.keyboard.press("Shift+Slash");
  assert.match(await desk.locator("dialog").innerText(), /Run the main file/);
  await shot(desk, "desktop-shortcuts");
  await desk.keyboard.press("Escape");
});

let codeLink = "";
await check("Share gives a link that carries the code", async () => {
  await desk.locator(".pg-header .pg-share-button").click();
  codeLink = await desk.getByRole("textbox", { name: "Link to this code" }).inputValue();
  assert.match(codeLink, /\/playground\/#code=[A-Za-z0-9_-]+$/);
  assert.match(await desk.locator(".pg-share a", { hasText: "Open in the Pythilo app" }).getAttribute("href"), /^pythilo:\/\/playground\/#code=/);
  await desk.getByRole("button", { name: "Copy link" }).click();
  await desk.locator(".pg-share-status", { hasText: "Link copied" }).waitFor();
  await shot(desk, "desktop-share");
  await desk.keyboard.press("Escape");
});
await check("the link opens the same files in a fresh browser, and editing drops the fragment", async () => {
  const fresh = await open({ width: 1280, height: 800 }, codeLink.replace(/^https?:\/\/[^/]+/, ""));
  assert.match(await fresh.locator(".pg-toast").first().innerText(), /from a link/);
  await row(fresh, "data").click(); await row(fresh, "pkg").click();
  assert.deepEqual(await tree(fresh), ["data", "rows.csv", "pkg", "helpers.py", "util.py", "main.py", "notes.md", "test_rows.py"]);
  assert.equal(await fresh.locator(".pg-header .pg-run-file").innerText(), "main.py");
  await runAndWait(fresh);
  assert.match(await output(fresh), /^42$/m);
  assert.match(fresh.url(), /#code=/);
  await fresh.locator(".cm-content").click(); await fresh.keyboard.insertText("# mine\n");
  await fresh.waitForFunction(() => !location.hash);
  await fresh.context().close();
});
await check("a damaged link explains itself and still opens a playground", async () => {
  const broken = await open({ width: 1280, height: 800 }, "/playground/#code=" + codeLink.split("code=")[1].slice(0, 40));
  assert.match(await broken.locator(".pg-toast-error").innerText(), /damaged|cut short/);
  assert.deepEqual(await tree(broken), ["main.py"]);
  await broken.getByRole("button", { name: "More options" }).click();
  await broken.getByRole("menuitem", { name: "Open a link…" }).click();
  await broken.getByRole("textbox", { name: "Link" }).fill(codeLink);
  await broken.getByRole("button", { name: "Open", exact: true }).click();
  await broken.waitForFunction(() => /^6 of 16 files/.test(document.querySelector(".pg-budget")?.textContent ?? ""));
  await broken.context().close();
});

await check("a live room syncs edits and new files between two browsers", async () => {
  await desk.locator(".pg-header .pg-share-button").click();
  await desk.getByRole("button", { name: "Start a live room" }).click();
  const field = desk.getByRole("textbox", { name: "Room link", exact: true });
  await field.waitFor({ timeout: 15_000 });
  const room = await field.inputValue();
  assert.match(room, /\/playground\/room\/[A-Za-z0-9_-]{24}\/#key=/);
  await shot(desk, "desktop-room");
  await desk.keyboard.press("Escape");
  const guest = await open({ width: 390, height: 844 }, room.replace(/^https?:\/\/[^/]+/, ""), { isMobile: true, hasTouch: true });
  await guest.waitForFunction(() => /^6 of 16 files/.test(document.querySelector(".pg-budget")?.textContent ?? ""), null, { timeout: 20_000 });
  await row(desk, "main.py").click();
  await desk.locator(".cm-content").click(); await desk.keyboard.press("ControlOrMeta+End"); await desk.keyboard.insertText("# from the host\n");
  await guest.getByRole("tab", { name: /Files/ }).click(); await row(guest, "main.py").click();
  await guest.waitForFunction(() => document.querySelector(".cm-content")?.textContent?.includes("# from the host"), null, { timeout: 15_000 });
  await guest.getByRole("tab", { name: /Files/ }).click();
  await guest.getByRole("button", { name: "New file", exact: true }).click();
  await guest.getByRole("textbox", { name: "New file name" }).fill("guest.py"); await guest.getByRole("textbox", { name: "New file name" }).press("Enter");
  await desk.waitForFunction(() => Array.from(document.querySelectorAll(".pg-tree-name"), item => item.textContent).includes("guest.py"), null, { timeout: 15_000 });
  // Rename and delete are off in a room, and say why.
  await guest.getByRole("tab", { name: /Files/ }).click();
  await row(guest, "guest.py").locator("button[aria-label^='More actions']").click();
  assert.equal(await guest.getByRole("menuitem", { name: "Delete" }).isDisabled(), true);
  await shot(guest, "phone-room");
  await guest.context().close();
});

await check("phone: tabs switch between files, code and output; Run shows output", async () => {
  const phone = await open({ width: 390, height: 844 }, "/playground/", { isMobile: true, hasTouch: true });
  await shot(phone, "phone-code");
  await phone.getByRole("tab", { name: /Files/ }).click();
  await phone.getByRole("button", { name: "New file", exact: true }).click();
  await phone.getByRole("textbox", { name: "New file name" }).fill("extra.py"); await phone.getByRole("textbox", { name: "New file name" }).press("Enter");
  assert.equal(await phone.getByRole("tab", { name: "extra.py" }).getAttribute("aria-selected"), "true");
  await phone.getByRole("tab", { name: /Files/ }).click();
  await shot(phone, "phone-files");
  await row(phone, "main.py").click();
  await phone.locator(".pg-tabs .pg-run-button").click();
  await phone.waitForFunction(() => /Hello, Pythilo/.test(document.querySelector(".pg-output")?.textContent ?? ""), null, { timeout: 90_000 });
  assert.equal(await phone.getByRole("tab", { name: /Output/ }).getAttribute("aria-selected"), "true");
  await shot(phone, "phone-output");
  await phone.locator(".pg-header .pg-share-button").click();
  await shot(phone, "phone-share");
  await phone.context().close();
});

await browser.close();
if (problems.length) { console.log(problems.join("\n")); process.exitCode = 1; }
console.log(problems.length ? `${problems.length} browser problem(s)` : "all playground flows passed");
