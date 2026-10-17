import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { key } from './policy.js';

// Exercise the real callable/trigger handlers with a serializable in-memory transaction adapter.
// Firebase emulator/rules tests are still required before deployment.
class Database {
  values = new Map(); queue = Promise.resolve();
  collection(path) { return new Query(this, path); }
  async runTransaction(action) {
    const prior = this.queue;
    let release; this.queue = new Promise(resolve => { release = resolve; });
    await prior;
    const writes = [];
    try {
      const result = await action({ get: ref => ref.get(),
        set: (ref, data) => writes.push([ref.path, data]),
        create: (ref, data) => { if (this.values.has(ref.path)) throw new Error('already-exists'); writes.push([ref.path, data]); },
        update: (ref, data) => writes.push([ref.path, { ...this.values.get(ref.path), ...data }]) });
      for (const [path, data] of writes) this.values.set(path, structuredClone(data));
      return result;
    } finally { release(); }
  }
}
class Ref {
  constructor(db, path) { this.db = db; this.path = path; }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { const value = this.db.values.get(this.path); return { exists: value !== undefined, id: this.path.split('/').at(-1), data: () => structuredClone(value) }; }
  async set(data) { this.db.values.set(this.path, structuredClone(data)); }
}
class Query {
  constructor(db, path, filters = [], max = Infinity) { this.db = db; this.path = path; this.filters = filters; this.max = max; }
  doc(id) { return new Ref(this.db, `${this.path}/${id}`); }
  where(field, operator, value) { return new Query(this.db, this.path, [...this.filters, [field, operator, value]], this.max); }
  orderBy() { return this; }
  limit(max) { return new Query(this.db, this.path, this.filters, max); }
  async get() {
    const paths = [...this.db.values.keys()].filter(path => path.startsWith(`${this.path}/`) && path.split('/').length === this.path.split('/').length + 1);
    const docs = [];
    for (const path of paths) {
      const data = this.db.values.get(path);
      if (this.filters.every(([field, op, value]) => op === 'array-contains' ? data[field]?.includes(value) : data[field] === value)) docs.push(await new Ref(this.db, path).get());
    }
    return { docs: docs.slice(0, this.max), size: Math.min(docs.length, this.max), empty: docs.length === 0 };
  }
}
const db = new Database();
mock.module('firebase-admin/firestore', { namedExports: { getFirestore: () => db, FieldValue: { serverTimestamp: () => new Date() } } });
process.env.PACCHI_FRIENDSHIPS_COLLECTION = 'existingFriends';
process.env.PACCHI_BLOCKS_COLLECTION = 'existingBlocks';
process.env.PACCHI_USERS_COLLECTION = 'existingUsers';
process.env.PACCHI_MESSAGES_COLLECTION = 'existingMessages';
const handlers = await import('./index.js');
const call = (name, uid, data = {}) => handlers[name].run({ auth: uid ? { uid } : undefined, data });
const reset = () => {
  db.values.clear();
  db.values.set('existingFriends/relation', { members: ['alice', 'bob'], status: 'accepted' });
  db.values.set('existingUsers/alice', { displayName: 'Alice' });
  db.values.set('existingUsers/bob', { displayName: 'Bob' });
};
const gift = { id: 'request-1', senderId: 'alice', recipientId: 'bob', stickerAssetId: 'pixel-heart', message: 'hello' };

