import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { allPosts } from '../app/blog/_lib/posts.ts';
const { courses } = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url), 'utf8'));
import { browserLabs } from '../lib/browser-labs.ts';

const names = ['validation-without-leakage','precision-recall-thresholds','attention-in-small-python','cosine-retrieval-from-scratch','decoding-temperature-beams','bpe-merge-by-merge'];
test('practice articles have real covers, runnable examples and valid lesson/lab destinations', () => {
  const posts = allPosts();
  for (const name of names) {
    const post = posts.find(p => p.slug === name);
    assert.ok(post, name);
    assert.ok(post.words >= 300, name);
    assert.ok(existsSync(`public${post.cover}`), name);
    assert.ok(/\.(png|jpg|jpeg|gif)$/i.test(post.cover), `${name}: cover must work in link previews`);
    const cover = readFileSync(`public${post.cover}`);
    assert.equal(cover.toString('hex', 0, 8), '89504e470d0a1a0a');
    assert.ok(cover.readUInt32BE(16) >= 1200 && cover.readUInt32BE(20) >= 600);
    assert.ok(post.blocks.some(b => b.kind === 'code' && b.language === 'python'), name);
    for (const [,url] of post.body.matchAll(/\]\((\/(?:learn|labs)\/[^)]+)\)/g)) {
      const [,kind,id] = url.split('/');
      assert.ok(kind === 'labs' ? browserLabs.some(l => l.id === id) : courses.some(c => c.id === id), `${name}: ${url}`);
    }
  }
});
