import XCTest

/// Build 31: moving on after a lesson, terminal tabs beside a running server,
/// the About screen, and the Learn and Labs lists.
@MainActor
final class Release31Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Passing every check puts "Next" on screen at once, pinned in the results,
    /// and keeps it in the lesson's own bar after the results close.
    func testNextLessonIsOnScreenAsSoonAsTheChecksPass() throws {
        let app = launch(["-tab", "learn", "-openLesson", "values-and-names", "-lessonMode", "code"])
        let check = app.buttons["lesson-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 30))
        for _ in 0..<6 {
            let hint = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hint ")).firstMatch
            guard hint.exists else { break }
            hint.tap()
        }
        app.buttons["Solution"].tap()
        app.buttons["Show the solution"].tap()
        check.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["All checks passed"].waitForExistence(timeout: 30))
        let next = app.buttons["lesson-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable, "Next must be visible without scrolling the results")
        XCTAssertTrue(app.descendants(matching: .any)["lesson-complete"].exists)
        capture("lesson-complete-next-pinned")

        // Closing the results keeps the way forward in the lesson's bar.
        app.navigationBars["All checks passed"].buttons["Done"].tap()
        let bar = app.buttons["lesson-next-bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.isHittable)
        capture("lesson-done-next-in-bar")
        bar.tap()
        XCTAssertTrue(app.navigationBars["Lesson 2 of 30"].waitForExistence(timeout: 10))
    }

    /// A Django server runs in one tab while tests run in another; the site keeps answering.
    func testDjangoTestsRunInASecondTabWhileTheServerRuns() throws {
        let app = launch(["-openTemplate", "django", "-freshTemplate", "YES", "-panel", "terminal",
                          "-terminal", "python manage.py runserver 127.0.0.1:8031",
                          "-terminalThen", "python manage.py test", "-terminalDelay", "6"])
        XCTAssertTrue(app.buttons["open-site"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["terminal-tab-2"].waitForExistence(timeout: 20))
        let output = app.textViews["output-text"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", "Ran 3 tests"), evaluatedWith: output)
        waitForExpectations(timeout: 90)
        XCTAssertTrue((output.value as? String ?? "").contains("OK"))
        XCTAssertFalse((output.value as? String ?? "").contains("fileno"))
        XCTAssertTrue(app.buttons["open-site"].exists, "The server is still running")
        capture("terminal-tabs-django-tests-beside-server")

        app.buttons["terminal-tab-1"].tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "development server at"), evaluatedWith: output)
        waitForExpectations(timeout: 10)
        capture("terminal-tab-1-server-log")

        // A third tab, then close it again.
        app.buttons["terminal-new-tab"].tap()
        XCTAssertTrue(app.buttons["terminal-tab-3"].waitForExistence(timeout: 5))
        app.buttons["terminal-close-3"].tap()
        XCTAssertTrue(app.buttons["terminal-tab-3"].waitForNonExistence(timeout: 5))

        // Closing the server's tab asks first, then stops it.
        app.buttons["terminal-close-1"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Stop and close"].tap()
        XCTAssertTrue(app.buttons["open-site"].waitForNonExistence(timeout: 20))
    }

    func testAboutShowsVersionAndLinks() throws {
        let app = launch([])
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        let about = app.buttons["settings-about"]
        for _ in 0..<6 where !about.isHittable { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        capture("settings-about-links")
        about.tap()
        let version = app.staticTexts["about-version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertTrue(version.label.hasPrefix("Version "), version.label)
        for title in ["Website", "User guide", "Help and support", "Privacy policy", "Terms of use"] {
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            for _ in 0..<4 where !link.exists { app.swipeUp() }
            XCTAssertTrue(link.exists, title)
        }
        capture("settings-about")
    }

    func testLearnTracksAndSearch() throws {
        let app = launch(["-tab", "learn"])
        XCTAssertTrue(app.buttons["learn-continue"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["learn-practice"].exists)
        let ml = app.buttons["learn-track-ml"]
        for _ in 0..<4 where !ml.isHittable { app.swipeUp() }
        ml.tap()
        let course = app.descendants(matching: .any)["course-ml"]
        for _ in 0..<6 where !course.exists { app.swipeUp() }
        XCTAssertTrue(course.exists)
        XCTAssertFalse(app.descendants(matching: .any)["course-foundations"].exists)
        capture("learn-ml-track")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let search = searchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("decorator")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-lesson-")).firstMatch.waitForExistence(timeout: 5))
        capture("learn-search")
    }
}
