# Changelog

## 未发布

### Changed

- 仓库收敛为纯 macOS 原生应用：删除网页管理器、本地 HTTP 服务、CLI、`.command` 入口和网页专用安全层。
- 删除旧网页项目目录的数据迁移；运行数据仅在 Application Support 目录或显式 `TYPELESS_DATA_DIR` 中初始化并保持私有权限。
- 删除网页专用测试和历史设计资料；构建 sidecar 只包含原生 App 所需的核心模块。
- App 版本定为 `1.0.0`（构建号 `1`）；页面与导航优化属于 1.0 的维护更新。Sidecar 核心和协议继续保持 `1.0.0` / `1.0`。

## native-macos-ui-update - 2026-07-14

### Changed

- 将“账号”设为默认首页，并将侧栏精简、重排为账号、主词库、备份与恢复、概览、设置。
- 将概览下调到设置上方，移除诊断和高级工具的独立入口；概览中的版本提醒会定位到设置页的高级功能区域。
- 统一设置页与其他内容页的系统语义背景、内容宽度和间距，隐藏最近活动、诊断日志与辅助功能状态。
- 将版本漂移、Typeless 补丁、设备标识重置、数据目录和高级任务迁入设置页下方的“高级功能”。
- 新安装默认不显示系统菜单栏状态图标；已经保存过的用户选择保持不变，仍可在设置中手动开启原有菜单。

## native-macos-v1.0.0 - 2026-07-12

### Added

- 新增仅支持 Apple Silicon、最低 macOS 14 的 SwiftUI 原生 App 与版本化 JSON Lines / JSON-RPC 2.0 sidecar。
- 新增账号、词库、备份恢复、诊断、高级功能、设置、菜单栏、通知和原生发布脚本。
- 新增固定 Node.js Darwin `arm64` runtime 的下载校验、Debug/Release 构建、ad-hoc 签名、未公证 DMG、SHA-256 和发布验证流程。

### Security

- Swift 只使用脱敏 DTO；token、Cookie 和 profile 不进入 Swift UI。
- sidecar 使用 stdio 通信，`stdout` 只发送协议帧，运行日志写入 `stderr`。