test('authenticated friendship checks reject unauthenticated, forged sender, outsiders and either-direction blocks', async () => {
  reset();
  await assert.rejects(call('pacchiSendGift', null, gift), { code: 'unauthenticated' });
  await assert.rejects(call('pacchiSendGift', 'bob', gift), { code: 'invalid-argument' });
  await assert.rejects(call('pacchiSendGift', 'alice', { ...gift, recipientId: 'mallory' }), { code: 'permission-denied' });
  await call('pacchiBlock', 'bob', { friendId: 'alice' });
  assert.ok(db.values.has(`existingBlocks/${key('bob', 'alice')}`));
  await assert.rejects(call('pacchiSendGift', 'alice', gift), { code: 'permission-denied' });
  assert.equal([...db.values.keys()].filter(path => path.startsWith('pacchiGifts/')).length, 0);
});
test('simultaneous gift send/accept retries create one gift and one recipient sticker', async () => {
  reset();
  await Promise.all([call('pacchiSendGift', 'alice', gift), call('pacchiSendGift', 'alice', gift)]);
  await assert.rejects(call('pacchiSendGift', 'alice', { ...gift, message: 'changed' }), { code: 'already-exists' });
  await assert.rejects(call('pacchiAcceptGift', 'alice', { id: gift.id }), { code: 'permission-denied' });
  await Promise.all([call('pacchiAcceptGift', 'bob', { id: gift.id }), call('pacchiAcceptGift', 'bob', { id: gift.id })]);
  assert.equal(db.values.get('pacchiGifts/request-1').status, 'accepted');
  assert.equal([...db.values.keys()].filter(path => path.startsWith('pacchiPrivate/bob/stickers/')).length, 1);
});
test('phone visits require sharing consent and accepted friendship; projection cannot expose private data', async () => {
  reset();
  await call('pacchiSendGift', 'alice', gift);
  await call('pacchiAcceptGift', 'bob', { id: gift.id });
  const item = { id: 'gift-request-1', assetId: 'pixel-heart', position: { x: 0.5, y: 0.5 }, scale: 1, rotation: 0, message: 'PRIVATE', imageReference: 'SECRET.jpg' };
  await call('pacchiPublish', 'bob', { profile: { visibility: 'friends' }, decorations: [item] });
  const visited = await call('pacchiVisit', 'alice', { friendId: 'bob' });
  assert.equal(visited.stickers.length, 1);
  assert.equal(JSON.stringify(visited).includes('PRIVATE'), false);
  assert.equal(JSON.stringify(visited).includes('SECRET'), false);
  await assert.rejects(call('pacchiPublish', 'alice', { profile: { visibility: 'friends' }, decorations: [item] }), { code: 'permission-denied' });
  await assert.rejects(call('pacchiVisit', 'mallory', { friendId: 'bob' }), { code: 'permission-denied' });
  await call('pacchiPublish', 'bob', { profile: { visibility: 'private' }, decorations: [] });
  await assert.rejects(call('pacchiVisit', 'alice', { friendId: 'bob' }), { code: 'permission-denied' });
});
test('mail uses server delivery, immutable request IDs, and recipient-only inboxes', async () => {
  reset();
  const letter = { id: 'letter-1', senderId: 'alice', recipientId: 'bob', message: 'private hello', envelopeStyle: 1, stampStyle: 2, sound: 0 };
  await assert.rejects(call('pacchiSendMail', 'alice', { ...letter, scheduledDeliveryAt: new Date().toISOString() }), { code: 'invalid-argument' });
  await Promise.all([call('pacchiSendMail', 'alice', letter), call('pacchiSendMail', 'alice', letter)]);
  assert.equal((await call('pacchiSnapshot', 'bob')).mail.length, 1);
  assert.equal((await call('pacchiSnapshot', 'alice')).mail.length, 0);
  await call('pacchiBlock', 'alice', { friendId: 'bob' });
  assert.equal((await call('pacchiSnapshot', 'bob')).mail.length, 0);
});
test('trusted delivered-message event retries generate one milestone per friend, never message content', async () => {
  reset();
  const message = { senderId: 'alice', recipientId: 'bob', kind: 'photo', delivered: true, text: 'PRIVATE' };
  const event = { data: { after: { data: () => message } } };
  await Promise.all([handlers.pacchiMessageMilestone.run(event), handlers.pacchiMessageMilestone.run(event)]);
  const snapshot = await call('pacchiSnapshot', 'alice');
  assert.equal(snapshot.stickers.length, 2);
  assert.deepEqual(new Set(snapshot.stickers.map(sticker => sticker.type)), new Set(['firstHello', 'firstPhoto']));
  assert.equal(JSON.stringify(snapshot.stickers).includes('PRIVATE'), false);
  await call('pacchiBlock', 'bob', { friendId: 'alice' });
  db.values.delete([...db.values.keys()].find(path => path.startsWith('pacchiPrivate/alice/stickers/')));
  await handlers.pacchiMessageMilestone.run(event);
  assert.equal((await call('pacchiSnapshot', 'alice')).stickers.length, 1, 'Blocked pair cannot generate new stickers');
});
test('daily photos are private recipient attachments, idempotent and blocked after revocation', async () => {
  reset();
  const imageBase64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xd9]).toString('base64');
  const moment = { dayId: '2026-10-17', promptId: 2, recipientId: 'bob', response: 'today sky', imageBase64 };
  await Promise.all([call('pacchiSendMoment', 'alice', moment), call('pacchiSendMoment', 'alice', moment)]);
  const inbox = await call('pacchiSnapshot', 'bob');
  assert.equal(inbox.mail.length, 1);
  const id = inbox.mail[0].id;
  assert.equal(inbox.mail[0].imageReference, id);
  assert.equal(JSON.stringify(inbox).includes(imageBase64), false, 'Attachment bytes must not leak into snapshots');
  assert.equal((await call('pacchiMailPhoto', 'bob', { id })).imageBase64, imageBase64);
  await assert.rejects(call('pacchiMailPhoto', 'mallory', { id }), { code: 'permission-denied' });
  await call('pacchiSendMoment', 'alice', { ...moment, response: 'changed' });
  assert.equal((await call('pacchiSnapshot', 'bob')).mail.length, 2, 'An edited response may be shared as a new letter');
  await call('pacchiBlock', 'bob', { friendId: 'alice' });
  await assert.rejects(call('pacchiMailPhoto', 'bob', { id }), { code: 'permission-denied' });
});
test('birthday stickers require voluntary sharing and remain unique across scheduled retries', async () => {
  reset();
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tokyo', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
  const part = name => Number(parts.find(item => item.type === name).value);
  db.values.set('existingUsers/bob', { displayName: 'Bob', birthday: { month: part('month'), day: part('day'), shareWithFriends: true } });
  db.values.set('existingUsers/alice', { displayName: 'Alice', birthday: { month: part('month'), day: part('day'), shareWithFriends: false } });
  await handlers.pacchiCalendarMilestones.run({});
  await handlers.pacchiCalendarMilestones.run({});
  assert.equal((await call('pacchiSnapshot', 'alice')).stickers.filter(sticker => sticker.type === 'birthday').length, 1);
  assert.equal((await call('pacchiSnapshot', 'bob')).stickers.length, 0);
});
