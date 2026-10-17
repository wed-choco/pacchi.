import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { assetIds, key, boundedText, identifier, decoration, samePayload, milestoneID } from './policy.js';

initializeApp();
const db = getFirestore();
const options = { region: 'asia-northeast1', enforceAppCheck: true };
const privateRoot = uid => db.collection('pacchiPrivate').doc(uid);
const collectionNames = {
  friends: process.env.PACCHI_FRIENDSHIPS_COLLECTION,
  blocks: process.env.PACCHI_BLOCKS_COLLECTION,
  users: process.env.PACCHI_USERS_COLLECTION,
  messages: process.env.PACCHI_MESSAGES_COLLECTION
};
function existing(name) {
  const path = collectionNames[name];
  if (!path || !/^[a-zA-Z][a-zA-Z0-9_-]*$/.test(path)) throw new HttpsError('failed-precondition', 'Existing app data adapter is not configured.');
  return db.collection(path);
}
function authenticated(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  return request.auth.uid;
}
function callable(handler) {
  return onCall(options, async request => {
    const uid = authenticated(request);
    try { return await handler(uid, request.data ?? {}); }
    catch (error) {
      if (error instanceof HttpsError) throw error;
      if (/^invalid-/.test(error.message)) throw new HttpsError('invalid-argument', error.message);
      // No raw database errors or private text in the response.
      console.error('Pacchi operation failed', error.code ?? error.name);
      throw new HttpsError('internal', 'The operation could not be completed.');
    }
  });
}
function blockRefs(a, b) { return [existing('blocks').doc(key(a, b)), existing('blocks').doc(key(b, a))]; }
async function accepted(reader, uid, other) {
  if (typeof other !== 'string' || !other || uid === other) throw new HttpsError('permission-denied', 'Accepted friends only.');
  const refs = blockRefs(uid, other);
  const [relations, leftBlock, rightBlock] = await Promise.all([
    reader.get(existing('friends').where('members', 'array-contains', uid).where('status', '==', 'accepted')),
    reader.get(refs[0]), reader.get(refs[1])
  ]);
  const match = relations.docs.find(document => {
    const members = document.data().members;
    return Array.isArray(members) && members.length === 2 && members.includes(other);
  });
  if (!match || leftBlock.exists || rightBlock.exists) throw new HttpsError('permission-denied', 'Accepted friends only.');
  return match;
}
const reader = { get: ref => ref.get() };
async function contacts(uid) {
  const relations = await existing('friends').where('members', 'array-contains', uid).where('status', '==', 'accepted').get();
  const ids = [...new Set(relations.docs.flatMap(doc => {
    const members = doc.data().members;
    return Array.isArray(members) && members.length === 2 ? members.filter(id => id !== uid && typeof id === 'string') : [];
  }))];
  const result = [];
  for (const id of ids) {
    try { await accepted(reader, uid, id); }
    catch (error) { if (error.code === 'permission-denied') continue; throw error; }
    const user = await existing('users').doc(id).get();
    result.push({ id, name: String(user.data()?.displayName ?? '友達').slice(0, 24) });
  }
  return result;
}
const iso = date => date?.toDate ? date.toDate().toISOString() : date;
const wire = data => ({ ...data, createdAt: iso(data.createdAt) });

export const pacchiSnapshot = callable(async uid => {
  const friends = await contacts(uid);
  const [stickers, gifts, mail] = await Promise.all([
    privateRoot(uid).collection('stickers').orderBy('createdAt', 'desc').limit(500).get(),
    db.collection('pacchiGifts').where('recipientId', '==', uid).orderBy('createdAt', 'desc').limit(100).get(),
    db.collection('pacchiMail').where('recipientId', '==', uid).orderBy('createdAt', 'desc').limit(100).get()
  ]);
  const permitted = new Set(friends.map(friend => friend.id));
  return { ownerId: uid, friends,
    stickers: stickers.docs.map(doc => wire(doc.data())),
    gifts: gifts.docs.map(doc => wire(doc.data())).filter(gift => permitted.has(gift.senderId)),
    mail: mail.docs.map(doc => { const { imageDigest, ...letter } = doc.data(); return wire(letter); }).filter(letter => permitted.has(letter.senderId)) };
});

