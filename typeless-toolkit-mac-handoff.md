# Typeless Toolkit 原生 macOS App：2.0 最新交接

## 1. 这份交接的用途

本文是后续开发、修 Bug、维护发布链路时的当前事实来源。它取代早期只记录“调研/设计阶段”的交接内容。

当前 2.0 是可直接运行的原生 macOS 桌面应用：SwiftUI 负责界面，App Bundle 内置 Node.js sidecar 负责业务核心；不依赖浏览器、WebView、终端常驻进程或 localhost 管理服务。2.0 主要调整原生界面的信息架构，核心协议和业务能力继续兼容 1.0。

## 2. 当前版本与仓库状态

- 仓库：`/Users/caozhifan/Documents/Git/typeless-toolkit-mac`
- 分支：`Mac-UI`
- App 版本：`2.0.0`（构建号 `2`）；Sidecar 核心和协议仍为 `1.0.0`。
- 1.0 功能提交：`7fc4004 feat: complete native desktop app 1.0 release`
- 上一个架构提交：`b90df71 fix: launch Typeless through macOS LaunchServices`
- Git 操作仅限本地：不要 push、不要创建 PR，除非用户明确要求。
- 目标平台：macOS 14+、Apple Silicon `arm64`。
- 分发方式：开源自行构建、ad-hoc 临时签名、未公证 DMG；不是 Mac App Store 沙盒应用。

工作区中的 `findings.md`、`progress.md`、`task_plan.md` 和本文属于调研/交接材料；不要使用 `git add .` 把历史材料、构建产物或用户自己的临时文件混入功能提交。

## 3. 用户可见的 2.0 功能

### 3.1 原生应用宿主

- SwiftUI 原生主窗口，不使用 `WKWebView`。
- Finder 风格 `NavigationSplitView` 侧边栏：账号、主词库、备份与恢复、概览、设置；启动后默认进入账号页。
- 系统自适应视觉：系统字体、SF Symbols、语义色、浅色/深色模式、标准 macOS 控件。
- 菜单栏状态入口默认关闭；用户可在设置中主动开启原有的打开窗口、刷新、连接、同步和退出操作。
- 应用激活时可以按设置刷新轻量状态；近期活动继续在内部记录，但不再作为设置页内容展示。

### 3.2 概览与连接

- 展示 Typeless CDP 连接状态、端口、账号数量、版本漂移、备份状态、补丁状态和活动任务。
- 通过 LaunchServices `/usr/bin/open -n Typeless.app --args --remote-debugging-port=9222` 启动 Typeless，确保系统辅助功能/麦克风权限归属 Typeless 本身。
- 连接建立前检查调试端口；必要时启动或等待 Typeless；不把“端口不可达”误报成已连接。
- 连接错误、授权请求未出现、抓取阶段错误分别返回安全且可恢复的阶段信息。

### 3.3 账号管理

- 列出已保存账号，展示昵称、邮箱、角色、token 有效期、实时 token 状态、用量/个性化摘要、词条数量和快照状态。
- 账号搜索；账号详情页查看远端词库、用量、个性化状态和快照信息。
- “添加账号”流程：建立连接 → 刷新当前 Typeless 页面 → 轮询授权请求 → 脱敏预览 → 用户确认昵称/邮箱 → 保存。
- 抓取结果通过短时一次性 `capture_id` 保存，Swift DTO 不接收 token；token 只在 Node sidecar 内部保留。
- 支持保存当前账号的本地登录快照。
- 删除账号需要服务端一次性确认；可选择同时删除对应快照。
- 切换账号快照需要一次性确认，切换前后会安全停止/恢复/重新启动 Typeless。

### 3.4 账号词库与主词库

- 查看、搜索账号词库。
- 添加单个词或批量添加词；输入会 trim、去空行并按既定规则去重。
- 删除词条，并等待远端结果确认。
- 同步单个账号词库：导出账号词 → 合并本地主词库 → 将缺失词导入账号。
- 同步全部账号，作为可观察、可取消的后台任务运行。
- 将主词库导入指定账号。
- 在两个账号之间复制缺失词。
- 查看主词库、搜索主词库、预览替换差异；主词库整批替换必须经过一次性确认。
- 大批量写入可能返回 `task_id`，UI 通过统一任务状态展示进度。

### 3.5 备份与恢复

- 查看运行数据是否有变化、最新备份时间、备份源、备份目录和备份状态。
- 创建本地运行备份。
- 通过系统文件选择器导出备份包。
- 选择备份文件后先检查 manifest、版本、文件数量、大小和摘要，再进入恢复确认。
- 恢复需要二阶段确认，并以后台任务执行；备份变化或内容不一致时拒绝提交。
- 运行时备份事务使用 staging、before-image、原子发布、提交后校验和失败回滚；启动时会恢复未完成事务。
- 备份内容覆盖账号、主词库、profiles、配置、版本状态等 canonical 运行数据，不直接暴露 token 到 Swift/UI。

### 3.6 诊断、版本和高级功能

