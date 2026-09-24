import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var preferences: AppPreferences
    @State private var isAdvancedExpanded = false

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
                    rotationSection
                        .id(SettingsSection.rotation)
                    versionSection

                    Divider()
                        .padding(.vertical, 2)

                    advancedHeader
                        .id(SettingsSection.advanced)

                    if isAdvancedExpanded {
                        AdvancedSettingsContent(model: model)
                    }
                }
                .padding(24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(.background.secondary)
            .task {
                await model.loadRotation()
            }
            .task(id: model.requestedSettingsSection) {
                guard let requestedSection = model.requestedSettingsSection else { return }
                if requestedSection == .advanced {
                    isAdvancedExpanded = true
                }
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

    private var rotationSection: some View {
        GroupBox("账号自动轮动（额度管理）") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("启用按词数自动轮动", isOn: Binding(
                    get: { model.rotationSettings.enabled },
                    set: { enabled in
                        var next = model.rotationSettings
                        next.enabled = enabled
                        Task { await model.updateRotationSettings(next) }
                    }
                ))
                .accessibilityHint("开启后，当本周累计词数达到阈值时自动或提醒切换下一个有效账号。")

                if model.rotationSettings.enabled {
                    Divider()

                    Picker("轮动模式", selection: Binding(
                        get: { model.rotationSettings.mode },
                        set: { mode in
                            var next = model.rotationSettings
                            next.mode = mode
                            Task { await model.updateRotationSettings(next) }
                        }
                    )) {
                        Text("通知提醒 (notify)").tag(RotationMode.notify)
                        Text("自动切号 (auto)").tag(RotationMode.auto)
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("词数阈值")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("词数阈值", value: Binding(
                                    get: { model.rotationSettings.wordThreshold },
                                    set: { val in
                                        var next = model.rotationSettings
                                        next.wordThreshold = max(100, val)
                                        Task { await model.updateRotationSettings(next) }
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                Text("词")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("提前预警词数")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("提前预警", value: Binding(
                                    get: { model.rotationSettings.warningWords },
                                    set: { val in
                                        var next = model.rotationSettings
                                        next.warningWords = max(0, val)
                                        Task { await model.updateRotationSettings(next) }
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                Text("词")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("检查间隔")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("检查间隔", selection: Binding(
                                get: { model.rotationSettings.intervalMinutes },
                                set: { val in
                                    var next = model.rotationSettings
                                    next.intervalMinutes = val
                                    Task { await model.updateRotationSettings(next) }
                                }
                            )) {
                                Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10)
                                Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30)
                                Text("60 分钟").tag(60)
                            }
                            .frame(width: 100)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("轮动状态:")
                                .fontWeight(.medium)
                            Text(model.rotationStatus.phase.displayName)
                                .foregroundStyle(phaseColor(model.rotationStatus.phase))
                            Spacer()
                            Button {
                                Task { await model.triggerRotationCheckNow() }
                            } label: {
                                if model.isRefreshingRotation {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("立即检查", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .disabled(model.isRefreshingRotation)
                        }

                        if let words = model.rotationStatus.usedWords {
                            let threshold = max(1, model.rotationSettings.wordThreshold)
                            ProgressView(
                                value: Double(min(words, threshold)),
                                total: Double(threshold)
                            ) {
                                HStack {
                                    Text("当前账号已用: \(words) / \(threshold) 词")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(Double(words) / Double(threshold) * 100))%")
                                        .font(.caption)
                                }
                            }
                        }

                        Text(model.rotationStatus.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let issue = model.rotationStatus.issue {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .padding(8)
                            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func phaseColor(_ phase: RotationPhase) -> Color {
        switch phase {
        case .disabled: return .secondary
        case .waiting: return .green
        case .checking: return .blue
        case .prompting: return .orange
        case .switching: return .purple
        case .paused: return .secondary
        case .error: return .red
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
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAdvancedExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isAdvancedExpanded ? "chevron.down" : "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("高级功能")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("这些操作会修改 Typeless 或本机身份。执行前会自动备份并要求再次确认。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isAdvancedExpanded ? "收起" : "展开")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
