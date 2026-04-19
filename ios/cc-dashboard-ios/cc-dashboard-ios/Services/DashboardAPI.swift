import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL，请检查服务器地址配置"
        case .invalidResponse:
            return "服务器响应异常"
        case .serverError(let msg):
            return msg
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

struct DashboardAPI {
    static func fetchSessions(baseURL: String) async throws -> [Session] {
        guard let url = URL(string: "\(baseURL)/api/sessions") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(SessionListResponse.self, from: data)
        return decoded.sessions
    }

    static func sendAction(baseURL: String, sessionId: String, action: String) async throws -> ActionResponse {
        guard let url = URL(string: "\(baseURL)/api/sessions/\(sessionId)/action") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ActionRequest(action: action))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ActionResponse.self, from: data)

        if !decoded.success {
            throw APIError.serverError(decoded.error ?? "未知错误")
        }

        return decoded
    }

    static func testConnection(baseURL: String) async throws -> Bool {
        _ = try await fetchSessions(baseURL: baseURL)
        return true
    }
}
