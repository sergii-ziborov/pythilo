import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { absolute, allPosts } from "../_lib/posts";

export const dynamic = "force-static";

const escape = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const types: Record<string, string> = { webp: "image/webp", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };
function enclosure(src: string) {
  const file = join(process.cwd(), "public", src.replace(/^\/+/, ""));
  if (!existsSync(file)) return "";
  const type = types[src.split(".").pop()!.toLowerCase()] ?? "application/octet-stream";
  return `      <enclosure url="${escape(absolute(src))}" type="${type}" length="${statSync(file).size}" />\n`;
}
const rfc822 = (date: string) => new Date(`${date}T09:00:00Z`).toUTCString();

export function GET() {
  const posts = allPosts(), home = absolute("/blog/");
  const items = posts.map(post => {
    const link = absolute(`/blog/${post.slug}/`);
    return `    <item>
      <title>${escape(post.title)}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      <pubDate>${rfc822(post.date)}</pubDate>
      <description>${escape(post.description)}</description>
${post.tags.map(tag => `      <category>${escape(tag)}</category>\n`).join("")}${post.cover ? enclosure(post.cover) : ""}    </item>`;
  }).join("\n");
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Pythilo blog</title>
    <link>${home}</link>
    <description>News and notes on Python, PyTorch and learning to code.</description>
    <language>en</language>
    <atom:link href="${absolute("/blog/rss.xml")}" rel="self" type="application/rss+xml" />
${posts[0] ? `    <lastBuildDate>${rfc822(posts[0].updated ?? posts[0].date)}</lastBuildDate>\n` : ""}${items}
  </channel>
</rss>
`;
  return new Response(xml, { headers: { "Content-Type": "application/rss+xml; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
}
