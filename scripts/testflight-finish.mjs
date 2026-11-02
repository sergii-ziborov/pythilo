// Waits for an uploaded build to finish Apple's processing, attaches the "What to Test"
// notes and gives the internal group access. Internal testers need no Beta App Review.
//   node scripts/testflight-finish.mjs <build-number> <notes-file>
// Credentials are read as in scripts/testflight.sh and never printed. The notes file is
// JSON, one string per locale. Nothing here submits the app for review.
import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const home = process.env.HOME;
const env = Object.fromEntries(readFileSync(process.env.ASC_ENV_FILE || `${home}/.private_keys/appstoreconnect.env`, "utf8")
  .split("\n").map((l) => l.trim().replace(/^export /, "")).filter((l) => l && !l.startsWith("#") && l.includes("="))
  .map((l) => { const [k, ...v] = l.split("="); return [k.trim(), v.join("=").trim().replace(/^["']|["']$/g, "")]; }));
const keyId = process.env.PYTHILO_ASC_KEY_ID || env.ASC_KEY_ID;
const key = readFileSync(`${home}/.private_keys/AuthKey_${keyId}.p8`, "utf8");
const APP = "6829637526", GROUP_NAME = "Pythilo Internal";
const [buildNumber, notesPath] = process.argv.slice(2);
if (!buildNumber || !notesPath) throw new Error("Usage: testflight-finish.mjs <build-number> <notes-file>");
const notes = JSON.parse(readFileSync(notesPath, "utf8"));

function token() {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const body = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({ iss: env.ASC_ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })}`;
  const signature = createSign("SHA256").update(body).sign({ key, dsaEncoding: "ieee-p1363" });
  return `${body}.${signature.toString("base64url")}`;
}

async function call(method, path, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) throw new Error(`${method} ${path} → ${response.status}\n${(await response.text()).slice(0, 800)}`);
  return response.status === 204 ? null : response.json();
}

let build, last = "";
const deadline = Date.now() + 60 * 60 * 1000;
while (Date.now() < deadline) {
  const list = await call("GET", `/builds?filter[app]=${APP}&filter[version]=${buildNumber}&limit=5`);
  const state = list.data[0]?.attributes.processingState ?? "awaiting_processing";
  if (state !== last) { console.log(new Date().toISOString(), "build", buildNumber, state); last = state; }
  if (state === "VALID") { build = list.data[0].id; break; }
  if (state === "INVALID" || state === "FAILED") throw new Error(`Apple processing failed: ${state}`);
  await new Promise((resolve) => setTimeout(resolve, 30000));
}
if (!build) throw new Error("Build did not finish processing within an hour");

const localizations = await call("GET", `/builds/${build}/betaBuildLocalizations`);
for (const [locale, whatsNew] of Object.entries(notes)) {
  const existing = localizations.data.find((x) => x.attributes.locale === locale);
  if (existing) await call("PATCH", `/betaBuildLocalizations/${existing.id}`, { data: { type: "betaBuildLocalizations", id: existing.id, attributes: { whatsNew } } });
  else await call("POST", "/betaBuildLocalizations", { data: { type: "betaBuildLocalizations", attributes: { locale, whatsNew }, relationships: { build: { data: { type: "builds", id: build } } } } });
}

const groups = await call("GET", `/betaGroups?filter[app]=${APP}&filter[name]=${encodeURIComponent(GROUP_NAME)}&limit=5`);
const group = groups.data[0]?.id ?? (await call("POST", "/betaGroups", { data: { type: "betaGroups",
  attributes: { name: GROUP_NAME, isInternalGroup: true, hasAccessToAllBuilds: true },
  relationships: { app: { data: { type: "apps", id: APP } } } } })).data.id;
const inGroup = await call("GET", `/betaGroups/${group}/builds?limit=200`);
if (!inGroup.data.some((b) => b.id === build)) {
  try {
    await call("POST", `/betaGroups/${group}/relationships/builds`, { data: [{ type: "builds", id: build }] });
  } catch (error) {
    // A group with access to all builds receives each build by itself and refuses the call.
    if (!/hasAccessToAllBuilds|ALL_BUILDS|STATE_ERROR|409/.test(error.message)) throw error;
  }
}
await new Promise((resolve) => setTimeout(resolve, 5000));
const [detail, testers] = await Promise.all([
  call("GET", `/builds/${build}/buildBetaDetail`),
  call("GET", `/betaGroups/${group}/betaTesters?limit=50`),
]);
console.log(JSON.stringify({ build, buildNumber, group, internalBuildState: detail.data.attributes.internalBuildState, testers: testers.data.length }));