- 诊断报告能力继续供内部状态读取和排障使用，但不再提供独立侧栏页面。
- 检测 Typeless 版本漂移；用户可确认当前版本作为基线。
- 设置页下方的“高级功能”集中展示设备状态、数据目录、版本漂移、补丁和高风险操作。
- “重置设备标识”是高风险操作：服务端先准备一次性确认，再执行 Keychain/device cache/用户数据相关清理和重启流程。
- “应用 Typeless 补丁”是高风险操作：检测目标 asar、显示可执行动作、二阶段确认、创建 before-image、原子修改、更新 Info.plist 完整性信息、ad-hoc 重签名、验证；失败时只回滚本次事务并再次校验。
- 补丁状态包含目标是否存在、是否已修改、检测到的文件、备份和错误信息。

### 3.7 任务、错误和安全交互

- 长任务统一返回 `task_id`、类型、状态、是否可取消、阶段、完成量、总量、结果和错误。
- UI 可列出活动任务、展示进度、记录近期活动、取消可取消任务。
- 高风险操作必须先 `operations.prepare`，确认 token 与规范化参数绑定且只能消费一次。
- Swift 只展示公开 DTO；未知字段、token、Cookie、profile、堆栈和内部错误不会进入 UI/API。
- 错误包含稳定 code、可恢复性、建议动作和安全 context；不能把底层异常原文直接显示给用户。

### 3.8 设置与高级功能

- 可开关菜单栏状态图标；全新安装默认关闭，已有用户保存的选择不会被覆盖。
- 可选择关闭最后一个窗口时退出，或让 App 留在菜单栏。
- 可开关启动/返回前台自动刷新（前台期间按固定间隔刷新轻量状态）。
- 可开关任务完成/失败系统通知；首次使用时请求 macOS 通知权限。
- 设置页显示 App/核心/Node/协议/架构信息，并在下方承载全部高级功能。
- 最近活动、诊断日志、Reduce Motion 和 Reduce Transparency 状态不再显示；界面仍遵循系统辅助功能环境。

## 4. 当前架构边界

### 4.1 SwiftUI 层

主要目录：`macOS/TypelessToolkit/`

- `App/AppModel.swift`：全局状态、导航、刷新、任务、账号/词库/备份/高级操作状态机。
- `Features/*`：各页面和 sheet；`RootView` 负责侧边栏与页面路由。
- `Domain/*`：Account、Backup、Task、Connection、Diagnostic、Patch 等脱敏模型。
- `CoreIPC/CoreClient.swift`：将 Swift 方法映射到版本化 RPC command；负责 JSON 解码和错误映射。
- `CoreIPC/SidecarProcess.swift`：启动内置 Node、握手、stderr 日志、异常重启和关闭。
- `CoreIPC/JSONLineTransport.swift`：stdin/stdout JSON Lines 编解码、请求关联、通知和 pending continuation。
- `Services/*`：设置持久化、文件选择器、近期活动。

Swift 不应直接读取账号文件、token、Cookie、profile、Typeless asar 或调用 Node 内部模块；新增功能应先定义脱敏 DTO 和 RPC command，再接 UI。

Sidecar 缺失、握手超时或协议不兼容时，AppRuntime 会回退到不可用 CoreClient；当前 UI 主要显示核心不可用/刷新失败。后续若优化安装诊断，可在这个边界补充更明确的修复建议。

### 4.2 Node sidecar 层

主要目录：`sidecar/`、`lib/`

- `sidecar/main.js`：stdio 入口、父进程存活检测、协议帧读取。
- `sidecar/protocol.js`：JSON-RPC 2.0 请求/响应/通知。
- `sidecar/command-registry.js`：`core.hello`、`core.shutdown` 和应用服务路由。
- `lib/application-service.js`：UI 无关的业务编排、输入校验、确认、任务和公开 DTO。
- `lib/common.js`：运行数据、Typeless 生命周期/CDP、远端 API、词库同步、备份、设备重置、补丁和版本漂移等核心能力。
- `lib/runtime-data.js`：稳定目录、旧版本迁移、权限收紧、运行恢复。
- `lib/patch-transaction.js`：通用补丁事务与回滚。
- `lib/task-runner.js`：任务状态、资源冲突、进度和取消。
- `lib/public-dto.js`：账号、抓取、词库、实时状态的白名单脱敏。
- `lib/core-errors.js`：稳定错误码和 wire shape。

Sidecar 不监听 localhost；stdout 只能输出协议帧，日志写 stderr。Node runtime 为打包进 App 的固定 Darwin arm64 Node 24.x。

### 4.3 RPC 约定

握手响应固定包含：

- `protocol_name: typeless-toolkit-core`
- `protocol_version: 1.0`
- `core_version: 1.0.0`
- Node 版本、架构、capabilities
- `runtime_data_path`
- 启动时运行数据恢复/迁移摘要

新增 command 时必须同时更新：

1. `lib/application-service.js` 的 capability 和执行路由；
2. `sidecar/command-registry.js`（如果需要特殊系统 command）；
3. Swift `CoreClientProtocol` / `LiveCoreClient`；
4. Swift DTO、错误映射、AppModel 状态机和对应 View；
5. Node/Swift 回归测试。

