import SwiftUI

struct AccountsView: View {
    @Bindable var model: AppModel
    @State private var showingAddAccount = false

    var body: some View {
        HSplitView {
            accountList
                .frame(minWidth: AppLayout.accountListMinimumWidth, idealWidth: 280, maxWidth: 340)

            detail
                .frame(minWidth: AppLayout.accountDetailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddAccount = true
                } label: {
                    Label("添加账号", systemImage: "person.badge.plus")
                }
                .help("从当前登录的 Typeless 抓取并保存账号")

                Button {
                    Task { await model.refreshAccounts() }
                } label: {
                    Label("刷新账号", systemImage: "arrow.clockwise")
                }
                .help("刷新账号列表")
            }
        }
        .sheet(isPresented: $showingAddAccount, onDismiss: model.dismissAddAccount) {
            AddAccountSheet(model: model) {
                showingAddAccount = false
            }
        }
        .sheet(item: Binding(
            get: { model.pendingAccountOperation },
            set: { if $0 == nil { model.cancelPendingAccountOperation() } }
        )) { operation in
            ConfirmationSheet(
                operation: operation,
                isPerforming: model.isPerformingAccountOperation,
                onCancel: model.cancelPendingAccountOperation,
                onConfirm: { Task { await model.confirmPendingAccountOperation() } }
            )
        }
        .task {
            if model.accounts.isEmpty {
                await model.refreshAccounts()
            }
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            if model.rotationSettings.enabled {
                rotationBanner
            }

            List(model.filteredAccounts, selection: $model.selectedAccountID) { account in
                AccountRow(
                    account: account,
                    isRotationActive: account.id == model.rotationStatus.currentUserId
                )
                    .tag(account.id)
                    .contextMenu {
                        Button("保存快照") {
                            Task { await model.saveSnapshot(accountID: account.id) }
                        }
                        Button("切换到此账号") {
                            Task { await model.prepareSwitchAccount(accountID: account.id) }
                        }
                        .disabled(!account.hasSnapshot)
                        Divider()
                        Menu("删除账号") {
                            Button("仅删除账号记录", role: .destructive) {
                                Task { await model.prepareDeleteAccount(accountID: account.id, deleteSnapshot: false) }
                            }
                            Button("删除账号和快照", role: .destructive) {
                                Task { await model.prepareDeleteAccount(accountID: account.id, deleteSnapshot: true) }
                            }
                        }
                    }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.accountSearchText, placement: .sidebar, prompt: "搜索账号")

            if model.accounts.isEmpty {
                EmptyStateView(
                    title: "还没有账号",
                    message: "添加当前登录的 Typeless 账号后，可在这里管理快照和词库。",
                    systemImage: "person.crop.circle.badge.plus",
                    actionTitle: "添加账号",
                    action: { showingAddAccount = true }
                )
                .padding()
            }
        }
        .background(.background)
    }

    private var rotationBanner: some View {
        Button {
            model.navigateToRotationSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("自动轮动")
                            .font(.caption.bold())
                        Text("· \(model.rotationStatus.phase.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let words = model.rotationStatus.usedWords {
                        Text("当前已用: \(words) / \(model.rotationSettings.wordThreshold) 词")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedAccountID,
           let account = model.accounts.first(where: { $0.id == id }) {
            AccountDetailView(account: account, model: model)
        } else {
            EmptyStateView(
                title: "选择一个账号",
                message: "查看账号状态、保存本地快照或切换 Typeless 登录态。",
                systemImage: "person.text.rectangle"
            )
        }
    }
}

private struct AccountRow: View {
    let account: Account
    var isRotationActive: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                if isRotationActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(account.nickname.isEmpty ? "未命名账号" : account.nickname)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isRotationActive {
                        Text("当前")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }
                }
                Text(account.email.isEmpty ? account.id : account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: account.hasSnapshot ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark")
                .foregroundStyle(account.hasSnapshot ? Color.green : Color.secondary)
                .help(account.hasSnapshot ? "已有本地快照" : "没有本地快照")
                .accessibilityLabel(account.hasSnapshot ? "已有本地快照" : "没有本地快照")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
