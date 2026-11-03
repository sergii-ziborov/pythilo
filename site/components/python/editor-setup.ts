"use client";
import { EditorView } from "@codemirror/view";
import { HighlightStyle, StreamLanguage, LanguageDescription, indentUnit } from "@codemirror/language";
import { python } from "@codemirror/lang-python";
import { markdown } from "@codemirror/lang-markdown";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { tags } from "@lezer/highlight";

export const pythonColors = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--code-keyword)" },
  { tag: [tags.function(tags.variableName), tags.function(tags.definition(tags.variableName)), tags.function(tags.propertyName)], color: "var(--code-function)" },
  { tag: [tags.definition(tags.className), tags.className], color: "var(--code-class)" },
  { tag: [tags.number, tags.bool, tags.null], color: "var(--code-number)" },
  { tag: [tags.string, tags.special(tags.string)], color: "var(--code-string)" },
  { tag: tags.comment, color: "var(--code-comment)" },
  { tag: tags.meta, color: "var(--code-decorator)" },
  { tag: tags.self, color: "var(--code-keyword)" },
  { tag: tags.heading, color: "var(--text)", fontWeight: "700" },
]);

export const editorTheme = EditorView.theme({
  "&": { color: "var(--text)", backgroundColor: "transparent", height: "100%" },
  ".cm-scroller": { fontFamily: "var(--mono)", lineHeight: "23px" },
  ".cm-content": { caretColor: "var(--text)", padding: "10px 0" },
  ".cm-gutters": { backgroundColor: "transparent", border: "0", color: "var(--gutter)" },
  ".cm-lineNumbers .cm-gutterElement": { padding: "0 12px 0 8px", minWidth: "36px" },
  ".cm-activeLine": { backgroundColor: "rgba(90, 169, 255, .06)" },
  ".cm-activeLineGutter": { backgroundColor: "transparent", color: "var(--soft)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": { backgroundColor: "rgba(90, 169, 255, .28) !important" },
  ".cm-cursor": { borderLeftColor: "var(--text)" },
  ".cm-matchingBracket": { backgroundColor: "rgba(255, 212, 59, .18)", outline: "0" },
  ".cm-ySelectionInfo": { fontFamily: "var(--sans)", fontSize: "11px", fontWeight: "700", padding: "1px 5px", borderRadius: "4px", color: "#0B1016", opacity: "1", top: "-1.25em" },
}, { dark: true });

export function languageFor(path: string) {
  const lower = path.toLowerCase();
  if (lower.endsWith(".py") || lower.endsWith(".pyi")) return [python(), indentUnit.of("    ")];
  if (/\.(toml|cfg|ini)$/.test(lower)) return [StreamLanguage.define(toml)];
  if (lower.endsWith(".md")) return [markdown({ codeLanguages: [LanguageDescription.of({ name: "Python", alias: ["py", "python"], support: python() })] })];
  return [];
}
