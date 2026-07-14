# 修复 Typeless 权限归属错误实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Typeless 的启动方式从“直接执行 App 内部二进制”改为“通过 macOS LaunchServices 启动完整 App Bundle 并传入 CDP 参数”，使辅助功能和麦克风权限归属于 Typeless，而不是 Typeless Toolkit 或 Terminal。

**Architecture:** Node Sidecar 继续负责 Typeless 的关闭、启动和 CDP 就绪等待，但启动动作统一经过 `/usr/bin/open` 所代表的 LaunchServices 路径；所有调用方继续复用 `launchTypeless()`，不各自实现启动命令。先通过纯函数和依赖注入测试锁定启动命令，再用真实 Release App 在干净的 TCC 状态下验证权限弹窗、授权持久化和 CDP 连接。

**Tech Stack:** Node.js CommonJS、`node:test`、macOS LaunchServices、`/usr/bin/open`、Electron Typeless、SwiftUI 外壳、XCTest、Xcode、TCC 系统设置。

---

## 1. 问题结论与修复边界

### 1.1 已确认现象

- Typeless Onboarding 中“允许 Typeless 将文本粘贴到任何文本框中”实际对应 macOS **辅助功能**权限，不是普通剪贴板权限。
- 当前桌面端启动链路为：

  ```text
  Typeless Toolkit.app
    └─ Node Sidecar
        └─ /Applications/Typeless.app/Contents/MacOS/Typeless
  ```

- 当前代码直接执行 Typeless 内部 Mach-O：

  ```javascript
  spawn(TYPELESS_BIN, [`--remote-debugging-port=${CDP_PORT}`], {
    detached: true,
    stdio: 'ignore',
  }).unref();
  ```

- 实际系统弹窗显示“Typeless Toolkit 想使用辅助功能”，而 Typeless 页面检查的是 Typeless 当前进程的信任状态，因此用户给 Toolkit 授权后，Onboarding 仍可能持续判断未授权。
- 从 Terminal 启动时权限归到 Terminal，进一步说明问题与启动责任进程归属有关。

### 1.2 本轮包含

- 将所有 Typeless 启动统一切换到 LaunchServices。
- 保留 `--remote-debugging-port=9222` 参数。
- 为启动命令、参数安全、调用次数和错误行为增加 Node 自动化测试。
- 验证连接建立、账号切换、设备重置、补丁完成/回滚后的重新启动均走同一启动器。
- 完成 Node、Swift、严格并发、Release、DMG 和真实权限流程验收。
- 增加面向用户的权限恢复说明和验收清单。

### 1.3 本轮不包含

- 不修改 Typeless Onboarding 状态文件。
- 不伪造或跳过 Typeless 的权限检测结果。
- 不直接修改 macOS TCC 数据库。
- 不在应用内自动执行 `tccutil reset`。
- 不让 Typeless Toolkit 自己申请辅助功能或麦克风权限。
- 不修改账号抓取、Token 存储、快照结构和词库业务。
- 不在本轮解决 Typeless 被补丁后发生的 vendor 签名丢失问题；该问题只纳入风险提示和兼容性验收。
- 不把 ad-hoc 签名升级为 Developer ID 签名；这是独立发布治理事项。

### 1.4 决策红线

- 启动参数必须使用参数数组传递，禁止拼接 shell 字符串。
- 启动目标必须是配置解析得到的 `Typeless.app`，禁止仅按显示名称启动未知同名应用。
- `launchTypeless()` 必须是唯一启动入口，业务服务不得新增第二套启动命令。
- CDP WebSocket 仍只允许本机地址和配置端口。
- 自动化测试通过不能替代真实 TCC 权限验收。
- 如果修复后弹窗仍显示 Typeless Toolkit，停止发布并执行第 8 节的升级方案，不得通过修改 Onboarding 文件掩盖问题。

## 2. 文件结构与职责

