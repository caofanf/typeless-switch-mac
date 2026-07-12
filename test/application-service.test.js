const test = require('node:test');
const assert = require('node:assert/strict');
const { createApplicationService } = require('../lib/application-service');

test('accounts.list returns sanitized live account state', async () => {
  const service = createApplicationService({
    core: {
      readAccounts: () => [{ user_id: 'u1', nickname: 'N', token: 'secret' }],
      liveStatus: async () => ({ token_valid: true, total_words: 2 }),
      hasSnapshot: () => true,
      snapshotMtime: () => '2026-07-12T00:00:00.000Z',
      tokenExpiryInfo: () => ({ token_expires_at: null, token_days_left: null }),
    },
  });
  const result = await service.execute('accounts.list', {});
  assert.equal(result.accounts.length, 1);
  assert.equal(result.accounts[0].user_id, 'u1');
  assert.equal(JSON.stringify(result).includes('secret'), false);
});

test('connection status is exposed without HTTP concepts', async () => {
  const service = createApplicationService({ core: {
    typelessConnectionStatus: async () => ({ cdp_reachable: false }),
  }});
  assert.deepEqual(await service.execute('connection.status', {}), { cdp_reachable: false });
});
