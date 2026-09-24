import SwiftUI

struct AccountDetailView: View {
    let account: Account
    @Bindable var model: AppModel
    @State private var newDictionaryTerm = ""
    @State private var bulkDictionaryInput = ""
    @State private var isPresentingBulkImport = false
    @State private var wordPendingDeletion: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                identitySection
                usageSection
                snapshotSection
                dictionarySection
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: account.id) { await model.refreshAccountDictionary(accountID: account.id) }
        .sheet(isPresented: $isPresentingBulkImport) { bulkImportSheet }
        .confirmationDialog(
            "删除词条？",
            isPresented: Binding(
                get: { wordPendingDeletion != nil },
                set: { if !$0 { wordPendingDeletion = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                guard let term = wordPendingDeletion else { return }
                wordPendingDeletion = nil
                Task { await model.deleteDictionaryWord(term, accountID: account.id) }
            }
            Button("取消", role: .cancel) { wordPendingDeletion = nil }
        } message: {
            Text("删除请求确认成功后，列表会从远端重新读取。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.nickname.isEmpty ? "未命名账号" : account.nickname)
                    .font(.largeTitle.weight(.semibold))
                Text(account.email.isEmpty ? account.id : account.email)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Menu {
                Button("仅删除账号记录", role: .destructive) {
                    Task { await model.prepareDeleteAccount(accountID: account.id, deleteSnapshot: false) }
                }
                Button("删除账号和快照", role: .destructive) {
                    Task { await model.prepareDeleteAccount(accountID: account.id, deleteSnapshot: true) }
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var identitySection: some View {
        GroupBox("账号信息") {
            VStack(spacing: 10) {
                LabeledContent("账号 ID", value: account.id)
                    .textSelection(.enabled)
                Divider()
                LabeledContent("套餐", value: account.role.isEmpty ? "未知" : account.role)
                Divider()
                LabeledContent("Token 状态") {
                    StatusView(
                        title: tokenTitle,
                        detail: tokenDetail,
                        tone: tokenTone
                    )
                }
                if let capturedAt = account.capturedAt {
                    Divider()
                    LabeledContent("最近抓取") {
                        Text(capturedAt, style: .relative)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var usageSection: some View {
        GroupBox("用量与个性化") {
            if let usage = account.live?.usage {
                VStack(spacing: 10) {
                    LabeledContent("本周字数", value: formattedWeeklyUsage(usage))
                    if model.rotationSettings.enabled {
                        Divider()
                        LabeledContent("轮动配额") {
                            let threshold = model.rotationSettings.wordThreshold
                            let weeklyWords = Int(usage.weeklyWordUsage ?? 0)
                            HStack(spacing: 6) {
                                Text("\(weeklyWords) / \(threshold) 词")
                                if weeklyWords >= threshold {
                                    Text("已达上限").font(.caption).foregroundStyle(.red)
                                } else if weeklyWords >= (threshold - model.rotationSettings.warningWords) {
                                    Text("即将达标").font(.caption).foregroundStyle(.orange)
                                } else {
                                    Text("正常").font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    Divider()
                    LabeledContent("累计字数", value: formattedNumber(usage.totalWords))
                    Divider()
                    LabeledContent("节省时间", value: formattedMinutes(usage.minutesSaved))
                    Divider()
                    LabeledContent("平均速度", value: formattedWPM(usage.averageWordsPerMinute))
                }
                .padding(.vertical, 4)
            } else {
                Text("连接 Typeless 后可查看套餐用量和个性化状态。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
    }

    private var snapshotSection: some View {
        GroupBox("本地登录快照") {
            HStack(alignment: .center, spacing: 16) {
                StatusView(
                    title: account.hasSnapshot ? "快照可用" : "尚未保存快照",
                    detail: snapshotDetail,
                    tone: account.hasSnapshot ? .good : .attention
                )
                Spacer()
                Button("保存快照") {
                    Task { await model.saveSnapshot(accountID: account.id) }
                }
                Button("切换到此账号") {
                    Task { await model.prepareSwitchAccount(accountID: account.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!account.hasSnapshot)
                .help(account.hasSnapshot ? "恢复快照并重新启动 Typeless" : "请先保存快照")
            }
            .padding(.vertical, 6)
        }
    }

    private var dictionarySection: some View {
        GroupBox("个人词库") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("添加一个词条", text: $newDictionaryTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addSingleDictionaryTerm() }
                    Button("添加") { addSingleDictionaryTerm() }
                        .disabled(newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWritingDictionary)
                    Button("批量添加…") { isPresentingBulkImport = true }
                    Button { Task { await model.syncAccountDictionary(accountID: account.id) } } label: {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if let task = model.dictionaryTask(for: account.id) {
                    HStack(spacing: 10) {
                        if let fraction = task.progress?.fractionCompleted {
                            ProgressView(value: fraction).frame(width: 150)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Text(task.progress?.message ?? "正在同步个人词库")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("取消") { Task { await model.cancelTask(id: task.id) } }
                            .disabled(!task.cancellable)
                    }
                }

                TextField("搜索词条", text: $model.dictionarySearchText)
                    .textFieldStyle(.roundedBorder)

                if model.isRefreshingDictionary && model.accountDictionary == nil {
                    ProgressView("正在读取个人词库…")
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if model.filteredAccountDictionaryWords.isEmpty {
                    ContentUnavailableView(
                        model.dictionarySearchText.isEmpty ? "个人词库为空" : "没有匹配的词条",
                        systemImage: "text.book.closed",
                        description: Text(model.dictionarySearchText.isEmpty ? "添加单个词条或批量粘贴。" : "尝试更换搜索关键词。")
                    )
                    .frame(minHeight: 150)
                } else {
                    List(model.filteredAccountDictionaryWords) { word in
                        HStack {
                            Text(word.term).textSelection(.enabled)
                            Spacer()
                            if word.auto {
                                Text("自动").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) { wordPendingDeletion = word.term } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("删除“\(word.term)”")
                        }
                    }
                    .frame(minHeight: 190, maxHeight: 280)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var bulkImportSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("批量添加词条").font(.title2.weight(.semibold))
            Text("每行一个词条。空行和重复项会自动移除。超过 100 条时会转为后台任务。")
                .foregroundStyle(.secondary)
            TextEditor(text: $bulkDictionaryInput)
                .font(.body.monospaced())
                .frame(width: 500, height: 280)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                .accessibilityLabel("批量词条，每行一个")
            HStack {
                Text("整理后 \(model.normalizedDictionaryTerms(from: bulkDictionaryInput).count) 条")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { isPresentingBulkImport = false }.keyboardShortcut(.cancelAction)
                Button("添加") {
                    let input = bulkDictionaryInput
                    isPresentingBulkImport = false
                    bulkDictionaryInput = ""
                    Task { await model.addDictionaryTerms(input, accountID: account.id) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.normalizedDictionaryTerms(from: bulkDictionaryInput).isEmpty)
            }
        }
        .padding(24)
    }

    private func addSingleDictionaryTerm() {
        let input = newDictionaryTerm
        guard !model.normalizedDictionaryTerms(from: input).isEmpty else { return }
        newDictionaryTerm = ""
        Task { await model.addDictionaryTerms(input, accountID: account.id) }
    }

    private var tokenTitle: String {
        guard let valid = account.live?.tokenValid else { return "未检查" }
        return valid ? "有效" : "已失效"
    }

    private var tokenDetail: String? {
        if let days = account.tokenDaysLeft { return days >= 0 ? "约剩余 \(days) 天" : "已过期" }
        return nil
    }

    private var tokenTone: StatusTone {
        guard let valid = account.live?.tokenValid else { return .neutral }
        return valid ? .good : .critical
    }

    private var snapshotDetail: String? {
        account.snapshotModifiedAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
    }

    private func formattedNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func formattedWeeklyUsage(_ usage: AccountUsage) -> String {
        let used = formattedNumber(usage.weeklyWordUsage)
        guard let limit = usage.weeklyWordLimit else { return used }
        return "\(used) / \(formattedNumber(limit))"
    }

    private func formattedMinutes(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) 分钟"
    }

    private func formattedWPM(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) 字/分钟"
    }
}
