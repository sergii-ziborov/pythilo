import { lookup } from "node:dns/promises";
import { connect as connectTLS } from "node:tls";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { proxyVariables } from "./errors.js";
import { SDK_VERSION, SERVER_NAME } from "./version.js";
import { CLIENT_CODECS } from "./core/playground-session.js";
import { configuredRelay, isLoopback, type RelayConfig } from "./relay.js";

const PROBE_ROOM = "doctor-probe-not-a-room0"; // Valid shape, never created: the relay answers 410.
const PROBE_TOKEN = "d".repeat(43);

export type DoctorCheck = { name: string; status: "ok" | "warning" | "failed" | "skipped"; detail: string };
export type DoctorReport = {
  integrationFamily: "pythilo"; server: { name: string; version: string; transport: "stdio"; source: string };
  node: { version: string; supported: boolean }; relay: { origin: string | null; source: RelayConfig["source"] | null }; checks: DoctorCheck[];
  proxy: { configured: string[]; envProxyEnabled: boolean; envProxySupported: boolean };
  ok: boolean;
};
type Options = { relay?: string; timeoutMs?: number; argv1?: string; environment?: NodeJS.ProcessEnv };

const failure = (error: unknown) => {
  const seen: string[] = []; let current = error;
  for (let depth = 0; depth < 6 && current && typeof current === "object"; depth++) {
    const value = current as { code?: unknown; name?: unknown; cause?: unknown };
    if (typeof value.code === "string") seen.push(value.code); else if (typeof value.name === "string" && value.name !== "Error" && value.name !== "TypeError") seen.push(value.name);
    current = value.cause;
  }
  return seen[0] ?? "connection failed";
};
const major = (version: string) => version.replace(/^v/, "").split(".").map(Number);
// NODE_USE_ENV_PROXY arrived in Node 24.0 and was backported to 22.21.
export function envProxySupported(version = process.version) { const [a, b] = major(version); return a >= 24 || (a === 22 && b >= 21); }
const masked = (value: string) => { const home = homedir(); return value.startsWith(home) ? "~" + value.slice(home.length) : value; };

function owningPackage(file: string) {
  let directory = path.dirname(file);
  for (let depth = 0; depth < 5; depth++, directory = path.dirname(directory)) {
    try { const name = JSON.parse(readFileSync(path.join(directory, "package.json"), "utf8")).name; if (typeof name === "string") return name; } catch {}
  }
  return "unknown";
}

/** Read-only: only an explicit doctor call looks at PATH, and it never edits anything. */
export function installedCommands(): DoctorCheck {
  const found = new Map<string, string>();
  for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
    if (!directory) continue;
    const file = path.join(directory, "pythilo");
    if (found.has(file) || !existsSync(file)) continue;
    try { found.set(file, owningPackage(realpathSync(file))); } catch {}
  }
  const foreign = [...found].filter(([, owner]) => owner !== "pythilo");
  if (foreign.length) return { name: "global-cli", status: "warning", detail: `${foreign.map(([file]) => masked(file)).join(", ")} is a pythilo command from another package. MCP configs that run \`pythilo\` from PATH would start it instead.` };
  return { name: "global-cli", status: "ok", detail: found.size ? `Commands on PATH: ${[...found.keys()].map(masked).join(", ")}.` : "No global pythilo command on PATH; npx or a path to dist/cli.mjs does not need one." };
}

function certificate(origin: URL, timeoutMs: number): Promise<DoctorCheck> {
  return new Promise(resolve => {
    const socket = connectTLS({ host: origin.hostname, port: Number(origin.port) || 443, servername: origin.hostname, timeout: timeoutMs }, () => {
      const peer = socket.getPeerCertificate();
      const days = peer.valid_to ? Math.floor((Date.parse(peer.valid_to) - Date.now()) / 86_400_000) : NaN;
      resolve(socket.authorized
        ? { name: "tls", status: "ok", detail: `Certificate verified for ${origin.hostname}${Number.isFinite(days) ? `, valid for ${days} more days` : ""}.` }
        : { name: "tls", status: "failed", detail: `Certificate not verified: ${socket.authorizationError}. Check system time and a corporate TLS root; do not disable verification.` });
      socket.destroy();
    });
    socket.once("timeout", () => { socket.destroy(); resolve({ name: "tls", status: "failed", detail: "TLS handshake timed out." }); });
    socket.once("error", error => { resolve({ name: "tls", status: "failed", detail: `TLS connection failed: ${failure(error)}. Do not disable verification.` }); });
  });
}

