import Foundation
import XCTest

final class TAPVideoPlaybackFixtureUITests: XCTestCase {
    private static let bundleIdentifier = "TAP-NAP.TAPCamDemo"
    private static let openIdentifier = "tap.video.fixture.open"
    private static let failedIdentifier = "tap.video.fixture.failed"
    private static let rawIdentifier = "tap.viewer.mode.raw"
    private static let twoDIdentifier = "tap.viewer.mode.2d"
    private static let threeDIdentifier = "tap.viewer.mode.3d"
    private static let playPauseIdentifier = "tap.video.playback.transport.playPause"
    private static let scrubberIdentifier = "tap.video.playback.transport.scrubber"
    private static let elapsedIdentifier = "tap.video.playback.transport.elapsed"
    private static let shareIdentifier = "tap.viewer.share"
    private static let opacityIdentifier = "tap.viewer.opacity"
    private static let selectedValueTokens = ["Selected", "已选中"]
    private static let selectedReadyValueTokens = [
        "Selected, Ready",
        "已选中，已就绪"
    ]
    private static let unavailableThreeDValueTokens = ["3D depth unavailable"]
    private static let pauseLabelTokens = ["Pause video", "暂停视频"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPendingPhotoDeleteConfirmationCanBeCancelledAndOpenedAgain() {
        assertPendingDeleteConfirmationCanBeCancelled(kind: "photo")
    }

    func testPendingVideoDeleteConfirmationCanBeCancelledAndOpenedAgain() {
        assertPendingDeleteConfirmationCanBeCancelled(kind: "video")
    }

    private func assertPendingDeleteConfirmationCanBeCancelled(kind: String) {
        let app = launchFixture(scenario: "rotation-0", pendingDeleteKind: kind)
        let delete = app.buttons["tap.viewer.delete"]
        for attempt in 1...2 {
            XCTAssertTrue(delete.isEnabled && delete.isHittable)
            delete.tap()
            let alert = app.alerts["Delete unsaved \(kind)?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            XCTAssertTrue(alert.buttons["Delete"].exists)
            keepScreenshot(of: app, named: "pending-\(kind)-delete-confirmation-\(attempt)")
            // Test only presentation and cancellation; never request deletion.
            alert.buttons["Cancel"].tap()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: alert
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
            XCTAssertTrue(delete.exists && delete.isEnabled && delete.isHittable)
        }
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
        XCTAssertFalse(opacityControl(in: app).exists)
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
        XCTAssertTrue(app.buttons[Self.playPauseIdentifier].exists)
        XCTAssertFalse(app.buttons[Self.playPauseIdentifier].isEnabled,
                       "The video transport must remain visible while the new player prepares.")

        let stableChrome = [
            app.navigationBars.buttons.firstMatch,
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

    func testVideoSystemShareCanBeCancelledAndOpenedAgain() throws {
        let app = launchFixture(scenario: "rotation-0")
        try openFixture(in: app)
        let share = app.buttons[Self.shareIdentifier]
        let shareVideo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share Video")).firstMatch

        func keepShareEvidence(_ name: String) {
            keepScreenshot(of: app, named: name)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "\(name)-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }

        for attempt in 1...2 {
            XCTAssertTrue(share.isEnabled && share.isHittable,
                          "Cancelling system Share must leave the Viewer Share button usable.")
            share.tap()
            XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(shareVideo.waitForExistence(timeout: 5))
            XCTAssertTrue(shareVideo.isEnabled && shareVideo.isHittable)
            shareVideo.tap()

            let activity = app.otherElements["ActivityListView"]
            let appeared = activity.waitForExistence(timeout: 10)
            keepShareEvidence("video-system-share-\(attempt)")
            XCTAssertTrue(appeared, "Share Video must present the native system activity list.")
            app.buttons["header.closeButton"].tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: activity)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            XCTAssertTrue(value(of: app.buttons[Self.rawIdentifier], containsAny: Self.selectedValueTokens),
                          "Cancelling system Share must retain the current Viewer mode.")
        }
        XCTAssertTrue(share.isEnabled && share.isHittable)
        keepShareEvidence("video-system-share-cancelled")
    }

    func testVideoThreeDKeepsSelectionAndShowsRawWithoutMetricCalibration() throws {
        let app = launchFixture(scenario: "performance-playback-15s", autoPlay: true)
        try openFixture(in: app)
        let threeD = app.buttons[Self.threeDIdentifier]
        XCTAssertTrue(threeD.exists)
        XCTAssertTrue(threeD.isEnabled)
        threeD.tap()
        XCTAssertTrue(waitForValue(threeD, containingAny: ["showing RAW", "显示 RAW"], timeout: 8))
        XCTAssertTrue(value(of: threeD, containsAny: Self.selectedValueTokens))
        XCTAssertTrue(app.staticTexts["tap.viewer.depthUnavailable"].exists)
        XCTAssertFalse(app.otherElements["tap.video.point-cloud"].exists)
    }

    func testVideoThreeDPlaysRGB() throws {
        let app = launchFixture(scenario: "point-cloud-rgb")
        try openFixture(in: app)
        let threeD = app.buttons[Self.threeDIdentifier]
        XCTAssertTrue(threeD.isEnabled)
        threeD.tap()
        let cloud = app.otherElements["tap.video.point-cloud"]
        XCTAssertTrue(waitForValue(cloud, containingAny: ["RGB points"], timeout: 8))
        keepScreenshot(of: app, named: "video-3d-rgb-paused")
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

    func testPagingFromPhotoToVideoKeepsTheScreenCenter() throws {
        let app = launchFixture(scenario: "rotation-0", gallery: true)
        app.buttons["tap.gallery.item.photos:fixture-0"].tap()
        let photo = app.images["tap.viewer.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.frame.midY, app.frame.midY, accuracy: 1)
        keepScreenshot(of: app, named: "mixed-paging-photo")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons[Self.playPauseIdentifier].waitForExistence(timeout: 5))
        let video = element("tap.video.playback.surface", in: app)
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertEqual(video.frame.midY, app.frame.midY, accuracy: 1,
                       "Switching media renderers must retain the full-screen center.")
        keepScreenshot(of: app, named: "mixed-paging-video")
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.frame.midY, app.frame.midY, accuracy: 1)
    }

    func testPhotoModesKeepMediaBoundsAndRestoreRawInteraction() throws {
        let app = launchFixture(scenario: "rotation-0", gallery: true)
        app.buttons["tap.gallery.item.photos:fixture-0"].tap()
        let photo = app.images["tap.viewer.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let originalFrame = photo.frame
        XCTAssertGreaterThan(originalFrame.width, app.frame.width * 0.9)
        keepScreenshot(of: app, named: "photo-modes-raw-before")

        func assertMediaBounds(_ media: XCUIElement) {
            XCTAssertTrue(media.waitForExistence(timeout: 5))
            XCTAssertEqual(media.frame.midX, originalFrame.midX, accuracy: 1)
            XCTAssertEqual(media.frame.midY, originalFrame.midY, accuracy: 1)
            XCTAssertEqual(media.frame.width, originalFrame.width, accuracy: 1)
            XCTAssertEqual(media.frame.height, originalFrame.height, accuracy: 1)
        }

        let twoD = app.buttons[Self.twoDIdentifier]
        XCTAssertTrue(twoD.isHittable)
        twoD.tap()
        XCTAssertTrue(waitForValue(twoD, containingAny: Self.selectedValueTokens, timeout: 3))
        XCTAssertFalse(value(of: app.buttons[Self.rawIdentifier], containsAny: Self.selectedValueTokens))
        let divider = app.otherElements.matching(NSPredicate(
            format: "label == %@ AND value ENDSWITH %@", "2D analysis", " percent"
        )).element
        assertMediaBounds(divider)
        // These retained images support manual border review; bounds alone do not prove appearance.
        keepScreenshot(of: app, named: "photo-modes-2d")
        divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: divider.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertTrue(waitForValue(divider, containingAny: (70...80).map { "\($0) percent" }, timeout: 3),
                      "Dragging across the media must move the actual 2D comparison divider.")

        let threeD = app.buttons[Self.threeDIdentifier]
        XCTAssertTrue(threeD.isHittable)
        threeD.tap()
        XCTAssertTrue(waitForValue(threeD, containingAny: Self.selectedValueTokens, timeout: 3))
        XCTAssertFalse(value(of: twoD, containsAny: Self.selectedValueTokens))
        let projection = app.otherElements.matching(NSPredicate(format: "label == %@", "3D projection")).element
        assertMediaBounds(projection)
        XCTAssertFalse(divider.exists, "3D must replace the 2D interaction surface.")
        keepScreenshot(of: app, named: "photo-modes-3d")

        let raw = app.buttons[Self.rawIdentifier]
        XCTAssertTrue(raw.isHittable)
        raw.tap()
        XCTAssertTrue(waitForValue(raw, containingAny: Self.selectedValueTokens, timeout: 3))
        XCTAssertFalse(value(of: threeD, containsAny: Self.selectedValueTokens))
        assertMediaBounds(photo)
        XCTAssertFalse(projection.exists)
        keepScreenshot(of: app, named: "photo-modes-raw-after")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        XCTAssertGreaterThan(photo.frame.width, originalFrame.width * 1.5,
                             "Returning to RAW must restore actual photo zoom interaction.")
    }

    func testGallerySystemBackPreservesScrollPositionForTheOpenedPhoto() throws {
        let app = launchFixture(scenario: "rotation-0", gallery: true)
        let cell = try scrolledGalleryCell(in: app, nearBottom: false)
        let identifier = cell.identifier
        let originalY = cell.frame.minY
        cell.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))

        let photo = app.images["tap.viewer.photo"].firstMatch
        let originalWidth = photo.frame.width
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).doubleTap()
        XCTAssertGreaterThan(photo.frame.width, originalWidth * 1.5,
                             "Double-tap must actually zoom the photo before testing edge-back.")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(photo.exists, "A cancelled back gesture must retain the Viewer.")
        returnToGalleryWithSystemGesture(in: app)

        let returnedCell = app.buttons[identifier]
        XCTAssertTrue(returnedCell.isHittable, "Returning lost the opened photo's visible grid position.")
        XCTAssertEqual(returnedCell.frame.minY, originalY, accuracy: 2,
                       "Returning to the same photo must preserve the grid's native scroll offset.")
    }

    func testGalleryPagingThenSystemBackRevealsTheCurrentPhoto() throws {
        let app = launchFixture(scenario: "rotation-0", gallery: true)
        let cell = try scrolledGalleryCell(in: app, nearBottom: true)
        let startIndex = try XCTUnwrap(Int(cell.identifier.split(separator: "-").last ?? ""))
        let targetID = "tap.gallery.item.photos:fixture-\(startIndex + 12)"
        XCTAssertFalse(app.buttons[targetID].isHittable, "The target must start outside the grid viewport.")
        cell.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))

        let selection = app.staticTexts["tap.gallery.selection"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.52))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.52))
        for step in 1...12 {
            start.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertTrue(waitForElement(selection, label: "photos:fixture-\(startIndex + step)", timeout: 3),
                          "One physical swipe must commit exactly the next photo.")
        }
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(waitForElement(selection, label: "photos:fixture-\(startIndex + 11)", timeout: 3),
                      "A previous-photo swipe away from the edge must stay in the Viewer.")
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(waitForElement(selection, label: "photos:fixture-\(startIndex + 12)", timeout: 3))

        returnToGalleryWithSystemGesture(in: app)

        XCTAssertTrue(app.buttons[targetID].isHittable,
                      "Returning after paging must reveal the current photo, not the originally opened photo.")
    }

    private func scrolledGalleryCell(in app: XCUIApplication, nearBottom: Bool) throws -> XCUIElement {
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.swipeUp(velocity: .slow)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tap.gallery.item."))
            .allElementsBoundByIndex.filter {
                $0.isHittable && $0.frame.minY > 120 && $0.frame.maxY < app.frame.maxY - 50
            }
        let index = nearBottom ? cells.count - 1 : cells.count / 2
        return try XCTUnwrap(cells.indices.contains(index) ? cells[index] : nil)
    }

    private func returnToGalleryWithSystemGesture(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.navigationBars["TAP Library"].waitForExistence(timeout: 5),
                      "The system edge gesture did not pop the Viewer back to the grid.")
    }

    private func launchFixture(
        scenario: String,
        gallery: Bool = false,
        language: String = "en",
        appLanguage: String? = nil,
        autoPlay: Bool = false,
        seekScheduleSeconds: [Double]? = nil,
        accessibilityDynamicType: Bool = false,
        playerReadinessDelayMilliseconds: Int? = nil,
        pendingDeleteKind: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleIdentifier)
        if ProcessInfo.processInfo.environment["TAPCAM_PR7_ENABLE_ACTIVITY_LOGGING"] == "1" {
            app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "YES"
        }
        app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE"] = "1"
        app.launchEnvironment["TAPCAM_UI_TEST_VIDEO_FIXTURE_SCENARIO"] = scenario
        if let pendingDeleteKind {
            app.launchEnvironment["TAPCAM_UI_TEST_PENDING_DELETE"] = pendingDeleteKind
        }
        if gallery {
            app.launchEnvironment["TAPCAM_UI_TEST_GALLERY_FIXTURE"] = "1"
        }
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

        if pendingDeleteKind != nil {
            XCTAssertTrue(app.buttons["tap.viewer.delete"].waitForExistence(timeout: 8))
            return app
        }
        if gallery {
            XCTAssertTrue(app.buttons["tap.gallery.item.photos:fixture-0"].waitForExistence(timeout: 8))
            return app
        }
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
        XCTAssertFalse(opacityControl(in: app).exists)
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
                containsAny: Self.unavailableThreeDValueTokens
            )
        )
    }

    private func dismissFixture(in app: XCUIApplication) throws {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back control is missing.")
        back.tap()
        XCTAssertTrue(app.buttons[Self.openIdentifier].waitForExistence(timeout: 8))
    }

    private func assertSharedViewerChrome(
        in app: XCUIApplication,
        selectedModeIdentifier: String? = nil
    ) {
        let back = app.navigationBars.buttons.firstMatch
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
        if !threeD.isEnabled {
            XCTAssertTrue(value(of: threeD, containsAny: Self.unavailableThreeDValueTokens))
        }
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
