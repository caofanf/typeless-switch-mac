# Typeless Toolkit 原生 macOS 应用设计规格

- 日期：2026-07-12
- 状态：待用户书面复核
- 目标平台：Apple Silicon（`arm64`）
- 最低系统：macOS 14 Sonoma
- 分发方式：开源自行构建、临时签名、未公证 `.dmg`

## 1. 背景与目标

Typeless Toolkit 目前是一个以 Node.js 为核心的 macOS 本机管理与自动化工具。它通过本地网页管理器提供多账号、登录态快照、词库同步、备份恢复、设备重置、Typeless 补丁、版本漂移检测和诊断等能力。

现有方案需要用户启动终端脚本、保持本地 HTTP 服务运行，再在浏览器中打开管理页。虽然业务能力完整，但日常入口、进程生命周期、系统交互和视觉体验都不像原生 Mac 软件。

本项目将它改造成一个可直接安装和启动的原生 macOS App，达到以下目标：

1. 日常使用不依赖浏览器和终端。
2. 使用 SwiftUI 构建符合 Apple 平台习惯的主窗口、菜单、确认流程和状态反馈。
3. 完整覆盖现有 Web 管理器的业务能力，不以 `WKWebView` 套壳冒充原生化。
4. 保留已经过测试的 Node 核心、事务恢复和数据兼容逻辑，避免首版重写高风险能力。
5. App 内不监听 `localhost`，通过私有进程通信降低攻击面。
6. 提供 Xcode 工程、可复现构建脚本、临时签名 `.app` 和未公证 `.dmg`。

## 2. 项目现状与必须保留的能力

### 2.1 当前项目定位

项目本质上是“Typeless 本机管理与自动化控制器”，不是普通网站。核心能力包括：

- 保存多个 Typeless 账号并显示实时状态；
- 通过 Chrome DevTools Protocol（CDP）识别当前登录账号和抓取 token；
- 保存、恢复账号登录态快照并切换账号；
- 管理主词库和各账号个人词库；
- 执行单词增删、批量导入、账号间复制和全量同步；
- 备份、导出、导入和事务化恢复运行数据；
- 重置 Typeless 设备身份和本地状态；
- 修改 `app.asar`、更新完整性哈希、执行 ad-hoc 重签名并在失败时回滚；
- 检测 Typeless 版本漂移；
- 检查路径、权限、管理连接和补丁状态。

### 2.2 兼容约束

原生 App 必须继续使用现有稳定数据目录：

```text
~/Library/Application Support/Typeless Toolkit/
```

必须兼容现有账号文件、profiles、主词库、运行备份、补丁事务备份、版本状态和配置。首次由新版本加载时，仍由现有 `runtime-data.js` 执行旧目录迁移、权限收紧和中断恢复。

不得在没有显式用户操作的情况下：

- 删除或覆盖现有数据；
- 自动重置设备；
- 自动修改 Typeless.app；
- 自动切换账号；
- 自动确认 Typeless 版本漂移。

## 3. 范围

### 3.1 首个完整版本包含

- 原生主窗口和标准 macOS 菜单；
- 概览、账号、主词库、备份与恢复、诊断、高级工具、设置；
- 菜单栏状态项，可由用户关闭；
- 完整替代现有 Web 管理器的功能；
- 后台任务进度、成功结果、错误恢复建议和最近活动；
- Xcode 工程与本地调试配置；
- Apple Silicon Node runtime 的固定版本准备脚本；
- 临时签名 `.app` 构建脚本；
- 未公证 `.dmg` 打包脚本；
- 首次打开的 Gatekeeper 放行说明。

### 3.2 明确不包含

- Intel Mac（`x86_64`）支持；
- Mac App Store 分发；
- Developer ID 签名和 Apple 公证；
- 自动更新框架；
- iCloud 同步；
- 全量 Swift 重写 Node 核心；
- iOS/iPadOS 版本；
- 修改 Typeless 云端 API 或绕过服务端鉴权。

## 4. 方案选择

### 4.1 采用方案

采用 **SwiftUI 原生宿主 + App 内置 Node Sidecar**：

```text
┌──────────────────────────────────────────────┐
│ Typeless Toolkit.app                         │
│                                              │
│  SwiftUI 界面与 macOS 生命周期               │
│       │                                      │
│       │ JSON Lines / stdin + stdout          │
│       ▼                                      │
│  内置 arm64 Node runtime + Core Service      │
│       │                                      │
│       ├─ Typeless API / CDP                  │
│       ├─ Keychain / 文件系统                 │
│       ├─ 备份与事务恢复                      │
│       └─ app.asar 补丁与 codesign            │
└──────────────────────────────────────────────┘
```

