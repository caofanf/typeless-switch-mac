const test = require('node:test');
const assert = require('node:assert/strict');
const { ConfirmationStore } = require('../lib/operation-confirmations');

test('confirmation is one-time and bound to canonical params', () => {
  let now = 1000;
  const store = new ConfirmationStore({ now: () => now, ttlMs: 120000 });
  const prepared = store.prepare('accounts.delete', { user_id: 'u1', delete_snapshot: false }, { title: '删除 N' });
  assert.equal(prepared.expires_at, 121000);
  assert.deepEqual(store.consume(prepared.confirmation_token, 'accounts.delete', {
    delete_snapshot: false, user_id: 'u1',
  }), { title: '删除 N' });
  assert.throws(() => store.consume(prepared.confirmation_token, 'accounts.delete', {
    user_id: 'u1', delete_snapshot: false,
  }), /确认已失效/);
});

test('confirmation rejects expiry and changed params', () => {
  let now = 1000;
  const store = new ConfirmationStore({ now: () => now, ttlMs: 10 });
  const prepared = store.prepare('device.reset', { scope: 'all' }, {});
  assert.throws(() => store.consume(prepared.confirmation_token, 'device.reset', { scope: 'other' }), /参数已变化/);
  now = 2000;
  assert.throws(() => store.consume(prepared.confirmation_token, 'device.reset', { scope: 'all' }), /确认已过期/);
});
