import Foundation
import XCTest

final class TAPVideoPlaybackFixtureUITests: XCTestCase {
    private static let bundleIdentifier = "TAP-NAP.TAPCamDemo"
    private static let openIdentifier = "tap.video.fixture.open"
    private static let failedIdentifier = "tap.video.fixture.failed"
    private static let backIdentifier = "tap.viewer.back"
    private static let rawIdentifier = "tap.viewer.mode.raw"
    private static let twoDIdentifier = "tap.viewer.mode.2d"
    private static let threeDIdentifier = "tap.viewer.mode.3d"
    private static let playPauseIdentifier = "tap.video.playback.transport.playPause"
    private static let scrubberIdentifier = "tap.video.playback.transport.scrubber"
    private static let elapsedIdentifier = "tap.video.playback.transport.elapsed"
    private static let gapIdentifier = "tap.video.playback.depthGapNotice"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGeometryScreenshotMatrix() throws {
        let scenarios = [
            "rotation-0",
            "rotation-90",
            "rotation-180",
            "rotation-270",
            "mirrored",
            "aspect-4x3",
            "aspect-16x9",
            "clean-aperture"
        ]

        for scenario in scenarios {
            let app = launchFixture(scenario: scenario)
            try openFixture(in: app)
            try selectTwoD(in: app)
            keepScreenshot(
                of: app,
                named: "video_\(scenario)_2d_shared-chrome_en_L"
            )
            app.terminate()
        }
    }

    func testRAWTwoDAndCustomTransportScreenshotMatrix() throws {
        let app = launchFixture(
            scenario: "performance-playback-15s"
        )
        try openFixture(in: app)

        assertSharedViewerChrome(in: app)
        let playPause = app.buttons[Self.playPauseIdentifier]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        XCTAssertTrue(playPause.isHittable, "Custom Play control must be physically tappable.")
        keepScreenshot(of: app, named: "video_performance_raw_paused_shared-chrome_en_L")

        playPause.tap()
        XCTAssertTrue(
            waitForElement(playPause, label: "Pause video", timeout: 3),
            "Custom transport did not start playback."
        )
        keepScreenshot(of: app, named: "video_performance_raw_playing_shared-chrome_en_L")

        try selectTwoD(in: app)
        keepScreenshot(of: app, named: "video_performance_2d_playing_shared-chrome_en_L")

        playPause.tap()
        XCTAssertTrue(
            waitForElement(playPause, label: "Play video", timeout: 3),
            "Custom transport did not pause playback."
        )
    }

