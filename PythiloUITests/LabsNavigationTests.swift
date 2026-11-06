import XCTest

/// Exercises the learner-facing route, including the answer sheet and Python trace.
@MainActor
final class LabsNavigationTests: XCTestCase {
    func testCatalogFiltersAndAttentionTrace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["96 interactive labs"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["ML · 45"].exists)
        app.buttons["AI · 28"].tap()
        XCTAssertTrue(app.staticTexts["ARTIFICIAL INTELLIGENCE · 28"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lab-descent"].exists)
        let catalog = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        catalog.name = "96-labs-ai-catalog"
        catalog.lifetime = .keepAlways
        add(catalog)
        let attention = app.buttons["lab-attention"]
        XCTAssertTrue(attention.exists)
        attention.tap()
        XCTAssertTrue(app.buttons["lab-answer"].waitForExistence(timeout: 5))
        app.buttons["lab-answer"].tap()
        app.buttons["Use it"].tap()
        app.buttons["lab-trace"].tap()
        let deadline = Date().addingTimeInterval(45)
        while !app.staticTexts["Every check passed"].exists && Date() < deadline {
            app.swipeUp()
            if app.staticTexts["Every check passed"].exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(app.staticTexts["Every check passed"].exists)
        let replay = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        replay.name = "attention-native-trace"
        replay.lifetime = .keepAlways
        add(replay)
    }
}
