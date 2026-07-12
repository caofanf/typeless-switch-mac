# Typeless Toolkit 原生 macOS 应用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 Typeless Toolkit Web 管理器改造成仅支持 Apple Silicon、可本地构建、临时签名并打包为未公证 `.dmg` 的原生 SwiftUI macOS App，同时完整复用并隔离现有 Node 核心能力。

**Architecture:** 将 `manager.js` 的业务用例抽到 UI 无关的 Node application service，HTTP 管理器和新 stdio sidecar 共用同一服务。SwiftUI App 通过版本化 JSON Lines 协议管理内置 Node sidecar，所有 token 和 profile 数据留在 Node 进程；Swift 只使用脱敏 DTO 和任务事件。

**Tech Stack:** Node.js 22+ 内置模块、`node:test`、Swift 6、SwiftUI、AppKit、XCTest、Xcode project、shell、`codesign`、`hdiutil`。

---

## 执行约束

- 当前分支：`Mac-UI`。
- Git 操作只允许在本地执行；允许 `git add`、`git commit`、本地 branch 操作。
- 禁止执行 `git push`、GitHub PR 创建和任何 GitHub 写操作。
- 当前机器只有 Command Line Tools，没有完整 Xcode。Node 阶段必须完整验证；Swift 源码可先用现有 Swift 工具做静态检查，但 `xcodebuild`、App 启动、签名和 `.dmg` 真机验收必须在完整 Xcode 可用后补跑。
- 保留现有 Web 管理器作为兼容入口，但新 App 不启动 HTTP server。
- 每个任务按 TDD 完成并本地提交；不得把现有未跟踪调研文件或无关 `.gitignore` 改动混入功能提交。

## 文件结构锁定

### Node 核心

```text
lib/
  application-service.js      # UI 无关业务用例和命令实现
  core-errors.js              # 稳定错误类型与错误码
  operation-confirmations.js  # 两阶段确认 token
  public-dto.js               # 脱敏 DTO
  task-runner.js               # 长任务、锁和进度
sidecar/
  main.js                      # stdio 进程入口
  protocol.js                  # JSON Lines 编解码与请求分发
  command-registry.js          # method 到 application service 的映射
```

### Node 测试

```text
test/
  application-service.test.js
  core-errors.test.js
  operation-confirmations.test.js
  public-dto.test.js
  task-runner.test.js
  sidecar-protocol.test.js
  sidecar-integration.test.js
```

### macOS App

```text
macOS/
  TypelessToolkit.xcodeproj/project.pbxproj
  TypelessToolkit/
    Info.plist
    TypelessToolkit.entitlements
    App/
      TypelessToolkitApp.swift
      AppDelegate.swift
      AppCommands.swift
      AppModel.swift
      MenuBarContent.swift
    CoreIPC/
      ProtocolMessages.swift
      JSONLineTransport.swift
      SidecarProcess.swift
      CoreClient.swift
      EventRouter.swift
    Domain/
      Account.swift
      CoreError.swift
      CoreTask.swift
      DictionaryModels.swift
      SystemModels.swift
    DesignSystem/
      StatusView.swift
      EmptyStateView.swift
      ConfirmationSheet.swift
    Features/
      Root/RootView.swift
      Overview/OverviewView.swift
      Accounts/AccountsView.swift
      Accounts/AccountDetailView.swift
      Accounts/AddAccountSheet.swift
      MasterDictionary/MasterDictionaryView.swift
      BackupRestore/BackupRestoreView.swift
      Diagnostics/DiagnosticsView.swift
      AdvancedTools/AdvancedToolsView.swift
      Settings/SettingsView.swift
    Services/
      AppPreferences.swift
      FileDialogService.swift
      RecentActivityStore.swift
    Resources/Sidecar/             # 构建时生成，不手工复制秘密配置
  TypelessToolkitTests/
    TestDoubles.swift
    JSONLineTransportTests.swift
    CoreClientTests.swift
    AppModelTests.swift
```

### 构建与发布

```text
scripts/
  prepare-sidecar.sh
  prepare-node-runtime.sh
  build-debug.sh
  build-release.sh
  package-dmg.sh
  verify-release.sh
release/
  node-runtime.env
  node-sha256.txt
  README-FIRST.txt
  THIRD_PARTY_NOTICES.md
```

---

### Task 1：稳定错误模型

**Files:**
- Create: `lib/core-errors.js`
- Create: `test/core-errors.test.js`

- [ ] **Step 1: 写失败测试**

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { CoreError, normalizeCoreError } = require('../lib/core-errors');

test('CoreError exposes a stable sanitized wire shape', () => {
  const error = new CoreError('ACCOUNT_NOT_FOUND', '账号不存在', {
    recoverable: true,
    suggested_action: 'accounts.list',
    context: { user_id: 'u1' },
  });
  assert.deepEqual(error.toWire(), {
    code: 'ACCOUNT_NOT_FOUND',
    message: '账号不存在',
    details: {
      recoverable: true,
      suggested_action: 'accounts.list',
      context: { user_id: 'u1' },
    },
  });
});

