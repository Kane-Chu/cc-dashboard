import SwiftUI

struct ConfirmSheetView: View {
    let session: Session
    let onConfirm: () async throws -> Void
    let onReject: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?

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

    private var sessionName: String {
        let components = session.workDir.split(separator: "/")
        return String(components.last ?? "Unknown")
    }

    private var toolInfo: String {
        guard let tools = session.pendingTools, let first = tools.first else {
            return "未知操作"
        }
        return "\(first.name)"
    }

    private var toolInput: String {
        guard let tools = session.pendingTools,
              let first = tools.first,
              let input = first.input else {
            return ""
        }
        var parts: [String] = []
        if let command = input["command"]?.value as? String {
            parts.append(command)
        } else if let desc = input["description"]?.value as? String {
            parts.append(desc)
        } else {
            parts.append("\(input)")
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: sourceIcon)
                                .foregroundStyle(sourceColor)
                                .font(.caption)
                                .frame(width: 20, height: 20)
                                .background(sourceColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(sessionName)
                                .font(.headline)
                        }

                        Text("等待确认操作")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Tool:")
                                    .foregroundStyle(.secondary)
                                Text(toolInfo)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .font(.subheadline)

                            if !toolInput.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("参数:")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)

                                    Text(toolInput)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(10)
                                        .background(Color.gray.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text(error)
                            }
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await performAction(action: "reject") }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("拒绝")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading)

                    Button {
                        Task { await performAction(action: "confirm") }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("确认")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading)
                }
                .padding()
            }
            .navigationTitle("确认操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func performAction(action: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if action == "confirm" {
                try await onConfirm()
            } else {
                try await onReject()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
