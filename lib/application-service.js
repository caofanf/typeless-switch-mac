'use strict';

const crypto = require('crypto');
const { CoreError } = require('./core-errors');
const { ConfirmationStore } = require('./operation-confirmations');
const { publicAccount, publicCapture, publicDictionary, publicLiveStatus } = require('./public-dto');
const { TaskRunner } = require('./task-runner');

const CAPABILITIES = Object.freeze([
  'system.getOverview',
  'connection.status',
  'version.status',
  'accounts.list',
  'accounts.detectCurrent',
  'dictionaries.getAccount',
  'master.get',
  'backup.status',
  'diagnostics.run',
  'patch.status',
  'tasks.listActive',
  'connection.establish',
  'operations.prepare',
  'accounts.captureCurrent',
  'accounts.saveCapture',
  'accounts.delete',
  'snapshots.save',
  'snapshots.switch',
  'version.acknowledge',
]);

function invalidRequest(message, context = {}) {
  return new CoreError('INVALID_REQUEST', message, {
    recoverable: true,
    context,
  });
}

function createApplicationService(options = {}) {
  const core = options.core || require('./common');
  const taskRunner = options.taskRunner || new TaskRunner();
  const confirmationStore = options.confirmationStore || new ConfirmationStore();
  const now = options.now || Date.now;
  const captures = new Map();
  const captureTtlMs = 5 * 60 * 1000;

  function requireParams(params) {
    if (!params || typeof params !== 'object' || Array.isArray(params)) {
      throw invalidRequest('请求参数必须是对象');
    }
    return params;
  }

  function requireText(params, field) {
    const value = params[field];
    if (typeof value !== 'string' || !value.trim()) {
      throw invalidRequest(`缺少参数：${field}`, { field });
    }
    return value.trim();
  }

  function findAccount(params) {
    const userId = requireText(params, 'user_id');
    const account = core.readAccounts().find(item => item.user_id === userId);
    if (!account) {
      throw new CoreError('ACCOUNT_NOT_FOUND', '账号不存在', {
        recoverable: true,
        suggested_action: 'accounts.list',
        context: { user_id: userId },
      });
    }
    return account;
  }

  async function listAccounts() {
    const accounts = core.readAccounts();
    const liveStates = await Promise.all(accounts.map(account => (
      core.liveStatus(account).catch(error => ({ token_valid: false, _err: error.message }))
    )));
    return {
      accounts: accounts.map((account, index) => {
        const hasSnapshot = core.hasSnapshot(account.user_id);
        return publicAccount(account, {
          live: publicLiveStatus(liveStates[index]),
          has_snapshot: hasSnapshot,
          snapshot_mtime: hasSnapshot ? core.snapshotMtime(account.user_id) : null,
          ...core.tokenExpiryInfo(account.token),
        });
      }),
    };
  }

  function takeCapture(captureId, consume = false) {
    const item = captures.get(captureId);
    if (!item || item.expiresAt <= now()) {
      captures.delete(captureId);
      throw new CoreError('CAPTURE_EXPIRED', '账号抓取结果已失效，请重新抓取', {
        recoverable: true,
        suggested_action: 'accounts.captureCurrent',
      });
    }
    if (consume) captures.delete(captureId);
    return item.capture;
  }

  const handlers = {
    'connection.establish': async () => {
      await core.ensureApp();
      return core.typelessConnectionStatus();
    },
    'operations.prepare': async params => {
      const method = requireText(params, 'method');
      const operationParams = params.params && typeof params.params === 'object' ? params.params : {};
      return confirmationStore.prepare(method, operationParams, params.summary || {});
    },
    'accounts.captureCurrent': async () => {
      const capture = await core.captureTokenCDP();
      if (!capture?.user_id || !capture?.token) {
        throw new CoreError('CURRENT_ACCOUNT_UNAVAILABLE', '抓取结果缺少账号信息', {
          recoverable: true,
          suggested_action: 'accounts.captureCurrent',
        });
      }
      const captureId = crypto.randomBytes(18).toString('base64url');
      captures.set(captureId, { capture, expiresAt: now() + captureTtlMs });
      return publicCapture(capture, captureId);
    },
    'accounts.saveCapture': async params => {
      const captureId = requireText(params, 'capture_id');
      const captured = takeCapture(captureId);
      const accounts = core.readAccounts();
      const index = accounts.findIndex(account => account.user_id === captured.user_id);
      const nickname = typeof params.nickname === 'string' ? params.nickname.trim().slice(0, 120) : '';
      const email = typeof params.email === 'string' ? params.email.trim().slice(0, 254) : '';
      const record = {
        user_id: captured.user_id,
        nickname: nickname || captured.nickname || email || captured.email || captured.user_id.slice(0, 8),
        email: email || captured.email || '',
        role: captured.role || '',
        token: captured.token,
        captured_at: captured.captured_at || new Date(now()).toISOString(),
        added_at: index >= 0 ? accounts[index].added_at : new Date(now()).toISOString(),
      };
      if (index >= 0) accounts[index] = record;
      else accounts.push(record);
      core.writeAccounts(accounts);
      core.saveSnapshot(captured.user_id);
      takeCapture(captureId, true);
      return publicAccount(record);
    },
    'accounts.delete': async params => {
      const userId = requireText(params, 'user_id');
      const confirmationParams = { user_id: userId, delete_snapshot: params.delete_snapshot === true };
      confirmationStore.consume(params.confirmation_token, 'accounts.delete', confirmationParams);
      const accounts = core.readAccounts();
      if (!accounts.some(account => account.user_id === userId)) {
        throw new CoreError('ACCOUNT_NOT_FOUND', '账号不存在', { recoverable: true });
      }
      core.writeAccounts(accounts.filter(account => account.user_id !== userId));
      if (confirmationParams.delete_snapshot && typeof core.deleteSnapshot === 'function') core.deleteSnapshot(userId);
      return { deleted: true, user_id: userId };
    },
    'snapshots.save': async params => {
      const account = findAccount(params);
      core.saveSnapshot(account.user_id);
      return { user_id: account.user_id, has_snapshot: core.hasSnapshot(account.user_id) };
    },
    'snapshots.switch': async params => {
      const account = findAccount(params);
      if (!core.hasSnapshot(account.user_id)) {
        throw new CoreError('SNAPSHOT_NOT_FOUND', '该账号没有可用快照', {
          recoverable: true,
          suggested_action: 'snapshots.save',
          context: { user_id: account.user_id },
        });
      }
      await core.killTypeless();
      if (typeof core.sleep === 'function') await core.sleep(1500);
      core.restoreSnapshot(account.user_id);
      core.launchTypeless();
      return { switched: true, user_id: account.user_id };
    },
    'version.acknowledge': async () => {
      const version = core.getTypelessVersion();
      if (version) core.writeVersionState(version);
      return core.versionDriftStatus();
    },
    'connection.status': async () => core.typelessConnectionStatus(),
    'version.status': async () => core.versionDriftStatus(),
    'accounts.list': listAccounts,
    'accounts.detectCurrent': async () => {
      const connection = await core.typelessConnectionStatus();
      if (!connection.cdp_reachable) {
        throw new CoreError('MANAGEMENT_CONNECTION_REQUIRED', 'Typeless 管理连接未开启', {
          recoverable: true,
          suggested_action: 'connection.establish',
          context: { connection },
        });
      }
      return publicCapture(await core.captureTokenCDP(null, false));
    },
    'dictionaries.getAccount': async params => {
      const account = findAccount(params);
      const response = await core.curlApi('GET', '/user/dictionary/list?size=500', account.token);
      return publicDictionary(response.data);
    },
    'master.get': async () => ({ words: core.readMaster() }),
    'backup.status': async () => core.runtimeDataStatus(),
    'diagnostics.run': async () => {
      const connection = await core.typelessConnectionStatus();
      return {
        connection,
        version: core.versionDriftStatus(),
        backup: core.runtimeDataStatus(),
        patch: core.paywallStatus(),
      };
    },
    'patch.status': async () => core.paywallStatus(),
    'tasks.listActive': async () => ({ tasks: taskRunner.listActive() }),
    'system.getOverview': async () => {
      const [connection, accounts, version] = await Promise.all([
        core.typelessConnectionStatus(),
        listAccounts(),
        Promise.resolve(core.versionDriftStatus()),
      ]);
      return {
        connection,
        accounts: accounts.accounts,
        version,
        backup: core.runtimeDataStatus(),
        patch: core.paywallStatus(),
        active_tasks: taskRunner.listActive(),
      };
    },
  };

  async function execute(method, params = {}) {
    if (typeof method !== 'string' || !method) throw invalidRequest('缺少命令名称');
    const handler = handlers[method];
    if (!handler) throw invalidRequest('不支持的命令', { method });
    return handler(requireParams(params));
  }

  return {
    execute,
    capabilities: () => [...CAPABILITIES],
    taskRunner,
    confirmationStore,
  };
}

module.exports = { createApplicationService };
