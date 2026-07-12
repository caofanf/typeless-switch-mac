'use strict';

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

  const handlers = {
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
