import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var testStatus: TestStatus = .idle

    enum TestStatus {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器配置") {
                    HStack {
                        Text("地址")
                        Spacer()
                        TextField("Tailscale IP", text: $settings.serverHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(minWidth: 150)
                    }

                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("7777", text: $settings.serverPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(minWidth: 80)
                    }
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            switch testStatus {
                            case .idle:
                                EmptyView()
                            case .testing:
                                ProgressView()
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(testStatus == .testing)

                    if case .failed(let msg) = testStatus {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("帮助") {
                    HStack {
                        Text("使用步骤")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 在电脑上安装并启动 Tailscale")
                        Text("2. 启动 cc-dashboard server (node server.js)")
                        Text("3. 输入电脑的 Tailscale IP (如 100.x.x.x)")
                        Text("4. 点击测试连接验证")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func testConnection() async {
        testStatus = .testing

        guard !settings.serverHost.isEmpty else {
            testStatus = .failed("请输入服务器地址")
            return
        }

        do {
            let api = DashboardAPI(settings: settings)
            _ = try await api.fetchSessions()
            testStatus = .success
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }
}
