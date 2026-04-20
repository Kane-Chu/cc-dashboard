import XCTest

final class SessionListUITests: XCTestCase {

    var app: XCUIApplication!
    let screenshotsDir = "/tmp/ios-screenshots"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: screenshotsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchShowsNavigationTitle() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Claude Sessions"].waitForExistence(timeout: 5))
        saveScreenshot(name: "01_launch_title")
    }

    func testSettingsButtonExists() {
        app.launch()
        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        saveScreenshot(name: "02_settings_button")
    }

    func testOpenAndCloseSettings() {
        app.launch()

        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        saveScreenshot(name: "03a_before_settings")

        settingsButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        saveScreenshot(name: "03b_settings_opened")

        let doneButton = app.buttons["完成"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(app.staticTexts["Claude Sessions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["完成"].waitForExistence(timeout: 2))
        saveScreenshot(name: "03c_settings_closed")
    }

    private func saveScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let path = "\(screenshotsDir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
}
