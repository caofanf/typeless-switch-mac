# Typeless Switch for macOS：当前交接（2026-07-14）

## 当前状态

项目已完成原生 macOS App 的 1.0 功能、页面与导航优化和纯 macOS 代码库整理。唯一的产品入口是 SwiftUI 主窗口；App Bundle 内置 Node.js sidecar，通过 stdio JSON Lines / JSON-RPC 2.0 提供业务能力。

- 仓库：`/Users/caozhifan/Documents/Git/typeless-switch-mac`
- 分支：`main`
- 页面优化基线提交：`7784850 feat(macOS): 完成 2.0 页面与导航优化`（历史提交信息）
- App 版本：`1.0.0`（构建号 `1`）
- Sidecar 核心 / 协议：`1.0.0` / `1.0`
- 远端：`origin -> https://github.com/bigbobro/typeless-switch-mac.git`
- 本地 `main` 尚未推送到 `origin/main`；未获用户明确授权时不要 push、修改远端或创建 PR。
- 当前纯 macOS 整理改动尚未提交；提交前必须精确暂存，不能使用 `git add .`。

## 本轮纯 macOS 整理（待提交）

- 已删除网页管理器、浏览器页面、本地 HTTP 安全模块，以及网页专用测试。
- 已删除 CLI 与三个 `.command` 终端入口；原生 App 是唯一支持的操作入口。
- 已删除旧网页目录迁移、迁移 marker、冲突复制与迁移后自动备份。首次启动只创建并保护原生运行数据目录；`RUNTIME_DATA.migration.status` 固定为 `none`，以保持现有 RPC/Swift DTO 兼容。
- 已从默认配置移除 `manager_port`，并从 sidecar 打包白名单移除网页安全模块。
- 已删除过时的设计/实施资料与旧交接文档；`README.md`、`CHANGELOG.md`、构建文档和本文件均已同步为纯 macOS 说明。

## 运行架构

- SwiftUI：`macOS/TypelessSwitch/`，负责账号、主词库、备份与恢复、概览和设置。
- Node sidecar：`sidecar/` 与 `lib/`，负责账号、快照、词库、备份、补丁、设备标识、任务和一次性确认。
- App 只打包 sidecar 所需的允许模块；不包含浏览器页面、本地 HTTP 服务或终端工具。
- 连接 Typeless 时会使用其调试端口 `127.0.0.1:9222`；这是原生 App 与 Typeless 的内部 CDP 连接，不是 Toolkit 对外提供的服务。
- Swift 不得读取 token、Cookie、profile、Typeless asar 或 Node 内部模块；新增能力应先设计脱敏 DTO 和 RPC command。

## 用户界面

- 默认首页为“账号”；侧栏顺序为账号、主词库、备份与恢复、概览、设置。
- 诊断与高级工具没有独立入口；高级功能整合在设置页。
- 设置页只展示 App 行为、通知、版本和高级功能；近期活动、诊断日志和辅助功能状态不显示。
- 新安装默认关闭菜单栏状态图标；用户可在设置中主动开启。

## 数据与安全

- 运行数据默认位于 `~/Library/Application Support/Typeless Switch/`；`TYPELESS_DATA_DIR` 仅用于显式开发或测试覆盖。
- 应用不会从项目目录或旧版工具目录迁移数据。旧账号、词库、快照、备份和配置需由用户自行保留或通过 App 的备份恢复功能处理。
- 运行数据目录使用 `0700`，敏感文件使用 `0600`；符号链接会被拒绝。
- 高风险操作必须使用 Node 侧的一次性确认 token；不得在 Swift UI 直接执行。

## 构建与验证

```bash
node --test

xcodebuild \
  -project macOS/TypelessSwitch.xcodeproj \
  -scheme TypelessSwitch \
  -destination 'platform=macOS,arch=arm64' \
  test

scripts/build-release.sh
scripts/package-dmg.sh
scripts/verify-release.sh
```

构建产物位于 `dist/`，不应提交。本次纯 macOS 整理已验证：

- `node --test`：104 项通过；
- Swift/XCTest：39 项通过；
- 严格 Release 构建（完整并发检查、警告视为错误）通过；
- `scripts/build-release.sh`、`scripts/package-dmg.sh` 与 `scripts/verify-release.sh` 通过；
- `git diff --check` 通过；sidecar 发布包只包含协议、业务核心、任务、确认、备份和 Node runtime，不包含网页模块。

## 开发与发布约束

1. 开始前检查 `git status --short --branch`，并精确暂存文件，禁止 `git add .`。
2. 仅保留 SwiftUI、sidecar、原生构建与发布所需内容；不要重新加入本地网页服务、浏览器界面、CLI 或旧目录迁移。
3. 公开发布时保留 `LICENSE`、上游致谢与免责声明，并核查所有上游许可证。
4. 当前 `origin` 是原作者仓库；发布到个人 GitHub 时应新增个人远端或将原远端改名为 `upstream`，再推送 `main` 和所需标签。