| 文件 | 操作 | 职责 |
| --- | --- | --- |
| `lib/common.js` | 修改 | 构造 LaunchServices 启动规格、启动 Typeless、保留 CDP 参数和统一错误 |
| `test/typeless-connection.test.js` | 修改 | 验证启动规格、参数数组、启动调用及 `ensureApp()` 回归 |
| `test/application-service.test.js` | 修改 | 验证账号切换等业务仍只调用统一的 `launchTypeless()` |
| `test/release-pipeline.test.js` | 修改 | 验证发布包包含启动修复，且没有恢复为直接执行内部二进制 |
| `docs/native-macos-build.md` | 修改 | 记录 LaunchServices 启动约束、权限清理和人工验收方式 |
| `docs/typeless-permission-acceptance.md` | 新建 | 非技术用户可执行的权限验收清单与结果记录模板 |

Swift 代码预计不修改。只有在第 4 节真实验证证明 `/usr/bin/open` 仍导致权限归到 Toolkit 时，才进入第 8 节 Swift `NSWorkspace` 升级方案。

## 3. 验收阶梯

| 层级 | 验收对象 | 目的 | 负责人 |
| --- | --- | --- | --- |
| L1 方案验收 | 根因、范围、红线、启动命令 | 确认没有通过绕过权限来“修复” | 主实现者 + 用户 |
| L2 模块验收 | 启动规格与 `launchTypeless()` | 确认不再直接执行内部二进制 | 主实现者 + 代码审查者 |
| L3 集成验收 | `ensureApp()`、账号切换、设备重置、补丁流程 | 确认所有重启入口行为一致 | 主实现者 |
| L4 系统验收 | TCC 弹窗、授权状态、CDP、重启持久化 | 确认真实用户问题消失 | 主实现者 + 用户 |
| L5 发布回归 | Release App、DMG、签名结构、安装后行为 | 确认可交付产物与开发构建一致 | 主实现者 + 用户 |

## 4. Task 1：建立真实基线并验证 LaunchServices 假设

**Files:**
- Create: `docs/typeless-permission-acceptance.md`

- [ ] **Step 1：记录基线环境**

  执行只读命令：

  ```bash
  sw_vers
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    /Applications/Typeless.app/Contents/Info.plist
  codesign -dvvv /Applications/Typeless.app 2>&1 | \
    grep -E 'Identifier=|TeamIdentifier=|Signature=|CDHash='
  codesign -dvvv 'dist/Typeless Toolkit.app' 2>&1 | \
    grep -E 'Identifier=|TeamIdentifier=|Signature=|CDHash='
  ```

  预期至少记录：

  ```text
  Typeless bundle id: now.typeless.desktop
  Toolkit bundle id: com.typelesstoolkit.mac
  Typeless 当前签名类型和 TeamIdentifier
  Toolkit 当前签名类型和 TeamIdentifier
  macOS 版本
  ```

- [ ] **Step 2：记录修复前复现步骤**

  在 `docs/typeless-permission-acceptance.md` 写入：

  ```markdown
  ## 修复前基线
  1. 完全退出 Typeless。
  2. 从 Typeless Toolkit 执行“连接”。
  3. 在 Typeless Onboarding 点击粘贴权限的“允许”。
  4. 记录系统弹窗显示的应用名称。
  5. 在系统设置中允许后返回 Typeless。

  实际结果：系统弹窗显示 Typeless Toolkit；Typeless 页面没有进入已授权状态。
  ```

- [ ] **Step 3：用户手动清理旧测试授权**

  在“系统设置 → 隐私与安全性”中手动检查并移除测试用旧记录：

  ```text
  辅助功能：Typeless Toolkit、Typeless、Terminal
  麦克风：Typeless Toolkit、Typeless、Terminal
  ```

  此步骤必须由用户确认执行。不得由应用、测试或发布脚本自动修改 TCC。

- [ ] **Step 4：执行最小 LaunchServices 实验**

  完全退出 Typeless 后，在 Terminal 执行：

  ```bash
  /usr/bin/open -n '/Applications/Typeless.app' \
    --args '--remote-debugging-port=9222'
  ```

  然后在 Onboarding 点击辅助功能“允许”。

  通过标准：

  ```text
  系统弹窗显示 Typeless，而不是 Terminal 或 Typeless Toolkit；
  在系统设置允许后，Onboarding 的辅助功能项变为已完成；
  麦克风权限弹窗显示 Typeless；
  两项完成后可以点击“继续”。
  ```

  阻断标准：如果弹窗仍显示 Terminal，或授权后 Onboarding 仍不刷新，则不进入 Task 2，直接执行第 8 节 Swift LaunchServices 升级方案。

