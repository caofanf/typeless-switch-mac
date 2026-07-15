import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var preferences: AppPreferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    behaviorSection
                    notificationsSection
                    versionSection

                    Divider()
                        .padding(.vertical, 2)

                    advancedHeader
                        .id(SettingsSection.advanced)
                    AdvancedSettingsContent(model: model)
                }
                .padding(24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(.background.secondary)
            .task(id: model.requestedSettingsSection) {
                guard let requestedSection = model.requestedSettingsSection else { return }
                await Task.yield()
                proxy.scrollTo(requestedSection, anchor: .top)
                model.clearSettingsNavigationRequest()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置").font(.largeTitle.bold())
            Text("调整窗口、菜单栏、通知和 Typeless 高级功能。")
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        GroupBox("App 行为") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("在菜单栏显示状态图标", isOn: $preferences.showsMenuBarExtra)
                    .accessibilityHint("默认关闭；开启后可从系统菜单栏使用常用操作。")
                Toggle("关闭最后一个窗口时退出 App", isOn: $preferences.quitAfterLastWindowClosed)
                    .disabled(!preferences.showsMenuBarExtra)
                    .accessibilityHint("关闭时若不退出，App 会留在菜单栏。")
                Toggle("启动和返回前台时自动刷新", isOn: $preferences.refreshOnActivation)
                    .accessibilityHint("开启后，前台期间每 30 秒刷新轻量状态。")
            }
            .padding(.vertical, 6)
        }
    }

    private var notificationsSection: some View {
        GroupBox("通知") {
            Toggle("任务完成或失败时发送系统通知", isOn: $preferences.notificationsEnabled)
                .padding(.vertical, 6)
                .accessibilityHint("首次发送通知时，macOS 可能请求通知权限。")
        }
    }

    private var versionSection: some View {
        GroupBox("版本") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("App", value: appVersion)
                LabeledContent("核心", value: "随 Sidecar 握手显示")
                LabeledContent("Node", value: "内置 arm64 运行时")
                LabeledContent("协议", value: "typeless-switch-core 1.0")
                LabeledContent("架构", value: "Apple Silicon (arm64)")
            }
            .textSelection(.enabled)
            .padding(.vertical, 6)
        }
    }

    private var advancedHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("高级功能")
                .font(.title2.bold())
            Text("这些操作会修改 Typeless 或本机身份。执行前会自动备份并要求再次确认。")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
