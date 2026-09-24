# Typeless Switch for macOS

Typeless Switch 是面向 macOS 的原生桌面应用，用于管理 Typeless 的账号、登录快照、个人词库、备份恢复、版本漂移、设备标识和本地补丁。

应用使用 SwiftUI 主窗口，并在 App Bundle 内置固定版本的 Darwin `arm64` Node.js sidecar。日常使用不需要浏览器、终端或系统安装的 Node.js。

当前 App 版本为 `1.1.0`（构建号 `2`），Sidecar 核心版本为 `1.1.0`。

## 使用要求

- Apple Silicon（M 系列芯片）；
- macOS 14 或更高版本；
- 已安装 Typeless.app；
- 首次打开未公证构建时，按 [`release/README-FIRST.txt`](release/README-FIRST.txt) 手动放行。

## 安装与打开

从源码构建后会得到：

```text
dist/Typeless Switch.app
dist/Typeless-Switch-<version>-arm64.dmg
dist/Typeless-Switch-<version>-arm64.dmg.sha256
```

核对 `.sha256` 后打开 DMG，把 App 拖到“Applications”。开源自行构建版本使用 ad-hoc 临时签名且未经过 Apple 公证；首次打开请在 Finder 中右键 App 并选择“打开”。如仍被阻止，请前往“系统设置”→“隐私与安全性”选择“仍要打开”。

完整构建、签名、DMG 与验证说明见 [`docs/native-macos-build.md`](docs/native-macos-build.md)。

## 日常使用

1. 打开 Typeless Switch；默认进入“账号”页面。
2. 在“账号”或“概览”中连接 Typeless。App 会通过 LaunchServices 启动 Typeless，并建立仅供管理使用的 CDP 连接。
3. 在 Typeless 中登录账号，返回 Toolkit 添加当前账号并保存登录快照。
4. 在“主词库”同步单个或全部账号；在“备份与恢复”创建、导出或恢复备份。
5. 在“设置”中调整菜单栏、通知和刷新行为；补丁、设备标识重置等高风险操作位于“高级功能”，均需要二次确认。
6. 在“设置”中配置“账号自动轮动”（默认阈值 2,000 词），支持达标后无缝自动切号或弹窗确认切换，避免额度耗尽。

系统菜单栏状态图标在新安装时默认关闭，用户可在设置中手动开启。添加账号、账号列表和账号切换都在主窗口完成。

## 原生功能

| 功能 | 原生入口 | 说明 |
| --- | --- | --- |
| 状态概览 | 概览 / 菜单栏 | 连接、账号、备份、补丁、版本和任务状态 |
| 多账号与快照 | 账号 | 添加、刷新、切换、删除和保存登录快照 |
| 账号自动轮动 | 设置 / 账号 / 菜单栏 | 依据本周用词量（默认 2,000 词）自动或提醒轮动切换有效账号 |
| 账号词库与主词库 | 主词库 | 词库编辑、单账号同步和全部同步 |
| 备份恢复 | 备份与恢复 | 本地备份、导出、检查和受保护恢复 |
| 高级功能 | 设置 | 版本漂移、数据目录、设备标识重置和 Typeless 补丁 |
| 偏好 | 设置 | 菜单栏、通知、刷新与版本信息 |

Swift 只接收脱敏 DTO；账号 token、Cookie 和 profile 始终留在本机 Node sidecar 与运行数据目录。App 与 sidecar 通过 `stdin/stdout` 上的 JSON Lines / JSON-RPC 2.0 通信，不启动本地 HTTP 服务。

## 从源码构建

先安装完整 Xcode，并完成首次初始化：

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

构建 Release App、DMG 和验证：

```bash
scripts/build-release.sh
scripts/package-dmg.sh
scripts/verify-release.sh
```

默认构建脚本从 Node.js 官方地址下载并校验固定的 Darwin `arm64` runtime。离线或本机开发时，可通过 `NODE_RUNTIME_PATH` 指向相同固定版本的 Mach-O `arm64` Node：

```bash
NODE_RUNTIME_PATH="$(command -v node)" scripts/build-debug.sh
```

## 数据与配置

运行数据默认位于：

```text
~/Library/Application Support/Typeless Switch/
```

- `accounts.json`：账号信息和 token；权限仅限当前用户，不要上传或分享。
- `profiles/`：各账号的 Typeless 登录快照；不要上传或分享。
- `Typeless词库主清单.csv`：本地主词库。
- `runtime-backups/`：本地运行数据备份。
- `patch-backups/`：应用 Typeless 补丁前的事务备份。
- `config.local.json`：本机路径和补丁适配覆盖配置；不会提交到 Git。

目录使用 `0700`，敏感文件使用 `0600`。应用不会从项目目录或旧版网页工具目录复制账号、词库、快照、备份或配置；如需保留旧数据，请在清理旧目录前自行导出并通过 App 的“备份与恢复”导入。

默认路径通常无需调整。若 Typeless 安装在非默认位置，可在运行数据目录创建 `config.local.json`：

```json
{
  "typeless_app": "/Applications/Typeless.app"
}
```

支持的配置项包括 `typeless_app`、`user_data_dir`、`device_cache_path`、`asar_path`、`cdp_port`、`api_base`、`master_csv` 和 `paywall`。完整默认值见 [`config.example.json`](config.example.json)。

## 安全与限制

- 该项目不隶属于 Typeless；请遵守 Typeless 的服务条款和适用法律。
- 高风险操作由 sidecar 准备一次性确认 token 后执行，Swift UI 不直接修改账号、profile、Typeless App 或系统凭据。
- 设备标识重置与补丁会修改本机状态或 Typeless.app，请先完成备份并确认操作影响。
- 当前发布方式为 ad-hoc 临时签名、未公证 DMG，不是 Mac App Store 沙盒应用。

## 许可证与致谢

本项目以 [MIT License](LICENSE) 发布。请保留版权与许可声明。

项目参考并致谢 `Jia131313/typeless-toolkit` 与 `estarpro1022/typeless-reset-device`。公开再发布前，请自行核查所有上游项目及依赖的许可证和发布要求。
