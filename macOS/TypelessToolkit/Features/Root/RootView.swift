import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $model.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Typeless Toolkit")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            destinationView
                .navigationTitle(model.selection.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.refreshOverview() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(model.isRefreshing)
                        .help("刷新当前状态")
                    }
                }
        }
        .task { await model.refreshOverview() }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.selection {
        case .overview:
            OverviewPlaceholder(model: model)
        case .accounts:
            PlaceholderView(title: "账号", message: "管理 Typeless 账号与本地快照。", systemImage: "person.2")
        case .masterDictionary:
            PlaceholderView(title: "主词库", message: "维护并同步跨账号使用的主词库。", systemImage: "text.book.closed")
        case .backupRestore:
            PlaceholderView(title: "备份与恢复", message: "创建、导出、检查和恢复工具包数据。", systemImage: "externaldrive.badge.timemachine")
        case .diagnostics:
            PlaceholderView(title: "诊断", message: "检查 Typeless、连接和本地数据状态。", systemImage: "stethoscope")
        case .advancedTools:
            PlaceholderView(title: "高级工具", message: "谨慎使用设备重置、补丁和版本工具。", systemImage: "wrench.and.screwdriver")
        case .settings:
            PlaceholderView(title: "设置", message: "调整启动、窗口和菜单栏行为。", systemImage: "gearshape")
        }
    }
}

private struct OverviewPlaceholder: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: connectionSymbol)
                .font(.system(size: 36))
                .foregroundStyle(connectionColor)
                .accessibilityHidden(true)
            Text("Typeless Toolkit")
                .font(.title2.weight(.semibold))
            Text(connectionDescription)
                .foregroundStyle(.secondary)
            if let error = model.lastErrorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
    }

    private var connectionSymbol: String {
        model.connectionState == .connected ? "checkmark.circle.fill" : "bolt.horizontal.circle"
    }

    private var connectionColor: Color {
        model.connectionState == .connected ? .green : .secondary
    }

    private var connectionDescription: String {
        switch model.connectionState {
        case .disconnected: "尚未建立 Typeless 管理连接"
        case .connecting: "正在建立 Typeless 管理连接…"
        case .connected: "Typeless 管理连接正常"
        case .degraded: "连接状态异常，请运行诊断"
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RootViewPreview: PreviewProvider {
    static var previews: some View {
        RootView(model: AppModel(coreClient: UnavailableCoreClient()))
            .frame(width: 1100, height: 720)
    }
}
