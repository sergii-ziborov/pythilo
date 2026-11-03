import { test } from "node:test";
import assert from "node:assert/strict";
import { runtimeSource, runtimeSourceRevision } from "../src/core/playground-runtime-source";
import { newPlaygroundDocument, validatePlaygroundDocument } from "../src/core/playground-document";

const source = { ...newPlaygroundDocument(), name: "Unicode 🐍", files: { "🐍.py": "N = 1\n", "main.py": 'print("🐍")\n', "é.py": "# café\n" } };
test("source identity preserves exact Unicode bytes with locale-independent path ordering", async () => {
  const value = runtimeSource(source);
  assert.deepEqual(value.paths, ["main.py", "é.py", "🐍.py"]);
  assert.equal(value.canonical, '["pythilo-runtime-source-v1","Unicode 🐍","main.py",[["main.py","print(\\"🐍\\")\\n"],["é.py","# café\\n"],["🐍.py","N = 1\\n"]]]');
  const reversed = { ...source, files: Object.fromEntries(Object.entries(source.files).reverse()), origin: { url: "https://github.com/example/source", commit: "a".repeat(40) } };
  assert.equal(await runtimeSourceRevision(source), await runtimeSourceRevision(reversed));
  assert.notEqual(await runtimeSourceRevision(source), await runtimeSourceRevision({ ...source, entryFile: "é.py" }));
  assert.notEqual(await runtimeSourceRevision(source), await runtimeSourceRevision({ ...source, files: { ...source.files, "é.py": "# café\n" } }));
});

test("native path aliases and unpaired surrogates are refused before a room merge", () => {
  for (const extra of [
    { "MAIN.py": "case alias" }, { "é.py": "Unicode alias" }, { "main.py/child.py": "file directory collision" },
    { "Folder/a.py": "a", "folder/b.py": "b" }, { ["🐍".repeat(70) + ".py"]: "long component" },
    { "bad.py": "unpaired \ud800" }, { ["bad\udfff.py"]: "bad path" },
  ]) assert.throws(() => validatePlaygroundDocument({ ...source, files: { ...source.files, ...extra } }));
  assert.throws(() => runtimeSource({ ...source, name: "bad\ud800" }));
  assert.equal(source.files["é.py"], "# café\n");
});
