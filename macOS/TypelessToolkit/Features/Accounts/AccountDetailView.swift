import SwiftUI

struct AccountDetailView: View {
    let account: Account
    @Bindable var model: AppModel

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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("词条数量")
                        .fontWeight(.medium)
                    Text("当前账号共有 \(account.live?.dictionaryCount ?? 0) 个词条")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("选择账号后在此管理", systemImage: "text.book.closed")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
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
