import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {Pythilo,PythiloError,PLAYGROUND_LIMITS} from '../src/index';
const env=Object.fromEntries(Object.entries(process.env).filter(([name])=>name!=='PYTHILO_RELAY'));
test('ESM and CommonJS expose a real library without launching an interpreter or MCP',async()=>{
 for(const format of ['esm','commonjs']) { const entry=path.resolve('dist/index.'+(format==='esm'?'mjs':'cjs'));const code=format==='esm'?`const {Pythilo}=await import(${JSON.stringify('file://'+entry)});const c=new Pythilo();console.log(JSON.stringify(await c.status()));c.close();`:`const {Pythilo}=require(${JSON.stringify(entry)});(async()=>{const c=new Pythilo();console.log(JSON.stringify(await c.status()));c.close()})()`;const r=spawnSync(process.execPath,['--input-type='+(format==='esm'?'module':'commonjs'),'-e',code],{encoding:'utf8',timeout:10000,env});assert.equal(r.status,0,r.stderr);assert.equal(JSON.parse(r.stdout).connected,false);assert.equal(r.stderr,''); }
 const client=new Pythilo({name:'Library agent'});assert.equal((await client.status()).connected,false);client.close();await assert.rejects(()=>client.status(),/closed/);
 assert.equal(PLAYGROUND_LIMITS.maximumLifetimeSeconds,86400);
});
test('participant labels are bounded and cannot inject controls or malformed Unicode',()=>{for(const name of ['', '\nagent', 'a'.repeat(41),'\ud800'])assert.throws(()=>new Pythilo({name}));});
test('the relay option is an origin, and without one the public relay is used',async()=>{
 for(const relay of ['https://relay.example/api','https://user:pw@relay.example','relay.example','ftp://relay.example'])assert.throws(()=>new Pythilo({relay}),(error:unknown)=>error instanceof PythiloError&&error.code==='RELAY_NOT_CONFIGURED'&&!error.message.includes('pw@'));
 const configured=new Pythilo({relay:'http://127.0.0.1:3212/'});assert.equal((await configured.status()).relay,'http://127.0.0.1:3212');configured.close();
 const saved=process.env.PYTHILO_RELAY;delete process.env.PYTHILO_RELAY;
 const client=new Pythilo();
 try{assert.equal((await client.status()).relay,'https://pythilo.com');}
 finally{client.close();if(saved!==undefined)process.env.PYTHILO_RELAY=saved;}
});
test('bounded operation queue refuses overload and close cancels pending calls',async()=>{const client=new Pythilo();const requests=Array.from({length:60},()=>client.status());client.close();const result=await Promise.allSettled(requests);assert(result.every(x=>x.status==='rejected'));});
test('mixed ESM, CommonJS and programmatic MCP imports share one quiet implementation',()=>{
 const esm=pathToFileURL(path.resolve('dist/index.mjs')).href,server=pathToFileURL(path.resolve('dist/server.mjs')).href,cjs=path.resolve('dist/index.cjs');
 const code=`import assert from 'node:assert/strict';import{createRequire}from'node:module';const esm=await import(${JSON.stringify(esm)});const cjs=createRequire(import.meta.url)(${JSON.stringify(cjs)});const server=await import(${JSON.stringify(server)});assert.equal(esm.Pythilo,cjs.Pythilo);assert.equal(typeof server.makeServer,'function');const client=new esm.Pythilo();assert(client instanceof cjs.Pythilo);assert.equal((await client.status()).connected,false);client.close();console.log('ok');`;
 const result=spawnSync(process.execPath,['--input-type=module','-e',code],{encoding:'utf8',timeout:10000,env});
 assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.trim(),'ok');assert.equal(result.stderr,'');
});
test('strict mixed-mode TypeScript consumers share one class type without dependency typings',()=>{
 const result=spawnSync(process.execPath,['node_modules/typescript/bin/tsc','-p','test/consumer/tsconfig.json'],{encoding:'utf8',timeout:15000});
 assert.equal(result.status,0,result.stdout+result.stderr);
});
test('library failures carry a stable code without losing their message',async()=>{
 const client=new Pythilo();
 try{await assert.rejects(()=>client.connect('https://example.com/#secret'),(error:unknown)=>{assert(error instanceof PythiloError);assert.equal(error.code,'INVALID_LINK');assert.equal(error.retryable,false);assert.match(error.message,/room link|unavailable/);assert(!error.message.includes('secret'));return true;});}
 finally{client.close();}
 const code=`const {PythiloError}=require(${JSON.stringify(path.resolve('dist/index.cjs'))});console.log(typeof PythiloError);`;
 assert.equal(spawnSync(process.execPath,['-e',code],{encoding:'utf8',timeout:10000}).stdout.trim(),'function');
});
