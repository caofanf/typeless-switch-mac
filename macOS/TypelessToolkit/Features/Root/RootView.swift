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
            AccountsView(model: model)
        case .masterDictionary:
            MasterDictionaryView(model: model)
        case .backupRestore:
            BackupRestoreView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model)
        case .advancedTools:
            AdvancedToolsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }

    private func refreshWhileActive() async {
        await model.handleAppBecameActive()
        guard model.preferences.refreshOnActivation else { return }
        let clock = ContinuousClock()
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard !Task.isCancelled, model.preferences.refreshOnActivation else { return }
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
