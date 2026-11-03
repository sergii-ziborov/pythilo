import { parser } from "@lezer/python";
import { highlightTree, tagHighlighter, tags } from "@lezer/highlight";

/** Token classes shared by static code on the site and the CodeMirror editor. */
export const pythonHighlighter = tagHighlighter([
  { tag: tags.keyword, class: "py-keyword" },
  { tag: [tags.function(tags.variableName), tags.function(tags.definition(tags.variableName)), tags.function(tags.propertyName)], class: "py-function" },
  { tag: [tags.definition(tags.className), tags.className], class: "py-class" },
  { tag: [tags.number, tags.bool, tags.null], class: "py-number" },
  { tag: [tags.string, tags.special(tags.string)], class: "py-string" },
  { tag: tags.comment, class: "py-comment" },
  { tag: tags.meta, class: "py-decorator" },
  { tag: tags.self, class: "py-self" },
]);

export type CodeToken = { text: string; className?: string };

/** Lines of tokens, so callers can number lines or wrap them. */
export function highlightPython(code: string): CodeToken[][] {
  const lines: CodeToken[][] = [[]];
  let cursor = 0;
  const push = (text: string, className?: string) => {
    const parts = text.split("\n");
    parts.forEach((part, index) => {
      if (index > 0) lines.push([]);
      if (part) lines.at(-1)!.push(className ? { text: part, className } : { text: part });
    });
  };
  const tree = parser.parse(code);
  highlightTree(tree, pythonHighlighter, (from, to, classes) => {
    if (from > cursor) push(code.slice(cursor, from));
    push(code.slice(from, to), classes);
    cursor = to;
  });
  if (cursor < code.length) push(code.slice(cursor));
  return lines;
}
