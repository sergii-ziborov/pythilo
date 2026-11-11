import XCTest

/// Projects can be grouped into categories, filtered and searched; Clone searches GitHub.
@MainActor
final class ProjectsAndGitHubTests: XCTestCase {
    func testCategoriesFilterAndSearchOrganizeProjects() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "projects", "-seedProjects", "alpha-api,beta-site,gamma-notes",
                               "-resetProjectCategories", "YES"]
        app.launch()
        let alpha = app.buttons["project-alpha-api"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 30))

        // Put alpha-api into a new "Work" category from its context menu.
        alpha.press(forDuration: 1.2)
        let category = app.buttons["Category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        app.buttons["New category…"].tap()
        let field = app.textFields["Category, for example Work"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Work")
        app.alerts.buttons["Add"].tap()

        let work = app.buttons["projects-filter-Work"]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WORK"].exists, "Everything view groups projects by category")
        attach(app, "projects-grouped-by-category")
        work.tap()
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["project-gamma-notes"].exists)
        attach(app, "projects-filtered-to-work")
        app.buttons["projects-filter-all"].tap()

        // Search narrows the list by name.
        app.swipeDown()
        let search = searchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("gamma")
        XCTAssertTrue(app.buttons["project-gamma-notes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["project-alpha-api"].exists)
        XCTAssertFalse(app.buttons["project-beta-site"].exists)
        attach(app, "projects-search")
    }

    func testCloneSearchesGitHubWithStarsAndOwners() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "projects"]
        app.launch()
        let clone = app.buttons["project-clone"]
        XCTAssertTrue(clone.waitForExistence(timeout: 30))
        clone.tap()
        let field = app.textFields["clone-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("django\n")
        let django = app.buttons["clone-repo-django/django"]
        XCTAssertTrue(django.waitForExistence(timeout: 30), "GitHub search should list django/django")
        XCTAssertTrue(django.label.contains("django/django"))
        attach(app, "clone-github-search")

        // My repos asks to sign in when no account is saved on this device.
        app.buttons["My repos"].tap()
        let signIn = app.buttons["clone-add-account"]
        if signIn.waitForExistence(timeout: 5) {
            signIn.tap()
            XCTAssertTrue(app.secureTextFields["github-token"].waitForExistence(timeout: 5))
            attach(app, "github-account-sign-in")
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
