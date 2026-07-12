const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
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

test('capture handle hides token and is consumed by save', async () => {
  const saved = [];
  const service = createApplicationService({ core: {
    captureTokenCDP: async () => ({ user_id: 'u1', token: 'secret', nickname: 'N' }),
    readAccounts: () => [],
    writeAccounts: accounts => saved.push(accounts),
    saveSnapshot: () => {},
  }, now: () => 1000 });
  const capture = await service.execute('accounts.captureCurrent', {});
  assert.equal(JSON.stringify(capture).includes('secret'), false);
  await service.execute('accounts.saveCapture', { capture_id: capture.capture_id, nickname: 'N' });
  assert.equal(saved[0][0].token, 'secret');
  await assert.rejects(() => service.execute('accounts.saveCapture', {
    capture_id: capture.capture_id,
  }), error => error.code === 'CAPTURE_EXPIRED');
});

test('dictionaries.addWords trims and removes empty terms', async () => {
  const calls = [];
  const service = createApplicationService({ core: {
    readAccounts: () => [{ user_id: 'u1', token: 't' }],
    curlApi: async (...args) => { calls.push(args); return { data: { success_count: 2 } }; },
  }});
  const result = await service.execute('dictionaries.addWords', {
    user_id: 'u1', terms: [' alpha ', '', 'beta'],
  });
  assert.equal(result.requested, 2);
  assert.equal(calls[0][3].content, 'alpha\nbeta');
});


test('backup.restore rejects a file changed after inspection', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tt-inspection-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const source = path.join(dir, 'backup.json');
  fs.writeFileSync(source, JSON.stringify({
    type: 'typeless-toolkit-macos-runtime-backup', version: 1, files: [],
  }));
  const service = createApplicationService({ core: {
    restoreRuntimeBackupBundle: () => { throw new Error('must not restore changed input'); },
  }, now: () => 1000 });
  const inspection = await service.execute('backup.inspect', { path: source });
  fs.appendFileSync(source, ' ');
  await assert.rejects(() => service.execute('backup.restore', {
    inspection_id: inspection.inspection_id,
    confirmation_token: 'unused',
  }), error => error.code === 'BACKUP_CHANGED');
});

test('device reset and patch require server-side confirmation', async () => {
  const service = createApplicationService({ core: {} });
  await assert.rejects(() => service.execute('device.reset', {}),
    error => error.code === 'CONFIRMATION_REQUIRED');
  await assert.rejects(() => service.execute('patch.apply', {}),
    error => error.code === 'CONFIRMATION_REQUIRED');
});