### 4.2 选择理由

- 现有高风险逻辑已经具备测试和恢复机制，复用它比首版全量 Swift 重写可靠；
- SwiftUI 能提供真正原生的窗口、列表、菜单、Sheet、文件选择和辅助功能；
- 标准输入输出通信不暴露 TCP 端口，不需要 Host、Origin、CORS 或浏览器 session secret；
- Node sidecar 只属于当前 App 进程，App 退出后不会留下后台 HTTP 服务；
- 版本化协议使 Swift UI 与 Node 内部实现解耦，未来可以逐模块迁移到 Swift。

### 4.3 未采用方案

- **SwiftUI + localhost HTTP**：迁移快，但继续保留端口冲突、本地请求鉴权和浏览器时代的安全复杂度，不作为终态。
- **全量 Swift 重写**：技术栈统一，但会同时重写 CDP、备份恢复、补丁事务和同步算法，首版回归风险过高。
- **WKWebView 套壳**：不能解决原生信息架构、交互、可访问性和后台生命周期问题，不接受。

## 5. 总体架构

### 5.1 分层

```text
SwiftUI Presentation
        │
Application Store / Feature Models
        │
CoreClient（typed async API）
        │
SidecarProcess + JSON-RPC Transport
        │
Node Command Service
        │
Existing Core Modules
        │
Typeless / macOS / Runtime Data
```

各层职责如下：

1. **SwiftUI Presentation**：只负责视图、导航、用户输入、Sheet、菜单和无障碍语义。
2. **Feature Models**：维护各页面状态，调用 `CoreClient`，不解析原始 JSON。
3. **CoreClient**：为 Swift 提供类型化 `async/await` 方法，将协议 DTO 转换为 Swift model。
4. **SidecarProcess**：负责进程启动、握手、请求关联、事件分发、stderr 日志、退出和重启。
5. **Node Command Service**：提供 UI 无关的命令注册表、输入校验、任务调度、DTO 脱敏和统一错误。
6. **Existing Core Modules**：继续承载 `common.js`、`runtime-data.js`、`patch-transaction.js` 的业务能力。

### 5.2 现有代码重构边界

`manager.js` 中的业务编排必须抽取到独立应用服务，HTTP 和 stdio 只作为适配器：

```text
lib/
  common.js
  runtime-data.js
  patch-transaction.js
  application-service.js       # UI 无关用例
  public-dto.js                # 脱敏和稳定 DTO
  errors.js                    # 稳定错误码
sidecar/
  main.js                      # stdio 入口
  protocol.js                  # JSON Lines 编解码
  command-registry.js          # method → handler
  task-runner.js               # 长任务与进度事件
manager.js                     # 兼容 HTTP 适配器
```

最终 Swift App 不依赖 `manager.js`，但现有网页入口可以继续调用同一个 `application-service.js`，用于过渡和兼容。业务规则不得在 HTTP 与 stdio 两套适配器中复制。

## 6. macOS App 模块设计

建议 Xcode 工程使用一个 App target 和一个 test target，Swift 源码按职责组织：

```text
macOS/
  TypelessToolkit.xcodeproj
  TypelessToolkit/
    App/
      TypelessToolkitApp.swift
      AppDelegate.swift
      AppCommands.swift
      MenuBarContent.swift
    DesignSystem/
      AppIconography.swift
      StatusStyle.swift
      ConfirmationStyle.swift
    Domain/
      Account.swift
      DictionaryEntry.swift
      RuntimeBackup.swift
      DiagnosticReport.swift
      CoreError.swift
      CoreTask.swift
    CoreIPC/
      CoreClient.swift
      SidecarProcess.swift
      JSONLineTransport.swift
      ProtocolMessages.swift
      EventRouter.swift
    Features/
      Overview/
      Accounts/
      MasterDictionary/
      BackupRestore/
      Diagnostics/
      AdvancedTools/
      Settings/
    Services/
      FileDialogService.swift
      NotificationService.swift
      RecentActivityStore.swift
      AppPreferences.swift
    Resources/
      Sidecar/
  TypelessToolkitTests/
```

原则：

- Feature 之间不直接持有彼此的可变状态；
- 共享业务状态由根级 `AppModel` 组合；
- 所有 Node 调用只经过 `CoreClient`；
- View 不直接读写文件、启动进程或执行命令；
- DTO 使用 `Codable`，协议字段保持 `snake_case`，Swift 属性用 `camelCase` 映射。

