import XCTest

final class SessionListUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchShowsNavigationTitle() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Claude Sessions"].waitForExistence(timeout: 5))
    }

    func testSettingsButtonExists() {
        app.launch()
        let settingsButton = app.buttons["gear"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
    }

    func testOpenAndCloseSettings() {
        app.launch()

        app.buttons["gear"].tap()

        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["服务器配置"].waitForExistence(timeout: 5))

        // 点击左上角返回按钮关闭设置页
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Claude Sessions"].waitForExistence(timeout: 5))
    }
}
