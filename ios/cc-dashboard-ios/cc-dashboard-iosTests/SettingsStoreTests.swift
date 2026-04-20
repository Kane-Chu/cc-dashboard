import XCTest
@testable import cc_dashboard_ios

final class SettingsStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "serverHost")
        UserDefaults.standard.removeObject(forKey: "serverPort")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "serverHost")
        UserDefaults.standard.removeObject(forKey: "serverPort")
        super.tearDown()
    }

    func testDefaultValues() {
        let store = SettingsStore()
        XCTAssertEqual(store.serverPort, "7777")
        XCTAssertEqual(store.serverHost, "")
        XCTAssertFalse(store.isConfigured)
    }

    func testBaseURL() {
        let store = SettingsStore()
        store.serverHost = "100.64.0.1"
        store.serverPort = "7777"
        XCTAssertEqual(store.baseURL, "http://100.64.0.1:7777")
        XCTAssertTrue(store.isConfigured)
    }

    func testBaseURLWithEmptyPort() {
        let store = SettingsStore()
        store.serverHost = "192.168.1.100"
        store.serverPort = ""
        XCTAssertEqual(store.baseURL, "http://192.168.1.100:7777")
    }

    func testBaseURLWithEmptyHost() {
        let store = SettingsStore()
        store.serverHost = ""
        XCTAssertEqual(store.baseURL, "http://localhost:7777")
    }
}
