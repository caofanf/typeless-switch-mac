import SwiftUI

struct MasterDictionaryView: View {
    @Bindable var model: AppModel
    @State private var selection = Set<String>()
    @State private var editorText = ""
    @State private var isPresentingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .searchable(text: $model.masterDictionarySearchText, prompt: "搜索主词库")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editorText = model.masterDictionary.words.joined(separator: "\n")
                    isPresentingEditor = true
                } label: {
                    Label("编辑主词库", systemImage: "square.and.pencil")
                }
                Button {
                    Task { await model.syncAllDictionaries() }
                } label: {
                    Label("同步所有账号", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task { await model.refreshMasterDictionary() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshingMasterDictionary)
            }
        }
        .task { await model.refreshMasterDictionary() }
        .sheet(isPresented: $isPresentingEditor) { replacementEditor }
        .sheet(item: Binding(
            get: { model.pendingMasterReplacement },
            set: { if $0 == nil { model.cancelMasterReplacement() } }
        )) { pending in
            MasterReplacementConfirmationSheet(
                pending: pending,
                isPerforming: model.isReplacingMasterDictionary,
                onCancel: model.cancelMasterReplacement,
                onConfirm: { Task { await model.confirmMasterReplacement() } }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("主词库")
                    .font(.title2.weight(.semibold))
                Text("集中维护词条，并按账号边界安全同步。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.masterDictionary.words.count) 条")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        if model.isRefreshingMasterDictionary && model.masterDictionary.words.isEmpty {
            ProgressView("正在读取主词库…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.filteredMasterDictionaryWords.isEmpty {
            EmptyStateView(
                title: model.masterDictionarySearchText.isEmpty ? "主词库为空" : "没有匹配的词条",
                message: model.masterDictionarySearchText.isEmpty ? "编辑主词库以添加第一批词条。" : "尝试更换搜索关键词。",
                systemImage: "text.book.closed"
            )
        } else {
            VStack(spacing: 0) {
                Table(model.filteredMasterDictionaryWords.map(MasterDictionaryRow.init), selection: $selection) {
                    TableColumn("词条") { row in
                        Text(row.term).textSelection(.enabled)
                    }
                }
                syncProgress
            }
        }
    }

    @ViewBuilder
    private var syncProgress: some View {
        if let task = model.activeTasks.first(where: { $0.type == "sync-all" || $0.type == "dictionaries.syncAll" }) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.progress?.message ?? "正在同步所有账号")
                        .font(.callout.weight(.medium))
                    if let fraction = task.progress?.fractionCompleted {
                        ProgressView(value: fraction).frame(maxWidth: 280)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let notice = model.taskCancellationNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("取消同步") { Task { await model.cancelTask(id: task.id) } }
                    .disabled(!task.cancellable)
            }
            .padding(16)
            .background(.bar)
        }
    }

    private var replacementEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑主词库")
                .font(.title2.weight(.semibold))
            Text("每行一个词条。空行和重复项会自动移除，提交前会显示差异摘要。")
                .foregroundStyle(.secondary)
            TextEditor(text: $editorText)
                .font(.body.monospaced())
                .frame(minWidth: 560, minHeight: 360)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                .accessibilityLabel("主词库词条，每行一个")
            HStack {
                Text("整理后 \(model.normalizedDictionaryTerms(from: editorText).count) 条")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { isPresentingEditor = false }
                    .keyboardShortcut(.cancelAction)
                Button("查看更改") {
                    isPresentingEditor = false
                    Task { await model.prepareMasterReplacement(from: editorText) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

private struct MasterDictionaryRow: Identifiable {
    let term: String
    var id: String { term }
}

private struct MasterReplacementConfirmationSheet: View {
    let pending: PendingMasterReplacement
    let isPerforming: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("确认替换主词库", systemImage: pending.diff.removed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(pending.diff.removed.isEmpty ? Color.accentColor : Color.orange)
            Text("写入前请核对差异。主词库只会在核心确认写入成功后更新。")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                DiffMetric(title: "新增", count: pending.diff.added.count, color: .green)
                DiffMetric(title: "移除", count: pending.diff.removed.count, color: .red)
                DiffMetric(title: "保留", count: pending.diff.unchanged.count, color: .secondary)
            }
            GroupBox("更改摘要") {
                VStack(alignment: .leading, spacing: 8) {
                    diffLine("新增", terms: pending.diff.added, color: .green)
                    diffLine("移除", terms: pending.diff.removed, color: .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction).disabled(isPerforming)
                Button("确认替换", role: pending.diff.removed.isEmpty ? nil : .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPerforming)
            }
        }
        .padding(24)
        .frame(width: 520)
        .overlay { if isPerforming { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) } }
    }

    private func diffLine(_ title: String, terms: [String], color: Color) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(color).frame(width: 40, alignment: .leading)
            Text(terms.isEmpty ? "无" : terms.prefix(8).joined(separator: "、"))
                .foregroundStyle(terms.isEmpty ? .secondary : .primary)
                .lineLimit(3)
        }
    }
}

private struct DiffMetric: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(count.formatted()).font(.title2.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}
