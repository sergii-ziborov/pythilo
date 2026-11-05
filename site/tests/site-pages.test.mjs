// Keeps the licences page, the guide and the screenshots in step with the repository.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { pythonPackages } from '../lib/licenses.ts';
import { guidePages } from '../lib/guide.ts';
import { gallery, shots } from '../lib/shots.ts';

const site = join(dirname(fileURLToPath(import.meta.url)), '..');
const repository = join(site, '..');
const normal = name => name.toLowerCase().replace(/[-_.]+/g, '-');

test('the licences page lists every bundled Python package at its locked version', () => {
  const lock = readFileSync(join(repository, 'runtime', 'requirements.lock'), 'utf8');
  const locked = new Map([...lock.matchAll(/^([A-Za-z0-9_.-]+)==([^\s\\]+)/gm)].map(([, name, version]) => [normal(name), version]));
  const listed = new Map(pythonPackages.map(([name, version]) => [normal(name), version]));
  assert.deepEqual([...listed.keys()].sort(), [...locked.keys()].sort());
  for (const [name, version] of locked) assert.equal(listed.get(name), version, name);
});

test('every guide page exists and every screenshot file is there', () => {
  for (const page of guidePages) assert.ok(existsSync(join(site, 'app', 'guide', page.slug, 'page.tsx')), page.slug);
  for (const shot of Object.values(shots)) assert.ok(existsSync(join(site, 'public', 'shots', `${shot.file}.webp`)), shot.file);
  assert.ok(gallery.length >= 8);
  for (const shot of gallery) assert.ok(shot.alt.length > 20, `${shot.file} needs real alt text`);
});

test('placeholders for undecided facts stay marked, never invented', () => {
  const info = readFileSync(join(site, 'lib', 'site-info.ts'), 'utf8');
  assert.doesNotMatch(info, /@gmail\.com/, 'no personal address on the site');
  for (const page of ['app/legal/terms/page.tsx', 'app/legal/privacy/page.tsx', 'app/pricing/page.tsx', 'app/guide/sqlite/page.tsx']) {
    assert.match(readFileSync(join(site, page), 'utf8'), /Placeholder/, page);
  }
});
