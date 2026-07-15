import SwiftUI

struct AddAccountSheet: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    @State private var nickname = ""
    @State private var email = ""

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 540, height: 440)
        .onChange(of: model.pendingAccountCapture) { _, capture in
            guard let capture else { return }
            nickname = capture.nickname
            email = capture.email
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.addAccountPhase {
        case .idle:
            intro
        case .establishingConnection:
            progress(title: "正在建立管理连接…", message: "请保持 Typeless 正在运行。")
        case .capturing:
            progress(title: "正在抓取当前账号…", message: "只会向界面返回脱敏后的账号信息。")
        case .reviewing:
            review
        case .saving:
            progress(title: "正在保存账号和本地快照…", message: "请勿退出 Typeless Switch。")
        case .completed:
            completed
        case .failed:
            failed
        }
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 58))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("添加当前 Typeless 账号")
                .font(.title2.weight(.semibold))
            Text("工具包将建立本机管理连接，抓取当前登录账号的脱敏信息，并保存可用于切换账号的本地快照。Token 不会发送给 Swift 界面。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 410)
        }
    }

    private func progress(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("核对账号信息", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text("以下信息可以修改后保存。认证凭据只保留在内置核心中。")
                .foregroundStyle(.secondary)

            Form {
                TextField("昵称", text: $nickname)
                TextField("邮箱", text: $email)
                LabeledContent("账号 ID", value: model.pendingAccountCapture?.userID ?? "—")
                    .textSelection(.enabled)
                LabeledContent("套餐", value: roleText)
            }
            .formStyle(.grouped)
        }
    }

    private var completed: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("账号已添加")
                .font(.title2.weight(.semibold))
            Text("账号信息与本地登录快照已安全保存。")
                .foregroundStyle(.secondary)
        }
    }

    private var failed: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("无法添加账号")
                .font(.title2.weight(.semibold))
            Text(model.lastErrorMessage ?? "请确认 Typeless 已登录并保持运行，然后重试。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("取消", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(model.addAccountPhase == .saving)
            Spacer()
            switch model.addAccountPhase {
            case .idle:
                Button("开始") { Task { await model.beginAddAccount() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .reviewing:
                Button("保存账号") {
                    Task { await model.savePendingAccount(nickname: nickname, email: email) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .completed:
                Button("完成", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("重试") { Task { await model.beginAddAccount() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
    }

    private var roleText: String {
        let role = model.pendingAccountCapture?.role ?? ""
        return role.isEmpty ? "未知" : role
    }
}
