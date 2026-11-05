// Build and package the official bridge before a release. The server builder uses
// this prepared archive, so ordinary site builds need no parent SDK checkout.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const site = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sdk = resolve(site, "../sdk");
const destination = resolve(site, "public/downloads");
mkdirSync(destination, { recursive: true });
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
execFileSync(npm, ["run", "check"], { cwd: sdk, stdio: "inherit" });
execFileSync(npm, ["run", "build"], { cwd: sdk, stdio: "inherit" });
const [archive] = JSON.parse(execFileSync(npm, ["pack", "--ignore-scripts", "--json", "--pack-destination", destination], { cwd: sdk, encoding: "utf8" }));
const handoff = readFileSync(resolve(site, "lib/playground-handoff.ts"), "utf8");
if (!handoff.includes(`/downloads/${archive.filename}`)) throw new Error("Update the bridge download URL before releasing.");
console.log(`Prepared ${archive.filename} (${archive.size} bytes), ${archive.integrity}`);
