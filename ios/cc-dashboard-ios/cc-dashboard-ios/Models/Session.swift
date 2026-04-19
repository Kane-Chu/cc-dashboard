import Foundation

enum SessionStatus: String, Codable, CaseIterable {
    case running = "running"
    case waiting = "waiting"
    case idle = "idle"
}

enum SessionSource: String, Codable {
    case terminal = "terminal"
    case vscode = "vscode"
}

struct Message: Codable {
    let type: String
    let content: String
    let time: String
}

struct PendingTool: Codable {
    let id: String
    let name: String
    let input: [String: AnyCodable]?
}

struct Session: Codable, Identifiable {
    let id: String
    let fullId: String
    let pid: Int
    let status: SessionStatus
    let startTime: TimeInterval
    let workDir: String
    let model: String
    let contextUsed: Int
    let contextTotal: Int
    let tokensInput: Int
    let tokensOutput: Int
    let recentMessages: [Message]
    let source: SessionSource
    let pendingTools: [PendingTool]?
}

struct SessionListResponse: Codable {
    let timestamp: String
    let sessions: [Session]
}

struct ActionRequest: Codable {
    let action: String
}

struct ActionResponse: Codable {
    let success: Bool
    let method: String?
    let error: String?
}

// 辅助类型：处理 API 返回的动态 JSON 字段（pendingTools.input）
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encode("\(value)")
        }
    }
}
