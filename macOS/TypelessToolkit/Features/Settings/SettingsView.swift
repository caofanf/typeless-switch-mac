import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                behaviorSection
                notificationsSection
                activitySection
                diagnosticsSection
                accessibilitySection
                versionSection
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置").font(.largeTitle.bold())
            Text("调整窗口、菜单栏、通知和本地活动记录。")
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        GroupBox("App 行为") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("在菜单栏显示状态图标", isOn: $preferences.showsMenuBarExtra)
                    .accessibilityHint("关闭后可通过主窗口继续使用工具包。")
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

    private var activitySection: some View {
        GroupBox("最近活动") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("保留数量", selection: activityLimitBinding) {
                    ForEach(AppPreferences.allowedActivityLimits, id: \.self) { count in
                        Text("\(count) 条").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityValue("保留 \(preferences.recentActivityLimit) 条")

                if model.recentActivities.isEmpty {
                    Label("尚无活动记录", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentActivities.prefix(8)) { activity in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: activity.kind.systemImage).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.title)
                                if let detail = activity.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(activity.occurredAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Button("清空活动记录", role: .destructive) { model.clearRecentActivities() }
                    .disabled(model.recentActivities.isEmpty)
            }
            .padding(.vertical, 6)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("诊断日志") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("日志级别", selection: $preferences.diagnosticLogLevel) {
                    ForEach(DiagnosticLogLevel.allCases) { level in Text(level.title).tag(level) }
                }
                .pickerStyle(.radioGroup)
                Label("调试级别只对当前运行有效；下次启动会自动恢复为信息级别。", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var accessibilitySection: some View {
        GroupBox("辅助功能") {
            VStack(alignment: .leading, spacing: 8) {
                StatusView(title: "减少动态效果", detail: reduceMotion ? "已启用" : "未启用", tone: reduceMotion ? .good : .neutral)
                StatusView(title: "降低透明度", detail: reduceTransparency ? "已启用" : "未启用", tone: reduceTransparency ? .good : .neutral)
                Text("界面使用系统字体、语义色、文字与图标共同表达状态，并遵循系统辅助功能设置。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var versionSection: some View {
        GroupBox("版本") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("App", value: appVersion)
                LabeledContent("核心", value: "随 Sidecar 握手显示")
                LabeledContent("Node", value: "内置 arm64 运行时")
                LabeledContent("协议", value: "typeless-toolkit-core 1.0")
                LabeledContent("架构", value: "Apple Silicon (arm64)")
            }
            .textSelection(.enabled)
            .padding(.vertical, 6)
        }
    }

    private var activityLimitBinding: Binding<Int> {
        Binding(
            get: { preferences.recentActivityLimit },
            set: { model.setRecentActivityLimit($0) }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
