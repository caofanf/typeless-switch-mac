#!/usr/bin/env node
/**
 * Typeless 多账号管理器 —— 本地 HTTP 适配器
 *
 * 浏览器兼容界面只负责 HTTP 安全、请求参数转换和旧响应格式；所有业务操作
 * 统一委托给 application service，确保 Web 与原生 macOS App 使用同一核心。
 */
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const C = require('./lib/common');
const { createApplicationService } = require('./lib/application-service');
const { CoreError } = require('./lib/core-errors');
const {
  LocalApiError,
  applySecurityHeaders,
  createLocalApiSecurity,
  readJsonBody,
} = require('./lib/local-api-security');
const {
  publicAccount, publicCapture, publicDictionary, publicLiveStatus, safeCount,
} = require('./lib/public-dto');

const HTTP_DATA_SELECTORS = Object.freeze({
  'accounts.list': result => result.accounts,
  'master.get': result => result.words,
});

function createManagerAdapter(options = {}) {
  const applicationService = options.applicationService
    || createApplicationService({ core: options.core || C });
  return {
    applicationService,
    async execute(method, params = {}) {
      const result = await applicationService.execute(method, params);
      const select = HTTP_DATA_SELECTORS[method] || (value => value);
      return { status: 'OK', data: select(result) };
    },
  };
}

const PORT = C.config.manager_port;
const security = createLocalApiSecurity({ port: PORT });
const managerAdapter = createManagerAdapter({ core: C });
const service = managerAdapter.applicationService;

function send(res, code, object) {
  applySecurityHeaders(res);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(object));
}

function readBody(req, limitBytes) {
  return limitBytes ? readJsonBody(req, { limitBytes }) : security.readJson(req);
}

async function readObjectBody(req, limitBytes) {
  const body = await readBody(req, limitBytes);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new LocalApiError(400, 'INVALID_INPUT', 'JSON 顶层必须是对象');
  }
  return body;
}

function coreErrorFromWire(error) {
  return new CoreError(error?.code || 'INTERNAL_ERROR', error?.message || '内部错误', error?.details || {});
}

async function executeTask(method, params = {}) {
  const started = await service.execute(method, params);
  if (!started || typeof started.task_id !== 'string') return started;
  const outcome = await service.taskRunner.wait(started.task_id);
  if (!outcome) throw new CoreError('INTERNAL_ERROR', '任务状态丢失');
  if (outcome.state === 'failed') throw coreErrorFromWire(outcome.error);
  if (outcome.state === 'cancelled') {
    throw new CoreError('OPERATION_CONFLICT', '任务已取消', { recoverable: true });
  }
  return outcome.result;
}

async function executeConfirmed(method, params, summary = {}) {
  const prepared = await service.execute('operations.prepare', { method, params, summary });
  return executeTask(method, { ...params, confirmation_token: prepared.confirmation_token });
}

function temporaryJsonPath(label) {
  fs.mkdirSync(C.ROOT, { recursive: true, mode: 0o700 });
  return path.join(C.ROOT, `.${label}-${crypto.randomBytes(12).toString('hex')}.json`);
}

function removeTemporaryFile(file) {
  try { fs.unlinkSync(file); } catch (_) {}
}

function taskResultData(result) {
  return result && typeof result === 'object' ? result : {};
}