- [ ] **Step 5：验证 CDP 参数生效**

  ```bash
  curl --fail --silent --show-error \
    http://127.0.0.1:9222/json/version
  curl --fail --silent --show-error \
    http://127.0.0.1:9222/json/list
  ```

  通过标准：两个请求均返回 JSON，且 `/json/list` 中只检查本机 Typeless 页面，不要求把 Onboarding 页面当成正式账号捕获页面。

- [ ] **Step 6：提交基线文档**

  ```bash
  git add docs/typeless-permission-acceptance.md
  git commit -m 'docs: record Typeless permission launch baseline'
  ```

## 5. Task 2：用 TDD 锁定 LaunchServices 启动规格

**Files:**
- Modify: `test/typeless-connection.test.js`
- Modify: `lib/common.js`

- [ ] **Step 1：写启动规格失败测试**

  在 `test/typeless-connection.test.js` 导入：

  ```javascript
  const {
    CDP_PORT,
    buildTypelessLaunchSpec,
    ensureApp,
    launchTypeless,
    selectTypelessCdpTarget,
    typelessConnectionStatus,
  } = require('../lib/common');
  ```

  增加测试：

  ```javascript
  test('Typeless 通过 LaunchServices 启动完整 app bundle', () => {
    assert.deepStrictEqual(buildTypelessLaunchSpec({
      appPath: '/Applications/Typeless.app',
      port: 9333,
    }), {
      executable: '/usr/bin/open',
      args: [
        '-n',
        '/Applications/Typeless.app',
        '--args',
        '--remote-debugging-port=9333',
      ],
    });
  });

  test('LaunchServices 启动参数保持数组边界且不经过 shell', () => {
    const spec = buildTypelessLaunchSpec({
      appPath: '/Applications/Typeless Preview.app',
      port: 9222,
    });
    assert.equal(spec.executable, '/usr/bin/open');
    assert.equal(spec.args[1], '/Applications/Typeless Preview.app');
    assert.equal(spec.args.includes('shell'), false);
    assert.equal(spec.args.length, 4);
  });

  test('缺少 Typeless app 路径时拒绝启动', () => {
    assert.throws(
      () => buildTypelessLaunchSpec({ appPath: '', port: 9222 }),
      /Typeless\.app 路径未配置/,
    );
  });
  ```

- [ ] **Step 2：运行测试确认红灯**

  ```bash
  node --test test/typeless-connection.test.js
  ```

  预期失败：

  ```text
  buildTypelessLaunchSpec is not a function
  ```

- [ ] **Step 3：实现纯启动规格函数**

  在 `lib/common.js` 的 kill/launch 区域增加：

  ```javascript
  function buildTypelessLaunchSpec(options = {}) {
    const appPath = options.appPath === undefined ? MAC_APP_PATH : options.appPath;
    const port = options.port === undefined ? CDP_PORT : options.port;
    if (typeof appPath !== 'string' || !appPath.trim()) {
      throw new Error('Typeless.app 路径未配置,无法启动');
    }
    return {
      executable: '/usr/bin/open',
      args: [
        '-n',
        appPath,
        '--args',
        `--remote-debugging-port=${port}`,
      ],
    };
  }
  ```

  将该函数加入 `module.exports`。不要删除 `TYPELESS_BIN`，因为诊断和兼容性检查仍使用它。

- [ ] **Step 4：运行测试确认绿灯**

  ```bash
  node --test test/typeless-connection.test.js
  ```

  预期：该文件全部测试通过。

- [ ] **Step 5：提交启动规格**

  ```bash
  git add lib/common.js test/typeless-connection.test.js
  git commit -m 'test: define LaunchServices Typeless launch contract'
  ```

## 6. Task 3：替换直接二进制启动并验证调用行为

**Files:**
- Modify: `test/typeless-connection.test.js`
- Modify: `lib/common.js`

