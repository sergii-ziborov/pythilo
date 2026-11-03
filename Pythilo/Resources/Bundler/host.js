// Builds a project with esbuild-wasm inside the app. Files come from the app
// through pythilo-bundler://project/, and the output goes back as base64; this
// page never touches the network.

const PROJECT = "pythilo-bundler://project/";
const EXTENSIONS = [".tsx", ".ts", ".jsx", ".js", ".mjs", ".cjs", ".json", ".css"];
const BINARY = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".otf"]);
const LOADERS = {
  ".js": "jsx", ".jsx": "jsx", ".ts": "ts", ".tsx": "tsx", ".mjs": "js", ".cjs": "js",
  ".json": "json", ".css": "css", ".txt": "text",
};

let initialized = null;
let texts = new Map();
let conditions = new Set();

function start() {
  if (!initialized) initialized = esbuild.initialize({ wasmURL: "pythilo-bundler://app/esbuild.wasm", worker: false });
  return initialized;
}

function normalize(path) {
  const out = [];
  for (const part of path.split("/")) {
    if (!part || part === ".") continue;
    if (part === "..") out.pop();
    else out.push(part);
  }
  return out.join("/");
}

const dirname = (path) => path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
const join = (...parts) => normalize(parts.filter((part) => part !== "").join("/"));
const extension = (path) => { const name = path.slice(path.lastIndexOf("/") + 1); return name.includes(".") ? name.slice(name.lastIndexOf(".")).toLowerCase() : ""; };

function url(path) {
  return PROJECT + path.split("/").map(encodeURIComponent).join("/");
}

async function readText(path) {
  if (texts.has(path)) return texts.get(path);
  const response = await fetch(url(path));
  const text = response.ok ? await response.text() : null;
  texts.set(path, text);
  return text;
}

async function readBytes(path) {
  const response = await fetch(url(path));
  return new Uint8Array(await response.arrayBuffer());
}

async function readJSON(path) {
  const text = await readText(path);
  if (text === null) return null;
  try { return JSON.parse(text); } catch { return null; }
}

async function asFile(path) {
  if (await readText(path) !== null) return path;
  for (const ext of EXTENSIONS) if (await readText(path + ext) !== null) return path + ext;
  return null;
}

async function asIndex(path) {
  for (const ext of EXTENSIONS) if (await readText(join(path, "index" + ext)) !== null) return join(path, "index" + ext);
  return null;
}

async function asDirectory(path) {
  const manifest = await readJSON(join(path, "package.json"));
  if (manifest) {
    const entry = (typeof manifest.browser === "string" && manifest.browser) || manifest.module || manifest.main;
    if (entry) {
      const found = await asFile(join(path, entry)) || await asIndex(join(path, entry));
      if (found) return found;
    }
  }
  return asIndex(path);
}

// Package "exports", as Node reads them: the first key whose condition holds.
function pick(target) {
  if (typeof target === "string") return target;
  if (Array.isArray(target)) {
    for (const item of target) { const found = pick(item); if (found) return found; }
    return null;
  }
  if (target && typeof target === "object") {
    for (const [key, value] of Object.entries(target)) {
      if (conditions.has(key)) { const found = pick(value); if (found) return found; }
    }
  }
  return null;
}

function exported(exports, subpath) {
  const sugar = typeof exports === "string" || Array.isArray(exports) || !Object.keys(exports).some((key) => key.startsWith("."));
  if (sugar) return subpath === "." ? pick(exports) : null;
  if (exports[subpath] !== undefined) return pick(exports[subpath]);
  for (const key of Object.keys(exports)) {
    const star = key.indexOf("*");
    if (star < 0) continue;
    const prefix = key.slice(0, star), suffix = key.slice(star + 1);
    if (subpath.startsWith(prefix) && subpath.endsWith(suffix) && subpath.length >= key.length - 1) {
      const middle = subpath.slice(prefix.length, subpath.length - suffix.length);
      const target = pick(exports[key]);
      return target && target.replace(/\*/g, middle);
    }
  }
  return null;
}

