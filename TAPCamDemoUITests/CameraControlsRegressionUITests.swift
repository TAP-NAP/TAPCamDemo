import XCTest

final class CameraControlsRegressionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCameraControlToolbarAndAdjustmentStripsRespondToSimulatedClicks() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "YES"
        app.launchEnvironment["TAPCAM_UI_TEST_REAL_APP"] = "1"
        app.launchEnvironment["TAPCAM_UI_TEST_CAMERA_CONTROLS"] = "1"
        app.launchArguments.append("--tapcam-camera-controls-ui-test-harness")
        app.launch()

        XCTAssertTrue(app.staticTexts["Camera Controls UI Harness"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForStatus(in: app, containing: "Ready"))

        let shutter = app.buttons["camera.capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 2))
        let proShutterFrame = shutter.frame

        let togglePro = app.buttons["camera.controlsHarness.togglePro"]
        XCTAssertTrue(togglePro.waitForExistence(timeout: 2))
        togglePro.tap()
        XCTAssertTrue(waitForStatus(in: app, containing: "Standard active"))
        assertFrame(shutter.frame, equals: proShutterFrame, accuracy: 1)

        togglePro.tap()
        XCTAssertTrue(waitForStatus(in: app, containing: "PRO active"))
        assertFrame(shutter.frame, equals: proShutterFrame, accuracy: 1)

        tapButton("camera.lowerToolbar.ev", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        drag(strip: strip(in: app), from: 0.50, to: 0.90)
        XCTAssertTrue(waitForStatus(in: app, containing: "EV"))

        tapButton("camera.lowerToolbar.iso", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForStatus(in: app, containing: "ISO strip shown"))
        assertAutomaticState(in: app)
        drag(strip: strip(in: app), from: 0.35, to: 0.68)
        XCTAssertTrue(waitForStatus(in: app, containing: "ISO"))
        restoreAuto(in: app)
        XCTAssertTrue(waitForStatus(in: app, containing: "ISO Auto restored"))
        assertAutomaticState(in: app)

        tapButton("camera.lowerToolbar.shutter", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForStatus(in: app, containing: "Shutter strip shown"))
        drag(strip: strip(in: app), from: 0.35, to: 0.65)
        XCTAssertTrue(waitForStatus(in: app, containing: "Shutter"))
        restoreAuto(in: app)
        XCTAssertTrue(waitForStatus(in: app, containing: "Shutter Auto restored"))

        tapButton("camera.lowerToolbar.focus", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForStatus(in: app, containing: "Focus strip shown"))
        drag(strip: strip(in: app), from: 0.45, to: 0.68)
        XCTAssertTrue(waitForStatus(in: app, containing: "MF"))
        restoreAuto(in: app)
        XCTAssertTrue(waitForStatus(in: app, containing: "Focus Auto restored"))

        tapButton("camera.lowerToolbar.focus", in: app)
        XCTAssertTrue(waitForStatus(in: app, containing: "Controls hidden"))

        let videoMode = app.buttons["camera.mode.video"]
        XCTAssertTrue(videoMode.waitForExistence(timeout: 2))
        videoMode.tap()
        XCTAssertTrue(waitForStatus(in: app, containing: "VIDEO selected"))
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 1) {
            button.tap()
            return
        }

        let fallbackButton = fallbackButton(for: identifier, in: app)
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 5), "Missing button \(identifier)")
        fallbackButton.tap()
    }

    private func fallbackButton(for identifier: String, in app: XCUIApplication) -> XCUIElement {
        switch identifier {
        case "camera.lowerToolbar.ev":
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "EV")).firstMatch
        case "camera.lowerToolbar.iso":
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ISO")).firstMatch
        case "camera.lowerToolbar.shutter":
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "S")).firstMatch
        case "camera.lowerToolbar.focus":
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "focus")).firstMatch
        default:
            app.buttons[identifier]
        }
    }

    private func strip(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["camera.tickedAdjustmentStrip"]
    }

    private func restoreAuto(in app: XCUIApplication) {
        let manualButton = app.buttons["camera.tickedAdjustmentStrip.automation"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 2))
        XCTAssertTrue(manualButton.isHittable)
        manualButton.tap()
    }

    private func assertAutomaticState(in app: XCUIApplication) {
        let identifier = "camera.tickedAdjustmentStrip.automation"
        let state = app.descendants(matching: .any)[identifier]
        let automaticState = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "exists == true AND label CONTAINS[c] %@",
                "Auto"
            ),
            object: state
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [automaticState], timeout: 2),
            .completed
        )
        XCTAssertFalse(app.buttons[identifier].exists)
    }

    private func drag(strip: XCUIElement, from startX: CGFloat, to endX: CGFloat) {
        let start = strip.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
        let end = strip.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func waitForStatus(
        in app: XCUIApplication,
        containing text: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let status = app.staticTexts.matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if status.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}