## 7. Sidecar 进程与生命周期

### 7.1 Bundle 布局

发布产物采用以下布局：

```text
Typeless Toolkit.app/
  Contents/
    MacOS/Typeless Toolkit
    Helpers/node
    Resources/Sidecar/main.js
    Resources/Sidecar/lib/...
    Resources/AppIcon.icns
```

- `Contents/Helpers/node` 是固定版本的官方 Darwin `arm64` Node 可执行文件；
- Sidecar JavaScript 只使用 Node 内置能力和项目源码，不在用户机器执行 `npm install`；
- Node 版本在仓库配置中固定，下载时校验 SHA-256；
- 构建脚本允许通过 `NODE_RUNTIME_PATH` 使用预先下载的兼容 runtime，以支持离线构建；
- 发布包和仓库必须附带 Node.js 对应许可证及第三方声明，版本升级时同步更新。

### 7.2 启动

App 首次需要核心数据时启动 sidecar，启动参数只包含：

```text
node Resources/Sidecar/main.js --transport=stdio --parent-pid=<pid>
```

规则：

1. App 进程全程最多存在一个 sidecar；
2. 工作目录显式设置为只读的 Sidecar 资源目录；
3. `stdout` 只能输出协议消息，日志只能写入 `stderr`；
4. 启动后 5 秒内必须完成 `core.hello` 握手；
5. 协议或架构不兼容时停止 sidecar，界面显示明确错误，不尝试降级到 HTTP；
6. sidecar 意外退出时，未完成请求统一失败为 `CORE_PROCESS_EXITED`；
7. App 可以自动重启一次；再次退出后必须由用户点击“重新连接”；
8. App 正常退出时先发送 `core.shutdown`，2 秒未退出则 `terminate`，再等待 1 秒后才强制终止。

Sidecar 同时监听父进程存活状态；检测到父进程消失后主动退出，避免孤儿进程。

## 8. 进程通信协议

### 8.1 帧格式

协议名：`typeless-toolkit-core`

协议版本：`1.0`

传输方式：UTF-8 JSON Lines。每一行必须是一个完整 JSON 对象，单行最大 8 MiB；备份包不直接塞入协议。

请求：

```json
{"jsonrpc":"2.0","id":"A12","method":"accounts.list","params":{}}
```

成功响应：

```json
{"jsonrpc":"2.0","id":"A12","result":{"accounts":[]}}
```

失败响应：

```json
{
  "jsonrpc":"2.0",
  "id":"A12",
  "error":{
    "code":"MANAGEMENT_CONNECTION_REQUIRED",
    "message":"Typeless 管理连接未开启",
    "details":{"recoverable":true,"suggested_action":"connection.establish"}
  }
}
```

事件通知：

```json
{
  "jsonrpc":"2.0",
  "method":"task.progress",
  "params":{"task_id":"T42","phase":"syncing","completed":2,"total":5,"message":"正在同步账号 2/5"}
}
```

### 8.2 握手

Swift 启动 sidecar 后首先调用：

```text
core.hello
```

返回：

- `protocol_name`
- `protocol_version`
- `core_version`
- `node_version`
- `architecture`
- `capabilities`
- `runtime_data_path`
- `recovery_summary`

Swift 只接受协议主版本 `1`、架构 `arm64`。次版本新增字段必须向后兼容，客户端忽略未知字段。

### 8.3 请求关联与并发

- `id` 由 Swift 生成，在一个进程会话中唯一；
- 读操作允许并发；
- 同一资源的写操作由 Node 服务串行化；
- 设备重置、备份恢复、补丁操作使用全局独占锁；
- 锁冲突返回 `OPERATION_CONFLICT` 和当前任务摘要；
- 请求默认超时 30 秒，长任务的“启动请求”超时 10 秒，任务本身由事件驱动，不使用无限请求超时。

### 8.4 长任务

以下能力采用任务模型：

- 全部账号同步；
- 单账号同步；
- 诊断；
- 备份恢复；
- 设备重置；
- Typeless 补丁；
- 大批量词库导入或复制。

启动命令立即返回：

```json
{"task_id":"T42","state":"running","cancellable":true}
```

任务状态：`queued`、`running`、`succeeded`、`failed`、`cancelled`。

任务事件：

- `task.started`
- `task.progress`
- `task.succeeded`
- `task.failed`
- `task.cancelled`

