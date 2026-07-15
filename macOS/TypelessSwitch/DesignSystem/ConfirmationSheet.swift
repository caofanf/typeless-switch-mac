import SwiftUI

struct ConfirmationSheet: View {
    let operation: PendingAccountOperation
    let isPerforming: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var summary: [String: JSONValue] {
        operation.confirmation.summary.objectValue ?? [:]
    }

    private var title: String {
        summary["title"]?.stringValue ?? defaultTitle
    }

    private var message: String {
        summary["message"]?.stringValue ?? "请核对操作影响后继续。"
    }

    private var defaultTitle: String {
        switch operation.kind {
        case .delete: "删除账号"
        case .switchSnapshot: "切换账号"
        }
    }

    private var isDestructive: Bool { operation.kind == .delete }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isDestructive ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox {
                LabeledContent("目标账号", value: operation.accountID)
                    .textSelection(.enabled)
                Divider()
                LabeledContent("确认有效期") {
                    Text(operation.confirmation.expiresAt, style: .relative)
                }
            }

            if isDestructive {
                Text("此操作无法撤销。")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPerforming)
                if isDestructive {
                    Button("删除", role: .destructive, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isPerforming)
                } else {
                    Button("切换并重新启动", action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isPerforming)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .overlay {
            if isPerforming {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
