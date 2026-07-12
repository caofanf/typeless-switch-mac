'use strict';

const crypto = require('crypto');
const { CoreError } = require('./core-errors');
const { ConfirmationStore } = require('./operation-confirmations');
const { publicAccount, publicCapture, publicDictionary, publicLiveStatus, safeCount } = require('./public-dto');
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
  'dictionaries.addWord',
  'dictionaries.addWords',
  'dictionaries.deleteWord',
  'dictionaries.syncAccount',
  'dictionaries.syncAll',
  'dictionaries.importMasterToAccount',
  'dictionaries.copyBetweenAccounts',
  'master.replace',
  'tasks.cancel',
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

  function accountById(userId) {
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

  function normalizedTerms(value) {
    if (!Array.isArray(value)) throw invalidRequest('terms 必须是数组', { field: 'terms' });
    return value.map(term => String(term || '').trim()).filter(Boolean);
  }

  async function bulkImport(account, terms) {
    if (!terms.length) throw invalidRequest('没有可添加的词', { field: 'terms' });
    const response = await core.curlApi('POST', '/user/dictionary/bulk-import', account.token, {
      content: terms.join('\n'),
    });
    return { requested: terms.length, imported: safeCount(response.data?.success_count) };
  }

  async function importMissing(account, candidates) {
    const response = await core.curlApi('GET', '/user/dictionary/list?size=500', account.token);
    const key = value => String(value || '').trim().toLocaleLowerCase();
    const existing = new Set((response.data?.words || []).map(word => key(word.term)));
    const missing = candidates.filter(term => !existing.has(key(term)));
    const imported = missing.length ? (await bulkImport(account, missing)).imported : 0;
    return { total: candidates.length, already: candidates.length - missing.length, imported };
  }

  const handlers = {
    'dictionaries.addWord': async params => {
      const account = findAccount(params);
      const term = requireText(params, 'term').slice(0, 500);
      await core.curlApi('POST', '/user/dictionary/add', account.token, { term });
      return { term };
    },
    'dictionaries.addWords': async params => {
      const account = findAccount(params);
      const terms = normalizedTerms(params.terms);
      if (terms.length > 100) {
        return taskRunner.start({ type: 'dictionary-import', resources: [`account:${account.user_id}`], cancellable: true },
          async ctx => {
            ctx.throwIfCancelled();
            const result = await bulkImport(account, terms);
            ctx.progress({ phase: 'importing', completed: terms.length, total: terms.length, message: '导入完成' });
            return result;
          });
      }
      return bulkImport(account, terms);
    },
    'dictionaries.deleteWord': async params => {
      const account = findAccount(params);
      const term = requireText(params, 'term');
      const list = await core.curlApi('GET', '/user/dictionary/list?size=500', account.token);
      const word = (list.data?.words || []).find(item => item.term === term);
      if (!word) throw new CoreError('INVALID_REQUEST', '词条不存在', { recoverable: true, context: { term } });
      await core.curlApi('POST', '/user/dictionary/delete', account.token, {
        user_dictionary_id: word.user_dictionary_id,
      });
      let absentHits = 0;
      for (let attempt = 0; attempt < 10; attempt += 1) {
        if (typeof core.sleep === 'function') await core.sleep(500);
        const check = await core.curlApi('GET', '/user/dictionary/list?size=500', account.token);
        if (!Array.isArray(check.data?.words)) continue;
        const exists = check.data.words.some(item => item.term === term);
        absentHits = exists ? 0 : absentHits + 1;
        if (absentHits >= 2) return { term, deleted: true };
      }
      throw new CoreError('INTERNAL_ERROR', '删除请求已发送，但词条仍存在', { recoverable: true });
    },
    'dictionaries.syncAccount': async params => {
      const account = findAccount(params);
      return taskRunner.start({ type: 'sync-account', resources: [`account:${account.user_id}`], cancellable: true },
        async ctx => {
          ctx.throwIfCancelled();
          const result = await core.syncAccount(account);
          ctx.progress({ phase: 'syncing', completed: 1, total: 1, message: '同步完成' });
          return result;
        });
    },
    'dictionaries.syncAll': async () => {
      const accounts = core.readAccounts();
      return taskRunner.start({ type: 'sync-all', resources: ['dictionary-sync'], cancellable: true }, async ctx => {
        const results = [];
        for (let index = 0; index < accounts.length; index += 1) {
          ctx.throwIfCancelled();
          const account = accounts[index];
          try {
            results.push({ user_id: account.user_id, ...(await core.syncAccount(account)) });
          } catch (error) {
            results.push({ user_id: account.user_id, error: error.message });
          }
          ctx.progress({ phase: 'syncing', completed: index + 1, total: accounts.length, message: `正在同步 ${index + 1}/${accounts.length}` });
        }
        return { accounts: results };
      });
    },
    'dictionaries.importMasterToAccount': async params => {
      const account = findAccount(params);
      const master = core.readMaster();
      return taskRunner.start({ type: 'import-master', resources: [`account:${account.user_id}`], cancellable: true },
        async ctx => {
          ctx.throwIfCancelled();
          return importMissing(account, master);
        });
    },
    'dictionaries.copyBetweenAccounts': async params => {
      const source = accountById(requireText(params, 'source_user_id'));
      const target = accountById(requireText(params, 'target_user_id'));
      if (source.user_id === target.user_id) throw invalidRequest('源账号和目标账号不能相同');
      return taskRunner.start({ type: 'copy-dictionary', resources: [`account:${target.user_id}`], cancellable: true }, async ctx => {
        ctx.throwIfCancelled();
        const response = await core.curlApi('GET', '/user/dictionary/list?size=500', source.token);
        const terms = (response.data?.words || []).map(word => word.term).filter(Boolean);
        return importMissing(target, terms);
      });
    },
    'master.replace': async params => {
      const terms = normalizedTerms(params.terms);
      confirmationStore.consume(params.confirmation_token, 'master.replace', { terms });
      return { words: core.writeMaster(terms) };
    },
    'tasks.cancel': async params => ({ cancelled: taskRunner.cancel(requireText(params, 'task_id')) }),
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