取消只在安全边界生效：同步可在账号或批次之间取消；诊断可在检查项之间取消。备份恢复、设备重置和补丁事务一旦进入提交阶段不可取消，界面必须禁用取消按钮并解释原因。

App 断开后重新握手，可通过 `tasks.listActive` 查询仍在运行的任务；sidecar 重启后不恢复普通任务，但现有运行数据恢复和补丁事务恢复机制必须先运行并在 `recovery_summary` 中报告。

### 8.5 文件传输

备份导入导出不通过大 JSON 帧传输：

- 导出：Swift 先显示 `NSSavePanel`，再把用户选择的绝对目标路径传给 `backup.export`；Node 使用临时文件、`fsync` 和原子 rename 写入。
- 导入：Swift 通过 `NSOpenPanel` 选择 `.json`，把绝对源路径传给 `backup.inspect`；Node 只读取和验证，不修改数据，并返回脱敏摘要及 5 分钟有效的一次性 `inspection_id`。用户确认摘要后，`backup.restore` 必须同时携带该 `inspection_id` 和高风险操作的 `confirmation_token`。
- `backup.restore` 执行前重新读取文件并核对检查阶段记录的文件标识、大小和 SHA-256；任一项变化都返回 `BACKUP_CHANGED`，不得恢复。
- 所有路径必须标准化并拒绝符号链接跳转；导出不得覆盖目录或非普通文件；恢复前始终创建 before-image。

## 9. 命令接口

### 9.1 核心与连接

| Method | 作用 |
|---|---|
| `core.hello` | 握手、能力和恢复摘要 |
| `core.shutdown` | 正常关闭 sidecar |
| `system.getOverview` | 聚合概览所需的轻量状态 |
| `connection.status` | 检查 Typeless 与 CDP 状态 |
| `connection.establish` | 必要时以调试端口重启 Typeless |
| `version.status` | 获取 Typeless 版本漂移状态 |
| `version.acknowledge` | 用户确认当前 Typeless 版本 |

### 9.2 账号与快照

| Method | 作用 |
|---|---|
| `accounts.list` | 获取脱敏账号及实时状态 |
| `accounts.detectCurrent` | 识别当前登录账号 |
| `accounts.captureCurrent` | 暂存当前账号抓取结果 |
| `accounts.saveCapture` | 使用一次性 capture ID 保存账号 |
| `accounts.delete` | 删除账号记录；是否删除快照由参数明确指定 |
| `snapshots.save` | 保存账号登录态快照 |
| `snapshots.switch` | 恢复快照并切换账号 |

`capture_id` 是 sidecar 内存中的一次性句柄，默认 5 分钟过期。Swift 永远不会收到原始 token。

### 9.3 词库

| Method | 作用 |
|---|---|
| `dictionaries.getAccount` | 获取账号个人词库和容量状态 |
| `dictionaries.addWord` | 添加单词 |
| `dictionaries.addWords` | 批量添加单词 |
| `dictionaries.deleteWord` | 按词条删除并验证结果 |
| `dictionaries.syncAccount` | 主词库与单账号全量对齐 |
| `dictionaries.syncAll` | 依次同步所有账号 |
| `dictionaries.importMasterToAccount` | 将主词库导入账号 |
| `dictionaries.copyBetweenAccounts` | 从一个账号复制到另一个账号 |
| `master.get` | 获取主词库 |
| `master.replace` | 原子替换主词库 |

### 9.4 备份、诊断与高级工具

| Method | 作用 |
|---|---|
| `backup.status` | 当前运行数据和最近备份状态 |
| `backup.create` | 创建手动运行数据备份 |
| `backup.inspect` | 只读验证待导入备份并返回摘要 |
| `backup.export` | 导出可迁移备份包到指定文件 |
| `backup.restore` | 事务化恢复已检查的备份 |
| `diagnostics.run` | 执行本机诊断并逐项报告 |
| `device.status` | 返回设备重置前置状态 |
| `device.reset` | 执行设备身份重置 |
| `patch.status` | 检查补丁、完整性和可恢复状态 |
| `patch.apply` | 执行或回退 Typeless 补丁 |
| `tasks.cancel` | 请求取消可取消任务 |
| `tasks.listActive` | 查询当前任务 |

### 9.5 高风险操作确认

以下操作必须经过“两阶段确认”，不能仅依赖 Swift 按钮：

- 删除账号；
- 恢复备份；
- 重置设备；
- 应用或回退 Typeless 补丁；
- 用主词库覆盖账号；
- 用一个账号词库覆盖另一个账号；
- 替换整个主词库。

流程：

