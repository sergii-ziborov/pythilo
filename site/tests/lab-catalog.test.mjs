import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { allLabs, browserLabs, labTopics, labTopicAssignments } from '../lib/browser-labs.ts';
import { filterLabCatalog } from '../lib/lab-catalog.ts';

const cards = allLabs.map(lab => ({ id: lab.id, title: lab.title, summary: lab.summary, section: lab.section,
  topic: labTopicAssignments[lab.id], topicTitle: labTopics.find(topic => topic.id === labTopicAssignments[lab.id]).title,
  runtime: lab.runtime === 'pytorch' ? 'pytorch' : 'browser' }));
const filter = (overrides = {}) => filterLabCatalog(cards, { query: '', section: '', runtime: '', ...overrides });

test('one shared topic owns every app Lab, including the classic native catalog', () => {
  const native = readFileSync(new URL('../../Pythilo/UI/Labs/LabCatalog.swift', import.meta.url), 'utf8');
  const classic = [...native.matchAll(/LabInfo\(id: "([^"]+)"[^\n]*?section: \.(\w+)/g)].map(([,id]) => id);
  assert.equal(labTopics.length, 13);
  assert.deepEqual(Object.keys(labTopicAssignments).sort(), [...classic, ...allLabs.map(lab => lab.id)].sort());
  assert.equal(new Set(labTopics.map(topic => topic.id)).size, 13);
  for (const lab of allLabs) assert.equal(labTopics.find(topic => topic.id === labTopicAssignments[lab.id])?.section, lab.section, lab.id);
});

test('PyTorch Labs remain readable on the site and never enter browser execution', () => {
  assert.equal(allLabs.length, 92);
  assert.equal(browserLabs.length, 74);
  const native = allLabs.filter(lab => lab.runtime === 'pytorch');
  assert.equal(native.length, 18);
  assert.equal(native.filter(lab => lab.title.startsWith('Project:')).length, 6);
  const courses = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url))).courses;
  for (const lab of native) {
    assert.ok(!browserLabs.some(item => item.id === lab.id));
    const lesson = courses.flatMap(course => course.lessons).find(item => lab.lessons.includes(item.id));
    assert.ok(lesson?.missing.includes('torch'), lab.id);
    assert.equal(lesson.solution, lab.answer);
    assert.ok(lesson.checks.length >= 4);
  }
});

test('topic search finds concepts and combines with section and runtime filters', () => {
  assert.deepEqual(filter({ query: 'rotary' }).map(lab => lab.id), ['torchrope']);
  assert.equal(filter({ query: 'pytorch training', runtime: 'pytorch' }).length, 9);
  assert.equal(filter({ runtime: 'pytorch', section: 'Machine learning' }).length, 9);
  assert.equal(filter({ runtime: 'pytorch', section: 'Artificial intelligence' }).length, 9);
  assert.equal(filter({ query: 'rotary', runtime: 'browser' }).length, 0);
  assert.equal(filter({ query: 'does-not-exist' }).length, 0);
  assert.equal(filter({ query: '   ' }).length, 92);
  assert.deepEqual(filter({ query: '  RoTaRy   geometry  ' }).map(lab => lab.id), ['torchrope']);
});