async function routeRequest(req, res) {
  let url;
  try { url = new URL(req.url, `http://localhost:${PORT}`); }
  catch (_) { throw new LocalApiError(400, 'INVALID_REQUEST_TARGET', '请求路径无效'); }
  const pathname = url.pathname;
  const method = req.method;

  if (method === 'GET' && pathname === '/api/health') {
    security.assertPageRequest(req);
    return send(res, 200, {
      status: 'OK',
      data: { product: 'typeless-toolkit-manager', state: 'ready', version: '2.3.0' },
    });
  }
  if (method === 'GET' && (pathname === '/' || pathname === '/index.html' || pathname === '/manager.html')) {
    security.assertPageRequest(req);
    const html = security.injectHtml(fs.readFileSync(path.join(C.CODE_DIR, 'manager.html'), 'utf8'));
    applySecurityHeaders(res);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (pathname.startsWith('/api/')) security.assertApiRequest(req);

  if (method === 'GET' && pathname === '/api/accounts') {
    return send(res, 200, await managerAdapter.execute('accounts.list'));
  }
  if (method === 'GET' && pathname === '/api/backup-status') {
    return send(res, 200, await managerAdapter.execute('backup.status'));
  }
  if (method === 'POST' && pathname === '/api/backup-runtime') {
    const data = await service.execute('backup.create', {});
    return send(res, 200, {
      status: 'OK', data,
      msg: data.backup_path ? '运行数据已备份' : '暂无运行数据可备份',
    });
  }
  if (method === 'GET' && pathname === '/api/backup-export') {
    const destination = temporaryJsonPath('http-backup-export');
    try {
      await service.execute('backup.export', { path: destination });
      const body = fs.readFileSync(destination);
      const filename = `typeless-toolkit-backup-${new Date().toISOString().slice(0, 10)}.json`;
      applySecurityHeaders(res);
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition': `attachment; filename="${filename}"`,
      });
      return res.end(body);
    } finally {
      removeTemporaryFile(destination);
    }
  }
  if (method === 'POST' && pathname === '/api/backup-restore') {
    const body = await readObjectBody(req, 128 * 1024 * 1024);
    const source = temporaryJsonPath('http-backup-import');
    try {
      fs.writeFileSync(source, `${JSON.stringify(body.bundle || body)}\n`, { mode: 0o600, flag: 'wx' });
      const inspection = await service.execute('backup.inspect', { path: source });
      const completed = await executeConfirmed('backup.restore', { inspection_id: inspection.inspection_id }, inspection.summary);
      const { status: backupStatus = {}, ...restore } = taskResultData(completed);
      return send(res, 200, { status: 'OK', msg: '备份已恢复', data: { ...restore, ...backupStatus } });
    } finally {
      removeTemporaryFile(source);
    }
  }
  if (method === 'GET' && pathname === '/api/current') {
    try {
      const data = await service.execute('accounts.detectCurrent', {});
      return send(res, 200, { status: 'OK', data });
    } catch (error) {
      const connection = error.details?.context?.connection || await service.execute('connection.status', {});
      const connected = connection.cdp_reachable === true;
      return send(res, 200, {
        status: 'FAIL',
        code: connected ? 'CURRENT_ACCOUNT_UNAVAILABLE' : 'MANAGEMENT_CONNECTION_REQUIRED',
        msg: connected ? error.message : 'Typeless 管理连接未开启',
        data: connection,
      });
    }
  }
  if (method === 'POST' && pathname === '/api/capture') {
    return send(res, 200, { status: 'OK', data: await service.execute('accounts.captureCurrent', {}) });
  }
  if (method === 'POST' && pathname === '/api/accounts') {
    const body = await readObjectBody(req);
    return send(res, 200, { status: 'OK', data: await service.execute('accounts.saveCapture', body) });
  }

  const accountAction = pathname.match(/^\/api\/accounts\/([^/]+)\/(snapshot|switch|dictionary|sync|words|word|import-master)$/);
  if (accountAction) {
    const userId = decodeURIComponent(accountAction[1]);
    const action = accountAction[2];
    if (method === 'POST' && action === 'snapshot') {
      const data = await service.execute('snapshots.save', { user_id: userId });
      return send(res, 200, { status: 'OK', msg: '快照已保存', has_snapshot: data.has_snapshot });
    }
    if (method === 'POST' && action === 'switch') {
      await service.execute('snapshots.switch', { user_id: userId });
      return send(res, 200, { status: 'OK', msg: '已切换并重启 Typeless' });
    }
    if (method === 'GET' && action === 'dictionary') {
      return send(res, 200, { status: 'OK', data: await service.execute('dictionaries.getAccount', { user_id: userId }) });
    }
    if (method === 'POST' && action === 'sync') {
      return send(res, 200, { status: 'OK', data: await executeTask('dictionaries.syncAccount', { user_id: userId }) });
    }
    if (method === 'POST' && action === 'words') {
      const body = await readObjectBody(req);
      return send(res, 200, { status: 'OK', data: await executeTask('dictionaries.addWords', { user_id: userId, terms: body.terms }) });
    }
    if (method === 'POST' && action === 'word') {
      const body = await readObjectBody(req);
      return send(res, 200, { status: 'OK', data: await service.execute('dictionaries.addWord', { user_id: userId, term: body.term }) });
    }
    if (method === 'DELETE' && action === 'word') {
      const data = await service.execute('dictionaries.deleteWord', { user_id: userId, term: url.searchParams.get('term') });
      return send(res, 200, { status: 'OK', data });
    }
    if (method === 'POST' && action === 'import-master') {
      const result = await executeTask('dictionaries.importMasterToAccount', { user_id: userId });
      return send(res, 200, {
        status: 'OK', data: { master: result.total, already: result.already, imported: result.imported },
      });
    }
  }

  const copyAction = pathname.match(/^\/api\/accounts\/([^/]+)\/copy-from\/([^/]+)$/);
  if (method === 'POST' && copyAction) {
    const result = await executeTask('dictionaries.copyBetweenAccounts', {
      target_user_id: decodeURIComponent(copyAction[1]),
      source_user_id: decodeURIComponent(copyAction[2]),
    });
    return send(res, 200, {
      status: 'OK', data: { src_count: result.total, imported: result.imported, already: result.already },
    });
  }

  const deleteAccount = pathname.match(/^\/api\/accounts\/([^/]+)$/);
  if (method === 'DELETE' && deleteAccount) {
    const params = { user_id: decodeURIComponent(deleteAccount[1]), delete_snapshot: false };
    await executeConfirmed('accounts.delete', params, { action: 'remove-account' });
    return send(res, 200, { status: 'OK' });
  }

  if (method === 'POST' && pathname === '/api/reset-device') {
    const result = await executeConfirmed('device.reset', {}, { action: 'reset-device' });
    return send(res, 200, {
      status: 'OK',
      msg: '设备已重置,Typeless 已以新设备 ID 启动(登录页),可注册新账号',
      manager_data_backup: result.manager_data_backup,
    });
  }
  if (method === 'GET' && pathname === '/api/paywall-status') {
    return send(res, 200, await managerAdapter.execute('patch.status'));
  }
  if (method === 'GET' && pathname === '/api/version-status') {
    return send(res, 200, await managerAdapter.execute('version.status'));
  }
  if (method === 'POST' && pathname === '/api/version-ack') {
    return send(res, 200, { status: 'OK', data: await service.execute('version.acknowledge', {}) });
  }
  if (method === 'GET' && pathname === '/api/diagnostics') {
    return send(res, 200, { status: 'OK', data: await service.execute('diagnostics.run', {}) });
  }
  if (method === 'POST' && pathname === '/api/patch-paywall') {
    const result = await executeConfirmed('patch.apply', { action: 'apply' }, { action: 'patch-paywall' });
    return send(res, 200, { status: 'OK', data: result });
  }
  if (method === 'POST' && pathname === '/api/sync-all') {
    const result = await executeTask('dictionaries.syncAll', {});
    return send(res, 200, { status: 'OK', data: result.accounts });
  }
  if (method === 'GET' && pathname === '/api/master') {
    return send(res, 200, await managerAdapter.execute('master.get'));
  }
  if (method === 'POST' && pathname === '/api/master') {
    const body = await readObjectBody(req);
    if (!Array.isArray(body.terms)) throw new LocalApiError(400, 'INVALID_INPUT', 'terms 必须是数组');
    const terms = body.terms.map(term => String(term || '').trim()).filter(Boolean);
    const result = await executeConfirmed('master.replace', { terms }, { action: 'replace-master', count: terms.length });
    return send(res, 200, { status: 'OK', data: result.words });
  }
  if (method === 'POST' && pathname === '/api/launch') {
    const data = await service.execute('connection.establish', {});
    return send(res, 200, { status: 'OK', msg: 'Typeless 管理连接已建立', data });
  }

  return send(res, 404, { status: 'FAIL', msg: `not found: ${pathname}` });
}

