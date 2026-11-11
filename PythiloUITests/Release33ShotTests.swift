import XCTest

/// Store and website screenshots for 1.0 (33). Run on a clean simulator with the status bar
/// overridden; each screen is attached at full resolution.
@MainActor
final class Release33ShotTests: XCTestCase {
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testShotProjects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "projects", "-resetProjectCategories", "YES",
            "-seedProjects", "notes-cli,algorithms-practice,torch-mnist,fastapi-todo,django-blog",
            "-seedCategories", "django-blog=Web;fastapi-todo=Web;torch-mnist=Machine learning;algorithms-practice=Learning;notes-cli=Learning"]
        app.launch()
        XCTAssertTrue(app.buttons["project-django-blog"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 1)
        attach("shot-projects")
    }

    func testShotGitHubSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "projects"]
        app.launch()
        let clone = app.buttons["project-clone"]
        XCTAssertTrue(clone.waitForExistence(timeout: 30))
        clone.tap()
        let field = app.textFields["clone-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("org:python\n")
        XCTAssertTrue(app.buttons["clone-repo-python/cpython"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 3) // avatars
        attach("shot-github")
    }

    func testShotLearnAlgorithms() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn"]
        app.launch()
        let track = app.buttons["learn-track-projects"]
        XCTAssertTrue(track.waitForExistence(timeout: 30))
        for _ in 0..<4 where !track.isHittable { app.swipeUp() }
        track.tap()
        Thread.sleep(forTimeInterval: 1)
        attach("shot-learn")
        let course = app.descendants(matching: .any)["course-algorithms"]
        for _ in 0..<6 where !course.isHittable { app.swipeUp() }
        course.tap()
        XCTAssertTrue(app.staticTexts["Halve a sorted list with binary search"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        attach("shot-algorithms")
    }
}