async function resolvePackage(specifier, fromDir) {
  const parts = specifier.split("/");
  const name = specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
  const rest = specifier.slice(name.length);
  const subpath = rest ? "." + rest : ".";
  let dir = fromDir;
  for (;;) {
    const base = join(dir, "node_modules", name);
    const manifest = await readJSON(join(base, "package.json"));
    if (manifest) {
      if (manifest.exports !== undefined && manifest.exports !== null) {
        const target = exported(manifest.exports, subpath);
        if (!target) throw new Error(`"${subpath}" is not exported by ${name}`);
        return join(base, target);
      }
      if (subpath === ".") return asDirectory(base);
      return await asFile(join(base, subpath)) || await asIndex(join(base, subpath));
    }
    if (!dir) return null;
    dir = dirname(dir);
  }
}

const project = {
  name: "pythilo-project",
  setup(build) {
    build.onResolve({ filter: /.*/ }, async (args) => {
      if (/^(node:|https?:|data:)/.test(args.path)) return { external: true };
      if (args.kind === "entry-point") {
        const found = await asFile(normalize(args.path));
        return found ? { path: found, namespace: "project" } : { errors: [{ text: `Cannot find the entry ${args.path}` }] };
      }
      const fromDir = args.importer ? dirname(args.importer) : "";
      if (args.path.startsWith("./") || args.path.startsWith("../") || args.path.startsWith("/") || args.path === "." || args.path === "..") {
        const base = args.path.startsWith("/") ? normalize(args.path) : join(fromDir, args.path);
        const found = await asFile(base) || await asIndex(base);
        return found ? { path: found, namespace: "project" } : { errors: [{ text: `Cannot find ${args.path}` }] };
      }
      try {
        const found = await resolvePackage(args.path, fromDir);
        if (found) return { path: found, namespace: "project" };
      } catch (error) {
        return { errors: [{ text: String(error.message || error) }] };
      }
      return { errors: [{ text: `Cannot find the package "${args.path}". Run npm install.` }] };
    });
    build.onLoad({ filter: /.*/, namespace: "project" }, async (args) => {
      const ext = extension(args.path);
      if (BINARY.has(ext)) return { contents: await readBytes(args.path), loader: "file", resolveDir: dirname(args.path) };
      const contents = await readText(args.path);
      if (contents === null) return { errors: [{ text: `Cannot read ${args.path}` }] };
      return { contents, loader: LOADERS[ext] || "js", resolveDir: dirname(args.path) };
    });
  },
};

function base64(bytes) {
  let text = "";
  for (let index = 0; index < bytes.length; index += 0x8000) text += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  return btoa(text);
}

window.pythiloBuild = async (options) => {
  await start();
  texts = new Map();
  conditions = new Set(["browser", "import", "module", "default", options.mode]);
  const started = performance.now();
  try {
    const result = await esbuild.build({
      entryPoints: options.entryPoints,
      bundle: true,
      write: false,
      absWorkingDir: "/",
      outdir: options.outfile ? undefined : "/" + options.outdir,
      outfile: options.outfile ? "/" + options.outfile : undefined,
      minify: options.minify,
      sourcemap: options.sourcemap ? "inline" : false,
      format: options.format || "iife",
      jsx: options.jsx || "automatic",
      target: "es2020",
      define: Object.assign({ "process.env.NODE_ENV": JSON.stringify(options.mode) }, options.define || {}),
      loader: options.loader || {},
      assetNames: "[name]-[hash]",
      plugins: [project],
      logLevel: "silent",
    });
    const warnings = await esbuild.formatMessages(result.warnings, { kind: "warning", color: false });
    return {
      ok: true,
      milliseconds: Math.round(performance.now() - started),
      version: esbuild.version,
      outputs: result.outputFiles.map((file) => ({ path: file.path.replace(/^\//, ""), base64: base64(file.contents), bytes: file.contents.length })),
      warnings,
    };
  } catch (error) {
    const errors = error.errors ? await esbuild.formatMessages(error.errors, { kind: "error", color: false }) : [String(error.message || error)];
    return { ok: false, milliseconds: Math.round(performance.now() - started), version: esbuild.version, errors, outputs: [], warnings: [] };
  }
};

start().then(() => window.webkit.messageHandlers.ready.postMessage(esbuild.version), (error) => window.webkit.messageHandlers.ready.postMessage("error: " + error));
