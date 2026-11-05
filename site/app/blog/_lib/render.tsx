import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Inline } from "@/components/markdown";
import { PythonCode } from "@/components/python-code";
import type { BlogBlock } from "./posts";

/** Width and height of a WebP, PNG or JPEG in public/, so the page reserves its space before it loads. */
export function imageSize(src: string): { width: number; height: number } | undefined {
  const file = join(process.cwd(), "public", src.replace(/^\/+/, ""));
  if (!src.startsWith("/") || !existsSync(file)) return undefined;
  const b = readFileSync(file);
  if (src.endsWith(".svg")) {
    const dimensions = b.toString("utf8").match(/<svg\b[^>]*\bwidth="(\d+)"[^>]*\bheight="(\d+)"/);
    if (dimensions) return { width: Number(dimensions[1]), height: Number(dimensions[2]) };
  }
  if (b.toString("ascii", 0, 4) === "RIFF" && b.toString("ascii", 8, 12) === "WEBP") {
    const chunk = b.toString("ascii", 12, 16);
    if (chunk === "VP8X") return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
    if (chunk === "VP8 ") return { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
    if (chunk === "VP8L") { const bits = b.readUInt32LE(21); return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff) }; }
  }
  if (b.readUInt32BE(0) === 0x89504e47) return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
  if (b[0] === 0xff && b[1] === 0xd8) {
    for (let i = 2; i < b.length - 9;) {
      if (b[i] !== 0xff) return undefined;
      const marker = b[i + 1], length = b.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) return { width: b.readUInt16BE(i + 7), height: b.readUInt16BE(i + 5) };
      i += 2 + length;
    }
  }
  return undefined;
}

export function BlogImage({ src, alt, priority = false, className }: { src: string; alt: string; priority?: boolean; className?: string }) {
  const size = imageSize(src);
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt={alt} {...size} className={className} loading={priority ? "eager" : "lazy"} decoding="async" {...(priority ? { fetchPriority: "high" as const } : {})} />;
}

export function BlogBody({ blocks }: { blocks: BlogBlock[] }) {
  return <>{blocks.map((block, index) => {
    switch (block.kind) {
      case "heading": {
        const Tag = `h${block.level}` as "h2" | "h3" | "h4";
        return <Tag key={index} id={block.id}><a href={`#${block.id}`} className="blog-anchor"><Inline text={block.text} /></a></Tag>;
      }
      case "paragraph": return <p key={index}><Inline text={block.text} /></p>;
      case "list": { const List = block.ordered ? "ol" : "ul"; return <List key={index}>{block.items.map((item, at) => <li key={at}><Inline text={item} /></li>)}</List>; }
      case "quote": return <blockquote key={index}><p><Inline text={block.text} /></p></blockquote>;
      case "rule": return <hr key={index} />;
      case "figure": return <figure key={index} className="blog-figure">
        <BlogImage src={block.src} alt={block.alt} />
        {block.caption ? <figcaption><Inline text={block.caption} /></figcaption> : null}
      </figure>;
      case "code": return block.language === "python" || block.language === "py"
        ? <PythonCode key={index} code={block.code} />
        : <pre key={index} className="code-block"><code>{block.code}</code></pre>;
    }
  })}</>;
}
