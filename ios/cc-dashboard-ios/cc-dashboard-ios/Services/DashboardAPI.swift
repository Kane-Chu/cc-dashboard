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
    private static func makeURL(baseURL: String, path: String) throws -> URL {
        guard let url = URL(string: baseURL + path),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw APIError.invalidURL
        }
        return url
    }

    static func fetchSessions(baseURL: String, session: URLSession = .shared) async throws -> [Session] {
        let url = try makeURL(baseURL: baseURL, path: "/api/sessions")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(SessionListResponse.self, from: data)
        return decoded.sessions
    }

    static func sendAction(baseURL: String, sessionId: String, action: String, session: URLSession = .shared) async throws -> ActionResponse {
        let url = try makeURL(baseURL: baseURL, path: "/api/sessions/\(sessionId)/action")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ActionRequest(action: action))

        let (data, response) = try await session.data(for: request)

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

    static func testConnection(baseURL: String, session: URLSession = .shared) async throws {
        _ = try await fetchSessions(baseURL: baseURL, session: session)
    }
}
