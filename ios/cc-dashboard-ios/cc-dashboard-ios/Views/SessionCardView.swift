import SwiftUI

struct SessionCardView: View {
    let session: Session

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .waiting: return .orange
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch session.status {
        case .running: return "执行中"
        case .waiting: return "等待确认"
        case .idle: return "空闲"
        }
    }

    private var sourceIcon: String {
        switch session.source {
        case .terminal: return "desktopcomputer"
        case .vscode: return "bolt.fill"
        }
    }

    private var sourceColor: Color {
        switch session.source {
        case .terminal: return .blue
        case .vscode: return .purple
        }
    }

    private var durationText: String {
        let seconds = (Date().timeIntervalSince1970 * 1000 - session.startTime) / 1000
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }

    private var sessionName: String {
        let components = session.workDir.split(separator: "/")
        return String(components.last ?? "Unknown")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sourceIcon)
                    .foregroundStyle(sourceColor)
                    .font(.caption)
                    .frame(width: 20, height: 20)
                    .background(sourceColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(sessionName)
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 3)
            }

            Text(session.workDir)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(session.model)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())

                Text(durationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 1.5)
        )
    }
}
