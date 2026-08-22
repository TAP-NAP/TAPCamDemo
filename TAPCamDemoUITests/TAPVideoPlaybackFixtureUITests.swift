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
    private static let shareIdentifier = "tap.viewer.share"
    private static let opacityIdentifier = "tap.viewer.opacity"
    private static let edgeToastIdentifier = "tap.viewer.edgeToast"
    private static let selectedValueTokens = ["Selected", "已选中"]
    private static let selectedReadyValueTokens = [
        "Selected, Ready",
        "已选中，已就绪"
    ]
    private static let comingSoonValueTokens = ["Coming soon", "即将推出"]
    private static let pauseLabelTokens = ["Pause video", "暂停视频"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testVideoTwoDModeUsesPhysicalHitAndPublishesSelectedState() throws {
        let app = launchFixture(scenario: "performance-playback-15s")
        try openFixture(in: app)

        let twoD = app.buttons[Self.twoDIdentifier]
        XCTAssertTrue(twoD.isHittable, "2D must not sit behind the player surface.")
        twoD.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            waitForValue(
                twoD,
                containingAny: Self.selectedValueTokens,
                timeout: 3
            ),
            "A physical tap did not select 2D."
        )
        XCTAssertFalse(
            value(
                of: app.buttons[Self.rawIdentifier],
                containsAny: Self.selectedValueTokens
            )
        )
        XCTAssertTrue(opacityControl(in: app).waitForExistence(timeout: 3))
    }

    func testShareOpensAnchoredSelectorBeforePlayerReadinessAndKeepsChromeStable() throws {
        let app = launchFixture(
            scenario: "rotation-0",
            playerReadinessDelayMilliseconds: 8_000
        )

        let open = app.buttons[Self.openIdentifier]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let share = app.buttons[Self.shareIdentifier]
        XCTAssertTrue(
            share.waitForExistence(timeout: 3),
            "Share must mount with the stable Viewer chrome."
        )
        XCTAssertTrue(
            share.isHittable,
            "Video Share must be physically tappable while AVPlayer is still preparing."
        )
        // The transport is mounted only after AVPlayer exists. Its absence is
        // the runtime proof that Share readiness is independent of player
        // readiness rather than merely happening to work after a fast load.
        XCTAssertFalse(
            app.buttons[Self.playPauseIdentifier].exists,
            "The fixture timing seam did not preserve the pre-player-readiness state."
        )

        let stableChrome = [
            app.buttons[Self.backIdentifier],
            share,
            app.buttons["tap.viewer.delete"],
            app.buttons[Self.rawIdentifier],
            app.buttons[Self.twoDIdentifier],
            app.buttons[Self.threeDIdentifier]
        ]
        for control in stableChrome {
            XCTAssertTrue(
                control.exists,
                "The stable Viewer chrome is incomplete before Share opens."
            )
        }
        share.tap()

        // Assert the native presentation role, not only a SwiftUI identifier:
        // compact adaptation must remain an anchored Popover on iPhone.
        let presentation = app.popovers.firstMatch
        XCTAssertTrue(
            presentation.waitForExistence(timeout: 2),
            "Share did not open the app-owned anchored presentation."
        )
        let shareVideo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Share Video")
        ).firstMatch
        XCTAssertTrue(
            shareVideo.waitForExistence(timeout: 1),
            "The anchored selector did not expose the video share choice."
        )
        XCTAssertLessThan(
            presentation.frame.width,
            app.frame.width * 0.9,
            "The app-owned selector adapted to a full-screen sheet instead of an anchor."
        )
        XCTAssertFalse(
            app.buttons[Self.playPauseIdentifier].exists,
            "Share could only be opened after player readiness, violating the interaction contract."
        )

        for control in stableChrome {
            XCTAssertTrue(control.exists, "Share presentation removed Viewer chrome.")
        }
        XCTAssertTrue(
            value(of: app.buttons[Self.rawIdentifier], containsAny: Self.selectedValueTokens),
            "Opening Share changed the selected Viewer mode."
        )
    }

    func testVideoThreeDShowsComingSoonWithoutChangingModeOrPlayback() throws {
        let app = launchFixture(
            scenario: "performance-playback-15s",
            autoPlay: true
        )
        try openFixture(in: app)

        let raw = app.buttons[Self.rawIdentifier]
        let threeD = app.buttons[Self.threeDIdentifier]
        let playPause = app.buttons[Self.playPauseIdentifier]
        XCTAssertTrue(threeD.isEnabled && threeD.isHittable)
        XCTAssertTrue(
            waitForElement(
                playPause,
                labelContainingAny: Self.pauseLabelTokens,
                timeout: 3
            ),
            "The fixture did not begin playback before the 3D interaction."
        )

        threeD.tap()
        let toast = element(Self.edgeToastIdentifier, in: app)
        XCTAssertTrue(toast.waitForExistence(timeout: 2))
        XCTAssertTrue(Self.comingSoonValueTokens.contains(toast.label))
        XCTAssertTrue(value(of: raw, containsAny: Self.selectedValueTokens))
        XCTAssertFalse(value(of: threeD, containsAny: Self.selectedValueTokens))
        XCTAssertTrue(Self.pauseLabelTokens.contains(playPause.label))
        keepScreenshot(of: app, named: "video_3d_coming-soon_toolbar_en_L")

        Thread.sleep(forTimeInterval: 1.2)
        threeD.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(
            toast.exists,
            "A repeated 3D tap must refresh the current toast dismissal token."
        )
        XCTAssertEqual(
            app.staticTexts.matching(identifier: Self.edgeToastIdentifier).count,
            1,
            "Repeated 3D taps must replace one toast instead of stacking copies."
        )
        XCTAssertTrue(value(of: raw, containsAny: Self.selectedValueTokens))
        XCTAssertTrue(Self.pauseLabelTokens.contains(playPause.label))
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

    private func launchFixture(
        scenario: String,
        language: String = "en",
        appLanguage: String? = nil,
        autoPlay: Bool = false,
        seekScheduleSeconds: [Double]? = nil,
        accessibilityDynamicType: Bool = false,
        playerReadinessDelayMilliseconds: Int? = nil
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
        if let playerReadinessDelayMilliseconds {
            app.launchEnvironment[
                "TAPCAM_UI_TEST_VIDEO_FIXTURE_PLAYER_READINESS_DELAY_MS"
            ] = String(playerReadinessDelayMilliseconds)
        }
        let appLanguageRawValue = appLanguage ?? language
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "zh-Hans" ? "zh_CN" : "en_US",
            "-TAPCamDemo.AppLanguage", appLanguageRawValue
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

    private func selectTwoD(in app: XCUIApplication) throws {
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
            if value(of: twoD, containsAny: Self.selectedReadyValueTokens) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let preparing = element("tap.video.playback.2d.preparing", in: app)
        XCTFail(
            "2D readiness did not publish its first registered depth frame "
                + "(modeValue=\(String(describing: twoD.value)), "
                + "preparing=\(preparing.exists))."
        )
    }

    private func assertSimplifiedChineseViewerCopy(in app: XCUIApplication) {
        XCTAssertEqual(app.buttons["tap.viewer.share"].label, "分享视频")
        XCTAssertEqual(app.buttons["tap.viewer.delete"].label, "删除视频")
        XCTAssertEqual(app.buttons[Self.threeDIdentifier].label, "3D 投影")
        XCTAssertTrue(
            value(
                of: app.buttons[Self.threeDIdentifier],
                containsAny: ["即将推出"]
            )
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
            value(
                of: app.buttons[expectedSelectedModeIdentifier],
                containsAny: Self.selectedValueTokens
            ),
            "The expected viewer mode did not publish its selected state."
        )
        XCTAssertTrue(
            threeD.isEnabled && threeD.isHittable,
            "Video 3D must remain visible and physically tappable."
        )
        XCTAssertTrue(
            value(of: threeD, containsAny: Self.comingSoonValueTokens)
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

    private func waitForElement(
        _ element: XCUIElement,
        labelContainingAny tokens: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tokens.contains(element.label) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return tokens.contains(element.label)
    }

    private func waitForValue(
        _ element: XCUIElement,
        containingAny tokens: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value(of: element, containsAny: tokens) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return value(of: element, containsAny: tokens)
    }

    private func value(
        of element: XCUIElement,
        containsAny tokens: [String]
    ) -> Bool {
        let publishedValue = String(describing: element.value)
        return tokens.contains { publishedValue.contains($0) }
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
        element(Self.opacityIdentifier, in: app)
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
