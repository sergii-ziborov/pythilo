import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encryptPlayground, decryptPlayground, newEncryptionSecret, base64url } from '../lib/playground-crypto.ts';

test('AES-GCM authenticates source, key and packet; distinct nonces avoid reuse', async () => {
  const key = newEncryptionSecret(), bytes = new TextEncoder().encode('print("🐍")');
  const first = await encryptPlayground(key, bytes), second = await encryptPlayground(key, bytes);
  assert.notEqual(first.iv, second.iv); assert.notEqual(first.data, second.data);
  assert.deepEqual(await decryptPlayground(key, first), bytes);
  await assert.rejects(decryptPlayground(newEncryptionSecret(), first));
  const data = Buffer.from(first.data, 'base64url'); data[0] ^= 1;
  await assert.rejects(decryptPlayground(key, { ...first, data: data.toString('base64url') }));
  await assert.rejects(decryptPlayground(key, first, 4));
});

test('a packet sealed for a Crabrix room does not open as a Pythilo room', async () => {
  const key = newEncryptionSecret(), raw = Buffer.from(key, 'base64url'), iv = crypto.getRandomValues(new Uint8Array(12));
  const aes = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt']);
  const sealed = async label => ({ iv: base64url(iv), data: base64url(new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: new TextEncoder().encode(label) }, aes, new Uint8Array([1, 2, 3])))) });
  await assert.rejects(decryptPlayground(key, await sealed('crabrix-playground-v1')));
  assert.deepEqual(await decryptPlayground(key, await sealed('pythilo-playground-v1')), new Uint8Array([1, 2, 3]));
});
