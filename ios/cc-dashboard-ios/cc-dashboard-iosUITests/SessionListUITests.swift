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
        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
    }

    func testOpenAndCloseSettings() {
        app.launch()

        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let doneButton = app.buttons["完成"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(app.staticTexts["Claude Sessions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["完成"].waitForExistence(timeout: 2))
    }
}
