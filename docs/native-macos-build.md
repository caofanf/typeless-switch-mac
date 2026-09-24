# 原生 macOS App 构建与分发

本文说明如何在 Apple Silicon Mac 上从源码构建 Typeless Switch 原生 App、进行 ad-hoc 临时签名、生成未公证 DMG，并验证本地发布候选。

## 1. 分发模型

本项目采用“开源项目自行构建 / 临时签名”方案：

- 提供 Xcode 工程和可重复执行的 shell 脚本；
- 仅构建 Darwin `arm64`，不生成 Intel 或 Universal Binary；
- 不要求 Apple Developer 账号；
- App 与内置 Node helper 使用 ad-hoc 签名；
- DMG 未经过 Apple 公证，首次打开可能需要用户手动放行；
- 所有 Git 操作都可在本地完成，构建与打包不要求推送仓库。

## 2. 环境要求

- Apple Silicon（`uname -m` 必须返回 `arm64`）；
- macOS 14 或更高版本；
- 完整 Xcode，而不是只有 Command Line Tools；
- 系统工具：`bash`、`curl`、`shasum`、`tar`、`file`、`codesign`、`hdiutil`、`spctl`、`ditto`、`PlistBuddy`；
- 网络构建需要访问 `https://nodejs.org`。

首次安装 Xcode 后执行：

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
xcrun swift --version
```

## 3. 固定 Node runtime

固定版本配置位于：

```text
release/node-runtime.env
release/node-sha256.txt
```

当前版本为 Node.js `v24.15.0` 的官方 `node-v24.15.0-darwin-arm64.tar.gz`。准备脚本会：

1. 从固定 HTTPS URL 下载归档；
2. 使用仓库记录的官方 SHA-256 执行 `shasum -a 256 -c`；
3. 只提取 `bin/node`；
4. 使用 `file` 验证 Mach-O `arm64`；
5. 使用 `node --version` 验证固定版本。

单独准备 runtime：

```bash
scripts/prepare-node-runtime.sh /tmp/typeless-node
/tmp/typeless-node --version
file /tmp/typeless-node
```

离线构建可设置 `NODE_RUNTIME_PATH`。该文件仍必须是固定版本的 Mach-O `arm64` Node：

```bash
NODE_RUNTIME_PATH="/absolute/path/to/node" \
  scripts/prepare-node-runtime.sh /tmp/typeless-node
```

`NODE_RUNTIME_PATH` 是构建输入，不会写入 App 配置，也不会替代版本与架构校验。

## 4. Sidecar 资源

准备命令：

```bash
scripts/prepare-sidecar.sh /tmp/typeless-sidecar
```

目标目录必须为空。脚本只复制明确允许的文件，并对每个 JavaScript 文件执行 `node --check`：

```text
Sidecar/
├── node
├── sidecar/
│   ├── main.js
│   ├── command-registry.js
│   └── protocol.js
├── lib/
│   └── 允许的核心模块
└── LICENSE
```

保持 `sidecar/` 与 `lib/` 的相对布局可以让生产资源和源码使用同一套 `require('../lib/...')` 路径。脚本不会复制 `accounts.json`、`config.json`、`profiles/`、备份、`.env`、`.git/` 或其他工作区内容。

## 5. Debug 构建

```bash
scripts/build-debug.sh
```

如果本机已安装固定版本 Node，可减少下载：

```bash
NODE_RUNTIME_PATH="$(command -v node)" scripts/build-debug.sh
```

脚本会准备 Sidecar、运行 `xcodebuild`、把资源写入 App bundle、先签名 Node helper、再签名外层 App，并执行：

```bash
codesign --verify --deep --strict "dist/Typeless Switch.app"
```

输出：

```text
dist/Typeless Switch.app
```

Xcode 工程位于 `macOS/TypelessSwitch.xcodeproj`。直接使用 Xcode 适合编辑、测试和调试 Swift 代码；需要可独立启动且包含固定 Node Sidecar 的完整 App 时，请使用上述脚本完成资源注入和签名。

## 6. Release 构建

```bash
scripts/build-release.sh
```

构建固定使用：

```text
ARCHS=arm64
ONLY_ACTIVE_ARCH=YES
CODE_SIGNING_ALLOWED=NO
```

Xcode 产物完成后，脚本执行以下步骤：

1. 复制到 `dist/Typeless Switch.app`；
2. 注入 `Contents/Resources/Sidecar/`；
3. 附加 `THIRD_PARTY_NOTICES.md`；
4. 对内置 Node helper 进行 ad-hoc 签名；
5. 从内到外签名 App；
6. 严格验证签名结构。

## 7. 生成 DMG

先完成 Release 构建，再运行：

```bash
scripts/package-dmg.sh
```

脚本使用 `hdiutil create -format UDZO` 生成压缩磁盘映像。安装布局包含：

```text
Typeless Switch.app
Applications -> /Applications
README-FIRST.txt
```

输出示例：

```text
dist/Typeless-Switch-1.1.0-arm64.dmg
dist/Typeless-Switch-1.1.0-arm64.dmg.sha256
```

校验下载或复制后的镜像：

```bash
cd dist
shasum -a 256 -c Typeless-Switch-1.1.0-arm64.dmg.sha256
```

## 8. 发布验证

```bash
scripts/verify-release.sh
```

如 `dist/` 中存在多个版本的 DMG，请显式传入路径：

```bash
scripts/verify-release.sh "dist/Typeless-Switch-1.1.0-arm64.dmg"
```

验证器检查：

- App 主程序和 Node helper 都是 Mach-O `arm64`；
- `codesign --verify --deep --strict` 通过；
- App bundle 不含账号、配置、profile、备份、`.env` 或 token 数据文件；
- 使用内置 Node 启动 Sidecar，`core.hello` 返回正确协议与 `arm64`；
- `.sha256` 校验通过；
- DMG 能只读挂载，并包含 App 与 Applications 链接；
- 记录 `spctl` 结果。未公证构建通常会被 Gatekeeper 拒绝，该结果本身不掩盖其他验证失败。

## 9. 完整发布候选检查

```bash
node --test