export const pacchiPublish = callable(async (uid, data) => {
  const visibility = data.profile?.visibility;
  if (!['private', 'friends'].includes(visibility) || !Array.isArray(data.decorations) || data.decorations.length > 20) throw new HttpsError('invalid-argument', 'Invalid sharing settings.');
  const decorations = data.decorations.map(decoration);
  if (new Set(decorations.map(item => item.id)).size !== decorations.length) throw new HttpsError('invalid-argument', 'Duplicate decorations.');
  await db.runTransaction(async tx => {
    const owned = await Promise.all(decorations.map(item => tx.get(privateRoot(uid).collection('stickers').doc(item.id))));
    if (owned.some((doc, index) => !doc.exists || doc.data().ownerId !== uid || doc.data().assetId !== decorations[index].assetId)) throw new HttpsError('permission-denied', 'Owned gift assets only.');
    tx.set(db.collection('pacchiPhones').doc(uid), { ownerId: uid, phoneColor: '#F4B8CA', visibility,
      // Private state revokes the server projection as well.
      stickers: visibility === 'friends' ? decorations : [], updatedAt: FieldValue.serverTimestamp() });
  });
  return {};
});
export const pacchiVisit = callable(async (uid, data) => {
  return db.runTransaction(async tx => {
    await accepted(tx, uid, data.friendId);
    const phone = await tx.get(db.collection('pacchiPhones').doc(data.friendId));
    if (!phone.exists || phone.data().visibility !== 'friends') throw new HttpsError('permission-denied', 'This phone is private.');
    return { ownerId: data.friendId, phoneColor: '#F4B8CA', stickers: phone.data().stickers.map(decoration) };
  });
});
export const pacchiSendGift = callable(async (uid, data) => {
  const id = identifier(data.id), message = boundedText(data.message, 60);
  if (!assetIds.has(data.stickerAssetId) || data.senderId !== uid) throw new HttpsError('invalid-argument', 'Choose a gift from the collection.');
  const gift = { id, senderId: uid, recipientId: data.recipientId, stickerAssetId: data.stickerAssetId, message, status: 'pending' };
  await db.runTransaction(async tx => {
    await accepted(tx, uid, gift.recipientId);
    const ref = db.collection('pacchiGifts').doc(id), current = await tx.get(ref);
    if (current.exists) {
      if (!samePayload(current.data(), gift, ['senderId', 'recipientId', 'stickerAssetId', 'message'])) throw new HttpsError('already-exists', 'This request ID has already been used.');
      return;
    }
    tx.create(ref, { ...gift, createdAt: FieldValue.serverTimestamp() });
  });
  return {};
});
export const pacchiAcceptGift = callable(async (uid, data) => {
  const ref = db.collection('pacchiGifts').doc(identifier(data.id));
  await db.runTransaction(async tx => {
    const doc = await tx.get(ref);
    if (!doc.exists || doc.data().recipientId !== uid) throw new HttpsError('permission-denied', 'This gift is not addressed to you.');
    const gift = doc.data();
    await accepted(tx, uid, gift.senderId);
    if (gift.status === 'accepted') return;
    if (gift.status !== 'pending' || !assetIds.has(gift.stickerAssetId)) throw new HttpsError('failed-precondition', 'Gift is not available.');
    const id = `gift-${gift.id}`;
    const shape = { 'pixel-heart': 'heart', 'pixel-star': 'star', 'pixel-bow': 'bow' }[gift.stickerAssetId];
    tx.set(privateRoot(uid).collection('stickers').doc(id), { id, ownerId: uid, friendId: gift.senderId,
      title: 'A LITTLE GIFT', type: 'gift', assetId: gift.stickerAssetId, createdAt: FieldValue.serverTimestamp(),
      position: { x: 0.5, y: 0.5 }, rotation: 0, scale: 1, shape, placed: false, layer: 0 });
    tx.update(ref, { status: 'accepted' });
  });
  return {};
});
export const pacchiSendMail = callable(async (uid, data) => {
  const id = identifier(data.id), message = boundedText(data.message, 240, true);
  if (data.senderId !== uid || data.scheduledDeliveryAt != null ||
      !Number.isInteger(data.envelopeStyle) || data.envelopeStyle < 0 || data.envelopeStyle > 2 ||
      !Number.isInteger(data.stampStyle) || data.stampStyle < 0 || data.stampStyle > 2 ||
      !Number.isInteger(data.sound) || data.sound < 0 || data.sound > 1) throw new HttpsError('invalid-argument', 'Invalid letter. Scheduled delivery is not enabled.');
  const letter = { id, senderId: uid, recipientId: data.recipientId, envelopeStyle: data.envelopeStyle,
    stampStyle: data.stampStyle, sound: data.sound, message, delivered: true, opened: false };
  await db.runTransaction(async tx => {
    await accepted(tx, uid, letter.recipientId);
    const ref = db.collection('pacchiMail').doc(id), current = await tx.get(ref);
    if (current.exists) {
      if (!samePayload(current.data(), letter, ['senderId', 'recipientId', 'envelopeStyle', 'stampStyle', 'sound', 'message'])) throw new HttpsError('already-exists', 'This request ID has already been used.');
      return;
    }
    tx.create(ref, { ...letter, createdAt: FieldValue.serverTimestamp() });
  });
  return {};
});
export const pacchiBlock = callable(async (uid, data) => {
  if (typeof data.friendId !== 'string' || data.friendId === uid || !data.friendId) throw new HttpsError('invalid-argument', 'Invalid friend.');
  await existing('blocks').doc(key(uid, data.friendId)).set({ blockerId: uid, blockedId: data.friendId, createdAt: FieldValue.serverTimestamp() });
  return {};
});

