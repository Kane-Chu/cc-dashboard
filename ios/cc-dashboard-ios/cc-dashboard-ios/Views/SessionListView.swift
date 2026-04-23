import SwiftUI

struct SessionListView: View {
    @State private var sessions: [Session] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var selectedSession: Session?
    @State private var showSettings = false
    @State private var showConfirmSheet = false

    private let settings = SettingsStore()

    private var sortedSessions: [Session] {
        sessions.sorted { a, b in
            let order: [SessionStatus: Int] = [.waiting: 0, .running: 1, .idle: 2]
            let orderA = order[a.status] ?? 3
            let orderB = order[b.status] ?? 3
            if orderA != orderB {
                return orderA < orderB
            }
            return a.startTime > b.startTime
        }
    }

    private var hasWaitingSession: Bool {
        sessions.contains { $0.status == .waiting }
    }

    private var pollingInterval: TimeInterval {
        hasWaitingSession ? 2.0 : 5.0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List(sortedSessions) { session in
                    SessionCardView(session: session)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if session.status == .waiting {
                                selectedSession = session
                                showConfirmSheet = true
                            }
                        }
                }
                .listStyle(.plain)
                .refreshable {
                    await loadSessions()
                }
                .overlay {
                    if sessions.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label("暂无活跃 Session", systemImage: "terminal")
                        } description: {
                            Text("确保电脑上的 Claude Code 正在运行")
                        }
                    }
                }

                if isLoading && sessions.isEmpty {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .navigationTitle("Claude Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityIdentifier("settings-button")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .sheet(isPresented: $showConfirmSheet) {
                if let session = selectedSession {
                    ConfirmSheetView(
                        session: session,
                        onConfirm: {
                            _ = try await DashboardAPI.sendAction(baseURL: settings.baseURL, sessionId: session.id, action: "confirm")
                            await loadSessions()
                        },
                        onReject: {
                            _ = try await DashboardAPI.sendAction(baseURL: settings.baseURL, sessionId: session.id, action: "reject")
                            await loadSessions()
                        }
                    )
                }
            }
            .task {
                await loadSessions()
            }
            .task(id: hasWaitingSession) {
                await startPolling()
            }
            .alert("连接失败", isPresented: $showErrorAlert) {
                Button("设置") {
                    showErrorAlert = false
                    showSettings = true
                }
                Button("忽略", role: .cancel) {
                    showErrorAlert = false
                }
            } message: {
                Text(errorMessage ?? "无法连接到服务器")
            }
        }
    }

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try await DashboardAPI.fetchSessions(baseURL: settings.baseURL)
            errorMessage = nil
        } catch {
            // 只在首次加载失败时弹窗（轮询失败静默处理）
            if sessions.isEmpty && !showErrorAlert {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            if Task.isCancelled { break }
            await loadSessions()
        }
    }
}
