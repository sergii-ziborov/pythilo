import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { unzipSync, strFromU8 } from 'fflate';
const courses = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url))).courses;
const labs = JSON.parse(readFileSync(new URL('../content/labs.json', import.meta.url))).labs;

test('six complete project sources contain local code and a pinned separate asset fetcher', () => {
  const course = courses.find(course => course.id === 'finetuning-projects');
  assert.equal(course.lessons.length, 6);
  for (const name of ['full', 'lora', 'domain', 'compare', 'resume', 'merge']) {
    const bytes = readFileSync(new URL(`../public/projects/bert-${name}.zip`, import.meta.url));
    assert.ok(bytes.length < 100_000, `${name}: large dependencies do not belong in project code`);
    const files = unzipSync(bytes), root = `bert-${name}/`;
    for (const path of ['main.py', 'pythilo_finetune.py', 'requirements.txt', 'runtime/finetune-assets.json', `finetune_projects/${name}.py`, 'fetch_assets.py']) assert.ok(files[root + path], path);
    assert.ok(!Object.keys(files).some(path => path.endsWith('.safetensors') || path.includes('/assets/')));
    const spec = JSON.parse(strFromU8(files[root + 'runtime/finetune-assets.json']));
    assert.equal(spec.weights.bytes, 17_739_144);
    assert.match(spec.weights.sha256, /^[a-f0-9]{64}$/);
    assert.ok(spec.weights.url.includes(spec.revision));
    const lab = labs.find(lab => lab.id === `torchbert${name}`), lesson = course.lessons.find(lesson => lab.lessons.includes(lesson.id));
    assert.equal(strFromU8(files[root + `finetune_projects/${name}.py`]), lesson.solution);
    assert.equal(lab.answer, lesson.solution);
    assert.equal(lab.runtime, 'pytorch');
  }
});

test('published instructions describe the separate course/topic and dependency downloads', () => {
  const guide = readFileSync(new URL('../app/guide/learn/page.tsx', import.meta.url), 'utf8');
  assert.match(guide, /Courses and Lab topics download separately/);
  assert.match(guide, /pause, resume and removal/);
  const privacy = readFileSync(new URL('../app/legal/privacy/page.tsx', import.meta.url), 'utf8');
  assert.match(privacy, /Hugging Face/);
  assert.match(privacy, /training results and dataset rows stay on your device/);
});
