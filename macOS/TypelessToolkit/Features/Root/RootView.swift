import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

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
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.connectionState != .connected {
                            Button {
                                Task { await model.establishConnection() }
                            } label: {
                                Label("建立连接", systemImage: "bolt.horizontal.circle")
                            }
                            .disabled(model.connectionState == .connecting)
                            .help("建立 Typeless 管理连接")
                        }

                        Button {
                            Task { await model.refreshOverview() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isRefreshing)
                        .help("刷新当前状态（Command-R）")
                    }
                }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshWhileActive()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.selection {
        case .overview:
            OverviewView(model: model)
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

    private func refreshWhileActive() async {
        await model.refreshOverview()
        let clock = ContinuousClock()
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await model.refreshOverview()
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        EmptyStateView(title: title, message: message, systemImage: systemImage)
    }
}

private struct RootViewPreview: PreviewProvider {
    static var previews: some View {
        RootView(model: AppModel(coreClient: UnavailableCoreClient()))
            .frame(width: 1100, height: 720)
    }
}
