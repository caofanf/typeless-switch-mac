const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createApplicationService } = require('../lib/application-service');
const { TaskRunner } = require('../lib/task-runner');

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

test('connection.establish 只通过 common 统一启动器建立连接', async () => {
  const calls = [];
  const service = createApplicationService({ core: {
    ensureApp: async () => calls.push('ensure'),
    typelessConnectionStatus: async () => ({
      state: 'connected', port: 9222, cdp_reachable: true,
    }),
  }});

  const result = await service.execute('connection.establish', {});

  assert.deepEqual(calls, ['ensure']);
  assert.equal(result.cdp_reachable, true);
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

test('snapshots.switch requires a matching one-time confirmation', async () => {
  const calls = [];
  const service = createApplicationService({ core: {
    readAccounts: () => [{ user_id: 'u1', nickname: 'N', token: 'secret' }],
    hasSnapshot: () => true,
    killTypeless: async () => calls.push('kill'),
    sleep: async () => {},
    restoreSnapshot: userId => calls.push(`restore:${userId}`),
    launchTypeless: () => calls.push('launch'),
  }});

  await assert.rejects(() => service.execute('snapshots.switch', { user_id: 'u1' }),
    error => error.code === 'CONFIRMATION_REQUIRED');
  const prepared = await service.execute('operations.prepare', {
    method: 'snapshots.switch',
    params: { user_id: 'u1' },
    summary: { title: '切换账号' },
  });
  const result = await service.execute('snapshots.switch', {
    user_id: 'u1', confirmation_token: prepared.confirmation_token,
  });

  assert.deepEqual(result, { switched: true, user_id: 'u1' });
  assert.deepEqual(calls, ['kill', 'restore:u1', 'launch']);
  await assert.rejects(() => service.execute('snapshots.switch', {
    user_id: 'u1', confirmation_token: prepared.confirmation_token,
  }), error => error.code === 'CONFIRMATION_REQUIRED');
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

test('patch.apply 成功后通过统一启动器重启 Typeless', async () => {
  const calls = [];
  const taskRunner = new TaskRunner({ idFactory: () => 'patch-success' });
  const service = createApplicationService({
    taskRunner,
    core: {
      backupRuntimeData: reason => { calls.push(`backup:${reason}`); return '/backup'; },
      killTypeless: async () => calls.push('kill'),
      sleep: async () => calls.push('sleep'),
      patchPaywall: async ({ action }) => { calls.push(`patch:${action}`); return { patched: true }; },
      launchTypeless: () => calls.push('launch'),
    },
  });
  const prepared = await service.execute('operations.prepare', {
    method: 'patch.apply', params: { action: 'apply' }, summary: { title: '补丁' },
  });

  const task = await service.execute('patch.apply', {
    action: 'apply', confirmation_token: prepared.confirmation_token,
  });
  const result = await taskRunner.wait(task.task_id);

  assert.equal(result.state, 'succeeded');
  assert.deepEqual(calls, ['backup:patch-paywall', 'kill', 'sleep', 'patch:apply', 'launch']);
});

test('patch.apply 可回滚失败后仍通过统一启动器恢复 Typeless', async () => {
  const calls = [];
  const taskRunner = new TaskRunner({ idFactory: () => 'patch-rollback' });
  const service = createApplicationService({
    taskRunner,
    core: {
      backupRuntimeData: () => '/backup',
      killTypeless: async () => calls.push('kill'),
      sleep: async () => calls.push('sleep'),
      patchPaywall: async () => {
        const error = new Error('补丁失败');
        error.rollback = 'succeeded';
        throw error;
      },
      launchTypeless: () => calls.push('launch'),
    },
  });
  const prepared = await service.execute('operations.prepare', {
    method: 'patch.apply', params: { action: 'apply' }, summary: { title: '补丁' },
  });

  const task = await service.execute('patch.apply', {
    action: 'apply', confirmation_token: prepared.confirmation_token,
  });
  const result = await taskRunner.wait(task.task_id);

  assert.equal(result.state, 'failed');
  assert.deepEqual(calls, ['kill', 'sleep', 'launch']);
});

test('diagnostics.run owns the detailed manager diagnostics orchestration', async () => {
  const service = createApplicationService({ core: {
    ROOT: '/data', CODE_DIR: '/code', MAC_APP_PATH: '/Typeless.app', TYPELESS_BIN: '/Typeless',
    ASAR_PATH: '/app.asar', MAC_INFO_PLIST: '/Info.plist', USERDATA_DIR: '/user-data',
    ACCOUNTS_FILE: '/data/accounts.json', PROFILES_DIR: '/data/profiles',
    RUNTIME_BACKUPS_DIR: '/data/runtime-backups', RUNTIME_DATA: { migration: { status: 'none' } },
    typelessConnectionStatus: async () => ({ port: 9222, cdp_reachable: false, state: 'disconnected' }),
    readAccounts: () => [],
    runtimeDataStatus: () => ({ status: 'no_data' }),
    versionDriftStatus: () => ({ drifted: false }),
    paywallStatus: () => ({ exists: false }),
    pathExists: target => target === '/Typeless.app',
    pathWritable: target => target === '/data',
  }});

  const result = await service.execute('diagnostics.run', {});

  assert.equal(result.typeless.app_path, '/Typeless.app');
  assert.equal(result.typeless.app_found, true);
  assert.equal(result.cdp.reachable, false);
  assert.equal(result.data.dir, '/data');
  assert.equal(result.data.writable, true);
  assert.equal(result.data.accounts_count, 0);
});
