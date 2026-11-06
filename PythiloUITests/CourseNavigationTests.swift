import XCTest

@MainActor
final class CourseNavigationTests: XCTestCase {
    func testLabTabCanOpenItsRelatedLessonAndReturnToPractice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-openLab", "rocauc"]
        app.launch()
        let lesson = app.buttons["lab-lesson-stat-roc-auc"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 30))
        lesson.tap()
        let lab = app.buttons["lesson-lab-rocauc"]
        XCTAssertTrue(lab.waitForExistence(timeout: 10))
        lab.tap()
        XCTAssertTrue(app.buttons["lab-answer"].waitForExistence(timeout: 10))
    }

    func testRelatedLessonAndLabNavigateInBothDirections() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-openLesson", "stat-roc-auc"]
        app.launch()
        let link = app.buttons["lesson-lab-rocauc"]
        XCTAssertTrue(link.waitForExistence(timeout: 30))
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["lab-answer"].waitForExistence(timeout: 10))
        let lesson = app.buttons["lab-lesson-stat-roc-auc"]
        XCTAssertTrue(lesson.exists)
        lesson.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["lesson-lab-rocauc"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "senior-lesson-lab-linked"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPydanticRootModelWorkedSolutionPassesThroughTheLessonUI() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-openLesson", "pd-root-model", "-lessonMode", "code"]
        app.launch()
        XCTAssertTrue(app.buttons["lesson-check"].waitForExistence(timeout: 20))
        for number in 1...3 { app.buttons["Hint \(number) of 3"].tap() }
        app.buttons["Solution"].tap()
        app.buttons["Show the solution"].tap()
        app.buttons["lesson-check"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["All checks passed"].waitForExistence(timeout: 30))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "pydantic-root-model-native-check"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPydanticReadingExampleRunsWithoutASolution() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-openLesson", "pd-root-model"]
        app.launch()
        let run = app.buttons["Run example"].firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 20))
        // Move the whole code card clear of the fixed lesson action bar.
        app.swipeUp()
        for _ in 0..<6 {
            if run.isHittable { break }
            app.swipeUp()
        }
        run.tap()
        XCTAssertTrue(app.navigationBars["Output"].waitForExistence(timeout: 30))
        let output = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "[\"tea\",\"new\"]")).firstMatch
        let ran = output.waitForExistence(timeout: 30)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "pydantic-reading-native-output"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if !ran { print(app.debugDescription) }
        XCTAssertTrue(ran)
    }
}
