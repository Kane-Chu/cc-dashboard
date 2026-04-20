import XCTest
@testable import cc_dashboard_ios

final class SessionModelTests: XCTestCase {

    func testSessionDecoding() throws {
        let json = """
        {
            "id": "3a06d74c-098f",
            "fullId": "3a06d74c-098f-4bb5-92a2-004d41e5ce22",
            "pid": 56783,
            "status": "running",
            "startTime": 1776524971038,
            "workDir": "/Users/kane/workspace/ybt",
            "model": "claude-sonnet-4-6",
            "contextUsed": 78,
            "contextTotal": 100,
            "tokensInput": 45231,
            "tokensOutput": 18432,
            "recentMessages": [
                {"type": "user", "content": "帮我优化代码", "time": "2分钟前"}
            ],
            "source": "terminal",
            "pendingTools": [
                {"id": "tool_abc", "name": "Bash", "input": {"command": "rm -rf node_modules"}}
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)

        XCTAssertEqual(session.id, "3a06d74c-098f")
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.source, .terminal)
        XCTAssertEqual(session.workDir, "/Users/kane/workspace/ybt")
        XCTAssertEqual(session.pendingTools?.first?.name, "Bash")
    }

    func testSessionListResponseDecoding() throws {
        let json = """
        {
            "timestamp": "2026-04-18T23:22:22.997Z",
            "sessions": [
                {
                    "id": "abc",
                    "fullId": "abc-def",
                    "pid": 1,
                    "status": "waiting",
                    "startTime": 1000,
                    "workDir": "/test",
                    "model": "sonnet",
                    "contextUsed": 50,
                    "contextTotal": 100,
                    "tokensInput": 100,
                    "tokensOutput": 50,
                    "recentMessages": [],
                    "source": "vscode"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SessionListResponse.self, from: data)

        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions.first?.status, .waiting)
        XCTAssertEqual(response.sessions.first?.source, .vscode)
    }

    func testActionResponseDecoding() throws {
        let successJson = """
        {"success": true, "method": "Terminal.app"}
        """
        let success = try JSONDecoder().decode(ActionResponse.self, from: successJson.data(using: .utf8)!)
        XCTAssertTrue(success.success)
        XCTAssertEqual(success.method, "Terminal.app")

        let failJson = """
        {"success": false, "error": "Session not found"}
        """
        let fail = try JSONDecoder().decode(ActionResponse.self, from: failJson.data(using: .utf8)!)
        XCTAssertFalse(fail.success)
        XCTAssertEqual(fail.error, "Session not found")
    }
}
