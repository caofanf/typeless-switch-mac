import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 Typeless Switch") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        if model.rotationSettings.enabled {
            Divider()

            if let words = model.rotationStatus.usedWords {
                Text("轮动用量: \(words) / \(model.rotationSettings.wordThreshold) 词")
            }
            Text("轮动状态: \(model.rotationStatus.phase.displayName)")

            Button("立即检查轮动") {
                Task { await model.triggerRotationCheckNow() }
            }
            .disabled(model.isRefreshingRotation)
        }

        Divider()

        Button("刷新状态") {
            Task { await model.refreshOverview() }
        }
        .keyboardShortcut("r")
        .disabled(model.isRefreshing)

        Button("建立管理连接") {
            Task { await model.establishConnection() }
        }
        .disabled(model.connectionState == .connecting)

        Button("同步全部词库") {
            Task { await model.syncAllDictionaries() }
        }

        Divider()

        Button("退出 Typeless Switch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
