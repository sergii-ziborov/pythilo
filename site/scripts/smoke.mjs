// Smoke test against a running server: `node scripts/smoke.mjs [origin]`.
// Exercises the relay as a client would (create, stream, update, presence, delete)
// and checks that the main pages render with the headers they need.
const origin = (process.argv[2] ?? 'http://127.0.0.1:3212').replace(/\/$/, '');
const bytes = length => Buffer.from(crypto.getRandomValues(new Uint8Array(length))).toString('base64url');
const packet = (length = 48) => ({ iv: bytes(12), data: bytes(length) });
const json = { 'Content-Type': 'application/json', 'X-Pythilo-Codecs': '1' };
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}`); if (!ok) failures++; };

// SSE reader that collects events until told to stop.
function stream(id, token, peer) {
  const events = [], abort = new AbortController();
  const done = (async () => {
    const response = await fetch(`${origin}/api/playground/rooms/${id}/events/?peer=${peer}&codecs=1`, { headers: { Authorization: 'Bearer ' + token }, signal: abort.signal });
    check(response.ok && response.headers.get('content-type') === 'text/event-stream', `SSE stream opens (${response.status})`);
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try {
      while (true) {
        const { done, value } = await reader.read(); if (done) return;
        buffer += decoder.decode(value, { stream: true });
        let end;
        while ((end = buffer.indexOf('\n\n')) >= 0) {
          const block = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const type = block.match(/^event: (.+)$/m)?.[1], data = block.match(/^data: (.+)$/m)?.[1];
          if (type && type !== 'ping') events.push({ type, data: JSON.parse(data) });
        }
      }
    } catch (error) { if (error.name !== 'AbortError') throw error; }
  })();
  return { events, stop: async () => { abort.abort(); await done.catch(() => {}); } };
}
const until = async (test, ms = 3000) => { const end = Date.now() + ms; while (Date.now() < end) { if (test()) return true; await new Promise(r => setTimeout(r, 50)); } return false; };

const health = await fetch(`${origin}/healthz/`);
check(health.ok && (await health.text()) === 'ok\n', 'healthz');

const created = await fetch(`${origin}/api/playground/rooms/`, { method: 'POST', headers: json, body: JSON.stringify({ snapshot: packet(), lifetimeSeconds: 120 }) });
const room = await created.json();
check(created.status === 201 && /^[A-Za-z0-9_-]{24}$/.test(room.id) && room.codec === 1, `create room (${created.status})`);
const refused = await fetch(`${origin}/api/playground/rooms/`, { method: 'POST', headers: { ...json, Origin: 'https://elsewhere.invalid' }, body: JSON.stringify({ snapshot: packet(), lifetimeSeconds: 120 }) });
check(refused.status === 403, 'a foreign Origin is refused');

const peer = bytes(16), sse = stream(room.id, room.edit, peer);
check(await until(() => sse.events.some(event => event.type === 'state')), 'stream starts with the encrypted state');
const state = sse.events.find(event => event.type === 'state')?.data;
check(state?.expiresAt === room.expiresAt && state?.sequence === 0, 'state carries the fixed expiry');

const update = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { method: 'POST', headers: { ...json, Authorization: 'Bearer ' + room.edit }, body: JSON.stringify({ type: 'update', peer, messageID: bytes(16), packet: packet() }) });
check(update.ok && (await update.json()).sequence === 1, 'post an update with the edit capability');
check(await until(() => sse.events.some(event => event.type === 'update' && event.data.sequence === 1)), 'the update arrives on the stream');
const viewWrite = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { method: 'POST', headers: { ...json, Authorization: 'Bearer ' + room.view }, body: JSON.stringify({ type: 'update', peer, messageID: bytes(16), packet: packet() }) });
check(viewWrite.status === 403, 'the view capability cannot write');

const presence = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { method: 'POST', headers: { ...json, Authorization: 'Bearer ' + room.view }, body: JSON.stringify({ type: 'presence', peer, packet: packet(64) }) });
check(presence.status === 204, 'post presence');
check(await until(() => sse.events.some(event => event.type === 'presence' && event.data.peer === peer)), 'presence arrives on the stream');
const read = await (await fetch(`${origin}/api/playground/rooms/${room.id}/`, { headers: { Authorization: 'Bearer ' + room.view, 'X-Pythilo-Codecs': '1' } })).json();
check(read.events.length === 1 && read.presence.length === 1, 'read returns events and presence');

const notOwner = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { method: 'DELETE', headers: { Authorization: 'Bearer ' + room.edit } });
check(notOwner.status === 403, 'only the owner can end the room');
const deleted = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { method: 'DELETE', headers: { Authorization: 'Bearer ' + room.owner } });
check(deleted.status === 204, 'the owner ends the room');
check(await until(() => sse.events.some(event => event.type === 'closed')), 'the stream says the room closed');
await sse.stop();
const gone = await fetch(`${origin}/api/playground/rooms/${room.id}/`, { headers: { Authorization: 'Bearer ' + room.view } });
check(gone.status === 410, 'a closed room is gone');

const pages = [['/', 'Real Python, '], ['/learn/', 'Python foundations'], ['/learn/deeper/functions-that-return-functions/', 'Changing a captured variable'], ['/playground/', 'Preparing the editor'], ['/ai/', 'claude mcp add --transport stdio pythilo -- npx -y pythilo']];
for (const [path, text] of pages) {
  const response = await fetch(origin + path), body = await response.text();
  check(response.ok && body.replaceAll('&#x27;', "'").includes(text), `${path} renders (${response.status})`);
  if (path.startsWith('/learn/') || path.startsWith('/playground/')) check(response.headers.get('cross-origin-embedder-policy') === 'require-corp' && response.headers.get('cross-origin-opener-policy') === 'same-origin', `${path} is cross-origin isolated`);
}
const worker = await fetch(`${origin}/pyodide/python-worker.mjs`), core = await fetch(`${origin}/pyodide/pyodide.mjs`), wasm = await fetch(`${origin}/pyodide/pyodide.asm.wasm`, { method: 'HEAD' });
check(worker.ok && core.ok && /javascript/.test(core.headers.get('content-type') ?? ''), 'Pyodide and the worker are served from this origin');
check(wasm.ok && wasm.headers.get('content-type') === 'application/wasm', 'the Wasm runtime is served as application/wasm');
console.log(failures ? `${failures} check(s) failed` : 'All smoke checks passed');
process.exit(failures ? 1 : 0);