const milestones = {
  firstHello: { title: 'FIRST HELLO', shape: 'heart' },
  firstPhoto: { title: 'FIRST PHOTO', shape: 'star' },
  anniversary: { title: 'FRIENDSHIP DAY', shape: 'circle' },
  birthday: { title: 'HAPPY BIRTHDAY', shape: 'bow' }
};
// Internal server-only entry point; never exported as a callable.
async function recordMilestone(owner, friend, type, period = '') {
  const id = milestoneID(owner, friend, type, period), ref = privateRoot(owner).collection('stickers').doc(id);
  await db.runTransaction(async tx => {
    await accepted(tx, owner, friend);
    const current = await tx.get(ref);
    if (current.exists) return;
    tx.create(ref, { id, ownerId: owner, friendId: friend, ...milestones[type], type,
      createdAt: FieldValue.serverTimestamp(), position: { x: 0.5, y: 0.5 }, rotation: 0, scale: 1, placed: false, layer: 0 });
  });
}
export const pacchiMessageMilestone = onDocumentWritten({ region: options.region,
  document: `${collectionNames.messages || '__pacchi_unconfigured_messages'}/{messageId}` }, async event => {
  const message = event.data?.after.data();
  if (!message || message.delivered !== true || !['text', 'photo'].includes(message.kind)) return;
  for (const [owner, friend] of [[message.senderId, message.recipientId], [message.recipientId, message.senderId]]) {
    try {
      await recordMilestone(owner, friend, 'firstHello');
      if (message.kind === 'photo') await recordMilestone(owner, friend, 'firstPhoto');
    } catch (error) { if (error.code !== 'permission-denied') throw error; }
  }
});
export const pacchiCalendarMilestones = onSchedule({ region: options.region, schedule: '15 9 * * *', timeZone: 'Asia/Tokyo' }, async () => {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
  const part = name => Number(parts.find(item => item.type === name).value);
  const year = part('year'), month = part('month'), day = part('day');
  let last;
  while (true) {
    let query = existing('friends').where('status', '==', 'accepted').orderBy('__name__').limit(200);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    for (const relation of page.docs) {
      const data = relation.data();
      if (!Array.isArray(data.members) || data.members.length !== 2) continue;
      for (const [owner, friend] of [[data.members[0], data.members[1]], [data.members[1], data.members[0]]]) {
        try {
          const since = data.acceptedAt?.toDate?.();
          if (since) {
            const then = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tokyo', month: '2-digit', day: '2-digit', year: 'numeric' }).formatToParts(since);
            const n = name => Number(then.find(item => item.type === name).value);
            if (n('year') < year && n('month') === month && n('day') === day) await recordMilestone(owner, friend, 'anniversary', String(year));
          }
          const profile = await existing('users').doc(friend).get();
          const birthday = profile.data()?.birthday;
          if (birthday?.shareWithFriends === true && birthday.month === month && birthday.day === day) await recordMilestone(owner, friend, 'birthday', String(year));
        } catch (error) { if (error.code !== 'permission-denied') throw error; }
      }
    }
    last = page.docs[page.docs.length - 1];
    if (page.size < 200) break;
  }
});

