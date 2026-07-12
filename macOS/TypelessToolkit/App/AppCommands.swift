import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("工具包") {
            Button("刷新状态") {
                Task { await model.refreshOverview() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRefreshing)

            Button("建立管理连接") {
                Task { await model.establishConnection() }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(model.connectionState == .connecting)

            Divider()

            Button("同步全部词库") {
                Task { await model.syncAllDictionaries() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
