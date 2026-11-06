import XCTest

/// Coordinate taps deliberately miss the glyphs but stay inside the visible control.
@MainActor
final class ButtonHitTargetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTraceAcceptsOneTapAtEachCorner() throws {
        let app = XCUIApplication()
        for point in [CGVector(dx: 0.08, dy: 0.18), CGVector(dx: 0.92, dy: 0.18),
                      CGVector(dx: 0.08, dy: 0.82), CGVector(dx: 0.92, dy: 0.82)] {
            app.launchArguments = ["-tab", "labs", "-openLab", "attention", "-labAnswer", "YES"]
            app.launch()
            let trace = app.buttons["lab-trace"]
            XCTAssertTrue(trace.waitForExistence(timeout: 20))
            XCTAssertGreaterThanOrEqual(trace.frame.height, 44)
            trace.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.sliders["lab-step"].waitForExistence(timeout: 15),
                          "One tap at \(point) must run Trace without touching its title")
            app.terminate()
        }
    }

    func testCatalogFiltersAndCardsAcceptPaddingTaps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs"]
        app.launch()
        let filter = app.buttons["AI · 37"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        filter.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).tap()
        XCTAssertTrue(app.staticTexts["ARTIFICIAL INTELLIGENCE · 37"].waitForExistence(timeout: 5))
        app.buttons["labs-topic-transformer-internals"].tap()
        let attention = app.buttons["lab-attention"]
        XCTAssertTrue(attention.exists)
        attention.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.92)).tap()
        XCTAssertTrue(app.buttons["lab-trace"].waitForExistence(timeout: 5))
    }

    func testProjectAndPlaygroundButtonsAcceptPaddingTaps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "projects"]
        app.launch()
        let newProject = app.buttons["project-new"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 20))
        newProject.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.85)).tap()
        XCTAssertTrue(app.textFields["project-name"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-tab", "playground"]
        app.launch()
        let join = app.buttons["room-join"]
        XCTAssertTrue(join.waitForExistence(timeout: 20))
        join.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8)).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "room-link").firstMatch.waitForExistence(timeout: 5))
    }

    func testLabChoicesAndChipsAcceptPaddingTaps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-openLab", "graph"]
        app.launch()
        let dfs = app.buttons["DFS"]
        XCTAssertTrue(dfs.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(dfs.frame.height, 44)
        dfs.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.18)).tap()
        XCTAssertTrue(dfs.isSelected)
        let tree = app.buttons["Tree"]
        XCTAssertGreaterThanOrEqual(tree.frame.height, 44)
        tree.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.82)).tap()
        XCTAssertTrue(tree.isSelected)
    }

    func testClassicTraceAcceptsPaddingTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-openLab", "sorting"]
        app.launch()
        let trace = app.buttons["lab-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 20))
        trace.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.18)).tap()
        XCTAssertTrue(app.sliders["lab-step"].waitForExistence(timeout: 15))
    }

    func testLessonCheckAcceptsPaddingTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-openLesson", "values-and-names", "-lessonMode", "code"]
        app.launch()
        let check = app.buttons["lesson-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 20))
        check.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.18)).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "lesson-report").firstMatch.waitForExistence(timeout: 15))
    }

    func testEditorRunAcceptsPaddingTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-openTemplate", "blank", "-panel", "code"]
        app.launch()
        let run = app.buttons["run-button"]
        XCTAssertTrue(run.waitForExistence(timeout: 20))
        run.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.18)).tap()
        let output = app.textViews["output-text"]
        XCTAssertTrue(output.waitForExistence(timeout: 10))
        let ran = NSPredicate(format: "value CONTAINS %@", "Hello from Python on this device")
        expectation(for: ran, evaluatedWith: output)
        waitForExpectations(timeout: 15)
    }
}
