import { test } from "node:test";
import assert from "node:assert/strict";
import { zipSync, strToU8 } from "fflate";
import { buildFileTree, flattenTree, folderPaths, moveOperation, movedPath, planFileOperation } from "../lib/playground-file-ops.ts";
import { readUploads } from "../lib/playground-upload.ts";

const project = () => ({ schemaVersion: 1, name: "demo", entryFile: "main.py", files: { "main.py": "import pkg.util\n", "pkg/util.py": "X = 1\n", "pkg/__init__.py": "", "notes.md": "# n\n" } });
const names = (paths, empty = [], open = []) => flattenTree(buildFileTree(paths, empty), new Set(open)).map(item => item.node.path);

test("empty folders show in the tree without being stored", () => {
  assert.deepEqual(names(["main.py"], ["data", "pkg/sub"], ["pkg"]), ["data", "pkg", "pkg/sub", "main.py"]);
  assert.deepEqual(names(["pkg/a.py"], ["pkg"], ["pkg"]), ["pkg", "pkg/a.py"], "an empty folder that gained a file is listed once");
  const empty = buildFileTree([], ["data"])[0];
  assert.equal(empty.kind, "folder"); assert.deepEqual(empty.children, []);
});

test("undoing a delete puts the files and the main file back", () => {
  const before = project();
  const deleted = planFileOperation(before, { kind: "delete-folder", path: "pkg" });
  assert.deepEqual(deleted.removed.sort(), ["pkg/__init__.py", "pkg/util.py"]);
  const files = Object.fromEntries(deleted.removed.map(path => [path, before.files[path]]));
  const restored = planFileOperation(deleted.document, { kind: "add-files", files });
  assert.deepEqual({ ...restored.document.files }, before.files);

  const noMain = planFileOperation(before, { kind: "delete-file", path: "main.py" });
  assert.equal(noMain.document.entryFile, "pkg/__init__.py", "the first remaining Python file runs instead");
  const back = planFileOperation(noMain.document, { kind: "add-files", files: { "main.py": before.files["main.py"] }, entryFile: "main.py" });
  assert.equal(back.document.entryFile, "main.py");
});

test("adding files overwrites by path, keeps one spelling per path and respects the limits", () => {
  const plan = planFileOperation(project(), { kind: "add-files", files: { "NOTES.md": "new\n", "data/rows.csv": "a\n" } });
  assert.equal(plan.document.files["NOTES.md"], "new\n");
  assert.equal("notes.md" in plan.document.files, false);
  assert.deepEqual(plan.added, ["NOTES.md", "data/rows.csv"]);
  assert.equal(planFileOperation(project(), { kind: "add-files", files: {}, entryFile: "pkg/util.py" }).document.entryFile, "pkg/util.py", "an empty add only changes the main file");
  const many = Object.fromEntries(Array.from({ length: 16 }, (_, index) => [`f${index}.py`, ""]));
  assert.throws(() => planFileOperation(project(), { kind: "add-files", files: many }), /1–16/);
  assert.throws(() => planFileOperation(project(), { kind: "add-files", files: { "photo.png": "x" } }), /Unsupported/);
});

test("moving into a folder keeps the name and refuses a folder inside itself", () => {
  assert.equal(movedPath("pkg/util.py", ""), "util.py");
  assert.equal(movedPath("main.py", "pkg"), "pkg/main.py");
  assert.deepEqual(moveOperation({ kind: "file", path: "main.py" }, "pkg"), { kind: "rename", from: "main.py", to: "pkg/main.py" });
  assert.deepEqual(moveOperation({ kind: "folder", path: "pkg" }, "lib"), { kind: "rename-folder", from: "pkg", to: "lib/pkg" });
  assert.equal(moveOperation({ kind: "file", path: "pkg/util.py" }, "pkg"), null, "already there");
  assert.equal(moveOperation({ kind: "folder", path: "pkg" }, "pkg/sub"), null, "inside itself");
  const moved = planFileOperation(project(), moveOperation({ kind: "file", path: "main.py" }, "pkg"));
  assert.equal(moved.document.entryFile, "pkg/main.py", "the main file follows its move");
  assert.deepEqual(folderPaths(["a/b/c.py", "a/d.py", "e.py"]), ["a", "a/b"]);
});

test("uploads keep text files, unpack a ZIP and skip what a project cannot hold", () => {
  const text = name => ({ name, bytes: strToU8(`# ${name}\n`) });
  const zip = { name: "repo-main.zip", bytes: zipSync({ "repo-main/app.py": strToU8("print(1)\n"), "repo-main/data/a.csv": strToU8("a\n"), "repo-main/logo.png": new Uint8Array([0x89, 0x50, 0xff, 0xfe]), "__MACOSX/repo-main/._app.py": strToU8("x") }) };
  const result = readUploads([text("main.py"), { name: "photo.jpg", bytes: new Uint8Array([0xff, 0xd8, 0xff]) }, zip]);
  assert.deepEqual(Object.keys(result.files).sort(), ["app.py", "data/a.csv", "main.py"], "GitHub's top folder is dropped");
  assert.deepEqual(result.skipped.sort(), ["logo.png", "photo.jpg"]);
  assert.deepEqual(Object.keys(readUploads([text("util.py")], "pkg").files), ["pkg/util.py"]);
  const packaged = readUploads([{ name: "p.zip", bytes: zipSync({ "pkg/__init__.py": strToU8(""), "pkg/core.py": strToU8("") }) }]);
  assert.deepEqual(Object.keys(packaged.files).sort(), ["pkg/__init__.py", "pkg/core.py"], "a top-level package keeps its folder");
  assert.equal(readUploads([{ name: "bom.py", bytes: new Uint8Array([0xef, 0xbb, 0xbf, 0x78]) }]).files["bom.py"], "x", "a byte order mark is dropped");
  assert.deepEqual(readUploads([{ name: "broken.zip", bytes: strToU8("not a zip") }]).skipped, ["broken.zip"]);
});
