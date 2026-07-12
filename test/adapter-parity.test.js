'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tt-adapter-parity-'));
process.env.TYPELESS_DATA_DIR = dataDir;
process.on('exit', () => fs.rmSync(dataDir, { recursive: true, force: true }));

const { createApplicationService } = require('../lib/application-service');
const { createManagerAdapter } = require('../manager');

function createReadOnlyCore() {
  return {
    readAccounts: () => [{ user_id: 'u1', nickname: 'One', token: 'secret' }],
    liveStatus: async () => ({ token_valid: true, total_words: 3 }),
    hasSnapshot: () => true,
    snapshotMtime: () => '2026-07-12T00:00:00.000Z',
    tokenExpiryInfo: () => ({ token_expires_at: null, token_days_left: null }),
    runtimeDataStatus: () => ({ status: 'backed_up', backed_up: true }),
    typelessConnectionStatus: async () => ({ state: 'connected', cdp_reachable: true, port: 9222 }),
    versionDriftStatus: () => ({ current: '1.2.3', last_seen: '1.2.3', drifted: false }),
    readMaster: () => ['alpha', 'beta'],
    paywallStatus: () => ({ exists: true, patched: false }),
  };
}

test('HTTP adapter serializes read-only application service commands without owning orchestration', async () => {
  const cases = [
    ['accounts.list', result => result.accounts],
    ['backup.status', result => result],
    ['connection.status', result => result],
    ['version.status', result => result],
    ['master.get', result => result.words],
    ['patch.status', result => result],
  ];

  for (const [method, select] of cases) {
    const core = createReadOnlyCore();
    const service = createApplicationService({ core });
    const adapter = createManagerAdapter({ core });
    const expected = select(await service.execute(method, {}));
    const response = await adapter.execute(method, {});

    assert.deepEqual(response, { status: 'OK', data: expected }, method);
    assert.equal(JSON.stringify(response).includes('secret'), false, method);
  }
});
