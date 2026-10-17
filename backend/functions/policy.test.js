import test from 'node:test';
import assert from 'node:assert/strict';
import { boundedText, identifier, decoration, samePayload, milestoneID } from './policy.js';

test('milestones are unique per owner/friend/type/anniversary year, stable across retries', () => {
  const id = milestoneID('alice', 'bob', 'firstHello');
  assert.equal(id, milestoneID('alice', 'bob', 'firstHello'));
  assert.notEqual(id, milestoneID('bob', 'alice', 'firstHello'));
  assert.notEqual(milestoneID('alice', 'bob', 'anniversary', '2026'), milestoneID('alice', 'bob', 'anniversary', '2027'));
});
test('public projection strips private message text, image and memory references', () => {
  const shared = decoration({ id: 'gift-1', assetId: 'pixel-heart', position: { x: 0.2, y: 0.8 }, scale: 1, rotation: 10,
    title: 'secret', message: 'private text', imageReference: 'private.jpg', linkedMemoryId: 'conversation' });
  assert.deepEqual(Object.keys(shared).sort(), ['assetId', 'id', 'position', 'rotation', 'scale']);
  assert.equal(JSON.stringify(shared).includes('private'), false);
});
test('gift collection cannot carry arbitrary images; invalid geometry is rejected', () => {
  const valid = { id: 'gift-1', assetId: 'pixel-star', position: { x: 0.5, y: 0.5 }, scale: 1, rotation: 0 };
  assert.throws(() => decoration({ ...valid, assetId: 'https://evil/image.jpg' }));
  assert.throws(() => decoration({ ...valid, id: '../private' }));
  assert.throws(() => decoration({ ...valid, scale: Infinity }));
  assert.throws(() => decoration({ ...valid, position: { x: -1, y: 1 } }));
});
test('request identifiers and text boundaries reject invalid payloads', () => {
  assert.equal(identifier('request-123'), 'request-123');
  assert.throws(() => identifier('../another-user'));
  assert.throws(() => boundedText(' ', 240, true));
  assert.throws(() => boundedText('x'.repeat(241), 240, true));
  assert.equal(boundedText('ありがとう', 5, true), 'ありがとう');
});
test('retry payload may only reuse an ID for identical immutable fields', () => {
  const old = { senderId: 'alice', recipientId: 'bob', message: 'hello', status: 'accepted' };
  assert.equal(samePayload(old, { ...old, status: 'pending' }, ['senderId', 'recipientId', 'message']), true);
  assert.equal(samePayload(old, { ...old, recipientId: 'mallory' }, ['senderId', 'recipientId', 'message']), false);
});