1. Swift 调用 `operations.prepare`，传入操作类型和目标参数；
2. Node 做前置检查并返回脱敏影响摘要、`confirmation_token` 和 2 分钟过期时间；
3. Swift 使用原生 Sheet 展示 Node 返回的真实影响摘要；
4. 用户确认后，Swift 调用实际命令并携带 token；
5. Node 校验 token 未过期、未使用且参数摘要没有变化，然后才执行；
6. token 无效时返回 `CONFIRMATION_REQUIRED`，必须重新准备，不可静默重试。

## 10. DTO、隐私与错误模型

### 10.1 DTO 原则

任何发给 Swift 的账号对象不得包含：

- token；
- Cookie；
- Local Storage 原文；
- Keychain 数据；
- 完整 profile 内容；
- 备份包中的秘密字段。

允许字段包括：账号 ID、昵称、邮箱的显示形式、套餐、配额、token 是否有效及过期时间、快照是否存在及时间、同步摘要和错误码。

### 10.2 稳定错误结构

错误包含：

- `code`：稳定机器码；
- `message`：可直接显示的中文信息；
- `details.recoverable`：是否可恢复；
- `details.suggested_action`：建议调用或界面动作；
- `details.context`：经过脱敏的诊断信息。

首版稳定错误码至少包括：

- `INVALID_REQUEST`
- `UNSUPPORTED_PROTOCOL`
- `CORE_PROCESS_EXITED`
- `MANAGEMENT_CONNECTION_REQUIRED`
- `CURRENT_ACCOUNT_UNAVAILABLE`
- `CAPTURE_EXPIRED`
- `ACCOUNT_NOT_FOUND`
- `TOKEN_EXPIRED`
- `SNAPSHOT_NOT_FOUND`
- `BACKUP_INVALID`
- `BACKUP_CHANGED`
- `RESTORE_RECOVERY_REQUIRED`
- `TYPELESS_NOT_INSTALLED`
- `TYPELESS_VERSION_DRIFTED`
- `PATCH_FAILED_ROLLED_BACK`
- `PATCH_RECOVERY_REQUIRED`
- `CONFIRMATION_REQUIRED`
- `OPERATION_CONFLICT`
- `PERMISSION_DENIED`
- `NETWORK_UNAVAILABLE`
- `INTERNAL_ERROR`

Swift 对未知错误码使用通用错误界面，并显示可复制的脱敏诊断 ID，不显示 token 或原始协议帧。

## 11. 原生信息架构

### 11.1 主窗口

主窗口使用 `NavigationSplitView`：

- **侧边栏**：概览、账号、主词库、备份与恢复、诊断、高级工具、设置；
- **内容栏**：当前模块列表、摘要或设置项；
- **详情栏**：账号详情、词库详情、诊断项详情等；
- 窄窗口自动退化为双栏或单栏导航。

默认窗口最小尺寸为约 `960 × 640 pt`，恢复用户上次窗口位置和侧边栏选择。

### 11.2 页面职责

#### 概览

显示当前账号、Typeless 管理连接、账号与词库摘要、最近备份、版本漂移、补丁状态、活动任务和最近活动。只提供高频动作，不堆叠所有高级按钮。

#### 账号

- 账号列表使用标准 selection；
- 详情展示身份、套餐、配额、token 状态、快照状态和个人词库；
- 工具栏提供添加账号、刷新、保存快照、切换账号和同步；
- 添加账号采用分步 Sheet：建立连接 → 抓取 → 核对脱敏信息 → 保存；
- 切换、删除和覆盖操作使用确认 Sheet。

#### 主词库

使用可搜索表格或列表，支持单条添加、批量粘贴、删除、去重和保存。替换整个词库前展示新增、删除和未变化数量。

#### 备份与恢复

显示数据目录、最近自动/手动备份、可恢复性和占用空间。导入分为“选择并检查”和“确认恢复”两步，不允许选中文件后立即覆盖数据。

#### 诊断

按检查项流式显示状态：等待、进行中、通过、警告、失败。每个问题提供解释、建议动作和复制诊断摘要，不把原始秘密写入剪贴板。

#### 高级工具

放置低频且高风险能力：设备重置、Typeless 补丁、版本确认、打开数据目录。默认不在概览突出展示。

#### 设置

包括：

- 是否显示菜单栏图标；
- 关闭主窗口后退出或留在菜单栏；
- 启动时是否自动刷新轻量状态；
- 通知偏好；
- 最近活动保留数量；
- 诊断日志级别；
- App、核心、Node 和协议版本信息。

