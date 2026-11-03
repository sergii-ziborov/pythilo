"use client";

import { useEffect, useRef } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { editorTheme, languageFor, pythonColors } from "./editor-setup";

/** A single-file Python editor without collaboration, for lessons. */
export function PlainEditor({ value, onChange, label, version }: { value: string; onChange: (value: string) => void; label: string; version: number }) {
  const parent = useRef<HTMLDivElement>(null), change = useRef(onChange); change.current = onChange;
  useEffect(() => {
    if (!parent.current) return;
    const editor = new EditorView({ parent: parent.current, state: EditorState.create({ doc: value, extensions: [
      lineNumbers(), history(), highlightActiveLine(), drawSelection(), indentOnInput(), bracketMatching(), closeBrackets(), EditorState.tabSize.of(4), EditorView.lineWrapping,
      ...languageFor("solution.py"), syntaxHighlighting(pythonColors), editorTheme,
      keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...historyKeymap, indentWithTab]),
      EditorView.updateListener.of(update => { if (update.docChanged) change.current(update.state.doc.toString()); }),
      EditorView.contentAttributes.of({ "aria-label": label, spellcheck: "false", autocorrect: "off", autocapitalize: "off" }),
    ] }) });
    return () => editor.destroy();
    // A new version replaces the text, for example after Reset.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version]);
  return <div className="plain-editor" ref={parent} />;
}
