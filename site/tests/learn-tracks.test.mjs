// The Learn tracks: every course in exactly one group, in the app's order, each with an icon.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { courseIcon, courseIconIds, groupByTrack, learnTracks, nextLesson, trackOf } from '../lib/learn-tracks.ts';
import { learnIcons } from '../lib/learn-icons.ts';

const courses = JSON.parse(readFileSync(new URL('../content/courses.json', import.meta.url))).courses;
const ids = new Set(courses.map(course => course.id));

test('every course lands in exactly one track group', () => {
  const groups = groupByTrack(courses);
  const placed = groups.flatMap(group => group.courses.map(course => course.id));
  assert.equal(placed.length, courses.length);
  assert.deepEqual([...placed].sort(), [...ids].sort());
  assert.equal(new Set(placed).size, placed.length);
  for (const group of groups) for (const course of group.courses) assert.equal(trackOf(course), group.track, course.id);
  // Groups keep the order of the tracks, and listed tracks keep the order of their lists.
  assert.deepEqual(groups.map(group => group.track.id), learnTracks.map(track => track.id).filter(id => groups.some(group => group.track.id === id)));
  for (const group of groups.filter(group => group.track.courses.length)) assert.deepEqual(group.courses.map(course => course.id), group.track.courses.filter(id => ids.has(id)));
});

test('the tracks list only real courses, each once, and match the app', () => {
  const listed = learnTracks.flatMap(track => track.courses);
  for (const id of listed) assert.ok(ids.has(id), `${id} is not a course`);
  assert.equal(new Set(listed).size, listed.length);
  assert.deepEqual(learnTracks.map(track => track.title), ['Python', 'Web, data & APIs', 'Machine learning', 'AI & transformers', 'Algorithms & projects', 'Interview practice', 'More']);
  assert.equal(new Set(learnTracks.map(track => track.accent)).size, learnTracks.length);
  // The same lists as LearnTrack in the app.
  const source = readFileSync(new URL('../../Pythilo/UI/Learn/LearnViews.swift', import.meta.url), 'utf8');
  const native = Object.fromEntries([...source.matchAll(/^\s+\.(\w+): \[((?:"[^"]+"(?:, )?)+)\],?$/gm)].map(([, id, list]) => [id, [...list.matchAll(/"([^"]+)"/g)].map(([, course]) => course)]));
  assert.deepEqual(Object.keys(native), ['python', 'web', 'ml', 'ai', 'projects']);
  for (const [id, list] of Object.entries(native)) assert.deepEqual(learnTracks.find(track => track.id === id).courses, list, id);
});

test('interview practice is its own track and unlisted courses go to More', () => {
  const interview = courses.filter(course => course.kind === 'interview');
  assert.ok(interview.length > 0);
  for (const course of interview) assert.equal(trackOf(course).id, 'interview');
  assert.deepEqual(groupByTrack(courses).find(group => group.track.id === 'interview').courses, interview);
  assert.equal(trackOf({ id: 'a-course-added-later', kind: 'path' }).id, 'more');
  const withNew = groupByTrack([...courses, { id: 'a-course-added-later', kind: 'path' }]);
  assert.deepEqual(withNew.at(-1).courses.map(course => course.id), ['a-course-added-later']);
  assert.equal(withNew.at(-1).track.id, 'more');
  // Today every course is listed, so "More" is empty and not shown.
  assert.ok(!groupByTrack(courses).some(group => group.track.id === 'more'));
});

test('every track and course has a drawn icon', () => {
  for (const track of learnTracks) assert.ok(learnIcons[track.icon], track.id);
  for (const id of courseIconIds) assert.ok(ids.has(id), `${id} has an icon but is not a course`);
  for (const course of courses) {
    assert.ok(learnIcons[courseIcon(course)], course.id);
    assert.ok(courseIconIds.includes(course.id), `${course.id} has no icon of its own`);
  }
  assert.equal(courseIcon({ id: 'a-course-added-later', kind: 'path' }), 'dots');
  for (const [name, path] of Object.entries(learnIcons)) assert.match(path, /^M[\d\s.,a-zA-Z-]+$/, name);
});

test('the next lesson follows the most recent progress through the track order', () => {
  const order = groupByTrack(courses).flatMap(group => group.courses).map(course => ({ id: course.id, lessons: course.lessons.map(lesson => lesson.id) }));
  const [first, second] = order;
  assert.equal(first.id, 'foundations');
  assert.deepEqual(nextLesson(order, {}), { course: 'foundations', lesson: first.lessons[0], index: 0, started: false });
  const passed = (course, index, at) => ({ [`${course.id}/${course.lessons[index]}`]: { passed: at } });
  // After the lesson passed last, skipping ones already passed.
  assert.deepEqual(nextLesson(order, { ...passed(first, 0, 1), ...passed(first, 1, 2) }), { course: 'foundations', lesson: first.lessons[2], index: 2, started: true });
  assert.equal(nextLesson(order, { ...passed(first, 4, 5), ...passed(first, 5, 1) }).index, 6);
  // The course worked on most recently wins over an earlier one.
  assert.equal(nextLesson(order, { ...passed(first, 0, 1), ...passed(second, 3, 9) }).course, second.id);
  assert.equal(nextLesson(order, { ...passed(first, 0, 1), ...passed(second, 3, 9) }).index, 4);
  // The last lesson of a course wraps to its first gap, and a finished course moves to the next one.
  assert.equal(nextLesson(order, passed(first, first.lessons.length - 1, 3)).index, 0);
  const finished = Object.assign({}, ...first.lessons.map((_, index) => passed(first, index, index + 1)));
  assert.deepEqual(nextLesson(order, finished), { course: second.id, lesson: second.lessons[0], index: 0, started: true });
  const everything = Object.assign({}, ...order.flatMap(course => course.lessons.map((_, index) => passed(course, index, 1))));
  assert.equal(nextLesson(order, everything), null);
  // Entries for lessons that no longer exist are ignored.
  assert.equal(nextLesson(order, { 'gone/lesson': { passed: 5 } }).started, false);
});
