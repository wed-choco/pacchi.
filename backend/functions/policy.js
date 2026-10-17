import { createHash } from 'node:crypto';

export const assetIds = new Set(['pixel-heart', 'pixel-star', 'pixel-bow']);
export function key(...parts) { return createHash('sha256').update(JSON.stringify(parts)).digest('hex'); }
export function boundedText(value, maximum, required = false) {
  if (typeof value !== 'string' || Array.from(value).length > maximum || (required && !value.trim())) throw new Error('invalid-text');
  return value;
}
export function identifier(value) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(value)) throw new Error('invalid-id');
  return value;
}
export function decoration(value) {
  const finite = (number, low, high) => typeof number === 'number' && Number.isFinite(number) && number >= low && number <= high;
  if (!value || typeof value.id !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(value.id) || !assetIds.has(value.assetId) ||
      !finite(value.position?.x, 0, 1) || !finite(value.position?.y, 0, 1) ||
      !finite(value.scale, 0.6, 1.7) || !finite(value.rotation, -100000, 100000)) throw new Error('invalid-decoration');
  // Construct an allowlist projection. Never copy caption, image, message, or memory fields.
  return { id: value.id, assetId: value.assetId, position: { x: value.position.x, y: value.position.y }, scale: value.scale, rotation: value.rotation };
}
export function samePayload(existing, proposed, fields) { return fields.every(field => existing[field] === proposed[field]); }
export function milestoneID(owner, friend, type, period = '') { return key(owner, friend, type, period); }