const server = http.createServer((req, res) => {
  routeRequest(req, res).catch(error => {
    const isLocal = error instanceof LocalApiError;
    const statusCode = isLocal
      ? error.statusCode
      : error.code === 'ACCOUNT_NOT_FOUND' ? 404
        : error.code === 'INVALID_REQUEST' || error.code === 'CONFIRMATION_REQUIRED' || error.code === 'SNAPSHOT_NOT_FOUND' ? 400
          : 500;
    send(res, statusCode, {
      status: 'FAIL',
      code: error.code || 'INTERNAL_ERROR',
      msg: error.message,
      ...(!isLocal && error.details ? { details: error.details } : {}),
    });
  });
});

server.on('error', error => {
  if (error.code === 'EADDRINUSE') {
    console.error(`[mgr] 端口 ${PORT} 已被占用。如果管理器已经打开,直接访问 http://127.0.0.1:${PORT}`);
    process.exit(1);
  }
  throw error;
});

server.on('clientError', (_error, socket) => {
  if (!socket.writable) return;
  socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
});

function startServer() {
  server.listen(PORT, '127.0.0.1', () => { C.log(`[mgr] 管理器运行于 http://127.0.0.1:${PORT}`); });
  return server;
}

if (require.main === module) startServer();

module.exports = {
  publicAccount,
  publicCapture,
  publicDictionary,
  publicLiveStatus,
  safeCount,
  security,
  server,
  startServer,
  createManagerAdapter,
  routeRequest,
};