- [ ] **Step 1：写 `launchTypeless()` 失败测试**

  ```javascript
  test('launchTypeless 调用 open 后立即解除子进程引用', () => {
    const calls = [];
    const child = { unref: () => calls.push({ type: 'unref' }) };
    const spawnFn = (executable, args, options) => {
      calls.push({ type: 'spawn', executable, args, options });
      return child;
    };

    launchTypeless({
      appPath: '/Applications/Typeless.app',
      port: 9222,
      spawnFn,
    });

    assert.deepStrictEqual(calls, [
      {
        type: 'spawn',
        executable: '/usr/bin/open',
        args: [
          '-n',
          '/Applications/Typeless.app',
          '--args',
          '--remote-debugging-port=9222',
        ],
        options: { detached: true, stdio: 'ignore' },
      },
      { type: 'unref' },
    ]);
  });
  ```

- [ ] **Step 2：运行测试确认旧实现失败**

  ```bash
  node --test test/typeless-connection.test.js
  ```

  预期失败原因：旧实现不接受 `spawnFn`，并直接调用 `TYPELESS_BIN`。

- [ ] **Step 3：最小修改 `launchTypeless()`**

  ```javascript
  function launchTypeless(options = {}) {
    const spawnFn = options.spawnFn || spawn;
    const spec = buildTypelessLaunchSpec(options);
    spawnFn(spec.executable, spec.args, {
      detached: true,
      stdio: 'ignore',
    }).unref();
  }
  ```

  删除以下生产路径：

  ```javascript
  spawn(TYPELESS_BIN, [`--remote-debugging-port=${CDP_PORT}`], ...)
  ```

  保留 `killTypeless()`、`ensureApp()` 和 CDP 轮询逻辑不变。

- [ ] **Step 4：运行连接测试**

  ```bash
  node --test test/typeless-connection.test.js
  ```

  预期：全部通过，包含：

  ```text
  已连接时不重启
  未连接时只关闭一次、启动一次
  超时时不误报已连接
  启动命令只调用 /usr/bin/open
  ```

- [ ] **Step 5：静态检查不存在直接启动回归**

  ```bash
  rg -n "spawn\(TYPELESS_BIN|execFile.*TYPELESS_BIN" lib test
  ```

  预期：无输出。诊断用途的 `TYPELESS_BIN` 常量可以存在，但不能再作为启动命令执行。

- [ ] **Step 6：提交实现**

  ```bash
  git add lib/common.js test/typeless-connection.test.js
  git commit -m 'fix: launch Typeless through macOS LaunchServices'
  ```

## 7. Task 4：业务集成回归和发布包防回退测试

**Files:**
- Modify: `test/application-service.test.js`
- Modify: `test/release-pipeline.test.js`

- [ ] **Step 1：扩展业务调用回归测试**

  保留 `snapshots.switch` 现有断言：

  ```javascript
  assert.deepEqual(calls, ['kill', 'restore:u1', 'launch']);
  ```

  为 `connection.establish` 增加：

  ```javascript
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
  ```

  目的：业务层只调用 `ensureApp()`/`launchTypeless()` 抽象，不自行拼接 `open` 或内部二进制路径。

- [ ] **Step 2：增加发布源码防回退测试**

  在 `test/release-pipeline.test.js` 增加：

  ```javascript
  test('发布 Sidecar 使用 LaunchServices 启动 Typeless', () => {
    const common = fs.readFileSync(path.join(ROOT, 'lib', 'common.js'), 'utf8');
    assert.match(common, /executable:\s*['"]\/usr\/bin\/open['"]/);
    assert.doesNotMatch(common, /spawn\(TYPELESS_BIN/);
  });
  ```

- [ ] **Step 3：运行相关测试**

  ```bash
  node --test \
    test/typeless-connection.test.js \
    test/application-service.test.js \
    test/release-pipeline.test.js
  ```

  预期：全部通过。

- [ ] **Step 4：运行 Node 全量测试**

  ```bash
  node --test
  ```

  预期：零失败、零取消。

- [ ] **Step 5：提交集成回归测试**

  ```bash
  git add test/application-service.test.js test/release-pipeline.test.js
  git commit -m 'test: prevent direct Typeless binary launch regression'
  ```

