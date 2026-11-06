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
  for(const id of path.projects){assert.equal(lessons.get(id)?.course.id,'senior-projects');projects.add(id);}
  assert.equal(path.projects.length,2);assert.ok(path.fieldwork.length>=2);assert.ok(path.review.length>=3);
 }
 assert.equal(projects.size,6);
 assert.equal(courses.filter(c=>c.order>=25).flatMap(c=>c.lessons).length,74);
});
test('twenty new labs link to existing lessons with runnable code and independent check cases',()=>{
 const linked=labs.filter(lab=>lab.lessons?.some(id=>lessons.get(id)?.course.order>=25));
 assert.equal(linked.length,20);assert.equal(labs.length,50);
 for(const lab of labs.filter(lab=>lab.lessons?.length))for(const id of lab.lessons){assert.ok(lessons.has(id),`${lab.id}: ${id}`);assert.ok(lab.answer.includes('def '));assert.notEqual(lab.answer,lab.starter);}
 assert.equal(linked.filter(l=>l.section==='Machine learning').length,12);
 assert.equal(linked.filter(l=>l.section==='Artificial intelligence').length,8);
});
test('advanced tensor lessons require native PyTorch and the other new lessons run in the browser',()=>{
 for(const course of courses.filter(c=>c.order>=25))for(const lesson of course.lessons){
  if(course.id==='deep-learning-practice')assert.ok(lesson.missing.includes('torch'),lesson.id);
  else assert.deepEqual(lesson.missing,[],lesson.id);
  assert.ok(lesson.checks.length>=3);assert.equal(lesson.hints.length,3);
 }
});
