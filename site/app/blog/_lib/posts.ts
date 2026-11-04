// Blog posts: Markdown files in content/blog with a small front matter block.
//
//   ---
//   title: What's new in Python
//   description: One or two sentences for cards, feeds and search results.
//   date: 2026-11-04
//   author: Pythilo
//   cover: /blog/slug/cover.webp
//   coverAlt: What the cover shows, for people who cannot see it.
//   tags: Python, Releases
//   ---
//
// The body is Markdown: headings, paragraphs, lists, fenced code, block quotes,
// rules and figures, written as an image alone on its line with an optional
// caption in the title: ![alt text](/blog/slug/image.webp "Caption").
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const BLOG_DIR = join(process.cwd(), "content", "blog");
export const SITE_ORIGIN = (process.env.SITE_ORIGIN || "https://pythilo.com").replace(/\/$/, "");
export const WORDS_PER_MINUTE = 230;

export type BlogBlock =
  | { kind: "heading"; level: number; text: string; id: string }
  | { kind: "paragraph"; text: string }
  | { kind: "list"; ordered: boolean; items: string[] }
  | { kind: "code"; language: string; code: string }
  | { kind: "quote"; text: string }
  | { kind: "rule" }
  | { kind: "figure"; src: string; alt: string; caption: string };

export type BlogPost = {
  slug: string;
  title: string;
  description: string;
  date: string;
  updated?: string;
  author: string;
  cover?: string;
  coverAlt: string;
  tags: string[];
  body: string;
  blocks: BlogBlock[];
  words: number;
  minutes: number;
  toc: { id: string; text: string; level: number }[];
};

/** Text without Markdown punctuation, for slugs, word counts and feeds. */
export function plainText(markdown: string): string {
  return markdown
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)\]\([^)\s]+\)/g, "$1")
    .replace(/[`*_]/g, "");
}

export function slugify(text: string): string {
  return plainText(text).toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "section";
}

export function parseFrontMatter(source: string): { data: Record<string, string>; body: string } {
  const match = source.replace(/\r\n/g, "\n").match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!match) return { data: {}, body: source };
  const data: Record<string, string> = {};
  for (const line of match[1].split("\n")) {
    const field = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/);
    if (field) data[field[1]] = field[2].trim().replace(/^(["'])(.*)\1$/, "$2");
  }
  return { data, body: match[2] };
}

export function parseBlog(source: string): BlogBlock[] {
  const lines = source.replace(/\r\n/g, "\n").split("\n"), blocks: BlogBlock[] = [], ids = new Set<string>();
  let paragraph: string[] = [], quote: string[] = [];
  const closeParagraph = () => { if (paragraph.length) blocks.push({ kind: "paragraph", text: paragraph.join(" ").trim() }); paragraph = []; };
  const closeQuote = () => { if (quote.length) blocks.push({ kind: "quote", text: quote.join(" ").trim() }); quote = []; };
  const close = () => { closeParagraph(); closeQuote(); };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = line.match(/^```\s*([\w+-]*)\s*$/);
    if (fence) {
      close();
      const code: string[] = [];
      while (++i < lines.length && !/^```\s*$/.test(lines[i])) code.push(lines[i]);
      blocks.push({ kind: "code", language: fence[1].toLowerCase(), code: code.join("\n") });
      continue;
    }
    const heading = line.match(/^(#{2,4})\s+(.+)$/);
    if (heading) {
      close();
      const text = heading[2].trim(), base = slugify(text);
      let id = base;
      for (let n = 2; ids.has(id); n++) id = `${base}-${n}`;
      ids.add(id);
      blocks.push({ kind: "heading", level: heading[1].length, text, id });
      continue;
    }
    const figure = line.match(/^!\[([^\]]*)\]\((\S+?)(?:\s+"([^"]*)")?\)\s*$/);
    if (figure) { close(); blocks.push({ kind: "figure", alt: figure[1], src: figure[2], caption: figure[3] ?? "" }); continue; }
    if (/^\s*(---|\*\*\*)\s*$/.test(line)) { close(); blocks.push({ kind: "rule" }); continue; }
    const quoted = line.match(/^>\s?(.*)$/);
    if (quoted) { closeParagraph(); quote.push(quoted[1]); continue; }
    const item = line.match(/^\s*(?:([-*])|(\d+)\.)\s+(.+)$/);
    if (item) {
      close();
      const ordered = !!item[2], last = blocks.at(-1);
      if (last?.kind === "list" && last.ordered === ordered) last.items.push(item[3]);
      else blocks.push({ kind: "list", ordered, items: [item[3]] });
      continue;
    }
    const last = blocks.at(-1);
    if (/^\s{2,}\S/.test(line) && !paragraph.length && last?.kind === "list") { last.items[last.items.length - 1] += " " + line.trim(); continue; }
    if (!line.trim()) { close(); continue; }
    closeQuote();
    paragraph.push(line.trim());
  }
  close();
  return blocks;
}

/** Words a reader reads: prose, list items, quotes and captions; code blocks are left out. */
export function countWords(blocks: BlogBlock[]): number {
  const text = blocks.map(block => block.kind === "list" ? block.items.join(" ")
    : block.kind === "figure" ? block.caption
    : block.kind === "code" || block.kind === "rule" ? ""
    : block.text).join(" ");
  return plainText(text).split(/\s+/).filter(word => /[\p{L}\p{N}]/u.test(word)).length;
}

export function readPost(slug: string): BlogPost | undefined {
  const file = join(BLOG_DIR, `${slug}.md`);
  if (!/^[a-z0-9-]+$/.test(slug) || !existsSync(file)) return undefined;
  const { data, body } = parseFrontMatter(readFileSync(file, "utf8"));
  if (!data.title || !/^\d{4}-\d{2}-\d{2}$/.test(data.date ?? "")) throw new Error(`content/blog/${slug}.md needs a title and a date (YYYY-MM-DD)`);
  const blocks = parseBlog(body), words = countWords(blocks);
  return {
    slug, body, blocks, words,
    title: data.title,
    description: data.description ?? "",
    date: data.date,
    ...(data.updated ? { updated: data.updated } : {}),
    author: data.author || "Pythilo",
    ...(data.cover ? { cover: data.cover } : {}),
    coverAlt: data.coverAlt ?? "",
    tags: (data.tags ?? "").split(",").map(tag => tag.trim()).filter(Boolean),
    minutes: Math.max(1, Math.round(words / WORDS_PER_MINUTE)),
    toc: blocks.flatMap(block => block.kind === "heading" && block.level <= 3 ? [{ id: block.id, text: plainText(block.text), level: block.level }] : []),
  };
}

/** Every post, newest first. */
export function allPosts(): BlogPost[] {
  if (!existsSync(BLOG_DIR)) return [];
  return readdirSync(BLOG_DIR).filter(file => file.endsWith(".md")).map(file => readPost(file.slice(0, -3))!)
    .sort((a, b) => b.date.localeCompare(a.date) || a.title.localeCompare(b.title));
}

export function formatDate(date: string): string {
  return new Date(`${date}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
}

export const absolute = (path: string) => path.startsWith("http") ? path : `${SITE_ORIGIN}${path}`;