xcodebuild \
  -project macOS/TypelessSwitch.xcodeproj \
  -scheme TypelessSwitch \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/TypelessSwitchDerivedData \
  test

xcodebuild \
  -project macOS/TypelessSwitch.xcodeproj \
  -scheme TypelessSwitch \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/TypelessSwitchStrictDerivedData \
  build \
  SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

scripts/build-release.sh
scripts/package-dmg.sh
scripts/verify-release.sh
```

Node 测试覆盖 sidecar 协议、运行数据、备份、任务、确认与发布准备。若受限环境阻止 Xcode 宏插件或本机 App 构建，应在允许 Xcode 执行宏插件的环境重新验证，不能把环境限制当成产品失败。

## 10. 首次打开未公证 App

推荐步骤：

1. 打开 DMG，将 App 拖入“Applications”；
2. 在 Finder 中右键 App，选择“打开”；
3. 在确认对话框中再次选择“打开”；
4. 如果仍被阻止，打开“系统设置”→“隐私与安全性”，点击“仍要打开”。

确认构建来源可信时，也可以移除隔离属性：

```bash
xattr -dr com.apple.quarantine "/Applications/Typeless Switch.app"
```

这不会把 App 变成已公证软件，只会移除当前文件的下载隔离标记。

## Typeless 启动与权限归属

Typeless Switch 必须通过 macOS LaunchServices 启动完整的 `Typeless.app`，不得直接执行
`Contents/MacOS/Typeless`。直接执行内部二进制会让辅助功能或麦克风权限归到启动者，导致
Typeless Onboarding 无法确认自身权限。

CDP 参数始终通过参数数组传递，对应命令为：

```bash
/usr/bin/open -n <Typeless.app> --args --remote-debugging-port=9222
```

如需重新验证权限归属，用户应手动在以下位置删除旧的测试授权记录后再测试：

```text
系统设置 → 隐私与安全性 → 辅助功能
系统设置 → 隐私与安全性 → 麦克风
```

仅删除 Typeless Switch、Typeless 或 Terminal 的相关测试记录；不得删除整个 TCC 数据库，
也不得让应用或脚本自动重置系统权限。

如果“解除升级弹窗”功能重新签名了 `Typeless.app`，Typeless 的代码身份会发生变化，macOS
可能要求重新授予辅助功能和麦克风权限。权限验收必须分别记录原厂签名状态和补丁后 ad-hoc
签名状态，不能把两者视为同一个 TCC 身份。

## 11. 常见问题

### 提示需要完整 Xcode

确认活动开发者目录：

```bash
xcode-select -p
xcodebuild -version
```

必要时切换：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### `NODE_RUNTIME_PATH` 被拒绝

运行：

```bash
file "$NODE_RUNTIME_PATH"
"$NODE_RUNTIME_PATH" --version
```

它必须同时匹配 `release/node-runtime.env` 中的版本，并显示 Mach-O `arm64`。

### SHA-256 校验失败

不要继续使用归档。删除下载缓存后重新运行，确认固定 URL 未被代理或镜像替换；只有更新 Node 版本时才应同时更新 `node-runtime.env`、官方 SHA-256 和第三方声明。

### 签名验证失败

必须先签嵌套的 Node helper，再签外层 App。不要在签名后修改 `Contents/`；任何资源变化都需要重新从内到外签名。

### App 启动但核心不可用

先运行：

```bash
scripts/verify-release.sh
```

检查 App 内是否存在：

```text
Contents/Resources/Sidecar/node
Contents/Resources/Sidecar/sidecar/main.js
Contents/Resources/Sidecar/lib/
```

诊断日志只应来自 Sidecar `stderr`，协议 `stdout` 不应混入普通日志。
