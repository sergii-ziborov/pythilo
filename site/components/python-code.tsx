import { highlightPython } from "@/lib/python-highlight";

/** Static, highlighted Python rendered on the server. */
export function PythonCode({ code, className = "code-block" }: { code: string; className?: string }) {
  const lines = highlightPython(code.replace(/\n$/, ""));
  return <pre className={className}><code>{lines.map((line, index) => <span key={index}>{line.map((token, part) => token.className ? <span key={part} className={token.className}>{token.text}</span> : token.text)}{index < lines.length - 1 ? "\n" : null}</span>)}</code></pre>;
}
