Typeless Switch for macOS — 首次打开说明
===========================================

此安装包面向 Apple Silicon（M 系列芯片），采用 ad-hoc 临时签名，属于未公证构建。
不需要 Apple Developer 账号，但 macOS 首次打开时可能会阻止运行。

推荐的首次打开方式
------------------

1. 打开 DMG，把“Typeless Switch”拖到“Applications”。
2. 在 Finder 的“应用程序”中找到“Typeless Switch”。
3. 右键（或按住 Control 点击）App，选择“打开”。
4. 在确认对话框中再次选择“打开”。

如果仍被系统阻止
----------------

打开“系统设置”→“隐私与安全性”，找到刚刚被阻止的 Typeless Switch，点击“仍要打开”。

仅当你确认 DMG 来自可信来源时，也可以在“终端”中移除隔离属性：

    xattr -dr com.apple.quarantine "/Applications/Typeless Switch.app"

安全说明
--------

- App 内置固定版本的 Darwin arm64 Node.js，不依赖系统安装 Node.js。
- App 不启动 localhost 管理服务，也不使用浏览器界面。
- 账号 token、Cookie 与 profile 数据保存在本机运行时数据目录，不打包进 App 或 DMG。
- 每次下载后请核对同目录 `.sha256` 文件。
