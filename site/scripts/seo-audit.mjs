// Checks what search engines and link previews see on every page of the sitemap.
//   node scripts/seo-audit.mjs <origin> [--sample N]
// For each URL: 200, one h1, a unique title, a description of 50 to 170 characters, a canonical
// that is the page itself, Open Graph and Twitter tags, JSON-LD that parses, and no noindex.
const origin = (process.argv[2] ?? "https://pythilo.com").replace(/\/$/, "");
const sampleAt = process.argv.indexOf("--sample");
const sample = sampleAt > 0 ? Number(process.argv[sampleAt + 1]) : 0;
const problems = [];
const fail = (path, message) => problems.push(`${path}  ${message}`);
const text = async path => { const response = await fetch(origin + path, { redirect: "manual" }); return { response, body: await response.text() }; };

const sitemap = (await text("/sitemap.xml")).body;
let paths = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => new URL(match[1]).pathname);
if (new Set(paths).size !== paths.length) fail("/sitemap.xml", "lists a URL twice");
const total = paths.length;
if (sample && sample < paths.length) {
  const kinds = new Map();
  for (const path of paths) { const kind = path.split("/").slice(1, 3).join("/").replace(/\/[^/]+$/, "/*"); if (!kinds.has(kind)) kinds.set(kind, path); }
  const step = Math.max(1, Math.floor(paths.length / sample));
  paths = [...new Set([...kinds.values(), ...paths.filter((_, index) => index % step === 0)])];
}

const attribute = (tag, name) => tag.match(new RegExp(`${name}="([^"]*)"`))?.[1];
const meta = (html, key, value) => { const tag = html.match(new RegExp(`<meta[^>]*${key}="${value}"[^>]*>`))?.[0]; return tag ? attribute(tag, "content") : undefined; };
const decode = value => value?.replace(/&#x27;/g, "'").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">");
const titles = new Map(), descriptions = new Map();

async function check(path) {
  const { response, body } = await text(path);
  if (response.status !== 200) return fail(path, `status ${response.status}`);
  if (/noindex/.test(response.headers.get("x-robots-tag") ?? "") || /<meta[^>]*name="robots"[^>]*noindex/.test(body)) fail(path, "is noindex but is in the sitemap");
  const h1 = (body.match(/<h1[\s>]/g) ?? []).length;
  if (h1 !== 1) fail(path, `${h1} h1 elements`);
  const title = decode(body.match(/<title>([^<]*)<\/title>/)?.[1] ?? "");
  if (!title) fail(path, "no title"); else titles.set(title, [...(titles.get(title) ?? []), path]);
  const description = decode(meta(body, "name", "description") ?? "");
  if (description.length < 50 || description.length > 170) fail(path, `description is ${description.length} characters`);
  else descriptions.set(description, [...(descriptions.get(description) ?? []), path]);
  const canonical = body.match(/<link rel="canonical" href="([^"]+)"/)?.[1];
  if (!canonical) fail(path, "no canonical"); else if (new URL(canonical).pathname !== path) fail(path, `canonical is ${canonical}`);
  else if (!canonical.startsWith("https://")) fail(path, "canonical is not https");
  for (const property of ["og:title", "og:description", "og:image", "og:url", "og:site_name"]) if (!meta(body, "property", property)) fail(path, `no ${property}`);
  if (!meta(body, "name", "twitter:card")) fail(path, "no twitter:card");
  for (const block of body.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try { const data = JSON.parse(block[1]); if (!data["@context"] || !data["@type"]) fail(path, "JSON-LD without @context or @type"); }
    catch { fail(path, "JSON-LD does not parse"); }
  }
}

const queue = [...paths];
await Promise.all(Array.from({ length: 8 }, async () => { for (let path; (path = queue.shift());) await check(path).catch(error => fail(path, String(error))); }));
for (const [title, pages] of titles) if (pages.length > 1) fail(pages[0], `title "${title}" is shared with ${pages.slice(1, 4).join(", ")}${pages.length > 4 ? ` and ${pages.length - 4} more` : ""}`);
for (const [description, pages] of descriptions) if (pages.length > 1) fail(pages[0], `description is shared with ${pages.slice(1, 4).join(", ")}${pages.length > 4 ? ` and ${pages.length - 4} more` : ""}: "${description.slice(0, 60)}…"`);

const assets = [["/favicon.ico", /icon/], ["/icon.svg", /svg/], ["/apple-icon.png", /png/], ["/icons/icon-192.png", /png/], ["/icons/icon-512.png", /png/], ["/icons/maskable-512.png", /png/], ["/manifest.webmanifest", /manifest\+json|json/], ["/opengraph-image.png", /png/], ["/robots.txt", /text\/plain/], ["/sitemap.xml", /xml/], ["/blog/rss.xml", /xml/]];
for (const [path, type] of assets) {
  const response = await fetch(origin + path);
  if (!response.ok || !type.test(response.headers.get("content-type") ?? "")) fail(path, `status ${response.status}, type ${response.headers.get("content-type")}`);
}
const robots = (await text("/robots.txt")).body;
if (!/Sitemap: https:\/\/pythilo\.com\/sitemap\.xml/.test(robots)) fail("/robots.txt", "does not point at https://pythilo.com/sitemap.xml");
const home = (await text("/")).body;
if (!/apple-itunes-app" content="app-id=6829637526"/.test(home)) fail("/", "no Smart App Banner tag");
if (!/"@type":"SoftwareApplication"/.test(home)) fail("/", "no SoftwareApplication structured data");

for (const problem of problems.sort()) console.log(problem);
console.log(`${paths.length} of ${total} sitemap pages checked on ${origin}: ${problems.length} problem(s)`);
process.exit(problems.length ? 1 : 0);