export async function runDoctor(options: Options = {}): Promise<DoctorReport> {
  const timeoutMs = options.timeoutMs ?? 8000, checks: DoctorCheck[] = [];
  const [nodeMajor] = major(process.version), supported = nodeMajor >= 22;
  checks.push({ name: "node", status: supported ? "ok" : "failed", detail: supported ? `Node ${process.version}.` : `Node ${process.version} is too old; Pythilo needs Node 22 or newer.` });
  const missing = ["fetch", "AbortSignal", "TextDecoder"].filter(name => !(name in globalThis)).concat(globalThis.crypto?.subtle ? [] : ["crypto.subtle"]);
  checks.push({ name: "node-api", status: missing.length ? "failed" : "ok", detail: missing.length ? `Missing: ${missing.join(", ")}.` : "fetch and WebCrypto are available." });
  const bundled = typeof __PYTHILO_RELEASE_VERSION__ === "string" ? __PYTHILO_RELEASE_VERSION__ : undefined;
  checks.push(bundled === undefined ? { name: "release", status: "skipped", detail: "Running from source; no release version is bundled." }
    : bundled === SDK_VERSION ? { name: "release", status: "ok", detail: `Bundle and package agree on ${SDK_VERSION}.` }
    : { name: "release", status: "failed", detail: `Bundle is ${SDK_VERSION}, but its package says ${bundled}.` });

  const configured = proxyVariables(), envProxyEnabled = process.env.NODE_USE_ENV_PROXY === "1", proxySupport = envProxySupported();
  if (!configured.length) checks.push({ name: "proxy", status: "ok", detail: "No proxy variables are set." });
  else if (envProxyEnabled && proxySupport) checks.push({ name: "proxy", status: "ok", detail: `${configured.join(", ")} set, and Node is told to use them.` });
  else checks.push({ name: "proxy", status: "warning", detail: `${configured.join(", ")} set, but this Node process does not use them for fetch. ${proxySupport ? "If direct connections fail, start the MCP server with NODE_USE_ENV_PROXY=1." : `Node ${process.version} has no NODE_USE_ENV_PROXY; use Node 22.21 or 24 and set it if direct connections fail.`}` });

  let relay: RelayConfig | undefined;
  try {
    relay = configuredRelay(options.relay, "--relay", options.environment ?? process.env);
    checks.push(relay ? { name: "relay-config", status: "ok", detail: `Relay ${relay.origin}, from ${relay.source}.` }
      : { name: "relay-config", status: "warning", detail: "No relay is configured. Joining a room from its link works; creating a room needs PYTHILO_RELAY or --relay <origin> (local development: http://127.0.0.1:3212)." });
  } catch (error) { checks.push({ name: "relay-config", status: "failed", detail: error instanceof Error ? error.message : "Invalid relay." }); }
  const report = (): DoctorReport => {
    const entry = options.argv1 ?? process.argv[1] ?? "";
    return { integrationFamily: "pythilo", server: { name: SERVER_NAME, version: SDK_VERSION, transport: "stdio", source: entry.includes("_npx") ? "npx" : entry.includes("node_modules") ? "npm package" : "local file" },
      node: { version: process.version, supported }, relay: { origin: relay?.origin ?? null, source: relay?.source ?? null }, checks, proxy: { configured, envProxyEnabled, envProxySupported: proxySupport }, ok: checks.every(check => check.status !== "failed") };
  };
  if (!relay) {
    for (const name of ["dns", "tls", "relay", "rooms"]) checks.push({ name, status: "skipped", detail: "No relay to check." });
    checks.push(installedCommands());
    return report();
  }
  const origin = new URL(relay.origin);
  if (isLoopback(origin.hostname)) checks.push({ name: "dns", status: "skipped", detail: "Loopback relay." });
  else {
    try { const address = await lookup(origin.hostname); checks.push({ name: "dns", status: "ok", detail: `${origin.hostname} resolves (IPv${address.family}).` }); }
    catch (error) { checks.push({ name: "dns", status: configured.length ? "warning" : "failed", detail: `${origin.hostname} does not resolve here: ${failure(error)}.` }); }
  }
  if (origin.protocol === "https:") checks.push(await certificate(origin, timeoutMs));
  else checks.push({ name: "tls", status: "skipped", detail: "This relay uses plain http; only a local relay should." });
  try {
    const response = await fetch(`${origin.origin}/healthz/`, { redirect: "error", cache: "no-store", signal: AbortSignal.timeout(timeoutMs) });
    await response.body?.cancel().catch(() => {});
    checks.push(response.ok ? { name: "relay", status: "ok", detail: `${origin.origin}/healthz/ answers HTTP ${response.status}.` } : { name: "relay", status: "failed", detail: `${origin.origin}/healthz/ answered HTTP ${response.status}.` });
  } catch (error) { checks.push({ name: "relay", status: "failed", detail: `${origin.origin}/healthz/ could not be reached: ${failure(error)}.${configured.length && !envProxyEnabled ? " Proxy variables are set but unused." : ""}` }); }
  // A deliberately unknown room proves the room route answers. No room is created or read.
  try {
    const response = await fetch(`${origin.origin}/api/playground/rooms/${PROBE_ROOM}/`, { redirect: "error", cache: "no-store", signal: AbortSignal.timeout(timeoutMs), headers: { Authorization: "Bearer " + PROBE_TOKEN, "X-Pythilo-Codecs": CLIENT_CODECS } });
    await response.body?.cancel().catch(() => {});
    const answered = response.status === 410 || response.status === 403;
    checks.push(answered ? { name: "rooms", status: "ok", detail: "The room API answers." } : { name: "rooms", status: "failed", detail: `The room API answered HTTP ${response.status}.` });
  } catch (error) { checks.push({ name: "rooms", status: "failed", detail: `The room API could not be reached: ${failure(error)}.` }); }
  checks.push(installedCommands());
  return report();
}

export function formatDoctor(report: DoctorReport): string {
  const marks = { ok: "ok  ", warning: "warn", failed: "FAIL", skipped: "skip" };
  return [`Pythilo doctor · ${report.server.name} ${report.server.version} · ${report.server.transport} · ${report.server.source}`, `Relay: ${report.relay.origin ? `${report.relay.origin} (${report.relay.source})` : "not configured"}`, ...report.checks.map(check => `${marks[check.status]} ${check.name}: ${check.detail}`),
    report.ok ? "No blocking problem found. This did not open a room or read any source." : "Blocking problems found. This did not open a room or read any source."].join("\n") + "\n";
}
declare const __PYTHILO_RELEASE_VERSION__: string | undefined;
