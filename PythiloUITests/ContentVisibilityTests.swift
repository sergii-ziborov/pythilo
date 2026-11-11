import XCTest

/// Courses and Lab topics can be downloaded, removed and hidden from their own lists.
@MainActor
final class ContentVisibilityTests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
    }

    func testHideAndShowACourse() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-showAllContent", "YES"]
        app.launch()
        let track = app.buttons["learn-track-projects"]
        XCTAssertTrue(track.waitForExistence(timeout: 30))
        for _ in 0..<4 where !track.isHittable { app.swipeUp() }
        track.tap()
        XCTAssertTrue(app.buttons["download-track-projects"].waitForExistence(timeout: 5) || app.staticTexts["offline-ready-download-track-projects"].exists,
                      "the track offers Download all")
        let course = app.descendants(matching: .any)["course-senior-projects"]
        scrollTo(course, in: app)
        course.press(forDuration: 1.2)
        let hide = app.buttons["Hide course"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        XCTAssertTrue(course.waitForNonExistence(timeout: 5), "a hidden course leaves the list")
        let reveal = app.buttons["learn-show-hidden"]
        scrollTo(reveal, in: app)
        XCTAssertTrue(reveal.label.contains("1 hidden course"))
        attach(app, "learn-hidden-footer")
        reveal.tap()
        scrollTo(course, in: app)
        XCTAssertTrue(course.exists)
        XCTAssertTrue(course.label.contains("Hidden"))
        attach(app, "learn-hidden-shown")
        course.press(forDuration: 1.2)
        let show = app.buttons["Show course"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        XCTAssertFalse(app.buttons["learn-show-hidden"].exists)
    }

    func testDownloadAndRemoveACourseFromItsMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-showAllContent", "YES", "-removeDownload", "course-data"]
        app.launch()
        let track = app.buttons["learn-track-web"]
        XCTAssertTrue(track.waitForExistence(timeout: 30))
        for _ in 0..<4 where !track.isHittable { app.swipeUp() }
        track.tap()
        let course = app.descendants(matching: .any)["course-data"]
        scrollTo(course, in: app)
        course.press(forDuration: 1.2)
        let download = app.buttons["Download course"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        let downloaded = NSPredicate(format: "label CONTAINS %@", "Downloaded")
        expectation(for: downloaded, evaluatedWith: course)
        waitForExpectations(timeout: 60)
        course.press(forDuration: 1.2)
        let remove = app.buttons["Remove download"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let confirm = app.alerts.buttons["Remove download"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attach(app, "learn-remove-confirmation")
        confirm.tap()
        expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "Downloaded"), evaluatedWith: course)
        waitForExpectations(timeout: 10)
        course.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Download course"].waitForExistence(timeout: 5), "the removed course can be downloaded again")
    }

    func testHideALabTopic() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-showAllContent", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["ML · 65"].waitForExistence(timeout: 30))
        app.buttons["ML · 65"].tap()
        let topic = app.buttons["labs-topic-pytorch-training"]
        scrollTo(topic, in: app)
        topic.press(forDuration: 1.2)
        let hide = app.buttons["Hide topic"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove download"].exists || app.buttons["Download topic"].exists || app.buttons["Cancel download"].exists)
        hide.tap()
        XCTAssertTrue(topic.waitForNonExistence(timeout: 5))
        let reveal = app.buttons["labs-show-hidden"]
        scrollTo(reveal, in: app)
        XCTAssertTrue(reveal.exists)
        reveal.tap()
        scrollTo(topic, in: app)
        topic.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Show topic"].waitForExistence(timeout: 5))
        app.buttons["Show topic"].tap()
        XCTAssertFalse(app.buttons["labs-show-hidden"].exists)
    }
}
