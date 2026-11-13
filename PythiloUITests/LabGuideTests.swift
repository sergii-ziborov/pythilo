import XCTest

/// Every Lab has an About sheet: what the algorithm is, how it works, its cost, uses and pitfalls.
/// It opens from the Lab's row before any download, and from the Lab's navigation bar.
@MainActor
final class LabGuideTests: XCTestCase {
    func testAboutOpensFromTheListAndFromTheLab() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        let topic = app.buttons["labs-topic-basics"]
        XCTAssertTrue(topic.waitForExistence(timeout: 30))
        for _ in 0..<12 { if topic.isHittable { break }; app.swipeUp() }
        tapVisiblePadding(topic, in: app, offset: CGVector(dx: 0.5, dy: 0.5))

        let about = app.buttons["lab-about-binsearch"]
        for _ in 0..<8 { if about.exists && about.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        about.tap()
        let title = app.staticTexts["lab-about-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Binary Search")
        for heading in ["The idea", "How it works", "What it costs"] {
            XCTAssertTrue(app.staticTexts[heading].exists, heading)
        }
        attach("lab-guide-top")
        app.swipeUp()
        for heading in ["Where it is used", "Watch out for", "In this Lab"] {
            let text = app.staticTexts[heading]
            for _ in 0..<4 { if text.exists { break }; app.swipeUp() }
            XCTAssertTrue(text.exists, heading)
        }
        attach("lab-guide-bottom")
        app.buttons["lab-about-done"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))

        // The same sheet from inside the Lab, whether or not its topic is downloaded.
        app.buttons["lab-binsearch"].tap()
        let inside = app.buttons["lab-about"]
        XCTAssertTrue(inside.waitForExistence(timeout: 15))
        inside.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        attach("lab-guide-from-lab")
        app.buttons["lab-about-done"].tap()
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
