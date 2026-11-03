export const PLAYGROUND_LIMITS = Object.freeze({
  files: 16, fileBytes: 64 * 1024, sourceBytes: 128 * 1024,
  maximumLifetimeSeconds: 24 * 60 * 60, participants: 4,
});

export type PlaygroundDocument = {
  schemaVersion: 1; name: string; entryFile: string; files: Record<string, string>;
  origin?: { url: string; commit?: string };
};

const encoder = new TextEncoder();
// Folders that hold caches, environments or another tool's state, never project source.
export const REFUSED_FOLDERS = Object.freeze(["__pycache__", ".venv", "venv", ".git", ".pythilo", "site-packages", "node_modules", ".mypy_cache", ".pytest_cache"]);
const forbidden = new Set<string>(REFUSED_FOLDERS);
// Extensions anywhere; the extensionless names only at the project root, as Crabrix's LICENSE and NOTICE.
const allowed = /(?:\.py|\.pyi|\.txt|\.md|\.rst|\.csv|\.tsv|\.json|\.toml|\.cfg|\.ini|\.yaml|\.yml|\.html|\.css|\.js|\.sql)$|^(?:requirements\.txt|LICENSE|NOTICE|README|\.gitignore)$/i;

export function isWellFormedUTF16(value: string): boolean {
  // Swift strings cannot represent isolated UTF-16 surrogates. Refuse them
  // before encoding/merging, rather than replacing source bytes on one client.
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  return true;
}

export const validProjectName = (name: string) => !!name.trim() && name.length <= 80 && isWellFormedUTF16(name) && !/[\u0000-\u001f\u007f]/.test(name);

/** One path on its own; collisions between paths are checked by the whole document. */
export function isValidSourcePath(path: string): boolean {
  const parts = path.split("/");
  return !(path.length > 180 || !isWellFormedUTF16(path) || path.startsWith("/") || path.includes("\\") || path.includes(":") || parts.length > 32 || parts.some(part => !part || encoder.encode(part).length > 255 || part === "." || part === ".." || forbidden.has(part.toLowerCase()) || part === "__proto__" || part === "constructor" || part === "prototype") ||
      !allowed.test(path) || /[\u0000-\u001f\u007f]/.test(path));
}

/** Text the interpreter and every client can hold, apart from the size limits. */
export const isValidSourceText = (text: string) => isWellFormedUTF16(text) && !/\u0000/.test(text);

// Typing keeps its spaces in the input; the trimmed name is stored when editing ends.
// Returns null when there is nothing to store, and throws when the name cannot be stored.
export function committedProjectName(draft: string, current: string): string | null {
  const name = draft.trim();
  if (!name || name === current) return null;
  if (!validProjectName(name)) throw new Error("Use a project name of up to 80 characters without control characters.");
  return name;
}

function sourceOriginURL(value: string): string {
  // The fixed native codec uses JavaScriptCore, which has no browser URL API.
  // Its only fallback is a bounded Foundation validator for these source links;
  // no URL fetching, filesystem access or project evaluation is exposed.
  if (typeof URL === "function") {
    const url = new URL(value);
    if (url.protocol !== "https:" || !["github.com", "gist.github.com"].includes(url.hostname) || url.username || url.password) throw new Error("Invalid source origin.");
    return url.toString();
  }
  const validate = (globalThis as unknown as { __pythiloSourceOrigin?: (value: string) => string | null }).__pythiloSourceOrigin;
  const normalized = validate?.(value);
  if (typeof normalized !== "string" || normalized.length >= 1000) throw new Error("Invalid source origin.");
  return normalized;
}

/** Ignores a missing or malformed origin, and throws for a link outside the allowed hosts. */
export function sourceOrigin(value: unknown): PlaygroundDocument["origin"] {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const candidate = value as Record<string, unknown>;
  if (typeof candidate.url !== "string" || candidate.url.length >= 1000) return undefined;
  const origin: NonNullable<PlaygroundDocument["origin"]> = { url: sourceOriginURL(candidate.url) };
  if (typeof candidate.commit === "string" && /^[a-f0-9]{40}$/.test(candidate.commit)) origin.commit = candidate.commit;
  return origin;
}

export function sourceBytes(files: Record<string, string>): number {
  return Object.values(files).reduce((sum, text) => sum + encoder.encode(text).byteLength, 0);
}

export function validatePlaygroundDocument(input: unknown): PlaygroundDocument {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid source project.");
  const value = input as Record<string, unknown>;
  if (value.schemaVersion !== 1 || typeof value.name !== "string" || !validProjectName(value.name) || typeof value.entryFile !== "string" ||
      !value.files || typeof value.files !== "object" || Array.isArray(value.files)) throw new Error("Invalid source project fields.");
  const entries = Object.entries(value.files);
  if (entries.length < 1 || entries.length > PLAYGROUND_LIMITS.files) throw new Error("A Playground supports 1–16 source files.");
  const files: Record<string, string> = Object.create(null);
  const canonicalPaths = new Set<string>(), directories = new Map<string, string>();
  const canonical = (path: string) => path.normalize("NFC").toLowerCase();
  let size = 0;
  for (const [path, text] of entries) {
    const parts = path.split("/");
    if (!isValidSourcePath(path)) throw new Error(`Unsupported source path: ${path.slice(0, 80)}`);
    const key = canonical(path);
    if (canonicalPaths.has(key)) throw new Error("Source paths collide on a native filesystem. No source was changed.");
    canonicalPaths.add(key);
    for (let depth = 1; depth < parts.length; depth++) {
      const parent = parts.slice(0, depth).join("/"), key = canonical(parent), previous = directories.get(key);
      if (previous !== undefined && previous.normalize("NFC") !== parent.normalize("NFC")) throw new Error("Source directory spellings conflict. No source was changed.");
      directories.set(key, parent);
    }
    if (typeof text !== "string" || !isValidSourceText(text) || encoder.encode(text).byteLength > PLAYGROUND_LIMITS.fileBytes) throw new Error("Each file must contain well-formed UTF-8 text up to 64 KiB; binary/media files are not accepted.");
    size += encoder.encode(text).byteLength;
    files[path] = text;
  }
  for (const key of directories.keys()) if (canonicalPaths.has(key)) throw new Error("A source file conflicts with a directory. No source was changed.");
  if (size > PLAYGROUND_LIMITS.sourceBytes) throw new Error("The source project exceeds 128 KiB.");
  if (!(value.entryFile in files) || !value.entryFile.endsWith(".py")) throw new Error("Choose a Python entry file.");
  const origin = sourceOrigin(value.origin);
  return { schemaVersion: 1, name: value.name.trim(), entryFile: value.entryFile, files, ...(origin ? { origin } : {}) };
}

export function newPlaygroundDocument(): PlaygroundDocument {
  return { schemaVersion: 1, name: "hello-pythilo", entryFile: "main.py", files: {
    "main.py": 'def greet(name):\n    return f"Hello, {name}!"\n\n\nprint(greet("Pythilo"))\n',
  } };
}
