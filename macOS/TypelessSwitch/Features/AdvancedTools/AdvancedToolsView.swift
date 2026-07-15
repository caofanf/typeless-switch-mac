import SwiftUI

struct AdvancedSettingsContent: View {
    @Bindable var model: AppModel
    private let fileDialogs = FileDialogService()

    private var advancedTask: CoreTask? {
        model.activeTasks.last { $0.type == "device-reset" || $0.type == "patch" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            versionSection
            patchSection
            resetSection
            dataSection
            if let advancedTask { taskSection(advancedTask) }
            if let message = model.lastErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await model.refreshAdvancedTools()
            if model.diagnosticReport == nil { await model.runDiagnostics() }
        }
        .sheet(isPresented: advancedConfirmationPresented) {
            if let pending = model.pendingAdvancedOperation {
                OperationConfirmationView(
                    confirmation: pending.confirmation,
                    defaultTitle: pending.kind.title,
                    confirmTitle: pending.kind.confirmTitle,
                    isDestructive: true,
                    isPerforming: model.isPerformingAdvancedOperation,
                    detailRows: [],
                    onCancel: { model.cancelPendingAdvancedOperation() },
                    onConfirm: {
                        Task {
                            switch pending.kind {
                            case .deviceReset: await model.confirmDeviceReset()
                            case .patch: await model.confirmPatchApplication()
                            }
                        }
                    }
                )
            }
        }
    }

    private var advancedConfirmationPresented: Binding<Bool> {
        Binding(get: { model.pendingAdvancedOperation != nil }, set: { if !$0, model.pendingAdvancedOperation != nil { model.cancelPendingAdvancedOperation() } })
    }

    private var versionSection: some View {
        GroupBox("版本漂移") {
            VStack(alignment: .leading, spacing: 12) {
                StatusView(
                    title: model.advancedVersionStatus?.drifted == true ? "检测到版本变化" : "版本状态正常",
                    detail: model.advancedVersionStatus?.current ?? "尚未检测",
                    tone: model.advancedVersionStatus?.drifted == true ? .attention : .good
                )
                if let last = model.advancedVersionStatus?.lastSeen { LabeledContent("上次确认版本", value: last) }
                Button("确认当前版本") { Task { await model.acknowledgeCurrentVersion() } }
                    .disabled(model.advancedVersionStatus?.current == nil)
            }
            .padding(.vertical, 6)
        }
    }

    private var patchSection: some View {
        GroupBox("Typeless 补丁") {
            VStack(alignment: .leading, spacing: 12) {
                StatusView(title: patchTitle, detail: model.advancedPatchStatus?.detectedFile, tone: patchTone)
                if model.advancedPatchStatus?.hasBackup == true {
                    Label("已找到原始文件备份", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                }
                Button("应用补丁…") { Task { await model.preparePatchApplication(action: "apply") } }
                    .disabled(model.advancedPatchStatus?.exists != true || model.isPerformingAdvancedOperation)
            }
            .padding(.vertical, 6)
        }
    }

    private var resetSection: some View {
        GroupBox("设备标识") {
            VStack(alignment: .leading, spacing: 12) {
                Label("重置会改变 Typeless 识别本机的方式，并可能影响当前会话。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let connection = model.deviceStatus?.connection {
                    LabeledContent("管理连接", value: connection.state.rawValue)
                }
                Button("重置设备标识…", role: .destructive) { Task { await model.prepareDeviceReset() } }
                    .disabled(model.isPerformingAdvancedOperation)
            }
            .padding(.vertical, 6)
        }
    }

    private var dataSection: some View {
        GroupBox("工具包数据") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.diagnosticReport?.data.directory ?? "尚未获取数据目录")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Text("账号、快照、词库和运行时备份保存在此目录。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("在 Finder 中打开") {
                    if let path = model.diagnosticReport?.data.directory { fileDialogs.openDirectory(path: path) }
                }
                .disabled(model.diagnosticReport?.data.directory.isEmpty != false)
            }
            .padding(.vertical, 6)
        }
    }

    private func taskSection(_ task: CoreTask) -> some View {
        GroupBox("高级操作任务") {
            VStack(alignment: .leading, spacing: 10) {
                StatusView(title: task.type == "patch" ? "补丁任务" : "设备重置任务", detail: task.progress?.message, tone: task.state == .failed ? .critical : (task.state == .succeeded ? .good : .progress))
                if let fraction = task.progress?.fractionCompleted { ProgressView(value: fraction) }
                if task.state == .queued || task.state == .running {
                    HStack {
                        Button("取消任务") { Task { await model.cancelTask(id: task.id) } }.disabled(!task.cancellable)
                        if !task.cancellable {
                            Label("事务已经提交，为避免数据损坏无法取消。", systemImage: "lock.fill")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var patchTitle: String {
        guard let status = model.advancedPatchStatus else { return "尚未检测" }
        if let error = status.error { return error }
        return status.patched == true ? "补丁已应用" : (status.exists ? "可以应用补丁" : "未找到目标文件")
    }
    private var patchTone: StatusTone {
        guard let status = model.advancedPatchStatus else { return .neutral }
        if status.error != nil { return .critical }
        return status.patched == true ? .good : (status.exists ? .attention : .critical)
    }
}

extension AdvancedOperationKind {
    fileprivate var title: String { switch self { case .deviceReset: "重置设备标识"; case .patch: "应用 Typeless 补丁" } }
    fileprivate var confirmTitle: String { switch self { case .deviceReset: "重置"; case .patch: "应用补丁" } }
}

struct OperationConfirmationView: View {
    let confirmation: Confirmation
    let defaultTitle: String
    let confirmTitle: String
    let isDestructive: Bool
    let isPerforming: Bool
    let detailRows: [(String, String)]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var summary: [String: JSONValue] { confirmation.summary.objectValue ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30)).foregroundStyle(isDestructive ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary["title"]?.stringValue ?? defaultTitle).font(.title2.weight(.semibold))
                    Text(summary["message"]?.stringValue ?? "请核对操作影响后继续。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !detailRows.isEmpty {
                GroupBox {
                    ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1).textSelection(.enabled)
                    }
                }
            }
            Label("此操作会在提交前创建安全备份；事务提交后将无法取消。", systemImage: "externaldrive.badge.timemachine")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction).disabled(isPerforming)
                Button(confirmTitle, role: isDestructive ? .destructive : nil, action: onConfirm)
                    .keyboardShortcut(.defaultAction).disabled(isPerforming)
            }
        }
        .padding(24).frame(width: 480)
        .overlay { if isPerforming { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) } }
    }
}