设置使用 `UserDefaults`；账号、token 和业务数据不进入 `UserDefaults`。

### 11.3 菜单栏

菜单栏只提供：

- 当前账号和连接状态；
- 打开主窗口；
- 刷新状态；
- 建立管理连接；
- 同步全部账号；
- 进行中任务摘要；
- 退出。

高风险操作不能直接在菜单栏无确认执行。

## 12. 视觉与交互规范

- 使用系统字体、SF Symbols、语义色和系统 Accent Color；
- 自动适配浅色与深色，不维护独立固定主题；
- 使用系统背景、`Material` 和标准 separator，避免仿网页卡片泛滥；
- 状态不能只靠颜色表达，必须同时使用图标和文字；
- 普通破坏性操作使用 `destructive` 按钮角色；
- 设备重置、补丁和恢复使用包含影响摘要的应用内 Sheet，不使用简单 `alert`；
- 长任务在对应页面和全局任务区同时可见；
- 成功采用短暂反馈和活动记录，失败保持可见直到用户处理；
- 尊重 Increase Contrast、Reduce Transparency、Reduce Motion 和 VoiceOver；
- 关键控件提供键盘操作，列表支持标准方向键和搜索焦点；
- 不复制现有 Web 版暖纸色主题，保留信息层级和友好语气即可。

## 13. 状态刷新与数据一致性

- `system.getOverview` 在窗口首次显示、App 恢复前台和用户手动刷新时调用；
- 前台可见时每 30 秒刷新轻量连接状态；后台不轮询；
- 账号实时状态和远端词库只在页面进入或手动刷新时请求；
- 写操作成功后由事件携带受影响资源，`AppModel` 只失效对应缓存；
- 同一资源只允许一个有效刷新任务，后发请求取消或替换前一个 UI 请求；
- Swift 不做乐观修改高风险业务数据，必须以 Node 成功结果为准；
- sidecar 断开后保留最后一次成功快照但标记为“可能已过期”，禁止高风险写操作。

## 14. 安全与权限

### 14.1 App Sandbox

首版关闭 App Sandbox。原因是核心能力需要：

- 访问稳定运行数据目录；
- 访问 Typeless 用户数据和应用包；
- 调用 `/usr/bin/security`、`codesign`、`xattr` 等系统工具；
- 启停 Typeless；
- 使用 CDP 与 Typeless 本机调试端口通信。

关闭 Sandbox 不代表放宽内部边界：App 仍只访问规格列出的目录和工具，不请求无关权限。

### 14.2 进程与命令安全

- Swift 使用 `Process.executableURL` 和参数数组启动 sidecar，不拼 shell 字符串；
- Node 继续使用 `execFile`/`spawn` 参数数组，不引入 `sh -c`；
- sidecar 不接受任意命令名、任意系统命令或任意脚本路径；
- 文件路径必须经过 canonicalization、类型和边界检查；
- 运行数据目录保持 `0700`，敏感文件保持 `0600`；
- 所有日志默认脱敏 token、Cookie、Authorization、capture 内容和备份秘密；
- 不监听 TCP/UDP/Unix Socket；
- sidecar 只继承必要环境变量，清理 `NODE_OPTIONS` 等可注入 Node 行为的变量；
- App 资源目录只读，运行数据不得写入 `.app` bundle。

### 14.3 补丁安全

补丁能力继续遵守现有事务流程：

1. 检查 Typeless 路径与版本；
2. 建立 before-image 和 manifest；
3. 修改副本；
4. 更新完整性哈希；
5. 原子提交；
6. 对 Typeless.app 执行 ad-hoc 重签名；
7. 校验；
8. 失败则精确回滚并再次校验；
9. 下次启动优先恢复中断事务。

Typeless 版本漂移时，界面必须警告用户重新诊断；补丁不得静默自动重做。

## 15. 日志、活动与诊断

### 15.1 日志

日志目录：

```text
~/Library/Logs/Typeless Toolkit/
```

- Swift 与 Node 分文件写入；
- 默认保留 7 天、单文件最大 5 MiB、最多 5 个轮转文件；
- 默认级别 `info`；
- `debug` 只能由用户在设置中临时开启，并在 App 重启后自动恢复为 `info`；
- 协议原文、token、Cookie 和备份内容不得写入日志。

### 15.2 最近活动

最近活动是脱敏的本地 UI 历史，例如“同步 3 个账号完成”“创建手动备份”。默认保留 100 条，可由用户清除。它不替代事务 manifest 和正式日志。

### 15.3 可复制诊断摘要