export const pacchiSpecialMailMilestone = onDocumentWritten({ region: options.region,
  document: 'pacchiMail/{mailId}' }, async event => {
  const mail = event.data?.after.data();
  if (!mail || mail.delivered !== true) return;
  for (const [owner, friend] of [[mail.senderId, mail.recipientId], [mail.recipientId, mail.senderId]]) {
    try {
      await recordMilestone(owner, friend, 'firstHello');
      if (mail.imageReference) await recordMilestone(owner, friend, 'firstPhoto');
    }
    catch (error) { if (error.code !== 'permission-denied') throw error; }
  }
});

export const pacchiSendMoment = callable(async (uid, data) => {
  if (typeof data.dayId !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(data.dayId) ||
      !Number.isInteger(data.promptId) || data.promptId < 0 || data.promptId > 4) throw new HttpsError('invalid-argument', 'Invalid moment.');
  const response = boundedText(data.response, 240);
  let imageBase64 = null;
  if (data.imageBase64 != null) {
    if (typeof data.imageBase64 !== 'string' || data.imageBase64.length > 266668) throw new HttpsError('invalid-argument', 'Image is too large.');
    const bytes = Buffer.from(data.imageBase64, 'base64');
    // Only private JPEG attachments; the public profile projection has no image field.
    if (bytes.length > 200000 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) throw new HttpsError('invalid-argument', 'Invalid JPEG.');
    imageBase64 = bytes.toString('base64');
  }
  if (!response.trim() && !imageBase64) throw new HttpsError('invalid-argument', 'Write a response or attach a photo.');
  const imageDigest = imageBase64 ? key(imageBase64) : '';
  const id = key(uid, data.recipientId, 'moment', data.dayId, response, imageDigest);
  const letter = { id, senderId: uid, recipientId: data.recipientId, envelopeStyle: 1, stampStyle: 1, sound: 0,
    message: response || '今日の空をおすそわけ。', delivered: true, opened: false,
    ...(imageBase64 ? { imageReference: id } : {}), imageDigest };
  await db.runTransaction(async tx => {
    await accepted(tx, uid, data.recipientId);
    const ref = db.collection('pacchiMail').doc(id), current = await tx.get(ref);
    if (current.exists) {
      if (!samePayload(current.data(), letter, ['senderId', 'recipientId', 'message', 'imageDigest'])) throw new HttpsError('already-exists', 'This request ID has already been used.');
      return;
    }
    if (imageBase64) tx.create(db.collection('pacchiMomentPhotos').doc(id), {
      ownerId: uid, recipientId: data.recipientId, imageBase64, createdAt: FieldValue.serverTimestamp()
    });
    tx.create(ref, { ...letter, createdAt: FieldValue.serverTimestamp() });
  });
  return {};
});
export const pacchiMailPhoto = callable(async (uid, data) => {
  const id = identifier(data.id);
  return db.runTransaction(async tx => {
    const mail = await tx.get(db.collection('pacchiMail').doc(id));
    if (!mail.exists || mail.data().recipientId !== uid || mail.data().imageReference !== id) throw new HttpsError('permission-denied', 'This attachment is not addressed to you.');
    await accepted(tx, uid, mail.data().senderId);
    const photo = await tx.get(db.collection('pacchiMomentPhotos').doc(id));
    if (!photo.exists || photo.data().recipientId !== uid || photo.data().ownerId !== mail.data().senderId) throw new HttpsError('permission-denied', 'Attachment is unavailable.');
    return { imageBase64: photo.data().imageBase64 };
  });
});
