import XCTest

@MainActor
final class InteractionNavigationTests: XCTestCase {
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

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: to))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMostlyVerticalDragsDoNotOpenOrCloseTheFileDrawer() throws {
        let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", "left", "-pythilo.drawerSwipe", "YES"])
        XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
        drag(app, from: CGVector(dx: 0.01, dy: 0.8), to: CGVector(dx: 0.42, dy: 0.15))
        capture("vertical-edge-drag")
        XCTAssertFalse(app.buttons["Close files"].exists, "A mostly vertical gesture must not open files")
        drag(app, from: CGVector(dx: 0.01, dy: 0.45), to: CGVector(dx: 0.8, dy: 0.45))
        XCTAssertTrue(app.buttons["Close files"].waitForExistence(timeout: 5))
        drag(app, from: CGVector(dx: 0.65, dy: 0.8), to: CGVector(dx: 0.25, dy: 0.15))
        XCTAssertTrue(app.buttons["Close files"].exists, "Vertical scrolling must not dismiss files")
    }

    func testFileDrawerSwipesFromBothEdgesAndOutsideTap() throws {
        for side in ["left", "right"] {
            let left = side == "left"
            let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", side, "-pythilo.drawerSwipe", "YES"])
            XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
            drag(app, from: CGVector(dx: left ? 0.01 : 0.99, dy: 0.45), to: CGVector(dx: left ? 0.8 : 0.2, dy: 0.45))
            XCTAssertTrue(app.buttons["Close files"].waitForExistence(timeout: 5), side)
            XCTAssertTrue(app.textFields["Find a file"].exists)
            capture("drawer-open-\(side)")
            drag(app, from: CGVector(dx: left ? 0.7 : 0.3, dy: 0.6), to: CGVector(dx: left ? 0.01 : 0.99, dy: 0.6))
            XCTAssertFalse(app.buttons["Close files"].exists, side)
            drag(app, from: CGVector(dx: left ? 0.01 : 0.99, dy: 0.45), to: CGVector(dx: left ? 0.8 : 0.2, dy: 0.45))
            XCTAssertTrue(app.buttons["Close files"].waitForExistence(timeout: 5))
            app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.97 : 0.03, dy: 0.5)).tap()
            XCTAssertFalse(app.buttons["Close files"].exists)
            app.terminate()
        }
    }

    func testDownloadsOpenAsAModalAndCloseFromEveryMainTab() throws {
        for tab in ["projects", "learn", "labs", "playground"] {
            let app = launch(["-tab", tab])
            let downloads = app.buttons["downloads-open"].firstMatch
            XCTAssertTrue(downloads.waitForExistence(timeout: 30), tab)
            downloads.tap()
            XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
            let bar = app.navigationBars["Downloads"].frame
            if app.frame.width > 600 {
                XCTAssertLessThan(bar.width, app.frame.width * 0.9)
                XCTAssertEqual(bar.midX, app.frame.midX, accuracy: 16)
            }
            capture("downloads-modal-\(tab)")
            let close = app.buttons["downloads-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 3), "Downloads needs an explicit modal close action: \(tab)")
            close.tap()
            XCTAssertFalse(app.navigationBars["Downloads"].exists)
            XCTAssertTrue(downloads.exists)
            app.terminate()
        }
    }

    func testDownloadRemovalUsesACenteredAlertAndCancelKeepsTheCourse() throws {
        let app = launch(["-tab", "learn", "-openCourse", "foundations"])
        let download = app.buttons["download-pack-course-foundations"]
        XCTAssertTrue(download.waitForExistence(timeout: 30))
        if download.isEnabled { download.tap() }
        XCTAssertTrue(app.staticTexts["offline-ready-download-pack-course-foundations"].waitForExistence(timeout: 60))
        let remove = app.buttons["Remove"].firstMatch
        tapVisiblePadding(remove, in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "Destructive confirmation must be a centered alert, including on iPad")
        XCTAssertEqual(alert.frame.midX, app.frame.midX, accuracy: 16)
        capture("download-remove-centered-alert")
        XCTAssertTrue(alert.buttons["Remove download"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["offline-ready-download-pack-course-foundations"].exists)
        remove.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Remove download"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: download)
        waitForExpectations(timeout: 10)
        download.tap()
        XCTAssertTrue(app.staticTexts["offline-ready-download-pack-course-foundations"].waitForExistence(timeout: 60))
    }

    func testEdgeBackSwipeReturnsFromCourseAndLinkedLesson() throws {
        let app = launch(["-tab", "learn", "-openCourse", "foundations"])
        XCTAssertTrue(app.buttons["download-pack-course-foundations"].waitForExistence(timeout: 30))
        drag(app, from: CGVector(dx: 0.005, dy: 0.45), to: CGVector(dx: 0.85, dy: 0.45))
        XCTAssertTrue(app.buttons["learn-continue"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-tab", "labs", "-openLab", "rocauc"]
        app.launch()
        let lesson = app.buttons["lab-lesson-stat-roc-auc"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 30))
        tapVisiblePadding(lesson, in: app)
        XCTAssertTrue(app.buttons["lesson-lab-rocauc"].waitForExistence(timeout: 5))
        drag(app, from: CGVector(dx: 0.005, dy: 0.45), to: CGVector(dx: 0.85, dy: 0.45))
        XCTAssertTrue(app.buttons["lab-answer"].waitForExistence(timeout: 5))
    }

    func testLabFiltersScrollLeftAndRightWithoutChangingTabs() throws {
        let app = launch(["-tab", "labs"])
        let ml = app.buttons["ML · 65"]
        XCTAssertTrue(ml.waitForExistence(timeout: 30))
        let rowY = ml.frame.midY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: rowY)).press(forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: rowY)))
        let algorithms = app.buttons["Algorithms · 10"]
        XCTAssertTrue(algorithms.isHittable)
        algorithms.tap()
        XCTAssertTrue(app.staticTexts["ALGORITHMS · 10"].waitForExistence(timeout: 5))
        origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: rowY)).press(forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: rowY)))
        XCTAssertTrue(ml.isHittable)
        ml.tap()
        XCTAssertTrue(app.staticTexts["MACHINE LEARNING · 65"].waitForExistence(timeout: 5))
    }

    func testDownloadsDismissBySwipingDownAndCanReopen() throws {
        let app = launch(["-tab", "projects"])
        let open = app.buttons["downloads-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()
        XCTAssertTrue(app.buttons["downloads-close"].waitForExistence(timeout: 5))
        let bar = app.navigationBars["Downloads"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: bar.midX, dy: bar.minY - 12)).press(forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: bar.midX, dy: min(app.frame.maxY - 20, bar.minY + app.frame.height * 0.7))))
        XCTAssertTrue(app.buttons["downloads-close"].waitForNonExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["downloads-close"].waitForExistence(timeout: 5))
        app.buttons["downloads-close"].tap()
    }

    func testProjectDownloadsKeepCloseActionAfterNavigation() throws {
        let app = launch(["-openTemplate", "blank"])
        let menu = app.buttons["project-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        app.buttons["project-downloads-menu"].tap()
        XCTAssertTrue(app.navigationBars["Project downloads"].waitForExistence(timeout: 5))
        let all = app.buttons["downloads-all"]
        for _ in 0..<8 { if all.isHittable { break }; app.scrollViews["project-downloads-content"].swipeUp() }
        all.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["downloads-close"].exists)
        let bar = app.navigationBars["Downloads"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: bar.minX + 2, dy: bar.maxY + 120)).press(forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: bar.maxX - 20, dy: bar.maxY + 120)))
        XCTAssertTrue(app.navigationBars["Project downloads"].waitForExistence(timeout: 5))
        all.tap()
        app.buttons["downloads-close"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Downloads"].exists)
    }

    func testNewProjectCanBeCancelledAndTestProjectDeletionUsesAnAlert() throws {
        let app = launch(["-tab", "projects"])
        let new = app.buttons["project-new"]
        XCTAssertTrue(new.waitForExistence(timeout: 30))
        new.tap()
        XCTAssertTrue(app.textFields["project-name"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(new.exists)
        new.tap()
        let name = "interaction-qa-" + UUID().uuidString.prefix(8)
        let field = app.textFields["project-name"]
        field.tap(); field.typeText(String(name))
        app.buttons["project-create"].tap()
        let back = app.buttons["Back to projects"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        let project = app.buttons["project-" + name]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.press(forDuration: 1)
        app.buttons["Delete"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(project.exists)
        project.press(forDuration: 1)
        app.buttons["Delete"].tap()
        alert.buttons["Delete"].tap()
        XCTAssertTrue(project.waitForNonExistence(timeout: 5))
    }

    func testLabResetAndAnswerUseModalWindows() throws {
        let app = launch(["-tab", "labs", "-openLab", "attention"])
        let reset = app.buttons["Start over"]
        XCTAssertTrue(reset.waitForExistence(timeout: 30))
        tapVisiblePadding(reset, in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        tapVisiblePadding(app.buttons["lab-answer"], in: app)
        XCTAssertTrue(app.buttons["Use it"].waitForExistence(timeout: 5))
        app.buttons["Use it"].tap()
        tapVisiblePadding(app.buttons["lab-trace"], in: app)
        XCTAssertTrue(app.staticTexts["Every check passed"].waitForExistence(timeout: 30))
        capture("lab-answer-modal-runs")
    }

    func testDisabledEdgeSwipesStillAllowTheFilesButton() throws {
        let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", "left", "-pythilo.drawerSwipe", "NO"])
        XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
        drag(app, from: CGVector(dx: 0.01, dy: 0.45), to: CGVector(dx: 0.85, dy: 0.45))
        XCTAssertFalse(app.buttons["Close files"].exists)
        app.buttons["Open project files"].tap()
        XCTAssertTrue(app.buttons["Close files"].waitForExistence(timeout: 5))
        app.buttons["Close files"].tap()
        XCTAssertFalse(app.buttons["Close files"].exists)
    }

    func testWorkspacePanelButtonsRemainUsable() throws {
        let app = launch(["-openTemplate", "blank"])
        XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
        let panels = app.frame.width > 600 ? ["terminal", "output", "problems", "debug"] : ["terminal", "output", "problems", "debug", "code"]
        for panel in panels {
            let button = app.buttons["panel-" + panel].firstMatch
            XCTAssertTrue(button.exists, panel)
            button.tap()
            XCTAssertTrue(button.isSelected, panel)
        }
        capture("workspace-panels")
    }

    func testLandscapeDrawerSwipesAndWorkspaceControls() throws {
        let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", "left", "-pythilo.drawerSwipe", "YES"])
        XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .landscapeLeft
        let deadline = Date().addingTimeInterval(10)
        while app.frame.width < app.frame.height && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        drag(app, from: CGVector(dx: 0.01, dy: 0.45), to: CGVector(dx: 0.55, dy: 0.45))
        XCTAssertTrue(app.buttons["Close files"].waitForExistence(timeout: 5))
        drag(app, from: CGVector(dx: 0.3, dy: 0.6), to: CGVector(dx: 0.01, dy: 0.6))
        XCTAssertFalse(app.buttons["Close files"].exists)
        for panel in ["terminal", "output", "problems", "debug", "code"] {
            let button = app.buttons["panel-" + panel].firstMatch
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(app.frame.contains(button.frame), panel)
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)).tap()
            XCTAssertTrue(button.isSelected, panel)
        }
        capture("landscape-gesture-controls")
        XCUIDevice.shared.orientation = .portrait
    }

    func testFileDeletionUsesAnAlertAndPreservesTheFileOnCancel() throws {
        let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", "left"])
        XCTAssertTrue(app.buttons["run-button"].waitForExistence(timeout: 30))
        if app.buttons["Open project files"].exists { app.buttons["Open project files"].tap() }
        app.buttons["New file"].tap()
        let name = "interaction-" + UUID().uuidString.prefix(8) + ".txt"
        let path = app.textFields["new-item-path"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(path.waitForExistence(timeout: 5), "The focused form must survive rotation")
        path.tap(); path.typeText(name)
        app.buttons["new-item-create"].tap()
        XCUIDevice.shared.orientation = .portrait
        if app.buttons["Open project files"].exists && !app.buttons["Close files"].exists {
            app.buttons["Open project files"].tap()
        }
        let file = app.buttons["tree-" + name]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.press(forDuration: 1)
        app.buttons["Delete"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(file.exists)
        file.press(forDuration: 1)
        app.buttons["Delete"].tap()
        alert.buttons["Delete"].tap()
        XCTAssertTrue(file.waitForNonExistence(timeout: 5))
    }

    func testProjectLinkShareWindowOpensAndDismissesWithoutSending() throws {
        let app = launch(["-openTemplate", "blank"])
        let menu = app.buttons["project-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        app.buttons["share-snapshot-link"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy' OR label == 'Copy Link'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Sharing must survive rotation")
        capture("project-link-share-window")
        app.buttons["project-share-close"].tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
    }

    func testDrawerGestureDoesNotCoverTheBackButtonsPadding() throws {
        let app = launch(["-openTemplate", "blank", "-pythilo.drawerSide", "left", "-pythilo.drawerSwipe", "YES"])
        let back = app.buttons["Back to projects"]
        XCTAssertTrue(back.waitForExistence(timeout: 30))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8)).tap()
        XCTAssertTrue(app.buttons["project-new"].waitForExistence(timeout: 5))
    }
}