## 8. 仅在 `/usr/bin/open` 验证失败时启用的 Swift 升级方案

该节是明确的失败分支，不与 Node LaunchServices 方案同时实现。

### 8.1 进入条件

满足任一条件即停止 Node 方案发布：

- `/usr/bin/open` 启动后辅助功能弹窗仍显示 Terminal 或 Typeless Toolkit；
- 系统设置已经允许 Typeless，但 `AXIsProcessTrustedWithOptions` 仍持续返回未授权；
- `/usr/bin/open` 无法稳定把 `--remote-debugging-port=9222` 传给 Typeless。

### 8.2 升级设计

新增 Swift 原生启动服务：

```swift
import AppKit

struct TypelessLaunchService {
    func launch(appURL: URL, cdpPort: Int) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = ["--remote-debugging-port=\(cdpPort)"]
        _ = try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
    }
}
```

需要另行设计 Sidecar → Swift 的启动请求边界，禁止让 Node 和 Swift 同时拥有启动权。建议新增受限的双向事件或将“建立连接”编排迁移到 `AppModel`，而不是让 Sidecar 调用任意 Swift 命令。

### 8.3 升级方案新增文件

| 文件 | 操作 |
| --- | --- |
| `macOS/TypelessToolkit/Services/TypelessLaunchService.swift` | 新建 |
| `macOS/TypelessToolkitTests/TypelessLaunchServiceTests.swift` | 新建 |
| `macOS/TypelessToolkit/App/AppModel.swift` | 修改 |
| `macOS/TypelessToolkit/CoreIPC/CoreClient.swift` | 修改 |
| `lib/application-service.js` | 修改 |

升级方案必须单独补充设计规格并经用户确认后实施，本计划不允许直接跨越此决策门槛。

## 9. Task 5：文档、权限恢复说明和风险提示

**Files:**
- Modify: `docs/native-macos-build.md`
- Modify: `docs/typeless-permission-acceptance.md`

- [ ] **Step 1：记录启动约束**

  在 `docs/native-macos-build.md` 增加：

  ```markdown
  ## Typeless 启动与权限归属

  Typeless Toolkit 必须通过 macOS LaunchServices 启动完整的
  `Typeless.app`，不得直接执行 `Contents/MacOS/Typeless`。直接执行内部
  二进制会让辅助功能或麦克风权限归到启动者，导致 Typeless Onboarding
  无法确认自身权限。

  CDP 参数通过参数数组传递：

  `/usr/bin/open -n <Typeless.app> --args --remote-debugging-port=9222`
  ```

- [ ] **Step 2：记录旧授权清理方法**

  文档只提供用户手动操作：

  ```text
  系统设置 → 隐私与安全性 → 辅助功能
  系统设置 → 隐私与安全性 → 麦克风
  ```

  用户删除旧的 Typeless Toolkit/Terminal 测试记录后重新测试。文档不得建议删除整个 TCC 数据库，也不得在脚本中自动重置其他应用权限。

- [ ] **Step 3：记录签名风险**

  ```markdown
  如果“解除升级弹窗”功能重新签名了 Typeless.app，Typeless 的代码身份会
  发生变化，macOS 可能要求重新授予辅助功能和麦克风权限。权限验收必须
  分别记录原厂签名状态和补丁后 ad-hoc 签名状态，不能把两者视为同一个
  TCC 身份。
  ```

- [ ] **Step 4：文档检查**

  ```bash
  rg -n "Contents/MacOS/Typeless|LaunchServices|辅助功能|麦克风|TCC" \
    docs/native-macos-build.md \
    docs/typeless-permission-acceptance.md
  ```

  预期：直接内部二进制只作为禁止示例出现；不包含自动绕过或静默修改 TCC 的指令。

- [ ] **Step 5：提交文档**

  ```bash
  git add docs/native-macos-build.md docs/typeless-permission-acceptance.md
  git commit -m 'docs: add Typeless permission acceptance workflow'
  ```

## 10. Task 6：完整代码 Review 流程

### 10.1 Review 输入

Review 前记录：

