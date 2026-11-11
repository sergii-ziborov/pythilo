import XCTest

@MainActor final class DownloadsNavigationTests: XCTestCase {
    func testCourseDownloadUnlocksReadingAndKeepsTheDownloadControlsVisible() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "learn", "-removeDownload", "course-foundations", "-openLesson", "values-and-names"]
        app.launch()
        let download = app.buttons["download-pack-course-foundations"]
        XCTAssertTrue(download.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["lesson-check"].exists)
        download.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Run example"].firstMatch.waitForExistence(timeout: 60))
        // A phone shows the lesson's code behind a tab; an iPad shows it beside the reading.
        if app.buttons["Code"].exists { app.buttons["Code"].tap() }
        XCTAssertTrue(app.buttons["lesson-check"].waitForExistence(timeout: 60))
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "downloaded-course-opens-native-lesson"; proof.lifetime = .keepAlways; add(proof)
    }

    func testNewPyTorchProjectDownloadsOnlyAfterExplicitAction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-removeDownload", "runtime-torch", "-openTemplate", "finetune-lora"]
        app.launch()
        let banner = app.buttons["project-downloads"]
        XCTAssertTrue(banner.waitForExistence(timeout: 30))
        banner.tap()
        XCTAssertTrue(app.navigationBars["Project downloads"].waitForExistence(timeout: 10))
        let download = app.buttons["download-project-packages"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(download.isEnabled, "Opening a project must leave its missing packages untouched")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Not downloaded")).firstMatch.exists)
        download.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let pause = app.buttons["download-pause-runtime-torch"]
        if pause.waitForExistence(timeout: 5) {
            pause.tap()
            XCTAssertTrue(app.buttons["download-resume-runtime-torch"].waitForExistence(timeout: 10))
            app.buttons["download-resume-runtime-torch"].tap()
        }
        app.buttons["downloads-close"].tap()
        XCTAssertTrue(app.navigationBars["Project downloads"].waitForNonExistence(timeout: 10))
        let menu = app.buttons["project-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertTrue(app.buttons["project-downloads-menu"].waitForExistence(timeout: 5))
        app.buttons["project-downloads-menu"].tap()
        XCTAssertTrue(app.navigationBars["Project downloads"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["offline-ready-download-project-packages"].waitForExistence(timeout: 180))
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "explicit-offline-project-download"; proof.lifetime = .keepAlways; add(proof)
    }

    func testDownloadCategoryPreparesAllItsLabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-removeDownload", "labs-pytorch-training"]
        app.launch()
        XCTAssertTrue(app.buttons["ML · 65"].waitForExistence(timeout: 30))
        app.buttons["ML · 65"].tap()
        let download = app.buttons["download-category-Machine learning"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        XCTAssertTrue(download.isEnabled)
        download.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["offline-ready-download-category-Machine learning"].waitForExistence(timeout: 180))
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "complete-ml-category-offline"; proof.lifetime = .keepAlways; add(proof)
    }
}
