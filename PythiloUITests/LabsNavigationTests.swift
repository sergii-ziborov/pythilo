import XCTest

/// Exercises the learner-facing route, including the answer sheet and Python trace.
@MainActor
final class LabsNavigationTests: XCTestCase {
    func testTopicsCollapseAndSearchFindsTensorLabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["136 interactive labs"].waitForExistence(timeout: 30))
        app.buttons["ML · 65"].tap()
        let topic = app.buttons["labs-topic-pytorch-training"]
        for _ in 0..<5 { if topic.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(topic.exists)
        XCTAssertFalse(app.buttons["lab-torchclip"].exists)
        tapVisiblePadding(topic, in: app, offset: CGVector(dx: 0.5, dy: 0.85))
        for _ in 0..<12 {
            if app.buttons["lab-torchclip"].exists { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        XCTAssertTrue(app.buttons["lab-torchclip"].waitForExistence(timeout: 5))
        tapVisiblePadding(topic, in: app)
        XCTAssertFalse(app.buttons["lab-torchclip"].exists)
        tapVisiblePadding(app.buttons["AI · 48"], in: app)
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("rotary")
        app.keyboards.buttons["Search"].tap()
        let rotary = app.buttons["lab-torchrope"]
        for _ in 0..<12 {
            if rotary.exists { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        XCTAssertTrue(rotary.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lab-torchgqa"].exists)
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "torch-topic-search-native"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testSeniorPreferenceProjectRunsAndLinksToItsLesson() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-openLab", "torchpreferenceproject", "-labAnswer", "YES"]
        app.launch()
        let trace = app.buttons["lab-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 30))
        for _ in 0..<10 { if trace.isHittable { break }; app.swipeUp() }
        tapVisiblePadding(trace, in: app, offset: CGVector(dx: 0.08, dy: 0.8))
        let passed = app.staticTexts["Every check passed"]
        let deadline = Date().addingTimeInterval(120)
        while !passed.exists && Date() < deadline {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        XCTAssertTrue(passed.exists)
        let lastStep = app.buttons["Last step"]
        for _ in 0..<8 { if lastStep.isHittable { break }; app.swipeUp() }
        tapVisiblePadding(lastStep, in: app)
        app.swipeUp()
        let replay = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        replay.name = "senior-preference-native-offline-passed"
        replay.lifetime = .keepAlways
        add(replay)
        let plot = app.staticTexts["ACTUAL OPTIMIZER STEPS"]
        for _ in 0..<24 {
            let y = plot.exists ? plot.frame.minY : -1
            if (140...280).contains(y) { break }
            let down = y < 140
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: down ? 0.3 : 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: down ? 0.55 : 0.35)))
        }
        XCTAssertTrue(plot.exists)
        let curve = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        curve.name = "senior-preference-training-curve"
        curve.lifetime = .keepAlways
        add(curve)
        let lesson = app.buttons["lab-lesson-project-torchpreferenceproject"]
        for _ in 0..<14 {
            if lesson.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7)))
        }
        tapVisiblePadding(lesson, in: app)
        XCTAssertTrue(app.buttons["lesson-lab-torchpreferenceproject"].waitForExistence(timeout: 10))
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
        tapVisiblePadding(lesson, in: app)
        XCTAssertTrue(app.buttons["lesson-lab-torchtinylm"].waitForExistence(timeout: 10))
    }

    func testCatalogFiltersAndAttentionTrace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["136 interactive labs"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["ML · 65"].exists)
        tapVisiblePadding(app.buttons["AI · 48"], in: app)
        XCTAssertTrue(app.staticTexts["ARTIFICIAL INTELLIGENCE · 48"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lab-descent"].exists)
        let catalog = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        catalog.name = "136-labs-ai-catalog"
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