```bash
BASE_SHA="$(git merge-base Mac-UI HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
git diff --stat "$BASE_SHA..$HEAD_SHA"
git diff --check "$BASE_SHA..$HEAD_SHA"
```

审查者必须读取：

```text
docs/superpowers/plans/2026-07-13-fix-typeless-permission-attribution.md
lib/common.js
test/typeless-connection.test.js
test/application-service.test.js
test/release-pipeline.test.js
docs/typeless-permission-acceptance.md
```

### 10.2 第一轮：规格符合性 Review

- [ ] 只修改了本计划列出的文件。
- [ ] `launchTypeless()` 是唯一启动入口。
- [ ] 不再执行 `TYPELESS_BIN`。
- [ ] 启动的是配置确定的完整 `Typeless.app`。
- [ ] `--remote-debugging-port` 仍被正确传入。
- [ ] 没有修改 Onboarding 状态或权限检测结果。
- [ ] 没有增加 Toolkit 的辅助功能/麦克风申请。
- [ ] 没有自动运行 `tccutil reset` 或直接访问 TCC 数据库。
- [ ] 账号、Token、快照和词库逻辑未发生无关变化。

发现 `Critical` 或 `Important` 问题后必须修复并重新执行相关测试；未解决前不得进入下一轮。

### 10.3 第二轮：安全与可靠性 Review

- [ ] `spawn` 使用固定可执行文件 `/usr/bin/open`。
- [ ] App 路径和端口使用参数数组，不经过 shell。
- [ ] 含空格的 App 路径不会被拆分。
- [ ] 不允许用户输入任意启动可执行文件。
- [ ] 已连接时不会无理由重启 Typeless。
- [ ] 启动失败或 CDP 超时不会误报连接成功。
- [ ] `killTypeless()` 仍只终止 Typeless，不扩大进程匹配范围。
- [ ] Release Sidecar 与仓库源码使用同一实现。
- [ ] 日志不包含账号 Token、Cookie 或 Authorization header。

### 10.4 第三轮：测试质量 Review

- [ ] 测试先于实现出现过红灯记录。
- [ ] 测试验证行为，不只匹配实现文本。
- [ ] 至少有一个测试覆盖 App 路径包含空格。
- [ ] 至少有一个测试覆盖自定义 CDP 端口。
- [ ] 至少有一个测试覆盖缺失 App 路径。
- [ ] 至少有一个测试证明不再直接执行 `TYPELESS_BIN`。
- [ ] `ensureApp()` 的已连接、重启成功、重启超时三条路径均通过。
- [ ] 真实 TCC 验收与自动化测试分开记录。

### 10.5 主集成 Review Gate

- [ ] `git diff --check` 通过。
- [ ] Node 全量测试通过。
- [ ] Swift 全量测试通过。
- [ ] 严格并发构建通过。
- [ ] Release App 构建成功。
- [ ] DMG 构建和校验成功。
- [ ] 真实权限主线通过。
- [ ] 拒绝权限和重试分支通过。
- [ ] 已写用户可直接照做的中文验收步骤。
- [ ] 用户原有 `.gitignore`、`findings.md`、`progress.md`、`task_plan.md` 和 `typeless-toolkit-mac-handoff.md` 未被纳入功能提交。

## 11. Task 7：自动化回归、Release 和 DMG 验证

**Files:**
- No source changes expected

- [ ] **Step 1：Node 全量测试**

  ```bash
  node --test
  ```

  通过标准：零失败、零取消、没有真实启动或关闭 Typeless。

- [ ] **Step 2：Swift 全量测试**

  ```bash
  xcodebuild \
    -project macOS/TypelessToolkit.xcodeproj \
    -scheme TypelessToolkit \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath /tmp/TypelessToolkitPermissionTests \
    test
  ```

  通过标准：所有 XCTest 通过。

- [ ] **Step 3：严格并发构建**

  ```bash
  xcodebuild \
    -project macOS/TypelessToolkit.xcodeproj \
    -scheme TypelessToolkit \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath /tmp/TypelessToolkitPermissionStrict \
    build \
    SWIFT_STRICT_CONCURRENCY=complete \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
  ```

  通过标准：`BUILD SUCCEEDED`，没有 warning。

