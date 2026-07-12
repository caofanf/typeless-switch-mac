import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if model.isStale {
                    staleBanner
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    connectionCard
                    accountsCard
                    backupCard
                    versionCard
                }

                tasksSection
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(.background.secondary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("概览")
                .font(.largeTitle.bold())
            Text("集中查看 Typeless 账号、管理连接、备份和版本状态。")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("显示的是上次成功获取的状态")
                    .fontWeight(.medium)
                Text(model.lastErrorMessage ?? "暂时无法联系核心服务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("重试") {
                Task { await model.refreshOverview() }
            }
            .disabled(model.isRefreshing)
        }
        .padding(12)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var connectionCard: some View {
        OverviewCard(title: "管理连接", systemImage: "bolt.horizontal.circle") {
            StatusView(
                title: connectionTitle,
                detail: model.overview.connection.cdpReachable ? "端口 \(model.overview.connection.port)" : nil,
                tone: connectionTone
            )
            Spacer(minLength: 14)
            Button(model.connectionState == .connected ? "重新连接" : "建立连接") {
                Task { await model.establishConnection() }
            }
            .disabled(model.connectionState == .connecting)
            .accessibilityHint("启动或重新建立与 Typeless 的本机管理连接")
        }
    }

    private var accountsCard: some View {
        OverviewCard(title: "账号", systemImage: "person.2") {
            HStack(alignment: .firstTextBaseline) {
                Text(model.overview.accountCount, format: .number)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text("个已保存账号")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            Button("查看账号") { model.selection = .accounts }
        }
    }

    private var backupCard: some View {
        OverviewCard(title: "数据保护", systemImage: "externaldrive.badge.timemachine") {
            StatusView(title: backupTitle, detail: backupDetail, tone: backupTone)
            Spacer(minLength: 14)
            Button("备份与恢复") { model.selection = .backupRestore }
        }
    }

    private var versionCard: some View {
        OverviewCard(title: "Typeless 版本", systemImage: "shippingbox") {
            StatusView(title: versionTitle, detail: model.overview.version.current, tone: versionTone)
            Spacer(minLength: 14)
            if model.overview.version.drifted {
                Button("查看高级工具") { model.selection = .advancedTools }
            }
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("正在进行")
                    .font(.title2.bold())
                Spacer()
                if !model.activeTasks.isEmpty {
                    Text("\(model.activeTasks.count) 项任务")
                        .foregroundStyle(.secondary)
                }
            }

            if model.activeTasks.isEmpty {
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Text("当前没有正在运行的任务")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            } else {
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(model.activeTasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(task: task)
                            if index < model.activeTasks.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var connectionTitle: String {
        switch model.connectionState {
        case .disconnected: "未连接"
        case .connecting: "正在连接"
        case .connected: "连接正常"
        case .degraded: "连接异常"
        }
    }

    private var connectionTone: StatusTone {
        switch model.connectionState {
        case .disconnected: .neutral
        case .connecting: .progress
        case .connected: .good
        case .degraded: .critical
        }
    }

    private var backupTitle: String {
        switch model.overview.backup.status {
        case .noData: "暂无数据"
        case .backedUp: "已备份"
        case .needsBackup: "建议创建备份"
        }
    }

    private var backupDetail: String? {
        model.overview.backup.latestBackup?.modifiedAt?.formatted(date: .abbreviated, time: .shortened)
    }

    private var backupTone: StatusTone {
        switch model.overview.backup.status {
        case .noData: .neutral
        case .backedUp: .good
        case .needsBackup: .attention
        }
    }

    private var versionTitle: String {
        if model.overview.version.drifted { return "检测到版本变化" }
        return model.overview.version.current == nil ? "尚未检测" : "版本一致"
    }

    private var versionTone: StatusTone {
        model.overview.version.drifted ? .attention : (model.overview.version.current == nil ? .neutral : .good)
    }
}

private struct OverviewCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private struct TaskRow: View {
    let task: CoreTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.type)
                    .fontWeight(.medium)
                if let message = task.progress?.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let fraction = task.progress?.fractionCompleted {
                    ProgressView(value: fraction)
                        .accessibilityLabel("任务进度")
                }
            }
            Spacer()
            Text(task.state.label)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

private extension CoreTaskState {
    var label: String {
        switch self {
        case .queued: "等待中"
        case .running: "进行中"
        case .succeeded: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
}
