import assert from "node:assert/strict";
import test from "node:test";
import { breadcrumbList, describe } from "../lib/seo.ts";

test("describe keeps short text and cuts long text on a word, within the limit", () => {
  assert.equal(describe("Short  text with `code`."), "Short text with code.");
  const long = describe("word ".repeat(80), 158);
  assert.ok(long.length <= 158, String(long.length));
  assert.ok(long.endsWith("word…"));
  assert.equal(describe("a".repeat(300), 100).length, 100);
});

test("breadcrumbs are absolute and numbered from one", () => {
  const list = breadcrumbList([["Learn", "/learn/"], ["Python foundations", "/learn/foundations/"]]);
  assert.deepEqual(list.itemListElement.map(item => [item.position, item.name, item.item]), [[1, "Learn", "https://pythilo.com/learn/"], [2, "Python foundations", "https://pythilo.com/learn/foundations/"]]);
});
