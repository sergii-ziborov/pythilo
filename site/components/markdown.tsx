import type { ReactNode } from "react";
import { parseInline, parseMarkdown } from "@/lib/markdown";
import { PythonCode } from "./python-code";

export function Inline({ text }: { text: string }) {
  return <>{parseInline(text).map((part, index) => part.kind === "code" ? <code key={index}>{part.text}</code>
    : part.kind === "strong" ? <strong key={index}>{part.text}</strong>
    : part.kind === "em" ? <em key={index}>{part.text}</em>
    : part.kind === "link" ? <a key={index} href={part.href} {...(part.href.startsWith("http") ? { target: "_blank", rel: "noreferrer" } : {})}>{part.text}</a>
    : part.text)}</>;
}

/** Server-rendered Markdown. `code` decides how a fenced block appears, for example with a Run button. */
export function Markdown({ source, code }: { source: string; code?: (code: string, language: string, index: number) => ReactNode }) {
  let codeIndex = 0;
  return <>{parseMarkdown(source).map((block, index) => {
    if (block.kind === "heading") { const Tag = (`h${Math.min(6, block.level + 1)}`) as "h2"; return <Tag key={index}><Inline text={block.text} /></Tag>; }
    if (block.kind === "paragraph") return <p key={index}><Inline text={block.text} /></p>;
    if (block.kind === "list") { const List = block.ordered ? "ol" : "ul"; return <List key={index}>{block.items.map((item, itemIndex) => <li key={itemIndex}><Inline text={item} /></li>)}</List>; }
    const position = codeIndex++;
    if (code) return <div key={index}>{code(block.code, block.language, position)}</div>;
    return block.language === "python" || block.language === "py" ? <PythonCode key={index} code={block.code} /> : <pre key={index} className="code-block"><code>{block.code}</code></pre>;
  })}</>;
}
