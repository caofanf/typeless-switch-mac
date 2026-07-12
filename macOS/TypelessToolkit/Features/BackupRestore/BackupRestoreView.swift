import SwiftUI

struct BackupRestoreView: View {
    @Bindable var model: AppModel
    private let fileDialogs = FileDialogService()

    private var restoreTask: CoreTask? {
        model.activeTasks.last { $0.type == "backup-restore" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let message = model.lastErrorMessage { errorBanner(message) }
                backupCard
                restoreCard
                if let restoreTask { restoreProgress(task: restoreTask) }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(.background.secondary)
        .task { await model.refreshBackupStatus() }
        .sheet(isPresented: restoreConfirmationPresented) {
            if let pending = model.pendingBackupRestore {
                OperationConfirmationView(
                    confirmation: pending.confirmation,
                    defaultTitle: "恢复备份",
                    confirmTitle: "恢复",
                    isDestructive: true,
                    isPerforming: model.backupRestorePhase == .restoring,
                    detailRows: [("检查标识", pending.inspection.inspectionID)],
                    onCancel: { model.cancelBackupRestoreConfirmation() },
                    onConfirm: { Task { await model.confirmBackupRestore() } }
                )
            }
        }
    }

    private var restoreConfirmationPresented: Binding<Bool> {
        Binding(
            get: { model.pendingBackupRestore != nil },
            set: { if !$0, model.pendingBackupRestore != nil { model.cancelBackupRestoreConfirmation() } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("备份与恢复").font(.largeTitle.bold())
            Text("保护工具包数据，并在恢复前检查备份的完整性与身份。")
                .foregroundStyle(.secondary)
        }
    }

    private var backupCard: some View {
        GroupBox("当前数据保护") {
            VStack(alignment: .leading, spacing: 14) {
                StatusView(title: backupStatusTitle, detail: backupStatusDetail, tone: backupStatusTone)
                Divider()
                HStack {
                    Button {
                        Task { await model.createBackup() }
                    } label: {
                        Label("立即备份", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(model.isCreatingBackup)

                    Button {
                        guard let url = fileDialogs.chooseBackupExportDestination(defaultName: defaultExportName) else { return }
                        Task { await model.exportBackup(to: url.path) }
                    } label: {
                        Label("导出备份…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.isExportingBackup)

                    if model.isCreatingBackup || model.isExportingBackup { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if let path = model.exportedBackupPath {
                    Button("在 Finder 中显示已导出的备份") { fileDialogs.revealInFinder(path: path) }
                        .buttonStyle(.link)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var restoreCard: some View {
        GroupBox("检查并恢复") {
            VStack(alignment: .leading, spacing: 14) {
                Label("备份文件只会传递给内置核心检查；SwiftUI 界面不会解析账号令牌、Cookie 或 profile。", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if model.requiresBackupReinspection {
                    Label("文件在检查后发生变化，必须重新检查后才能恢复。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let inspection = model.pendingBackupInspection {
                    inspectionSummary(inspection)
                } else if model.backupRestorePhase == .inspecting {
                    ProgressView("正在检查备份…")
                }

                HStack {
                    Button {
                        model.beginBackupSelection()
                        guard let url = fileDialogs.chooseBackupForImport() else { return }
                        Task { await model.inspectBackup(at: url.path) }
                    } label: {
                        Label(model.pendingBackupInspection == nil ? "选择备份…" : "重新选择…", systemImage: "doc.badge.magnifyingglass")
                    }
                    .disabled(model.backupRestorePhase == .inspecting || model.backupRestorePhase == .restoring)

                    if model.pendingBackupInspection != nil && !model.requiresBackupReinspection {
                        Button("审阅并恢复…") { Task { await model.prepareBackupRestore() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.backupRestorePhase == .preparingConfirmation)
                    }
                    Spacer()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func inspectionSummary(_ inspection: BackupInspection) -> some View {
        VStack(spacing: 8) {
            LabeledContent("备份格式", value: inspection.summary.type)
            LabeledContent("格式版本", value: inspection.summary.version.formatted())
            LabeledContent("创建时间", value: inspection.summary.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")
            LabeledContent("文件数量", value: inspection.summary.fileCount.formatted())
            LabeledContent("备份大小", value: ByteCountFormatter.string(fromByteCount: Int64(inspection.summary.size), countStyle: .file))
            LabeledContent("检查有效期") { Text(inspection.expiresAt, style: .relative) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .textSelection(.enabled)
    }

    private func restoreProgress(task: CoreTask) -> some View {
        GroupBox("恢复任务") {
            VStack(alignment: .leading, spacing: 10) {
                StatusView(title: task.state.labelText, detail: task.progress?.message, tone: task.state.statusTone)
                if let fraction = task.progress?.fractionCompleted { ProgressView(value: fraction) }
                else if task.state == .queued || task.state == .running { ProgressView() }

                HStack {
                    if task.state == .queued || task.state == .running {
                        Button("取消任务") { Task { await model.cancelTask(id: task.id) } }
                            .disabled(!task.cancellable)
                    }
                    if !task.cancellable && (task.state == .queued || task.state == .running) {
                        Label("事务已经提交，为避免数据损坏无法取消。", systemImage: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var backupStatusTitle: String {
        switch model.backupStatus.status {
        case .noData: "暂无需要备份的数据"
        case .backedUp: "数据已备份"
        case .needsBackup: "建议创建新备份"
        }
    }

    private var backupStatusDetail: String? { model.backupStatus.latestBackup?.modifiedAt?.formatted(date: .abbreviated, time: .shortened) }
    private var backupStatusTone: StatusTone { model.backupStatus.status == .backedUp ? .good : (model.backupStatus.status == .needsBackup ? .attention : .neutral) }
    private var defaultExportName: String { "typeless-toolkit-backup-\(Date().formatted(.iso8601.year().month().day())).json" }
}

private extension CoreTaskState {
    var labelText: String {
        switch self { case .queued: "等待恢复"; case .running: "正在恢复"; case .succeeded: "恢复完成"; case .failed: "恢复失败"; case .cancelled: "恢复已取消" }
    }
    var statusTone: StatusTone {
        switch self { case .queued: .neutral; case .running: .progress; case .succeeded: .good; case .failed: .critical; case .cancelled: .attention }
    }
}
