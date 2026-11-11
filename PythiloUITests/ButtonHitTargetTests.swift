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
        let filter = app.buttons["AI · 48"]
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        filter.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).tap()
        XCTAssertTrue(app.staticTexts["ARTIFICIAL INTELLIGENCE · 48"].waitForExistence(timeout: 5))
        app.buttons["labs-topic-transformer-internals"].tap()
        let attention = app.buttons["lab-attention"]
        XCTAssertTrue(attention.exists)
        tapVisiblePadding(attention, in: app, offset: CGVector(dx: 0.6, dy: 0.92))
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
        app.launchArguments = ["-openTemplate", "blank", "-freshTemplate", "YES", "-panel", "code"]
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

@MainActor
extension XCTestCase {
    /// iPadOS keeps a .searchable field behind a toolbar button until it is tapped.
    func searchField(in app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 3) { return field }
        let button = app.buttons["Search"].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        return field
    }
}

// XCUITest considers partially covered/offscreen controls hittable on this SDK.
// Keep the exact padding point clear of the navigation and floating tab bars.
@MainActor
extension XCTestCase {
    func tapVisiblePadding(_ element: XCUIElement, in app: XCUIApplication,
                           offset: CGVector = CGVector(dx: 0.5, dy: 0.5),
                           file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<24 {
            let point = element.coordinate(withNormalizedOffset: offset).screenPoint
            let window = app.windows.firstMatch.frame
            let visible = CGRect(x: window.minX + 8, y: window.minY + 120,
                                 width: window.width - 16, height: window.height - 230)
            if visible.contains(point) {
                element.coordinate(withNormalizedOffset: offset).tap()
                return
            }
            let up = point.y > visible.maxY
            // Swipe along the outer margin, outside the nested code editor.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.7 : 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: up ? 0.3 : 0.7)))
        }
        XCTFail("Control padding did not enter the unobscured viewport: \(element.identifier)", file: file, line: line)
    }
}