- [ ] **Step 4：构建 Release**

  ```bash
  scripts/build-release.sh
  ```

  通过标准：

  ```text
  dist/Typeless Toolkit.app 存在；
  内置 Node Sidecar 存在；
  codesign --verify --deep --strict 通过。
  ```

- [ ] **Step 5：验证发布包实际包含修复**

  ```bash
  rg -n "/usr/bin/open|buildTypelessLaunchSpec" \
    'dist/Typeless Toolkit.app/Contents/Resources/Sidecar/lib/common.js'
  rg -n "spawn\(TYPELESS_BIN" \
    'dist/Typeless Toolkit.app/Contents/Resources/Sidecar/lib/common.js'
  ```

  通过标准：第一条有结果，第二条无结果。

- [ ] **Step 6：构建和验证 DMG**

  ```bash
  scripts/package-dmg.sh
  scripts/verify-release.sh
  ```

  通过标准：DMG 可只读挂载，包含 App 与 Applications 链接，SHA-256 校验通过，Sidecar 握手通过。

## 12. Task 8：真实功能验收流程

### 12.1 验收前准备

- [ ] 使用本轮生成的 Release App，不使用旧 `/tmp` Debug App。
- [ ] 将 Release App 放到固定路径后再测试，避免移动 App 导致系统权限记录混淆。
- [ ] 完全退出 Typeless 和 Typeless Toolkit。
- [ ] 记录 Typeless 是否为原厂签名；如果已经被补丁重签，单独标记。
- [ ] 用户手动清理旧的 Toolkit/Terminal 测试授权，不自动清理其他应用权限。

### 12.2 主线 A：首次连接和辅助功能权限

1. 打开最新 `Typeless Toolkit.app`。
2. 点击需要建立 Typeless 管理连接的入口。
3. 等待 Typeless Onboarding 出现。
4. 点击“允许 Typeless 将文本粘贴到任何文本框中”的“允许”。
5. 检查系统弹窗应用名称。
6. 打开系统设置并允许该应用。
7. 返回 Typeless Onboarding。

通过标准：

- [ ] 系统弹窗显示 **Typeless**，不显示 Typeless Toolkit 或 Terminal。
- [ ] 系统设置的辅助功能列表出现 Typeless。
- [ ] 授权后 Onboarding 对应项目在合理时间内变为勾选状态。
- [ ] 不需要重复点击“允许”。
- [ ] Typeless Toolkit 不需要辅助功能权限。

### 12.3 主线 B：麦克风权限

1. 在同一个 Onboarding 流程继续申请麦克风权限。
2. 允许 Typeless 使用麦克风。
3. 返回 Onboarding。

通过标准：

- [ ] 麦克风弹窗显示 Typeless。
- [ ] 系统设置的麦克风列表出现 Typeless。
- [ ] Onboarding 麦克风项目变为勾选状态。
- [ ] 两项完成后“继续”按钮可用。

### 12.4 主线 C：授权持久化

1. 完成 Onboarding。
2. 退出 Typeless。
3. 退出 Typeless Toolkit。
4. 重新打开 Toolkit 并再次建立连接。

通过标准：

- [ ] Typeless 不再重复申请已授予的辅助功能权限。
- [ ] Typeless 不再重复申请已授予的麦克风权限。
- [ ] Typeless 可以正常进入主界面。
- [ ] Toolkit 可以连接 `127.0.0.1:9222`。

### 12.5 分支 D：用户拒绝权限

1. 清理本轮测试权限后重新开始。
2. 在辅助功能弹窗选择拒绝。
3. 返回 Onboarding 后再次点击允许。
4. 从系统设置手动打开权限。

通过标准：

- [ ] 拒绝后应用不崩溃、不伪造成功状态。
- [ ] 用户仍能再次打开系统设置。
- [ ] 后续手动允许后 Onboarding 能恢复。
- [ ] Toolkit 不会替 Typeless静默修改权限。

### 12.6 分支 E：Typeless 已带 CDP 运行

1. 使用 LaunchServices 和 `9222` 先启动 Typeless。
2. 再打开 Toolkit 建立连接。

通过标准：

