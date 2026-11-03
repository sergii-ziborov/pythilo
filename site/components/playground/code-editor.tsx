"use client";

import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { yCollab, yUndoManagerKeymap, ySyncAnnotation } from "y-codemirror.next";
import * as Y from "yjs";
import type { Awareness } from "y-protocols/awareness";
import { editorTheme, languageFor, pythonColors } from "@/components/python/editor-setup";

/** Lives as long as the workspace, so switching files keeps Undo, the cursor and the scroll position. */
export type FileEditorState = { text: Y.Text; undo: Y.UndoManager; anchor: number; head: number; top: number; left: number };
export function createFileEditorState(text: Y.Text): FileEditorState { return { text, undo: new Y.UndoManager(text), anchor: 0, head: 0, top: 0, left: 0 }; }

export function PlaygroundCodeEditor({ fileState, readOnly, onLimit, awareness, maximumBytes, filePath }: {
  filePath: string; awareness: Awareness; maximumBytes: number; fileState: FileEditorState; readOnly: boolean; onLimit: () => void;
}) {
  const text = fileState.text;
  const parent = useRef<HTMLDivElement>(null), view = useRef<EditorView | null>(null);
  const configuration = useRef(new Compartment());
  const onLimitRef = useRef(onLimit); onLimitRef.current = onLimit;
  const maximumRef = useRef(maximumBytes); maximumRef.current = maximumBytes;
  const options = (locked: boolean) => [EditorState.readOnly.of(locked), EditorView.editable.of(!locked)];

  useEffect(() => {
    if (!parent.current) return;
    const undo = fileState.undo, length = text.length;
    const state = EditorState.create({ doc: text.toString(), selection: { anchor: Math.min(fileState.anchor, length), head: Math.min(fileState.head, length) }, extensions: [
      lineNumbers(), highlightActiveLine(), highlightActiveLineGutter(), drawSelection(), indentOnInput(), bracketMatching(), closeBrackets(), EditorState.tabSize.of(4),
      ...languageFor(filePath), syntaxHighlighting(pythonColors), editorTheme,
      keymap.of([...yUndoManagerKeymap, ...closeBracketsKeymap, ...defaultKeymap, indentWithTab]),
      yCollab(text, awareness, { undoManager: undo }),
      configuration.current.of(options(readOnly)),
      EditorState.transactionFilter.of(transaction => {
        // An edit that shortens the file is always allowed, so an oversized file can be fixed.
        const size = (doc: typeof transaction.newDoc) => new TextEncoder().encode(doc.toString()).length;
        if (!transaction.annotation(ySyncAnnotation) && transaction.docChanged && size(transaction.newDoc) > maximumRef.current && size(transaction.newDoc) > size(transaction.startState.doc)) {
          queueMicrotask(() => onLimitRef.current()); return [];
        }
        return transaction;
      }),
      EditorView.contentAttributes.of({ "aria-label": `${filePath} source`, spellcheck: "false", autocorrect: "off", autocapitalize: "off" }),
    ] });
    const editor = new EditorView({ parent: parent.current, state }); view.current = editor;
    editor.scrollDOM.scrollTo(fileState.left, fileState.top);
    return () => {
      const selection = editor.state.selection.main;
      fileState.anchor = selection.anchor; fileState.head = selection.head;
      fileState.top = editor.scrollDOM.scrollTop; fileState.left = editor.scrollDOM.scrollLeft;
      view.current = null; editor.destroy();
    };
    // Y.Text identity changes only when switching files; read-only reconfigures below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fileState, filePath]);

  useEffect(() => { view.current?.dispatch({ effects: configuration.current.reconfigure(options(readOnly)) }); }, [readOnly]);
  return <div className="pg-code-editor" ref={parent} />;
}