诊断摘要包含：

- App、核心、Node、协议和 macOS 版本；
- Apple Silicon 架构；
- Typeless 安装路径和版本；
- 数据目录是否可读写；
- CDP 是否可达；
- 备份和补丁恢复状态；
- 稳定错误码。

不包含账号 token、Cookie、个人词库全文或备份内容。

## 16. 构建与分发

### 16.1 开发前置条件

- Apple Silicon Mac；
- macOS 14 或更高；
- 完整 Xcode；
- Xcode Command Line Tools；
- `git`、`curl`、`shasum`、`hdiutil` 和 `codesign`。

不要求 Apple Developer 账号。

### 16.2 构建脚本

仓库提供：

```text
scripts/prepare-node-runtime.sh
scripts/build-debug.sh
scripts/build-release.sh
scripts/package-dmg.sh
scripts/verify-release.sh
```

职责：

1. `prepare-node-runtime.sh`
   - 下载固定版本 Node Darwin `arm64` 包；
   - 校验仓库中记录的 SHA-256；
   - 只提取 `node` 可执行文件；
   - 支持 `NODE_RUNTIME_PATH` 离线覆盖。

2. `build-debug.sh`
   - 检查完整 Xcode 和当前架构；
   - 生成或准备 Sidecar 资源；
   - 通过 `xcodebuild` 构建 Debug App；
   - 使用临时签名。

3. `build-release.sh`
   - 运行 Node 与 Swift 测试；
   - 构建 `Release`、`ARCHS=arm64`；
   - 校验 bundle 中没有开发目录、秘密配置或可写源码状态；
   - 先临时签名 Node helper，再签名 App；
   - 输出到 `dist/Typeless Toolkit.app`。

4. `package-dmg.sh`
   - 建立只读安装布局，包含 App 和 `/Applications` 链接；
   - 使用 `hdiutil` 生成压缩 UDZO 镜像；
   - 输出带版本号的未公证 `.dmg` 和 SHA-256 文件。

5. `verify-release.sh`
   - `file` 校验主程序和 Node helper 都包含 `arm64`；
   - `codesign --verify --deep --strict` 校验签名结构；
   - 启动 sidecar 并执行握手 smoke test；
   - 挂载 `.dmg`，检查安装布局和可读性；
   - 明确记录 `spctl` 可能因未公证而拒绝，不把该预期结果当作构建失败。

### 16.3 临时签名

最终产物使用 ad-hoc 签名：

```text
codesign --force --sign - <nested executable>
codesign --force --sign - <app bundle>
```

签名按嵌套代码由内到外执行。构建脚本不得要求 `DEVELOPMENT_TEAM`，不得把个人证书标识写入工程。

### 16.4 首次打开说明

README 和 DMG 内说明文件必须明确：

1. 将 App 拖入“应用程序”；
2. 首次启动若被 macOS 拦截，在 Finder 中右键 App，选择“打开”，再确认；
3. 或在“系统设置 → 隐私与安全性”中选择“仍要打开”；
4. 仅在用户理解来源并需要命令行处理时，提供：

```bash
xattr -dr com.apple.quarantine "/Applications/Typeless Toolkit.app"
```

不得声称产物已公证或可绕过 Gatekeeper。

## 17. 测试策略

### 17.1 Node

保留现有测试并新增：

- 应用服务用例测试；
- stdio 协议解析、最大帧、乱码和未知 method 测试；
- DTO 脱敏测试；
- 确认 token 过期、复用和参数漂移测试；
- 任务状态、串行锁和安全取消测试；
- sidecar 握手、退出和父进程消失测试；
- 文件导入导出路径与符号链接测试；
- HTTP 与 stdio 适配器业务结果一致性测试。

### 17.2 Swift

使用 XCTest 覆盖：

- JSON Lines 分帧和半包/多包；
- 请求关联、超时和未知事件；
- sidecar 启动、握手、异常退出和一次重启；
- DTO 解码兼容未知字段；
- 页面 ViewModel 的加载、空状态、错误和任务状态；
- 高风险确认流程；
- 设置和窗口状态恢复。

### 17.3 集成与发布验证

在 Apple Silicon 真机执行：

- 首次安装和右键打开；
- 无系统 Node 环境下启动；
- 概览和账号读取；
- 管理连接建立；
- 添加账号、快照和切号；
- 词库增删、批量导入和同步；
- 备份导出、检查和恢复；
- 中断恢复演练；
- 补丁失败回滚演练；
- App 退出后无残留 sidecar；
- 深色、高对比度、Reduce Motion 和 VoiceOver 基本检查；
- 从 `.dmg` 安装后的完整 smoke test。

