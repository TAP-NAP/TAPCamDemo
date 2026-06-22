import XCTest

final class ShutterCaptureSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingShutterRequestsDepthCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "YES"
        app.launchEnvironment["TAPCAM_UI_TEST_REAL_APP"] = "1"

        addPermissionInterruptionMonitor()
        app.launch()
        dismissPermissionAlertIfNeeded(in: app)

        let shutter = app.buttons["camera.capture.shutter"]
        XCTAssertTrue(
            shutter.waitForExistence(timeout: 30),
            "Expected the camera shutter accessibility element to be available."
        )

        let status = app.staticTexts["camera.capture.status"]
        let previousStatus = status.exists ? status.label : ""

        shutter.tap()
        dismissPermissionAlertIfNeeded(in: app)

        XCTAssertTrue(
            waitForCaptureStatusChange(in: app, previousStatus: previousStatus, timeout: 20),
            "Expected tapping the shutter to move the capture status forward."
        )
    }

    private func addPermissionInterruptionMonitor() {
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in Self.preferredPermissionButtonTitles where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    private func dismissPermissionAlertIfNeeded(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in Self.preferredPermissionButtonTitles where springboard.buttons[title].exists {
            springboard.buttons[title].tap()
            return
        }

        app.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func waitForCaptureStatusChange(
        in app: XCUIApplication,
        previousStatus: String,
        timeout: TimeInterval
    ) -> Bool {
        let status = app.staticTexts["camera.capture.status"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            dismissPermissionAlertIfNeeded(in: app)

            if status.exists,
               status.label != previousStatus,
               Self.acceptedCaptureStatusPrefixes.contains(where: status.label.hasPrefix) {
                return true
            }

            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static let preferredPermissionButtonTitles = [
        "Allow",
        "Allow Full Access",
        "Allow Access to All Photos",
        "OK",
        "Continue"
    ]

    private static let acceptedCaptureStatusPrefixes = [
        "Capture queued",
        "Capture saved",
        "Capture failed"
    ]
}
