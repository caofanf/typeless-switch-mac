import SwiftUI

enum StatusTone: Sendable {
    case neutral
    case good
    case attention
    case critical
    case progress

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .good: .green
        case .attention: .orange
        case .critical: .red
        case .progress: .blue
        }
    }

    var systemImage: String {
        switch self {
        case .neutral: "minus.circle"
        case .good: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .progress: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        }
    }
}

struct StatusView: View {
    let title: String
    var detail: String?
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(title)
                .fontWeight(.medium)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "\(title)，\($0)" } ?? title)
    }
}
