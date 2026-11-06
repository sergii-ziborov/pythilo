import XCTest

/// Exercises the learner-facing route, including the answer sheet and Python trace.
@MainActor
final class LabsNavigationTests: XCTestCase {
    func testTopicsCollapseAndSearchFindsTensorLabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["114 interactive labs"].waitForExistence(timeout: 30))
        app.buttons["ML · 54"].tap()
        let topic = app.buttons["labs-topic-pytorch-training"]
        for _ in 0..<5 { if topic.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(topic.exists)
        XCTAssertFalse(app.buttons["lab-torchclip"].exists)
        topic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        XCTAssertTrue(app.buttons["lab-torchclip"].waitForExistence(timeout: 5))
        topic.tap()
        XCTAssertFalse(app.buttons["lab-torchclip"].exists)
        app.buttons["AI · 37"].tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("rotary")
        XCTAssertTrue(app.buttons["lab-torchrope"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lab-torchgqa"].exists)
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "torch-topic-search-native"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testTinyTransformerRunsInTheAppAndLinksToItsLesson() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-openLab", "torchtinylm", "-labAnswer", "YES"]
        app.launch()
        let trace = app.buttons["lab-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 30))
        for _ in 0..<8 { if trace.isHittable { break }; app.swipeUp() }
        trace.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).tap()
        XCTAssertTrue(app.staticTexts["Every check passed"].waitForExistence(timeout: 90))
        let replay = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        replay.name = "tiny-transformer-native-passed"
        replay.lifetime = .keepAlways
        add(replay)
        let lesson = app.buttons["lab-lesson-project-torchtinylm"]
        for _ in 0..<12 { if lesson.isHittable { break }; app.swipeDown() }
        lesson.tap()
        XCTAssertTrue(app.buttons["lesson-lab-torchtinylm"].waitForExistence(timeout: 10))
    }

    func testCatalogFiltersAndAttentionTrace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["114 interactive labs"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["ML · 54"].exists)
        app.buttons["AI · 37"].tap()
        XCTAssertTrue(app.staticTexts["ARTIFICIAL INTELLIGENCE · 37"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lab-descent"].exists)
        let catalog = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        catalog.name = "114-labs-ai-catalog"
        catalog.lifetime = .keepAlways
        add(catalog)
        app.buttons["labs-topic-transformer-internals"].tap()
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
