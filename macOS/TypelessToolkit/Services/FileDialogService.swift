import AppKit
import UniformTypeIdentifiers

@MainActor
final class FileDialogService {
    func chooseBackupForImport() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择要检查的备份"
        panel.message = "备份内容将由内置核心安全检查，界面不会读取其中的秘密数据。"
        panel.prompt = "检查备份"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseBackupExportDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出工具包备份"
        panel.prompt = "导出"
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func revealInFinder(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openDirectory(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
