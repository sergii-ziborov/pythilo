import XCTest

/// A Labs topic card on a narrow phone: its text, Download button, Pause and "N of M ready"
/// must never be drawn on top of each other, before, during or after a partial download.
@MainActor
final class LabsCardLayoutTests: XCTestCase {
    func testTopicDownloadControlsNeverOverlapTheirText() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tab", "labs", "-removeDownload", "labs-pytorch-training"]
        app.launch()
        XCTAssertTrue(app.buttons["ML · 65"].waitForExistence(timeout: 30))
        app.buttons["ML · 65"].tap()
        let topic = app.buttons["labs-topic-pytorch-training"]
        for _ in 0..<5 { if topic.isHittable { break }; app.swipeUp() }
        tapVisiblePadding(topic, in: app, offset: CGVector(dx: 0.5, dy: 0.85))

        let id = "download-pack-labs-pytorch-training"
        let download = app.buttons[id]
        let note = app.staticTexts["Save this topic, its packages and data to use it offline."]
        for _ in 0..<8 { if download.exists && download.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        XCTAssertTrue(note.exists)
        assertApart(note, download, "the description and the Download button")
        attach(app, "labs-card-ready-to-download")

        download.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let status = app.staticTexts["offline-status-\(id)"]
        for _ in 0..<60 where !status.exists && download.exists { Thread.sleep(forTimeInterval: 0.5) }
        if !status.exists && !download.exists {
            // PyTorch was already on this device: only the small topic pack downloaded, at once,
            // and a topic that is offline hides its download row.
            XCTAssertTrue(app.buttons["lab-torchclip"].exists)
            attach(app, "labs-card-offline-at-once")
            return
        }
        XCTAssertTrue(status.exists)
        let pause = app.buttons["pause-\(id)"]
        assertApart(note, download, "the description and the busy button")
        assertApart(status, download, "the status and the busy button")
        if pause.exists {
            assertApart(status, pause, "the status and Pause")
            attach(app, "labs-card-downloading")
            pause.tap()
        }

        // Paused part-way: the user's case, a Download button beside "1 of 2 ready".
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        let resumed = NSPredicate(format: "isEnabled == true")
        expectation(for: resumed, evaluatedWith: download)
        waitForExpectations(timeout: 30)
        if status.exists {
            assertApart(status, download, "the partial status and the Download button")
            assertApart(note, status, "the description and the partial status")
        }
        attach(app, "labs-card-partly-downloaded")
    }

    private func assertApart(_ a: XCUIElement, _ b: XCUIElement, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let overlap = a.frame.intersection(b.frame)
        XCTAssertTrue(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                      "\(what) overlap: \(a.frame) and \(b.frame)", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
