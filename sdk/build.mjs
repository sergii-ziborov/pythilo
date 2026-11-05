import { build } from "esbuild";
import { mkdir, readFile, readdir, writeFile, chmod } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
const root = path.dirname(fileURLToPath(import.meta.url));
const packageInfo = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
const versionSource = await readFile(path.join(root, "src/version.ts"), "utf8");
if (!versionSource.includes(`SDK_VERSION = "${packageInfo.version}"`)) throw new Error("CLI and package versions must match.");
// package.json is the one version source. The plugin's install files are generated.
const writeJSON = (file, value) => writeFile(path.join(root, file), JSON.stringify(value, null, 2) + "\n");
const npxArgs = ["-y", `--package=https://pythilo.com/downloads/pythilo-${packageInfo.version}.tgz`, "pythilo"];
await writeJSON(".mcp.json", { mcpServers: { pythilo: { command: "npx", args: npxArgs } } });
const plugin = JSON.parse(await readFile(path.join(root, ".claude-plugin/plugin.json"), "utf8"));
await writeJSON(".claude-plugin/plugin.json", { ...plugin, version: packageInfo.version });
const result = await build({ absWorkingDir: root, entryPoints: ["src/cli.ts"], outdir: "dist", outExtension: {".js":".mjs"}, bundle: true, platform: "node", target: "node22", format: "esm", metafile: true,
  define: { __PYTHILO_RELEASE_VERSION__: JSON.stringify(packageInfo.version) },
  // A few SDK dependencies still use CJS builtins. createRequire resolves only
  // bundled dependencies/builtins, never project-controlled module paths.
  banner: { js: 'import { createRequire as __pythiloCreateRequire } from "node:module"; const require = __pythiloCreateRequire(import.meta.url);' } });
await chmod(path.join(root, "dist/cli.mjs"), 0o755);
const library = await build({absWorkingDir:root,entryPoints:["src/runtime-entry.ts"],outfile:"dist/implementation.cjs",bundle:true,platform:"node",target:"node22",format:"cjs",metafile:true});
await writeFile(path.join(root,"dist/index.cjs"),'const core = require("./implementation.cjs"); module.exports = { Pythilo: core.Pythilo, PythiloError: core.PythiloError, PLAYGROUND_LIMITS: core.PLAYGROUND_LIMITS };\n');
await writeFile(path.join(root,"dist/index.mjs"),'import core from "./implementation.cjs"; export const Pythilo = core.Pythilo; export const PythiloError = core.PythiloError; export const PLAYGROUND_LIMITS = core.PLAYGROUND_LIMITS;\n');
await writeFile(path.join(root,"dist/server.mjs"),'import core from "./implementation.cjs"; export const makeServer = core.makeServer;\n');
execFileSync(process.execPath,["node_modules/typescript/bin/tsc","--noEmit","false","--declaration","--emitDeclarationOnly","--outDir","dist","--rootDir","src"],{cwd:root,stdio:"inherit"});
const packages = new Map();
const bundledInputs = new Set([...Object.keys(result.metafile.inputs), ...Object.keys(library.metafile.inputs)]);
for (const input of bundledInputs) {
  if (!input.includes("node_modules")) continue;
  let directory = path.dirname(path.resolve(root, input));
  while (directory !== path.dirname(directory)) {
    try {
      const info = JSON.parse(await readFile(path.join(directory, "package.json"), "utf8"));
      if (info.name && info.version) { packages.set(info.name + "@" + info.version, { directory, info }); break; }
    } catch {}
    directory = path.dirname(directory);
  }
}
const notices = ["Pythilo SDK — third-party components\nOriginal component licenses apply independently of the Pythilo bridge license.\n"];
for (const [name, { directory, info }] of [...packages].sort(([a], [b]) => a.localeCompare(b))) {
  let license;
  for (const file of ["LICENSE", "LICENSE.txt", "LICENSE.md", "license", "license.md"]) { try { license = await readFile(path.join(directory, file), "utf8"); break; } catch {} }
  if (!license) throw new Error("Missing license text: " + name);
  notices.push(`\n${"=".repeat(72)}\n${name} · ${info.license ?? "see original text"}\n${license}`);
  for (const file of ["NOTICE", "NOTICE.txt", "NOTICE.md"]) { try { notices.push(await readFile(path.join(directory, file), "utf8")); } catch {} }
}
await mkdir(path.join(root, "dist"), { recursive: true });
await writeFile(path.join(root, "ThirdPartyNotices.txt"), notices.join("\n"));
await writeFile(path.join(root, "dist/components.json"), JSON.stringify([...packages].map(([name, { info }]) => ({ name, license: info.license })), null, 2) + "\n");
const sources = {};
for (const input of new Set([...bundledInputs].filter(file => !file.includes("node_modules")).concat(["src/types.ts", "src/core/provenance.json", "build.mjs", "tsconfig.json", "package.json", "README.md"]))) {
  const file = path.resolve(root, input), relative = path.relative(root, file);
  if (relative.startsWith("..") || path.isAbsolute(relative)) throw new Error("Bundled source is outside the package.");
  sources[relative.split(path.sep).join("/")] = createHash("sha256").update(await readFile(file)).digest("hex");
}
await writeFile(path.join(root, "dist/source-manifest.json"), JSON.stringify({ version: packageInfo.version, sourceSHA256: sources }, null, 2) + "\n");