当前开发环境只有 Command Line Tools、没有完整 Xcode，因此设计阶段可完成，但 Swift 编译、签名结构、运行和 `.dmg` 真机验证必须在安装完整 Xcode 后执行。

## 18. 迁移与兼容策略

- 新 App 第一次启动前不要求用户搬迁数据；
- Node core 继续识别现有稳定数据目录；
- 若检测到旧 release 目录数据，沿用现有安全迁移规则，并在概览显示迁移摘要；
- Web 管理器和 `.command` 脚本在迁移期保留，但 README 将原生 App 标记为推荐入口；
- 原生 App 达到功能对等并完成一个稳定版本后，可将网页入口标记为 legacy，但不在首版删除；
- 原生 App 与旧 Web 管理器不得同时执行写操作。核心使用数据目录锁；若发现另一实例持锁，返回 `OPERATION_CONFLICT`，不强行接管。

## 19. 分阶段实施

### 里程碑 1：核心服务与协议

- 从 `manager.js` 抽取 `application-service.js`；
- 建立稳定 DTO、错误码和命令注册表；
- 建立 stdio sidecar、握手、任务和锁；
- 让 HTTP 适配器复用同一服务；
- 完成 Node 协议与兼容测试。

### 里程碑 2：原生壳与只读体验

- 创建 Xcode 工程和 SwiftUI 导航；
- 集成 sidecar 生命周期；
- 完成概览、账号列表、连接状态、版本状态、诊断只读体验；
- 完成浅深色、错误状态和菜单栏基础能力。

### 里程碑 3：账号与词库工作流

- 添加账号、快照、切换和删除；
- 个人词库和主词库管理；
- 单账号和全部同步；
- 任务进度、确认流程和活动历史。

### 里程碑 4：备份与高级工具

- 手动备份、导出、检查和恢复；
- 设备重置；
- 补丁状态、应用、回退和恢复摘要；
- 文件对话框和高风险确认完整覆盖。

### 里程碑 5：构建与发布

- 固定 Node runtime；
- 完成 Debug/Release 构建脚本；
- 临时签名、`.dmg`、校验和首次打开文档；
- Apple Silicon 真机回归和发布清单。

每个里程碑都必须保持 Node 测试通过；从里程碑 2 开始同时保持 Swift 测试通过。不得以“后续补齐”为由在发布版本留下 Web-only 功能。

## 20. 验收标准

当且仅当以下条件全部满足，原生化目标才算完成：

1. Apple Silicon 用户可从 Xcode 或脚本构建 App，不需要开发者账号；
2. 构建脚本能产出临时签名 `.app` 和未公证 `.dmg`；
3. 安装后日常使用无需打开终端或浏览器；
4. App 不监听本地 HTTP 端口；
5. 没有安装系统 Node 的机器也能运行；
6. 现有运行数据可直接读取，迁移和中断恢复有效；
7. Web 管理器已有的账号、快照、词库、同步、备份、恢复、诊断、重置、补丁和版本能力均有原生入口；
8. Swift 进程和日志中不出现 token、Cookie 或 profile 原文；
9. 高风险操作均经过两阶段确认并保留事务恢复能力；
10. sidecar 随 App 生命周期启动和退出，不留下孤儿进程；
11. Node 与 Swift 自动化测试通过；
12. `.dmg` 在 Apple Silicon 真机完成首次打开和核心流程 smoke test；
13. 界面在浅色、深色、键盘操作和基本辅助功能下可用；
14. 文档明确说明临时签名、未公证和首次放行步骤，不误导用户。

## 21. 已确定决策

- 产品形态：原生 macOS App，而不是 WebView 套壳；
- 平台：仅 Apple Silicon `arm64`；
- 最低系统：macOS 14 Sonoma；
- UI：SwiftUI，遵循 Apple 原生视觉和交互规范；
- 架构：SwiftUI + 内置 Node sidecar；
- IPC：版本化 JSON Lines，经 `stdin/stdout`；
- 网络：App 自身不监听本地服务端口；
- 数据：兼容现有 `Application Support/Typeless Toolkit`；
- 安全：token 留在 Node，Swift 只接收脱敏 DTO；
- 分发：开源自行构建、ad-hoc 临时签名、未公证 `.dmg`；
- 兼容：迁移期保留 Web/CLI 入口，但原生 App 不依赖它们；
- 发布门槛：完整功能对等，而不是只完成一个展示壳。
