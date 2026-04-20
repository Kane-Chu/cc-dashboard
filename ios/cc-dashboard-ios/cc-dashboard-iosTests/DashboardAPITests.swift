import XCTest
@testable import cc_dashboard_ios

@MainActor
final class DashboardAPITests: XCTestCase {

    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession.invalidateAndCancel()
        super.tearDown()
    }

    func testFetchSessionsSuccess() async throws {
        let json = """
        {
            "timestamp": "2026-04-18T23:22:22.997Z",
            "sessions": [
                {
                    "id": "abc",
                    "fullId": "abc-def",
                    "pid": 1,
                    "status": "running",
                    "startTime": 1000,
                    "workDir": "/test",
                    "model": "sonnet",
                    "contextUsed": 50,
                    "contextTotal": 100,
                    "tokensInput": 100,
                    "tokensOutput": 50,
                    "recentMessages": [],
                    "source": "terminal"
                }
            ]
        }
        """

        MockURLProtocol.mockResponse = (
            data: json.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "http://test/api/sessions")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            error: nil
        )

        let sessions = try await DashboardAPI.fetchSessions(baseURL: "http://test", session: mockSession)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.status, .running)
    }

    func testFetchSessionsInvalidURL() async {
        do {
            _ = try await DashboardAPI.fetchSessions(baseURL: "not a url", session: mockSession)
            XCTFail("Should throw invalidURL")
        } catch let error as APIError {
            XCTAssertEqual(error, APIError.invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchSessionsServerError() async {
        MockURLProtocol.mockResponse = (
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "http://test/api/sessions")!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
            error: nil
        )

        do {
            _ = try await DashboardAPI.fetchSessions(baseURL: "http://test", session: mockSession)
            XCTFail("Should throw invalidResponse")
        } catch let error as APIError {
            XCTAssertEqual(error, APIError.invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSendActionSuccess() async throws {
        let json = """
        {"success": true, "method": "Terminal.app"}
        """

        MockURLProtocol.mockResponse = (
            data: json.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "http://test/api/sessions/abc/action")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            error: nil
        )

        let response = try await DashboardAPI.sendAction(baseURL: "http://test", sessionId: "abc", action: "confirm", session: mockSession)
        XCTAssertTrue(response.success)
    }

    func testSendActionFailure() async {
        let json = """
        {"success": false, "error": "Session ended"}
        """

        MockURLProtocol.mockResponse = (
            data: json.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "http://test/api/sessions/abc/action")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            error: nil
        )

        do {
            _ = try await DashboardAPI.sendAction(baseURL: "http://test", sessionId: "abc", action: "confirm", session: mockSession)
            XCTFail("Should throw serverError")
        } catch let error as APIError {
            if case .serverError(let msg) = error {
                XCTAssertEqual(msg, "Session ended")
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Mock URLProtocol

@MainActor
class MockURLProtocol: URLProtocol {
    static var mockResponse: (data: Data, response: HTTPURLResponse, error: Error?)?

    static func reset() {
        mockResponse = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let mock = MockURLProtocol.mockResponse else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }

        if let error = mock.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocol(self, didReceive: mock.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension APIError: Equatable {
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse):
            return true
        case (.serverError(let a), .serverError(let b)):
            return a == b
        case (.networkError, .networkError):
            return true
        default:
            return false
        }
    }
}