## 5. 数据、权限和安全约束

- 默认运行数据目录：`~/Library/Application Support/Typeless Toolkit/`。
- 账号 token、profiles、Cookie 和远端凭据只在 Node sidecar/本地数据层；不得序列化进 Swift DTO、日志、UI 或普通 RPC 结果。
- 账号抓取结果只返回 `capture_id`、user id、昵称、邮箱、角色、时间；`capture_id` 五分钟内有效且保存后消费。
- 运行数据迁移拒绝符号链接和非常规文件；同名冲突 fail closed；staging 校验通过后才发布；目录通常为 `0700`，敏感文件为 `0600`。
- 高风险操作不得在 Swift 侧自行执行；必须由 Node application service 先准备、服务端确认、消费一次性 token。
- 不要把 `TYPELESS_DATA_DIR`、账号 token、临时备份或本机路径写入公开日志/截图/测试输出。
- 该 App 不是沙盒应用，因为设备重置、Typeless App 修改、重签名和系统进程控制需要本机权限；发布文案必须明确 ad-hoc、未公证和首次 Gatekeeper 放行方式。

## 6. 构建、测试和发布

### 全量 Node 测试

```bash
node --test test/*.test.js
```

当前核心基线：123 项通过。涉及本机回环监听的安全集成测试在受限沙箱中可能出现 `listen EPERM`；应在允许 `127.0.0.1` 的环境重跑，不能把沙箱限制误判成产品失败。

### Swift 测试

```bash
xcodebuild \
  -project macOS/TypelessToolkit.xcodeproj \
  -scheme TypelessToolkit \
  -destination 'platform=macOS,arch=arm64' \
  test
```

当前 2.0 基线：39 项 Swift/XCTest 通过。

### Release 构建与 DMG

```bash
scripts/build-release.sh
scripts/package-dmg.sh
scripts/verify-release.sh "dist/Typeless-Toolkit-2.0.0-arm64.dmg"
```

产物：

- `dist/Typeless Toolkit.app`
- `dist/Typeless-Toolkit-2.0.0-arm64.dmg`
- `dist/Typeless-Toolkit-2.0.0-arm64.dmg.sha256`

Release 构建会准备 Sidecar、下载/校验 arm64 Node、构建 Swift App、复制 sidecar、ad-hoc 签名并验证。构建产物在 `.gitignore` 中，不应提交到 Git。

## 7. 后续开发建议

### 优先级 A：稳定性与可观测性

1. 保持每个用户可见流程都有真实的阶段错误和恢复建议；新增 RPC 不要吞掉错误。
2. 为真实 Typeless 版本和未登录/登录中/网络失败/端口失效场景补充集成测试。
3. 继续检查 Swift 解码模型与 Typeless 远端字段形状；远端对象字段必须在 Node 侧归一化为稳定 DTO。
4. 关注 sidecar 退出、父进程退出、App 重启、CDP reload 失败和中途取消时的清理。

### 优先级 B：长任务与体验

1. 为同步、恢复、诊断、补丁增加更细的阶段文案、进度和取消反馈。
2. 统一近期活动、通知和任务错误的展示策略。
3. 对备份恢复、设备重置、补丁应用继续做真实文件/进程验收，但测试环境必须使用备份和明确确认。

### 优先级 C：发布质量

1. 加入 Developer ID 签名和 notarization（若用户以后需要公开分发）。
2. 为 release 产物建立版本号、变更日志、SHA-256 和回滚说明。
3. 评估是否需要 Intel 支持；当前协议、Node runtime 和构建脚本只保证 arm64。
4. 若未来要进入 Mac App Store，需要重新设计沙盒权限和高风险功能边界，不应直接套用当前 2.0 架构。

## 8. 后续任务的标准工作流

1. 先看 `git status --short`、最近提交和本文；不要假设旧调研文档代表当前实现。
2. 用 `rg` 定位 Swift command、application service、common 核心和现有测试。
3. 先添加最小回归测试，确认测试能捕获问题，再实现修复。
4. 只在用户明确授权的范围内修改文件；Git 暂存必须精确列出文件，禁止 `git add .`。
5. 运行相关 Node/Swift 测试，再跑全量测试和 `git diff --check`。
6. 需要发布时重新构建 `.app`、DMG、checksum 并运行 `verify-release.sh`。
7. Git 只做本地 commit；提交前说明是否保留用户已有的未跟踪文档，默认不 push。

## 9. 当前已知的历史材料

`findings.md`、`progress.md`、`task_plan.md` 主要记录 2026-07-12 的调研、视觉选择和原生化设计过程，其中部分状态（例如“尚未实现”“缺少完整 Xcode”）已经过时。后续开发应以源码、提交 `7fc4004`、当前构建脚本、测试结果和本文为准；历史材料仅用于理解为什么选择 SwiftUI + Node sidecar、stdio RPC、Finder 式侧边栏和临时签名分发。