test('normalizeCoreError hides unknown stack and secret-bearing fields', () => {
  const normalized = normalizeCoreError(Object.assign(new Error('boom'), { token: 'secret' }));
  assert.equal(normalized.code, 'INTERNAL_ERROR');
  assert.equal(normalized.message, '内部错误');
  assert.equal(JSON.stringify(normalized).includes('secret'), false);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/core-errors.test.js`
Expected: FAIL with `Cannot find module '../lib/core-errors'`.

- [ ] **Step 3: 实现稳定错误类型**

```js
'use strict';

const KNOWN_CODES = new Set([
  'INVALID_REQUEST', 'UNSUPPORTED_PROTOCOL', 'CORE_PROCESS_EXITED',
  'MANAGEMENT_CONNECTION_REQUIRED', 'CURRENT_ACCOUNT_UNAVAILABLE',
  'CAPTURE_EXPIRED', 'ACCOUNT_NOT_FOUND', 'TOKEN_EXPIRED',
  'SNAPSHOT_NOT_FOUND', 'BACKUP_INVALID', 'BACKUP_CHANGED',
  'RESTORE_RECOVERY_REQUIRED', 'TYPELESS_NOT_INSTALLED',
  'TYPELESS_VERSION_DRIFTED', 'PATCH_FAILED_ROLLED_BACK',
  'PATCH_RECOVERY_REQUIRED', 'CONFIRMATION_REQUIRED',
  'OPERATION_CONFLICT', 'PERMISSION_DENIED', 'NETWORK_UNAVAILABLE',
  'INTERNAL_ERROR',
]);

class CoreError extends Error {
  constructor(code, message, details = {}, options = {}) {
    super(message, options);
    this.name = 'CoreError';
    this.code = KNOWN_CODES.has(code) ? code : 'INTERNAL_ERROR';
    this.details = {
      recoverable: details.recoverable === true,
      suggested_action: details.suggested_action || null,
      context: details.context && typeof details.context === 'object' ? details.context : {},
    };
  }
  toWire() {
    return { code: this.code, message: this.message, details: this.details };
  }
}

function normalizeCoreError(error) {
  if (error instanceof CoreError) return error.toWire();
  return new CoreError('INTERNAL_ERROR', '内部错误', { recoverable: false }).toWire();
}

module.exports = { CoreError, KNOWN_CODES, normalizeCoreError };
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `node --test test/core-errors.test.js`
Expected: 2 tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/core-errors.js test/core-errors.test.js
git commit -m "feat: add stable core error model"
```

### Task 2：统一脱敏 DTO

**Files:**
- Create: `lib/public-dto.js`
- Create: `test/public-dto.test.js`
- Modify: `manager.js:45-142`

- [ ] **Step 1: 写失败测试覆盖账号、抓取和词库脱敏**

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { publicAccount, publicCapture, publicDictionary } = require('../lib/public-dto');

test('public DTOs never expose credentials', () => {
  const account = publicAccount({ user_id: 'u1', nickname: 'N', token: 'secret', cookie: 'c' });
  const capture = publicCapture({ user_id: 'u1', token: 'secret', user_info: { private: true } }, 'cap');
  const dictionary = publicDictionary({ words: [{ term: 'alpha', auto: true, internal: 'x' }] });
  assert.equal(JSON.stringify({ account, capture, dictionary }).includes('secret'), false);
  assert.equal(JSON.stringify({ account, capture, dictionary }).includes('private'), false);
  assert.deepEqual(dictionary.words, [{ term: 'alpha', auto: true }]);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/public-dto.test.js`
Expected: FAIL with missing module.

- [ ] **Step 3: 将 `manager.js` 现有纯 DTO 函数原样抽入 `lib/public-dto.js`**

导出下列稳定接口，并只保留白名单字段：

```js
module.exports = {
  publicAccount,
  publicCapture,
  publicDictionary,
  publicLiveStatus,
  safeCount,
};
```

`manager.js` 改为：

```js
const {
  publicAccount, publicCapture, publicDictionary, publicLiveStatus, safeCount,
} = require('./lib/public-dto');
```

- [ ] **Step 4: 运行新旧脱敏测试**

Run: `node --test test/public-dto.test.js test/public-account.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/public-dto.js manager.js test/public-dto.test.js test/public-account.test.js
git commit -m "refactor: centralize public DTO sanitization"
```

### Task 3：两阶段确认 token

**Files:**
- Create: `lib/operation-confirmations.js`
- Create: `test/operation-confirmations.test.js`

- [ ] **Step 1: 写失败测试覆盖签发、单次消费、过期和参数变化**

```js
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
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/operation-confirmations.test.js`
Expected: FAIL with missing module.

- [ ] **Step 3: 实现 `ConfirmationStore`**

使用 `crypto.randomBytes(24).toString('base64url')` 生成 token；使用递归排序键后的 JSON 作为 canonical params；记录 method、params hash、summary、expiresAt 和 consumed；任何校验失败都抛出 `CoreError('CONFIRMATION_REQUIRED', ...)`。

核心接口：

```js
class ConfirmationStore {
  constructor({ now = Date.now, ttlMs = 120000 } = {}) {}
  prepare(method, params, summary) {}
  consume(token, method, params) {}
  prune() {}
}
module.exports = { ConfirmationStore, canonicalJson };
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `node --test test/operation-confirmations.test.js`
Expected: 2 tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/operation-confirmations.js test/operation-confirmations.test.js
git commit -m "feat: add two-phase operation confirmations"
```

### Task 4：后台任务、进度和资源锁

**Files:**
- Create: `lib/task-runner.js`
- Create: `test/task-runner.test.js`

- [ ] **Step 1: 写失败测试**

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskRunner } = require('../lib/task-runner');

test('task runner emits progress and terminal result', async () => {
  const events = [];
  const runner = new TaskRunner({ emit: event => events.push(event) });
  const task = runner.start({ type: 'sync', resources: ['account:u1'], cancellable: true }, async ctx => {
    ctx.progress({ phase: 'syncing', completed: 1, total: 1, message: '完成' });
    return { changed: 2 };
  });
  const result = await runner.wait(task.task_id);
  assert.equal(result.state, 'succeeded');
  assert.deepEqual(result.result, { changed: 2 });
  assert.deepEqual(events.map(event => event.method), [
    'task.started', 'task.progress', 'task.succeeded',
  ]);
});

test('resource conflicts are rejected', async () => {
  let release;
  const runner = new TaskRunner();
  runner.start({ type: 'restore', resources: ['global-write'], cancellable: false },
    () => new Promise(resolve => { release = resolve; }));
  assert.throws(() => runner.start({ type: 'patch', resources: ['global-write'] }, async () => ({})),
    error => error.code === 'OPERATION_CONFLICT');
  release({});
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/task-runner.test.js`
Expected: FAIL with missing module.

- [ ] **Step 3: 实现 `TaskRunner`**

`start()` 同步返回 `{ task_id, state, cancellable }`，异步执行 handler；`TaskContext` 提供 `progress()`、`throwIfCancelled()` 和 `setCancellable()`；任务终态保留到进程退出；资源锁在 `finally` 中释放。

```js
class TaskRunner {
  constructor({ emit = () => {}, idFactory } = {}) {}
  start(spec, handler) {}
  cancel(taskId) {}
  listActive() {}
  wait(taskId) {}
}
module.exports = { TaskRunner };
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `node --test test/task-runner.test.js`
Expected: 2 tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/task-runner.js test/task-runner.test.js
git commit -m "feat: add core task runner and resource locks"
```

### Task 5：应用服务只读用例

**Files:**
- Create: `lib/application-service.js`
- Create: `test/application-service.test.js`

- [ ] **Step 1: 写依赖注入的失败测试**

```js
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
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/application-service.test.js`
Expected: FAIL with missing module.

- [ ] **Step 3: 实现只读 command handlers**

`createApplicationService({ core = require('./common'), taskRunner, confirmationStore })` 返回：

```js
{
  execute(method, params),
  capabilities(),
  taskRunner,
  confirmationStore,
}
```

首批 method：

```text
system.getOverview
connection.status
version.status
accounts.list
accounts.detectCurrent
dictionaries.getAccount
master.get
backup.status
diagnostics.run
patch.status
tasks.listActive
```

每个 handler 只调用注入的 `core`，输入缺失抛出 `CoreError('INVALID_REQUEST', ...)`，账号查找失败抛出 `ACCOUNT_NOT_FOUND`。

- [ ] **Step 4: 运行应用服务和现有状态测试**

Run: `node --test test/application-service.test.js test/public-account.test.js test/version-drift.test.js test/typeless-connection.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/application-service.js test/application-service.test.js
git commit -m "feat: add read-only application service commands"
```

### Task 6：账号、快照与连接写用例

**Files:**
- Modify: `lib/application-service.js`
- Modify: `test/application-service.test.js`

- [ ] **Step 1: 写失败测试覆盖 capture 句柄和 token 隔离**

新增测试：

```js
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
```

- [ ] **Step 2: 运行单测并确认失败**

Run: `node --test --test-name-pattern='capture handle' test/application-service.test.js`
Expected: FAIL because method is not registered.

- [ ] **Step 3: 实现命令**

加入 5 分钟内存 capture store，并实现：

```text
connection.establish
operations.prepare
accounts.captureCurrent
accounts.saveCapture
accounts.delete
snapshots.save
snapshots.switch
version.acknowledge
```

`accounts.delete` 必须消费确认 token；`snapshots.switch` 先恢复快照再启动 Typeless；所有返回值使用 public DTO。

- [ ] **Step 4: 运行相关测试**

Run: `node --test test/application-service.test.js test/token-expiry.test.js test/runtime-data.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/application-service.js test/application-service.test.js
git commit -m "feat: add account and snapshot application commands"
```

### Task 7：词库命令与可取消同步任务

**Files:**
- Modify: `lib/application-service.js`
- Modify: `test/application-service.test.js`

- [ ] **Step 1: 写失败测试覆盖批量词条规范化和同步进度**

```js
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
```

- [ ] **Step 2: 运行单测并确认失败**

Run: `node --test --test-name-pattern='addWords' test/application-service.test.js`
Expected: FAIL because method is not registered.

- [ ] **Step 3: 实现词库命令**

实现：

```text
dictionaries.addWord
dictionaries.addWords
dictionaries.deleteWord
dictionaries.syncAccount
dictionaries.syncAll
dictionaries.importMasterToAccount
dictionaries.copyBetweenAccounts
master.replace
tasks.cancel
```

`syncAccount`、`syncAll` 和大批量导入经 `TaskRunner` 执行；`syncAll` 在账号之间调用 `throwIfCancelled()`；覆盖类操作消费 confirmation token；删除词条保留现有“两次确认不存在”的验证规则。

- [ ] **Step 4: 运行词库和应用服务测试**

Run: `node --test test/application-service.test.js test/dict-diff.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/application-service.js test/application-service.test.js
git commit -m "feat: add dictionary commands and sync tasks"
```

### Task 8：备份检查、恢复、设备重置和补丁任务

**Files:**
- Modify: `lib/application-service.js`
- Modify: `lib/runtime-data.js`
- Modify: `test/application-service.test.js`
- Modify: `test/backup-bundle.test.js`

- [ ] **Step 1: 写失败测试覆盖备份检查后文件变化**

使用临时目录创建备份文件，`backup.inspect` 后修改内容，再调用 `backup.restore`，断言错误码为 `BACKUP_CHANGED`；另测 `device.reset` 和 `patch.apply` 未携带确认 token 时返回 `CONFIRMATION_REQUIRED`。

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/application-service.test.js test/backup-bundle.test.js`
Expected: new inspection tests FAIL.

- [ ] **Step 3: 实现备份文件 API 和高风险任务**

在 application service 实现：

```text
backup.create
backup.inspect
backup.export
backup.restore
device.status
device.reset
patch.apply
```

`backup.inspect` 保存 `{ realpath, stat.dev, stat.ino, size, sha256, expiresAt }`；`backup.restore` 重新核对后才读取 bundle，并依次消费 `inspection_id` 与 `confirmation_token`。恢复、重置和补丁使用 `global-write` 独占锁，提交阶段调用 `ctx.setCancellable(false)`。

- [ ] **Step 4: 运行备份、补丁和运行数据测试**

Run: `node --test test/backup-bundle.test.js test/patch-transaction.test.js test/runtime-data.test.js test/application-service.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add lib/application-service.js lib/runtime-data.js test/application-service.test.js test/backup-bundle.test.js
git commit -m "feat: add protected backup and advanced operations"
```

### Task 9：JSON Lines 协议

**Files:**
- Create: `sidecar/protocol.js`
- Create: `test/sidecar-protocol.test.js`

- [ ] **Step 1: 写失败测试覆盖半包、多包、超限和错误响应**

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { JsonLineDecoder, createRpcHandler } = require('../sidecar/protocol');

test('decoder handles split and multiple frames', () => {
  const frames = [];
  const decoder = new JsonLineDecoder({ onFrame: value => frames.push(value) });
  decoder.push(Buffer.from('{"id":"1"'));
  decoder.push(Buffer.from('}\n{"id":"2"}\n'));
  assert.deepEqual(frames, [{ id: '1' }, { id: '2' }]);
});

test('rpc handler returns normalized errors', async () => {
  const output = [];
  const handle = createRpcHandler({
    execute: async () => { throw new Error('secret internals'); },
    send: message => output.push(message),
  });
  await handle({ jsonrpc: '2.0', id: '1', method: 'x', params: {} });
  assert.equal(output[0].error.code, 'INTERNAL_ERROR');
  assert.equal(JSON.stringify(output[0]).includes('secret internals'), false);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/sidecar-protocol.test.js`
Expected: FAIL with missing module.

- [ ] **Step 3: 实现编解码和 RPC handler**

- 单帧上限 `8 * 1024 * 1024`；
- 空行忽略；
- 非对象、无 method、非 `2.0` 返回 `INVALID_REQUEST`；
- `send()` 只写单行 `JSON.stringify(message) + '\n'`；
- notification 无 `id` 时不发送结果响应；
- 所有异常经 `normalizeCoreError()`。

- [ ] **Step 4: 运行测试并确认通过**

Run: `node --test test/sidecar-protocol.test.js`
Expected: all tests PASS.

- [ ] **Step 5: 本地提交**

```bash
git add sidecar/protocol.js test/sidecar-protocol.test.js
git commit -m "feat: add versioned JSON lines protocol"
```

### Task 10：Sidecar 入口、握手和父进程生命周期

**Files:**
- Create: `sidecar/command-registry.js`
- Create: `sidecar/main.js`
- Create: `test/sidecar-integration.test.js`

- [ ] **Step 1: 写子进程集成失败测试**

测试用 `spawn(process.execPath, ['sidecar/main.js', '--transport=stdio', '--parent-pid=' + process.pid])`，发送 `core.hello`，断言：

```js
assert.equal(result.protocol_name, 'typeless-toolkit-core');
assert.equal(result.protocol_version, '1.0');
assert.equal(result.architecture, process.arch);
assert.equal(result.capabilities.includes('accounts.list'), true);
```

随后发送 `core.shutdown`，断言 2 秒内进程以 code 0 退出，stderr 不包含协议 JSON。

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/sidecar-integration.test.js`
Expected: FAIL because `sidecar/main.js` is missing.

- [ ] **Step 3: 实现 sidecar**

`command-registry.js` 包装 `applicationService.execute()`；`main.js`：

- 拒绝非 `--transport=stdio`；
- 清理 `NODE_OPTIONS`；
- stdout 只交给 protocol sender；
- 日志写 stderr；
- `core.hello` 返回协议、核心、Node、架构、capabilities、数据目录和恢复摘要；
- `core.shutdown` 响应后关闭 stdin 并退出；
- 每 2 秒检查 parent PID，父进程消失后退出；
- 将 TaskRunner 事件作为 JSON-RPC notification 发送。

- [ ] **Step 4: 运行 sidecar 和全量 Node 测试**

Run: `node --test test/*.test.js`
Expected: all业务断言 PASS；若当前沙箱仍禁止 `127.0.0.1`，只允许现有 manager security integration 因 `listen EPERM` 失败并记录环境限制。

- [ ] **Step 5: 本地提交**

```bash
git add sidecar/command-registry.js sidecar/main.js test/sidecar-integration.test.js
git commit -m "feat: add managed stdio sidecar process"
```

### Task 11：HTTP 管理器复用 application service

**Files:**
- Modify: `manager.js`
- Modify: `test/manager-security-integration.test.js`
- Create: `test/adapter-parity.test.js`

- [ ] **Step 1: 写适配器一致性失败测试**

对只读命令使用同一 fake core，比较 application service 结果与 HTTP adapter 序列化结果，至少覆盖账号、备份状态、连接状态、版本状态、主词库和补丁状态。

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test test/adapter-parity.test.js`
Expected: FAIL because manager still owns duplicated orchestration.

- [ ] **Step 3: 重构 `manager.js`**

- 保留 Host、Origin、session secret 和静态 HTML 安全逻辑；
- API route 只做 HTTP body/query 转换，再调用 `applicationService.execute(method, params)`；
- 文件下载 route 使用 service 返回的目标文件或受控 stream；
- 错误统一映射 `CoreError`；
- `module.exports` 保留 `startServer` 和测试依赖接口；
- 不改变现有 URL 和 Web UI 响应结构。

- [ ] **Step 4: 运行 Web 安全、适配器和全量 Node 测试**

Run: `node --test test/*.test.js`
Expected: 除已知沙箱监听限制外全部 PASS；在非沙箱环境应 100% PASS。

- [ ] **Step 5: 本地提交**

```bash
git add manager.js test/manager-security-integration.test.js test/adapter-parity.test.js
git commit -m "refactor: share application service across adapters"
```

### Task 12：Xcode 工程和原生 App 壳

**Files:**
- Create: `macOS/TypelessToolkit.xcodeproj/project.pbxproj`
- Create: `macOS/TypelessToolkit/Info.plist`
- Create: `macOS/TypelessToolkit/TypelessToolkit.entitlements`
- Create: `macOS/TypelessToolkit/App/TypelessToolkitApp.swift`
- Create: `macOS/TypelessToolkit/App/AppDelegate.swift`
- Create: `macOS/TypelessToolkit/App/AppModel.swift`
- Create: `macOS/TypelessToolkit/Features/Root/RootView.swift`
- Create: `macOS/TypelessToolkitTests/TestDoubles.swift`
- Create: `macOS/TypelessToolkitTests/AppModelTests.swift`

- [ ] **Step 1: 写失败的 AppModel 测试**

```swift
import XCTest
@testable import TypelessToolkit

@MainActor
final class MockCoreClient: CoreClientProtocol {
    var overview = SystemOverview.empty
    func getOverview() async throws -> SystemOverview { overview }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testDefaultSelectionIsOverview() {
        let model = AppModel(coreClient: MockCoreClient())
        XCTAssertEqual(model.selection, .overview)
        XCTAssertEqual(model.connectionState, .disconnected)
    }
}
```

- [ ] **Step 2: 创建工程并验证测试尚不能编译**

Run: `xcodebuild -project macOS/TypelessToolkit.xcodeproj -scheme TypelessToolkit -destination 'platform=macOS,arch=arm64' test`
Expected: FAIL because AppModel and root UI are not yet implemented；当前无完整 Xcode 时记录 `xcode-select` 前置条件，不伪造结果。

- [ ] **Step 3: 实现最小原生壳**

- Deployment Target `14.0`；
- `ARCHS = arm64`，`EXCLUDED_ARCHS = x86_64`；
- App Sandbox 关闭；
- `WindowGroup` 默认尺寸 `1100 × 720`、最小 `960 × 640`；
- `RootView` 使用 `NavigationSplitView`；
- `SidebarDestination` 包含 overview、accounts、masterDictionary、backupRestore、diagnostics、advancedTools、settings；
- AppModel 使用 `@Observable @MainActor` 管理 selection、connectionState 和 activeTasks。

- [ ] **Step 4: 运行工程测试或静态类型检查**

优先 Run: `xcodebuild ... test`，Expected: PASS。

没有完整 Xcode 时 Run: `swiftc -parse macOS/TypelessToolkit/App/*.swift macOS/TypelessToolkit/Features/Root/*.swift`，Expected: no syntax errors，并保留完整 Xcode 验证为发布阻塞项。

- [ ] **Step 5: 本地提交**

```bash
git add macOS
git commit -m "feat: add native SwiftUI macOS application shell"
```

### Task 13：Swift JSON Lines 与 Sidecar 生命周期

**Files:**
- Create: `macOS/TypelessToolkit/CoreIPC/ProtocolMessages.swift`
- Create: `macOS/TypelessToolkit/CoreIPC/JSONLineTransport.swift`
- Create: `macOS/TypelessToolkit/CoreIPC/SidecarProcess.swift`
- Create: `macOS/TypelessToolkit/CoreIPC/EventRouter.swift`
- Create: `macOS/TypelessToolkitTests/JSONLineTransportTests.swift`

- [ ] **Step 1: 写失败测试覆盖半包和多帧**

```swift
func testDecoderHandlesSplitAndMultipleFrames() throws {
    var decoder = JSONLineDecoder(maxFrameBytes: 8 * 1024 * 1024)
    XCTAssertEqual(try decoder.append(Data(#"{"id":"1""#.utf8)).count, 0)
    let frames = try decoder.append(Data("}\n{\"id\":\"2\"}\n".utf8))
    XCTAssertEqual(frames.count, 2)
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/JSONLineTransportTests`
Expected: FAIL with missing `JSONLineDecoder`.

- [ ] **Step 3: 实现 IPC 基础设施**

- `JSONRPCRequest/Response/Notification` 使用 `Codable`；
- decoder 按换行拆帧并限制 8 MiB；
- `SidecarProcess` 使用 `Process`、三个 Pipe、固定 bundle URL 和清理后的 environment；
- 启动 5 秒握手超时；
- 异常退出使 pending continuation 全部失败；
- 自动重启最多一次；
- 正常关闭等待 2 秒，随后 terminate；
- EventRouter 把 `task.*` notification 发布到 `AsyncStream<CoreEvent>`。

- [ ] **Step 4: 运行 IPC 测试**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/JSONLineTransportTests`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/CoreIPC macOS/TypelessToolkitTests/JSONLineTransportTests.swift
git commit -m "feat: add Swift sidecar transport and lifecycle"
```

### Task 14：Swift Domain 与类型化 CoreClient

**Files:**
- Create: `macOS/TypelessToolkit/Domain/Account.swift`
- Create: `macOS/TypelessToolkit/Domain/CoreError.swift`
- Create: `macOS/TypelessToolkit/Domain/CoreTask.swift`
- Create: `macOS/TypelessToolkit/Domain/DictionaryModels.swift`
- Create: `macOS/TypelessToolkit/Domain/SystemModels.swift`
- Create: `macOS/TypelessToolkit/CoreIPC/CoreClient.swift`
- Create: `macOS/TypelessToolkitTests/CoreClientTests.swift`

- [ ] **Step 1: 写 fake transport 的失败测试**

```swift
func testListAccountsDecodesSanitizedDTO() async throws {
    let transport = MockRPCTransport(result: #"{"accounts":[{"user_id":"u1","nickname":"N","has_snapshot":true}]}"#)
    let client = LiveCoreClient(transport: transport)
    let accounts = try await client.listAccounts()
    XCTAssertEqual(accounts.first?.id, "u1")
    XCTAssertEqual(transport.lastMethod, "accounts.list")
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/CoreClientTests`
Expected: FAIL with missing models/client.

- [ ] **Step 3: 实现模型和客户端接口**

定义 `CoreClientProtocol: Sendable`，提供所有规格命令的类型化 `async throws` 方法；`LiveCoreClient` 只负责 DTO 编解码，不包含页面状态。所有模型容忍未知 JSON 字段，日期用 ISO 8601 自定义 decoder；未知错误码映射 `.unknown(code:message:)`。

- [ ] **Step 4: 运行 CoreClient 测试**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/CoreClientTests`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/Domain macOS/TypelessToolkit/CoreIPC/CoreClient.swift macOS/TypelessToolkitTests/CoreClientTests.swift
git commit -m "feat: add typed Swift core client and domain models"
```

### Task 15：概览、状态设计系统和菜单栏

**Files:**
- Create: `macOS/TypelessToolkit/DesignSystem/StatusView.swift`
- Create: `macOS/TypelessToolkit/DesignSystem/EmptyStateView.swift`
- Create: `macOS/TypelessToolkit/Features/Overview/OverviewView.swift`
- Create: `macOS/TypelessToolkit/App/MenuBarContent.swift`
- Create: `macOS/TypelessToolkit/App/AppCommands.swift`
- Modify: `macOS/TypelessToolkit/App/AppModel.swift`
- Modify: `macOS/TypelessToolkit/App/TypelessToolkitApp.swift`

- [ ] **Step 1: 为 AppModel 概览刷新写失败测试**

测试 `refreshOverview()` 成功更新 account、connection、backup、version 和 active tasks；失败保留上次快照并设置 `isStale = true`。

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/AppModelTests`
Expected: new tests FAIL.

- [ ] **Step 3: 实现原生概览和菜单**

- 使用系统 `GroupBox`、`LabeledContent`、toolbar 和 SF Symbols；
- 状态同时显示图标、文字和颜色；
- 前台每 30 秒只刷新轻量状态，后台停止；
- 菜单栏提供打开窗口、刷新、建立管理连接、同步全部和退出；
- 高风险操作不放菜单栏；
- `CommandMenu` 提供标准键盘快捷键。

- [ ] **Step 4: 运行 AppModel 测试和 Swift 编译**

Run: `xcodebuild ... test`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/App macOS/TypelessToolkit/DesignSystem macOS/TypelessToolkit/Features/Overview macOS/TypelessToolkitTests/AppModelTests.swift
git commit -m "feat: add native overview and menu bar experience"
```

### Task 16：账号、添加流程、快照和切换

**Files:**
- Create: `macOS/TypelessToolkit/Features/Accounts/AccountsView.swift`
- Create: `macOS/TypelessToolkit/Features/Accounts/AccountDetailView.swift`
- Create: `macOS/TypelessToolkit/Features/Accounts/AddAccountSheet.swift`
- Create: `macOS/TypelessToolkit/DesignSystem/ConfirmationSheet.swift`
- Modify: `macOS/TypelessToolkit/App/AppModel.swift`
- Modify: `macOS/TypelessToolkitTests/AppModelTests.swift`

- [ ] **Step 1: 写添加账号和确认流程失败测试**

覆盖状态顺序：`idle → establishingConnection → capturing → reviewing → saving → completed`；测试 capture DTO 不含 token；删除和切号必须先调用 `prepareOperation()`。

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/AppModelTests`
Expected: new account workflow tests FAIL.

- [ ] **Step 3: 实现账号原生工作流**

- 账号列表使用 selection 和搜索；
- Detail 显示身份、套餐、配额、token 状态、快照时间和个人词库入口；
- 添加账号使用分步 Sheet；
- 切号、删除、覆盖使用 Node 返回影响摘要的 ConfirmationSheet；
- destructive 按钮使用系统 role；
- 所有写操作完成后仅失效受影响缓存。

- [ ] **Step 4: 运行测试和编译**

Run: `xcodebuild ... test`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/Features/Accounts macOS/TypelessToolkit/DesignSystem/ConfirmationSheet.swift macOS/TypelessToolkit/App/AppModel.swift macOS/TypelessToolkitTests/AppModelTests.swift
git commit -m "feat: add native account and snapshot workflows"
```

### Task 17：个人词库、主词库和同步任务 UI

**Files:**
- Create: `macOS/TypelessToolkit/Features/MasterDictionary/MasterDictionaryView.swift`
- Modify: `macOS/TypelessToolkit/Features/Accounts/AccountDetailView.swift`
- Modify: `macOS/TypelessToolkit/App/AppModel.swift`
- Modify: `macOS/TypelessToolkitTests/AppModelTests.swift`

- [ ] **Step 1: 写词库状态失败测试**

覆盖搜索、批量输入去空项、删除、主词库 replace diff 摘要、单账号同步进度、全部同步取消只在账号边界生效。

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/AppModelTests`
Expected: dictionary workflow tests FAIL.

- [ ] **Step 3: 实现词库界面**

- 使用 `Table` 或标准 `List`；
- 支持搜索、单条添加、批量粘贴、删除和去重；
- replace 前显示 added/removed/unchanged；
- 任务在页面 progress 区和全局任务区同步显示；
- 不对远端词库做乐观更新。

- [ ] **Step 4: 运行测试和编译**

Run: `xcodebuild ... test`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/Features/MasterDictionary macOS/TypelessToolkit/Features/Accounts/AccountDetailView.swift macOS/TypelessToolkit/App/AppModel.swift macOS/TypelessToolkitTests/AppModelTests.swift
git commit -m "feat: add dictionary management and sync UI"
```

### Task 18：备份恢复、诊断和高级工具 UI

**Files:**
- Create: `macOS/TypelessToolkit/Features/BackupRestore/BackupRestoreView.swift`
- Create: `macOS/TypelessToolkit/Features/Diagnostics/DiagnosticsView.swift`
- Create: `macOS/TypelessToolkit/Features/AdvancedTools/AdvancedToolsView.swift`
- Create: `macOS/TypelessToolkit/Services/FileDialogService.swift`
- Modify: `macOS/TypelessToolkit/App/AppModel.swift`
- Modify: `macOS/TypelessToolkitTests/AppModelTests.swift`

- [ ] **Step 1: 写失败测试覆盖导入检查与高风险确认**

测试恢复流程必须为 `selecting → inspecting → reviewing → preparingConfirmation → restoring → completed`；文件变化错误回到 reviewing 并要求重新检查；device reset 和 patch apply 不可绕过 confirmation。

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/AppModelTests`
Expected: backup/advanced workflow tests FAIL.

- [ ] **Step 3: 实现三个页面**

- 文件选择使用 `NSOpenPanel/NSSavePanel`；
- 备份导入先检查再确认，不在 Swift 解析秘密包；
- 诊断按事件显示等待、进行中、通过、警告、失败；
- 高级工具集中设备重置、补丁、版本确认和打开数据目录；
- 事务提交后禁用取消并显示原因；
- 可复制诊断摘要只使用脱敏字段。

- [ ] **Step 4: 运行测试和编译**

Run: `xcodebuild ... test`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/Features/BackupRestore macOS/TypelessToolkit/Features/Diagnostics macOS/TypelessToolkit/Features/AdvancedTools macOS/TypelessToolkit/Services/FileDialogService.swift macOS/TypelessToolkit/App/AppModel.swift macOS/TypelessToolkitTests/AppModelTests.swift
git commit -m "feat: add backup diagnostics and advanced tools UI"
```

### Task 19：设置、最近活动、日志和辅助功能

**Files:**
- Create: `macOS/TypelessToolkit/Features/Settings/SettingsView.swift`
- Create: `macOS/TypelessToolkit/Services/AppPreferences.swift`
- Create: `macOS/TypelessToolkit/Services/RecentActivityStore.swift`
- Modify: `macOS/TypelessToolkit/App/AppModel.swift`
- Modify: `macOS/TypelessToolkitTests/AppModelTests.swift`

- [ ] **Step 1: 写失败测试**

覆盖菜单栏开关、关闭窗口行为、前台刷新、通知、活动最多 100 条、清空活动、debug 日志在下次启动恢复 info。

- [ ] **Step 2: 运行测试并确认失败**

Run: `xcodebuild ... test -only-testing:TypelessToolkitTests/AppModelTests`
Expected: preference/activity tests FAIL.

- [ ] **Step 3: 实现设置和可访问性**

- 非秘密偏好写 `UserDefaults`；
- 最近活动为脱敏 Codable 数组；
- 所有状态提供 icon + text；
- 为关键控件添加 accessibility label/value/help；
- 尊重 Reduce Motion 和 Reduce Transparency；
- 标准列表键盘导航和搜索焦点可用；
- debug 日志偏好只在当前进程有效。

- [ ] **Step 4: 运行测试和编译**

Run: `xcodebuild ... test`
Expected: PASS.

- [ ] **Step 5: 本地提交**

```bash
git add macOS/TypelessToolkit/Features/Settings macOS/TypelessToolkit/Services macOS/TypelessToolkit/App/AppModel.swift macOS/TypelessToolkitTests/AppModelTests.swift
git commit -m "feat: add settings activity history and accessibility"
```

### Task 20：准备 Sidecar 和固定 Node runtime

**Files:**
- Create: `scripts/prepare-sidecar.sh`
- Create: `scripts/prepare-node-runtime.sh`
- Create: `release/node-runtime.env`
- Create: `release/node-sha256.txt`
- Create: `release/THIRD_PARTY_NOTICES.md`
- Modify: `.gitignore`

- [ ] **Step 1: 写 shell smoke 检查并确认当前缺失**

Run: `test -x scripts/prepare-sidecar.sh && test -x scripts/prepare-node-runtime.sh`
Expected: FAIL.

- [ ] **Step 2: 实现 `prepare-sidecar.sh`**

脚本使用 `set -euo pipefail`，创建构建目录，只复制 sidecar 入口和允许的 `lib/*.js`、许可证；拒绝复制 `accounts.json`、`config.json`、profiles、备份、`.env` 和 Git 元数据；执行 `node --check` 检查全部 JS。

- [ ] **Step 3: 实现固定 Node runtime 准备**

`release/node-runtime.env` 固定 `NODE_VERSION`、Darwin arm64 URL 和 archive 名；`node-sha256.txt` 记录官方 archive SHA-256；脚本先支持 `NODE_RUNTIME_PATH`，否则 `curl --fail --location` 下载，校验 `shasum -a 256 -c` 后只提取 `bin/node`。目标必须经 `file` 验证为 arm64/Mach-O。

- [ ] **Step 4: 运行准备脚本验证**

Run: `scripts/prepare-sidecar.sh /tmp/typeless-sidecar && NODE_RUNTIME_PATH="$(command -v node)" scripts/prepare-node-runtime.sh /tmp/typeless-node`
Expected: sidecar tree 不含秘密文件，两个目标均存在且可执行，`/tmp/typeless-node --version` 成功。

- [ ] **Step 5: 本地提交**

```bash
git add scripts/prepare-sidecar.sh scripts/prepare-node-runtime.sh release .gitignore
git commit -m "build: prepare bundled sidecar and Node runtime"
```

### Task 21：Debug、Release、临时签名和 DMG

**Files:**
- Create: `scripts/build-debug.sh`
- Create: `scripts/build-release.sh`
- Create: `scripts/package-dmg.sh`
- Create: `scripts/verify-release.sh`
- Create: `release/README-FIRST.txt`

- [ ] **Step 1: 确认构建入口当前缺失**

Run: `test -x scripts/build-release.sh && test -x scripts/package-dmg.sh`
Expected: FAIL.

- [ ] **Step 2: 实现 Debug 与 Release 构建脚本**

两个脚本均检查 `uname -m = arm64` 和完整 Xcode；调用准备脚本；使用：

```bash
xcodebuild -project macOS/TypelessToolkit.xcodeproj \
  -scheme TypelessToolkit -configuration Release \
  -derivedDataPath build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO build
```

随后复制到 `dist/Typeless Toolkit.app`，先 `codesign --force --sign -` Node helper，再从内到外签 App，并执行 `codesign --verify --deep --strict`。

- [ ] **Step 3: 实现 DMG 和首次放行说明**

`package-dmg.sh` 创建 staging，放 App 和 `/Applications` symlink，使用 `hdiutil create -format UDZO` 输出 `dist/Typeless-Toolkit-<version>-arm64.dmg`，并生成 `.sha256`。`README-FIRST.txt` 说明 Finder 右键打开、系统设置“仍要打开”和可选 `xattr -dr` 命令，明确“未公证”。

- [ ] **Step 4: 实现发布验证器**

验证器检查：

- 主程序和 Node helper 为 arm64；
- `codesign --verify --deep --strict` 通过；
- `core.hello` smoke test 通过；
- bundle 不含 token、accounts、profiles、`.env`；
- DMG 可挂载、包含 App 和 Applications 链接；
- `spctl` 因未公证失败只记录预期说明，不掩盖其他失败。

- [ ] **Step 5: 本地提交**

```bash
git add scripts release/README-FIRST.txt
git commit -m "build: add ad hoc signed app and DMG pipeline"
```

### Task 22：文档、全量验证与本地发布候选

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Create: `docs/native-macos-build.md`

- [ ] **Step 1: 更新用户和构建文档**

README 将原生 App 标记为推荐入口，保留 Web/CLI legacy 说明；构建文档写明完整 Xcode、Apple Silicon、无开发者账号、Node runtime 准备、本地构建、临时签名、DMG、首次放行和故障诊断。

- [ ] **Step 2: 运行 Node 全量测试**

Run: `node --test test/*.test.js`
Expected: 非沙箱环境 100% PASS；当前沙箱如仅有 `listen EPERM`，记录该环境限制并在允许监听的本机终端补跑。

- [ ] **Step 3: 运行 Swift 全量测试和 Release 构建**

Run: `xcodebuild -project macOS/TypelessToolkit.xcodeproj -scheme TypelessToolkit -destination 'platform=macOS,arch=arm64' test`
Expected: PASS.

Run: `scripts/build-release.sh`
Expected: `dist/Typeless Toolkit.app` exists and signature verification passes.

- [ ] **Step 4: 打包并验证 DMG**

Run: `scripts/package-dmg.sh && scripts/verify-release.sh`
Expected: versioned arm64 `.dmg` and `.sha256` exist; all verifier checks pass except documented expected Gatekeeper notarization rejection.

- [ ] **Step 5: Apple Silicon 真机手工验收**

依次验证：首次放行、无系统 Node 启动、概览、管理连接、账号添加、快照切换、词库增删与同步、备份导出与恢复、中断恢复、补丁失败回滚、App 退出无 sidecar、浅深色、高对比度、Reduce Motion、VoiceOver 基本导航。

- [ ] **Step 6: 本地提交发布候选，不推送**

```bash
git add README.md CHANGELOG.md docs/native-macos-build.md
git commit -m "docs: document native macOS build and installation"
git status --short
git log --oneline --decorate -20
```

Expected: 功能文件均已提交；只允许用户已有的明确未跟踪/未提交文件保留；不执行 `git push`。

---

## 自审映射

- 规格第 5–10 节（应用服务、协议、任务、确认、DTO）：Task 1–11。
- 规格第 11–13 节（信息架构、视觉、状态一致性）：Task 12–19。
- 规格第 14–15 节（安全、日志、诊断）：Task 3、8、10、18、19、20。
- 规格第 16 节（构建与分发）：Task 20–22。
- 规格第 17 节（测试）：每个任务的 TDD 步骤及 Task 22 全量验收。
- 规格第 18 节（迁移与兼容）：Task 5、8、11、22。
- 规格第 20 节全部验收标准：Task 22 的自动化和真机验收清单。

计划不包含未决或延期占位项。所有远程 Git 操作均被明确排除。
