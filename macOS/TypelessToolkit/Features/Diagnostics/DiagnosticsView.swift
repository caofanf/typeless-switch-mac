import AppKit
import SwiftUI

enum DiagnosticCheckState {
    case waiting, running, passed, warning, failed

    var label: String {
        switch self { case .waiting: "等待"; case .running: "进行中"; case .passed: "通过"; case .warning: "警告"; case .failed: "失败" }
    }
    var tone: StatusTone {
        switch self { case .waiting: .neutral; case .running: .progress; case .passed: .good; case .warning: .attention; case .failed: .critical }
    }
}

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GroupBox("检查结果") {
                    VStack(spacing: 0) {
                        diagnosticRow("Typeless 应用", detail: typelessDetail, state: typelessState)
                        Divider()
                        diagnosticRow("管理连接", detail: connectionDetail, state: connectionState)
                        Divider()
                        diagnosticRow("工具包数据目录", detail: dataDetail, state: dataState)
                        Divider()
                        diagnosticRow("运行时备份", detail: backupDetail, state: backupState)
                        Divider()
                        diagnosticRow("Typeless 版本", detail: versionDetail, state: versionState)
                        Divider()
                        diagnosticRow("应用补丁", detail: patchDetail, state: patchState)
                    }
                }

                if let message = model.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(.background.secondary)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("诊断").font(.largeTitle.bold())
                Text("检查安装、连接、数据保护和版本状态。诊断摘要不包含秘密数据。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                copySummary()
            } label: {
                Label(copied ? "已复制" : "复制摘要", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(model.diagnosticReport == nil)
            Button {
                Task { await model.runDiagnostics() }
            } label: {
                Label(model.isRunningDiagnostics ? "正在诊断" : "运行诊断", systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRunningDiagnostics)
        }
    }

    private func diagnosticRow(_ title: String, detail: String, state: DiagnosticCheckState) -> some View {
        HStack(spacing: 14) {
            StatusView(title: title, detail: detail, tone: state.tone)
            Spacer()
            Text(state.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(state.tone.color)
        }
        .padding(.vertical, 12)
    }

    private var defaultState: DiagnosticCheckState { model.isRunningDiagnostics ? .running : (model.diagnosticReport == nil ? .waiting : .passed) }
    private var typelessState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.typeless.appFound ? .passed : .failed }
    private var connectionState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.cdp.reachable ? .passed : .warning }
    private var dataState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.data.writable ? .passed : .failed }
    private var backupState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.backup.status == .needsBackup ? .warning : .passed }
    private var versionState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.version.drifted ? .warning : .passed }
    private var patchState: DiagnosticCheckState { guard let r = model.diagnosticReport else { return defaultState }; return r.patch.error == nil ? (r.patch.exists ? .passed : .warning) : .failed }

    private var typelessDetail: String { model.diagnosticReport.map { $0.typeless.appFound ? $0.typeless.appPath : "未找到应用" } ?? "尚未检查" }
    private var connectionDetail: String { model.diagnosticReport.map { $0.cdp.reachable ? "端口 \($0.cdp.port) 可达" : "端口 \($0.cdp.port) 不可达" } ?? "尚未检查" }
    private var dataDetail: String { model.diagnosticReport.map { $0.data.writable ? "可写 · \($0.data.accountCount) 个账号" : "目录不可写" } ?? "尚未检查" }
    private var backupDetail: String { model.diagnosticReport.map { $0.backup.status == .needsBackup ? "数据有更新" : "状态正常" } ?? "尚未检查" }
    private var versionDetail: String { model.diagnosticReport.map { $0.version.current ?? "未检测到版本" } ?? "尚未检查" }
    private var patchDetail: String { model.diagnosticReport.map { $0.patch.error ?? ($0.patch.patched == true ? "已应用" : "未应用") } ?? "尚未检查" }

    private func copySummary() {
        guard let report = model.diagnosticReport else { return }
        let migration = report.data.migration.objectValue?["status"]?.stringValue ?? "unknown"
        let summary = """
        Typeless Toolkit 诊断摘要
        Typeless App: \(report.typeless.appFound ? "found" : "missing")
        CDP: \(report.cdp.state.rawValue), port=\(report.cdp.port), reachable=\(report.cdp.reachable)
        Data: writable=\(report.data.writable), accounts=\(report.data.accountCount), migration=\(migration)
        Backup: \(report.backup.status.rawValue)
        Version: current=\(report.version.current ?? "unknown"), drifted=\(report.version.drifted)
        Patch: exists=\(report.patch.exists), patched=\(report.patch.patched.map(String.init) ?? "unknown")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        copied = true
    }
}
