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
        app.buttons["Code"].tap()
        XCTAssertTrue(app.buttons["lesson-check"].waitForExistence(timeout: 60))
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "downloaded-course-opens-native-lesson"; proof.lifetime = .keepAlways; add(proof)
    }

    func testNewPyTorchProjectHasLocalCodeAndVisibleAutomaticPackageDownload() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-removeDownload", "runtime-torch", "-openTemplate", "finetune-lora"]
        app.launch()
        let banner = app.buttons["project-downloads"]
        XCTAssertTrue(banner.waitForExistence(timeout: 30))
        banner.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Python packages"].exists)
        let pause = app.buttons["download-pause-runtime-torch"]
        if pause.waitForExistence(timeout: 5) {
            pause.tap()
            XCTAssertTrue(app.buttons["download-resume-runtime-torch"].waitForExistence(timeout: 10))
        }
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "automatic-project-packages-download-manager"; proof.lifetime = .keepAlways; add(proof)
    }
}
