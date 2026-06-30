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

        tapButton("camera.lowerToolbar.ev", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        drag(strip: strip(in: app), from: 0.50, to: 0.90)
        XCTAssertTrue(waitForStatus(in: app, containing: "EV"))

        tapButton("camera.lowerToolbar.iso", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        drag(strip: strip(in: app), from: 0.20, to: 0.74)
        XCTAssertTrue(waitForStatus(in: app, containing: "ISO"))

        tapButton("camera.lowerToolbar.shutter", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        drag(strip: strip(in: app), from: 0.30, to: 0.64)
        XCTAssertTrue(waitForStatus(in: app, containing: "Shutter"))

        tapButton("camera.lowerToolbar.focus", in: app)
        XCTAssertTrue(strip(in: app).waitForExistence(timeout: 2))
        drag(strip: strip(in: app), from: 0.50, to: 0.82)
        XCTAssertTrue(waitForStatus(in: app, containing: "MF"))

        tapButton("camera.lowerToolbar.focus", in: app)
        XCTAssertTrue(waitForStatus(in: app, containing: "AF restored"))

        let videoMode = app.buttons["VIDEO mode coming soon"]
        XCTAssertTrue(videoMode.waitForExistence(timeout: 2))
        videoMode.tap()
        XCTAssertTrue(waitForStatus(in: app, containing: "Coming soon"))
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
}