// Public declarations are self-contained: consumers do not need Yjs or MCP SDK types.
const publicTypes = await readFile(path.join(root,"dist/types.d.ts"),"utf8");
const publicAPI = (await readFile(path.join(root,"dist/index.d.ts"),"utf8")).split("\n").filter(line=>!line.startsWith("import type ")&&!line.startsWith("export type *")&&!line.startsWith("export { PLAYGROUND_LIMITS")&&!line.startsWith("export { PythiloError")).join("\n");
const declarations=publicTypes+"\nexport declare const PLAYGROUND_LIMITS: Readonly<{files:16;fileBytes:number;sourceBytes:number;maximumLifetimeSeconds:number;participants:4}>;\nexport declare class PythiloError extends Error { readonly code: string; readonly retryable: boolean; readonly action: string; readonly details?: Record<string, unknown>; toJSON(): Record<string, unknown>; }\n"+publicAPI;
await writeFile(path.join(root,"dist/index.d.ts"),'export * from "./index.cjs";\n');
await writeFile(path.join(root,"dist/index.d.cts"),declarations);

// The shared core is ported from the Crabrix SDK. src/core/provenance.json names the donor
// commit and the hash of each donor file; every core file must be listed there.
const digest = createHash("sha256").update(await readFile(path.join(root, "dist/cli.mjs"))).digest("hex");
const provenance = JSON.parse(await readFile(path.join(root, "src/core/provenance.json"), "utf8"));
if (!/^[a-f0-9]{40}$/.test(provenance.commit ?? "")) throw new Error("src/core/provenance.json needs the full donor commit.");
const coreFiles = (await readdir(path.join(root, "src/core"))).filter(file => file.endsWith(".ts")).map(file => "src/core/" + file);
const unlisted = coreFiles.filter(file => !provenance.files?.[file]);
if (unlisted.length) throw new Error("Core files without provenance: " + unlisted.join(", "));
const core = [];
for (const [file, origin] of Object.entries(provenance.files).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)) {
  if (typeof origin.donor !== "string" || !/^[a-f0-9]{64}$/.test(origin.donorSHA256 ?? "")) throw new Error("Incomplete provenance: " + file);
  core.push({ file, sha256: createHash("sha256").update(await readFile(path.join(root, file))).digest("hex"), donor: origin.donor, donorSHA256: origin.donorSHA256, adaptations: origin.adaptations });
}
await mkdir(path.join(root, "docs"), { recursive: true });
await writeJSON("docs/protocol-core.json", {
  version: packageInfo.version, sha256: { "dist/cli.mjs": digest },
  requires: "Node.js 22+", source: "src/cli.ts and src/core", npmPackage: `pythilo@${packageInfo.version}`,
  documentFormats: [1], runtimeProfile: "python3-v1",
  core: { repository: provenance.repository, commit: provenance.commit, files: core },
});