    func testVideoTwoDModeUsesPhysicalHitAndPublishesSelectedState() throws {
        let app = launchFixture(scenario: "performance-playback-15s")
        try openFixture(in: app)

        let twoD = app.buttons[Self.twoDIdentifier]
        XCTAssertTrue(twoD.isHittable, "2D must not sit behind the player surface.")
        twoD.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            waitForValue(twoD, containing: "Selected", timeout: 3),
            "A physical tap did not select 2D."
        )
        XCTAssertFalse(
            String(describing: app.buttons[Self.rawIdentifier].value).contains("Selected")
        )
        XCTAssertTrue(opacityControl(in: app).waitForExistence(timeout: 3))
    }

    func testCustomTransportCanSeek() throws {
        let app = launchFixture(scenario: "performance-playback-15s")
        try openFixture(in: app)

        let scrubber = app.sliders[Self.scrubberIdentifier]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertTrue(scrubber.isHittable, "Custom video scrubber must be physically hittable.")
        scrubber.adjust(toNormalizedSliderPosition: 0.7)
        let confirmedElapsed = element(Self.elapsedIdentifier, in: app)
        XCTAssertTrue(confirmedElapsed.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForConfirmedElapsed(confirmedElapsed, timeout: 5),
            "AVPlayer did not confirm the seeked position."
        )
    }

    func testGapSeekAndSimplifiedChineseScreenshots() throws {
        var app = launchFixture(scenario: "depth-gap", language: "zh-Hans")
        try openFixture(in: app)
        try selectTwoD(in: app, acceptingSignedGap: true)
        XCTAssertTrue(
            element(Self.gapIdentifier, in: app).waitForExistence(timeout: 8),
            "Expected the automatic seek into the signed depth gap to clear the overlay and show a notice."
        )
        assertSharedViewerChrome(in: app, selectedModeIdentifier: Self.twoDIdentifier)
        XCTAssertTrue(opacityControl(in: app).exists)
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(of: app, named: "video_depth-gap_2d_shared-chrome_zh-Hans_L")
        app.terminate()

        app = launchFixture(scenario: "seek-discontinuity")
        try openFixture(in: app)
        try selectTwoD(in: app)
        Thread.sleep(forTimeInterval: 1.4)
        keepScreenshot(of: app, named: "video_seek-discontinuity_2d_after-seek_en_L")
    }

    func testAccessibilityDynamicTypeScreenshots() throws {
        var app = launchFixture(
            scenario: "performance-playback-15s",
            autoPlay: true,
            accessibilityDynamicType: true
        )
        try openFixture(in: app)
        try selectTwoD(in: app)
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(
            of: app,
            named: "video_performance_2d_shared-chrome_en_AXXXL"
        )
        app.terminate()

        app = launchFixture(
            scenario: "depth-gap",
            language: "zh-Hans",
            accessibilityDynamicType: true
        )
        try openFixture(in: app)
        try selectTwoD(in: app, acceptingSignedGap: true)
        XCTAssertTrue(element(Self.gapIdentifier, in: app).waitForExistence(timeout: 8))
        assertSharedViewerChrome(in: app, selectedModeIdentifier: Self.twoDIdentifier)
        XCTAssertTrue(opacityControl(in: app).exists)
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(
            of: app,
            named: "video_depth-gap_2d_shared-chrome_zh-Hans_AXXXL"
        )
    }

    func testFiveOpenTwoDPlayDismissCycles() throws {
        let app = launchFixture(
            scenario: "performance-playback-15s",
            autoPlay: true
        )
        let holdsForCapture = ProcessInfo.processInfo.environment["TAPCAM_PR7_MEMGRAPH_HOLD"] == "1"

        emitHandshake("TAPCAM_PR7_MEMGRAPH_BASELINE_READY")
        if holdsForCapture {
            Thread.sleep(forTimeInterval: 30)
        }

        for cycle in 1...5 {
            try openFixture(in: app)
            try selectTwoD(in: app)
            Thread.sleep(forTimeInterval: 0.6)
            try dismissFixture(in: app)
            XCTAssertTrue(
                app.buttons[Self.openIdentifier].waitForExistence(timeout: 8),
                "Fixture landing page did not return after lifecycle cycle \(cycle)."
            )
        }

        emitHandshake("TAPCAM_PR7_MEMGRAPH_AFTER_FIVE_READY")
        if holdsForCapture {
            Thread.sleep(forTimeInterval: 30)
        }
    }

    func testPerformanceOpenRGBTwoDPlayTenSecondsDismiss() throws {
        let app = launchFixture(
            scenario: "performance-playback-15s",
            autoPlay: true
        )
        prepareTraceHandshake()
        defer { completeTraceHandshake() }

        try openFixture(in: app)
        XCTAssertFalse(opacityControl(in: app).exists)
        try selectTwoD(in: app)
        Thread.sleep(forTimeInterval: 10)
        try dismissFixture(in: app)

    }

    func testPerformancePlaySeekThreeTimesResumeDismiss() throws {
        let app = launchFixture(
            scenario: "performance-playback-15s",
            autoPlay: true,
            seekScheduleSeconds: [3, 10, 6]
        )
        prepareTraceHandshake()
        defer { completeTraceHandshake() }

        try openFixture(in: app)
        try selectTwoD(in: app)
        Thread.sleep(forTimeInterval: 3)
        try dismissFixture(in: app)

    }

    private func launchFixture(
        scenario: String,
        language: String = "en",
        autoPlay: Bool = false,
        seekScheduleSeconds: [Double]? = nil,
        accessibilityDynamicType: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleIdentifier)
        if ProcessInfo.processInfo.environment["TAPCAM_PR7_ENABLE_ACTIVITY_LOGGING"] == "1" {
            app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "YES"
        }
        app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE"] = "1"
        app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE_SCENARIO"] = scenario
        if autoPlay {
            app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE_AUTOPLAY"] = "1"
        }
        if let seekScheduleSeconds {
            app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE_SEEK_SCHEDULE"] =
                seekScheduleSeconds.map { String($0) }.joined(separator: ",")
        }
        if accessibilityDynamicType {
            app.launchEnvironment[
                "TAPCAM_UI_TEST_VIDEO_FIXTURE_ACCESSIBILITY_DYNAMIC_TYPE"
            ] = "1"
        }
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "zh-Hans" ? "zh_CN" : "en_US"
        ]
        app.launch()

        let open = app.buttons[Self.openIdentifier]
        let failure = element(Self.failedIdentifier, in: app)
        let deadline = Date().addingTimeInterval(scenario == "performance-playback-15s" ? 60 : 35)
        while Date() < deadline {
            if open.exists {
                return app
            }
            if failure.exists {
                XCTFail("Fixture generation failed: \(failure.label)")
                return app
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Fixture \(scenario) did not become ready before the timeout.")
        return app
    }

    private func openFixture(in app: XCUIApplication) throws {
        let open = app.buttons[Self.openIdentifier]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let twoD = app.buttons[Self.twoDIdentifier]
        XCTAssertTrue(twoD.waitForExistence(timeout: 15), "Video viewer chrome did not appear.")
        assertSharedViewerChrome(in: app)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !twoD.isEnabled {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            twoD.isEnabled,
            "Video viewer did not finish manifest, metadata-track, and registration setup."
        )
    }

    private func selectTwoD(
        in app: XCUIApplication,
        acceptingSignedGap: Bool = false
    ) throws {
        let twoD = app.buttons[Self.twoDIdentifier]
        XCTAssertTrue(twoD.waitForExistence(timeout: 10), "2D control is missing.")
        let enabledDeadline = Date().addingTimeInterval(10)
        while Date() < enabledDeadline, !twoD.isEnabled {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(twoD.isEnabled, "Fixture registration did not enable 2D playback.")
        XCTAssertTrue(twoD.isHittable, "2D control is covered by the video player surface.")
        twoD.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let opacity = opacityControl(in: app)
        guard opacity.waitForExistence(timeout: 3) else {
            keepScreenshot(of: app, named: "diagnostic_2d-control-missing")
            XCTFail("2D opacity control did not appear.")
            return
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if String(describing: twoD.value).contains("Selected, Ready") {
                return
            }
            if acceptingSignedGap, element(Self.gapIdentifier, in: app).exists {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let preparing = element("tap.video.playback.2d.preparing", in: app)
        let gap = element(Self.gapIdentifier, in: app)
        XCTFail(
            "2D readiness did not publish its first registered depth frame "
                + "(modeValue=\(String(describing: twoD.value)), "
                + "preparing=\(preparing.exists), gap=\(gap.exists))."
        )
    }

    private func dismissFixture(in app: XCUIApplication) throws {
        let back = app.buttons[Self.backIdentifier]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back control is missing.")
        back.tap()
        XCTAssertTrue(app.buttons[Self.openIdentifier].waitForExistence(timeout: 8))
    }

    private func assertSharedViewerChrome(
        in app: XCUIApplication,
        selectedModeIdentifier: String? = nil
    ) {
        let back = app.buttons[Self.backIdentifier]
        let share = app.buttons["tap.viewer.share"]
        let delete = app.buttons["tap.viewer.delete"]
        XCTAssertTrue(back.exists && back.isHittable)
        XCTAssertTrue(share.exists && share.isHittable)
        XCTAssertTrue(delete.exists && delete.isHittable)

        let raw = app.buttons[Self.rawIdentifier]
        let twoD = app.buttons[Self.twoDIdentifier]
        let threeD = app.buttons[Self.threeDIdentifier]
        XCTAssertTrue(raw.exists && raw.isEnabled && raw.isHittable)
        XCTAssertTrue(twoD.exists)
        XCTAssertTrue(threeD.exists)
        let expectedSelectedModeIdentifier = selectedModeIdentifier ?? Self.rawIdentifier
        XCTAssertTrue(
            String(describing: app.buttons[expectedSelectedModeIdentifier].value).contains("Selected"),
            "The expected viewer mode did not publish its selected state."
        )
        XCTAssertFalse(threeD.isEnabled, "Video 3D must remain visible but disabled.")
        XCTAssertTrue(
            String(describing: threeD.value).contains("Unavailable for video")
        )
        XCTAssertTrue(app.buttons[Self.playPauseIdentifier].exists)
        XCTAssertTrue(app.sliders[Self.scrubberIdentifier].exists)
    }

    private func waitForElement(
        _ element: XCUIElement,
        label: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == label {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.label == label
    }

    private func waitForValue(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if String(describing: element.value).contains(text) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return String(describing: element.value).contains(text)
    }

    private func waitForConfirmedElapsed(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = element.value as? String ?? ""
            if !value.isEmpty, value != "0:00" {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let value = element.value as? String ?? ""
        return !value.isEmpty && value != "0:00"
    }

    private func opacityControl(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "2D overlay opacity"))
            .firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryPath = ProcessInfo.processInfo.environment[
            "TAPCAM_PR7_SCREENSHOT_DIRECTORY"
        ] ?? "/tmp/TAPCamDemo-PR7/runtime-screenshots"
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try? screenshot.pngRepresentation.write(
            to: directoryURL.appendingPathComponent("\(name).png"),
            options: .atomic
        )
    }

    private func prepareTraceHandshake() {
        emitHandshake("TAPCAM_PR7_READY_FOR_TRACE")
        if ProcessInfo.processInfo.environment["TAPCAM_PR7_TRACE_HANDSHAKE"] == "1" {
            Thread.sleep(forTimeInterval: 10)
        }
    }

    private func completeTraceHandshake() {
        emitHandshake("TAPCAM_PR7_TRACE_COMPLETE")
        Thread.sleep(forTimeInterval: 2)
    }

    private func emitHandshake(_ value: String) {
        FileHandle.standardError.write(Data("\(value)\n".utf8))
    }
}
