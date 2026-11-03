// The small Markdown subset the course files use: headings, paragraphs, fenced
// code, bullet and numbered lists, inline code, emphasis and links.
export type MarkdownBlock =
  | { kind: "heading"; level: number; text: string }
  | { kind: "paragraph"; text: string }
  | { kind: "code"; language: string; code: string }
  | { kind: "list"; ordered: boolean; items: string[] };

export function parseMarkdown(source: string): MarkdownBlock[] {
  const lines = source.replace(/\r\n/g, "\n").split("\n"), blocks: MarkdownBlock[] = [];
  let paragraph: string[] = [];
  const close = () => { if (paragraph.length) blocks.push({ kind: "paragraph", text: paragraph.join(" ").trim() }); paragraph = []; };
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
    const heading = line.match(/^(#{1,6})\s+(.+)$/);
    if (heading) { close(); blocks.push({ kind: "heading", level: heading[1].length, text: heading[2].trim() }); continue; }
    const item = line.match(/^\s*(?:([-*])|(\d+)\.)\s+(.+)$/);
    if (item) {
      close();
      const ordered = !!item[2], last = blocks.at(-1);
      if (last?.kind === "list" && last.ordered === ordered) last.items.push(item[3]);
      else blocks.push({ kind: "list", ordered, items: [item[3]] });
      continue;
    }
    // An indented line continues the previous list item.
    const last = blocks.at(-1);
    if (/^\s{2,}\S/.test(line) && !paragraph.length && last?.kind === "list") { last.items[last.items.length - 1] += " " + line.trim(); continue; }
    if (!line.trim()) { close(); continue; }
    paragraph.push(line.trim());
  }
  close();
  return blocks;
}

export type InlinePart = { kind: "text" | "code" | "strong" | "em"; text: string } | { kind: "link"; text: string; href: string };

export function parseInline(text: string): InlinePart[] {
  const parts: InlinePart[] = [], pattern = /`([^`]+)`|\*\*([^*]+)\*\*|(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])|(?<![\w_])_([^_\s][^_]*)_(?![\w_])|\[([^\]]+)\]\(([^)\s]+)\)/g;
  let cursor = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > cursor) parts.push({ kind: "text", text: text.slice(cursor, match.index) });
    if (match[1] !== undefined) parts.push({ kind: "code", text: match[1] });
    else if (match[2] !== undefined) parts.push({ kind: "strong", text: match[2] });
    else if (match[3] !== undefined || match[4] !== undefined) parts.push({ kind: "em", text: match[3] ?? match[4] });
    else if (/^(https?:\/\/|\/)/.test(match[6])) parts.push({ kind: "link", text: match[5], href: match[6] });
    else parts.push({ kind: "text", text: match[5] });
    cursor = match.index + match[0].length;
  }
  if (cursor < text.length) parts.push({ kind: "text", text: text.slice(cursor) });
  return parts;
}