- [ ] Toolkit 检测到管理端口后不重启 Typeless。
- [ ] 不出现新的权限弹窗。
- [ ] 原有 Typeless 窗口状态不丢失。

### 12.7 分支 F：账号切换后的重新启动

1. 在 Toolkit 中选择一个有本地快照的账号。
2. 确认切换。
3. 等待 Typeless 重新启动。

通过标准：

- [ ] Typeless 使用 LaunchServices 重启。
- [ ] 已授予权限不会错误转移给 Toolkit。
- [ ] CDP 端口恢复可用。
- [ ] 快照切换结果与修改前一致。

### 12.8 分支 G：补丁后的签名风险验收

仅在用户主动测试“解除升级弹窗”时执行：

1. 记录补丁前 Typeless 的 `TeamIdentifier` 和 `CDHash`。
2. 执行补丁。
3. 记录补丁后的签名信息。
4. 再次检查辅助功能和麦克风状态。

通过标准：

- [ ] 文档明确说明签名变化可能触发重新授权。
- [ ] 如果系统要求重新授权，弹窗仍应显示 Typeless，不得显示 Toolkit。
- [ ] 补丁失败回滚后 Typeless 仍能通过 LaunchServices 启动。

## 13. 最终 Definition of Done

只有同时满足以下条件才可以声明完成：

- [ ] 修复前问题有可复现记录和截图。
- [ ] `/usr/bin/open` 最小实验证明权限归属正确；否则已停止并进入 Swift 升级设计。
- [ ] 生产代码不再直接执行 `Contents/MacOS/Typeless`。
- [ ] 所有 Typeless 重启路径复用统一启动器。
- [ ] 自动化测试覆盖带空格路径、自定义端口、缺失路径、已连接、重启成功和超时。
- [ ] Node 全量测试通过。
- [ ] Swift 全量测试通过。
- [ ] 严格并发构建通过。
- [ ] Release App、DMG 和发布验证通过。
- [ ] 辅助功能弹窗显示 Typeless。
- [ ] 麦克风弹窗显示 Typeless。
- [ ] 授权后 Onboarding 可以继续。
- [ ] 重启后授权保持有效。
- [ ] 拒绝权限后恢复路径可用。
- [ ] 没有自动操作 TCC、没有绕过权限检查、没有泄露敏感信息。
- [ ] 独立代码审查无未解决的 Critical/Important 问题。
- [ ] 用户按照中文验收清单确认结果符合预期。

## 14. 用户最终验收回报模板

```text
【Typeless 权限归属修复验收】

测试版本：
macOS 版本：
Typeless 版本：
Typeless 是否打过补丁：是 / 否

1. 辅助功能弹窗显示：
   [ ] Typeless
   [ ] Typeless Toolkit
   [ ] Terminal
   [ ] 没有弹窗

2. 允许辅助功能后：
   [ ] Onboarding 立即显示完成
   [ ] 仍停留在“允许”

3. 麦克风弹窗显示：
   [ ] Typeless
   [ ] Typeless Toolkit
   [ ] Terminal
   [ ] 没有弹窗

4. 两项授权后：
   [ ] 可以点击继续并进入 Typeless
   [ ] 仍无法继续

5. 退出并重新打开后：
   [ ] 权限保持有效，不再重复申请
   [ ] 再次要求授权

6. Toolkit 管理连接：
   [ ] 可以连接 127.0.0.1:9222
   [ ] 无法连接

附加现象或截图：
```

## 15. 提交、回滚和分支纪律

- 实施必须在 `codex/` 前缀的新探索分支进行，不直接修改 `Mac-UI`。
- 每个 Task 形成独立本地提交，便于按步骤回滚。
- 暂存必须精确列出文件，禁止 `git add .`。
- 用户原有文件不得纳入提交：

  ```text
  .gitignore
  findings.md
  progress.md
  task_plan.md
  typeless-toolkit-mac-handoff.md
  ```

- 未经用户明确要求，不执行 `git push`，不创建 PR。
- 若真实 TCC 验收失败，使用 `git revert` 回滚实现提交，保留基线文档和失败证据；禁止用修改 Onboarding 文件作为应急补丁。
