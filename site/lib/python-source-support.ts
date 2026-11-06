import runtime from "../content/runtime.json" with { type: "json" };

const supported = new Set<string>([...runtime.stdlib, ...runtime.imports]);

/** Reading blocks can need different packages from the lesson's exercise. */
export function browserSourceMissing(source: string): string[] {
  const names = new Set<string>();
  for (const line of source.split("\n")) {
    const from = line.match(/^\s*from\s+([A-Za-z_]\w*)[\w.]*\s+import\b/);
    if (from) { names.add(from[1]); continue; }
    const plain = line.match(/^\s*import\s+(.+)$/);
    if (plain) for (const part of plain[1].split(",")) {
      const name = part.trim().match(/^([A-Za-z_]\w*)/);
      if (name) names.add(name[1]);
    }
  }
  const missing = [...names].filter(name => !supported.has(name));
  if (/\b(threading|concurrent\.futures|to_thread|ThreadPoolExecutor)\b/.test(source)) missing.push("threads");
  return [...new Set(missing)].sort();
}
