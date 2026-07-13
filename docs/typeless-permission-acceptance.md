# Typeless 权限归属验收清单

本清单用于验证辅助功能和麦克风权限归属于 Typeless，而非 Typeless Toolkit 或 Terminal。
所有授权、拒绝和删除旧授权的操作必须由用户在系统设置中手动完成；应用、测试和构建脚本
不得自动修改 TCC 数据库。

## 修复前基线

1. 完全退出 Typeless。
2. 从 Typeless Toolkit 执行“连接”。
3. 在 Typeless Onboarding 点击粘贴权限的“允许”。
4. 记录系统弹窗显示的应用名称。
5. 在系统设置中允许后返回 Typeless。

历史实际结果：系统弹窗显示 Typeless Toolkit；Typeless 页面没有进入已授权状态。

## LaunchServices 最小实验

测试环境：macOS（请在最终验收记录中填写具体版本）。

1. 在「系统设置 → 隐私与安全性」的“辅助功能”和“麦克风”中，手动移除 Typeless Toolkit、
   Typeless、Terminal 的测试记录。
2. 完全退出 Typeless。
3. 在 Terminal 运行：

   ```bash
   /usr/bin/open -n '/Applications/Typeless.app' \
     --args '--remote-debugging-port=9222'
   ```

4. 在 Onboarding 点击辅助功能的“允许”。
5. 确认系统弹窗显示 **Typeless**，在系统设置中允许后确认 Onboarding 更新为完成。
6. 确认 CDP 可用：

   ```bash
   curl --fail --silent --show-error http://127.0.0.1:9222/json/version
   curl --fail --silent --show-error http://127.0.0.1:9222/json/list
   ```

本轮最小实验结果：辅助功能弹窗显示 **Typeless**，`/json/version` 返回 Electron/Typeless 的
有效 JSON。此结果只验证启动归属与 CDP 参数；以下完整验收仍需在本轮 Release App 上完成。

## Release 验收

在固定路径安装本轮生成的 Release App 后，完全退出 Typeless 和 Typeless Toolkit。

1. 从 Toolkit 建立连接，在 Typeless Onboarding 申请辅助功能。
2. 确认弹窗和系统设置列表显示 Typeless，而不是 Typeless Toolkit 或 Terminal；允许后 Onboarding
   应更新，Toolkit 本身不需要辅助功能权限。
3. 在同一流程申请麦克风；确认弹窗和系统设置列表显示 Typeless，允许后 Onboarding 更新。
4. 完成 Onboarding 后退出两个应用，再通过 Toolkit 建立连接；确认不重复申请已授予的权限，
   并且 `127.0.0.1:9222` 可连接。
5. 拒绝辅助功能后再次请求并在系统设置手动允许；确认 Typeless 不崩溃、不会伪造成功状态，
   且可恢复。
6. 先以 LaunchServices 和端口 `9222` 启动 Typeless，再打开 Toolkit；确认 Toolkit 不重启 Typeless。
7. 如需测试账号切换，确认重启后 CDP 可用、授权没有转移给 Toolkit。

## 签名状态与结果记录

```text
测试版本：
macOS 版本：
Typeless 版本：
Typeless 是否打过补丁：是 / 否
原厂签名 / TeamIdentifier / CDHash：
补丁后签名 / TeamIdentifier / CDHash（如适用）：

辅助功能弹窗显示：Typeless / Typeless Toolkit / Terminal / 没有弹窗
允许后 Onboarding：已完成 / 仍停留在“允许”
麦克风弹窗显示：Typeless / Typeless Toolkit / Terminal / 没有弹窗
两项授权后：可继续 / 无法继续
重启后权限：保持有效 / 再次要求授权
Toolkit 管理连接：可连接 127.0.0.1:9222 / 无法连接
附加现象或截图：
```
