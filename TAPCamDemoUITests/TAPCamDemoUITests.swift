//
//  TAPCamDemoUITests.swift
//  TAPCamDemoUITests
//
//  Created by Harold on 2026/4/24.
//

import XCTest

final class TAPCamDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFOVSelectorSelects48mm() throws {
        try skipWhenRunningOnSimulator()

        let app = XCUIApplication()
        app.launch()

        let fortyEight = app.buttons["Use 48mm field of view"]
        XCTAssertTrue(fortyEight.waitForExistence(timeout: 10), "48mm FOV button should be visible on a depth-capable rear camera.")
        fortyEight.tap()

        let active48mmStatus = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "48mm")).firstMatch
        XCTAssertTrue(active48mmStatus.waitForExistence(timeout: 5), "Selecting 48mm should update the visible active camera status.")
    }

    @MainActor
    func testFOVSelectorSwitchesThrough77mmForDiagnostics() throws {
        try skipWhenRunningOnSimulator()

        let app = XCUIApplication()
        app.launch()

        let twentyFour = app.buttons["Use 24mm field of view"]
        let seventySeven = app.buttons["Use 77mm field of view"]
        XCTAssertTrue(twentyFour.waitForExistence(timeout: 10), "24mm FOV button should be visible on a depth-capable rear camera.")
        XCTAssertTrue(seventySeven.waitForExistence(timeout: 10), "77mm FOV button should be visible on a depth-capable rear camera.")

        twentyFour.tap()
        waitForPreviewTransition()
        seventySeven.tap()
        waitForPreviewTransition()
        twentyFour.tap()
        waitForPreviewTransition()
        seventySeven.tap()

        let active77mmStatus = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "77mm")).firstMatch
        XCTAssertTrue(active77mmStatus.waitForExistence(timeout: 5), "Selecting 77mm should update the visible active camera status.")
    }

    private func skipWhenRunningOnSimulator() throws {
        /*
         This test verifies the real FOV selector against hardware discovery.
         The iOS simulator has no depth-capable camera, so it can compile the UI
         target but cannot prove the 48mm depth-safe zoom path. Real-device
         validation should still run this test during attended acceptance.
         */
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            throw XCTSkip("48mm FOV selection requires a depth-capable physical camera.")
        }
    }

    private func waitForPreviewTransition() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}
