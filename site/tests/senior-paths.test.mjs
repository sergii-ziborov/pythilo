import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {seniorPaths} from '../lib/senior-paths.ts';
const courses=JSON.parse(readFileSync(new URL('../content/courses.json',import.meta.url))).courses;
const labs=JSON.parse(readFileSync(new URL('../content/labs.json',import.meta.url))).labs;
const ids=new Set(courses.map(c=>c.id));
const lessons=new Map(courses.flatMap(c=>c.lessons.map(l=>[l.id,{course:c,...l}])));
test('three advanced paths resolve real courses and distinct integration projects',()=>{
 assert.equal(seniorPaths.length,3);
 const projects=new Set();
 for(const path of seniorPaths){
  for(const id of [...path.prerequisites,...path.courses])assert.ok(ids.has(id),id);
  for(const id of path.projects){assert.ok(lessons.get(id)?.title.startsWith('Project:'),id);projects.add(id);}
  assert.equal(path.projects.length,path.id==='python'?2:16);assert.ok(path.fieldwork.length>=2);assert.ok(path.review.length>=3);
 }
 assert.equal(projects.size,34);
 // Courses 25 to 38 are the advanced paths; later courses are general practice.
 assert.equal(courses.filter(c=>c.order>=25&&c.order<=38).flatMap(c=>c.lessons).length,138);
});
test('advanced labs link to existing lessons with runnable code and independent check cases',()=>{
 const linked=labs.filter(lab=>lab.lessons?.some(id=>lessons.get(id)?.course.order>=25&&lessons.get(id)?.course.order<=38));
 assert.equal(linked.length,84);assert.equal(labs.length,114);
 for(const lab of labs.filter(lab=>lab.lessons?.length))for(const id of lab.lessons){assert.ok(lessons.has(id),`${lab.id}: ${id}`);assert.ok(lab.answer.includes('def '));assert.notEqual(lab.answer,lab.starter);}
 assert.equal(linked.filter(l=>l.section==='Machine learning').length,44);
 assert.equal(linked.filter(l=>l.section==='Artificial intelligence').length,40);
});

test('twenty-four systems labs include twelve composed projects with adversarial checks',()=>{
 const added=courses.filter(c=>c.order>=32 && c.order<=33).flatMap(c=>c.lessons);
 assert.equal(added.length,24);
 assert.equal(added.filter(l=>l.title.startsWith('Project:')).length,12);
 for(const lesson of added){
  assert.ok(labs.some(lab=>lab.lessons?.includes(lesson.id)),lesson.id);
  assert.ok(lesson.checks.length>=4,lesson.id);
 }
 assert.equal(labs.reduce((count,lab)=>count+(lab.lessons?.length??0),0),111);
});
test('advanced tensor lessons require native PyTorch and the other new lessons run in the browser',()=>{
 for(const course of courses.filter(c=>c.order>=25))for(const lesson of course.lessons){
  if(['deep-learning-practice','pytorch-training','transformer-engineering','finetuning-projects','robust-ml-engineering','alignment-engineering'].includes(course.id))assert.ok(lesson.missing.includes('torch'),lesson.id);
  else assert.deepEqual(lesson.missing,[],lesson.id);
  assert.ok(lesson.checks.length>=3);assert.equal(lesson.hints.length,3);
 }
});
