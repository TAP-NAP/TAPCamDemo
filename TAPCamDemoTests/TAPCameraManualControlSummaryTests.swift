//
//  TAPCameraManualControlSummaryTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraManualControlSummaryTests {
    @Test func manualControlSummaryDistinguishesNoChangeFromExplicitAuto() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let noChangeSummary = CameraManualControlSummary(
            resolution: CameraManualControlIntent
                .noChanges(targetDeviceID: capability.deviceID)
                .resolved(against: capability)
        )
        let explicitAutoSummary = CameraManualControlSummary(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .continuousAuto,
                focus: .continuousAuto,
                whiteBalance: .continuousAuto,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )

        let noChangeExposure = try #require(noChangeSummary.rows.first { $0.kind == .exposure })
        let autoExposure = try #require(explicitAutoSummary.rows.first { $0.kind == .exposure })
        let autoFocus = try #require(explicitAutoSummary.rows.first { $0.kind == .focus })
        let autoWhiteBalance = try #require(explicitAutoSummary.rows.first { $0.kind == .whiteBalance })

        #expect(noChangeExposure.state == .unchanged)
        #expect(noChangeExposure.requestKind == .unchanged)
        #expect(noChangeExposure.value == "No change")
        #expect(!noChangeExposure.isRequested)
        #expect(autoExposure.state == .requested)
        #expect(autoExposure.requestKind == .explicitAuto)
        #expect(autoExposure.value == "Automatic exposure")
        #expect(autoFocus.requestKind == .explicitAuto)
        #expect(autoFocus.value == "Continuous auto focus")
        #expect(autoWhiteBalance.requestKind == .explicitAuto)
        #expect(autoWhiteBalance.value == "Automatic white balance")
    }

    @Test func manualControlSummaryPublishesExecutableManualRows() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let summary = CameraManualControlSummary(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .custom(iso: 100, shutterDurationSeconds: 1.0 / 120.0),
                focus: .autoFocus(pointOfInterest: .init(x: 0.5, y: 0.6)),
                whiteBalance: .locked,
                aperture: nil,
                zoomFactor: 2
            ).resolved(
                against: capability,
                depthSafeZoomRanges: [1...3]
            )
        )

        let requestedRows = summary.rows.filter(\.isRequested)

        #expect(requestedRows.map(\.title) == ["Exposure", "Focus", "White balance", "Zoom"])
        #expect(requestedRows.map(\.value) == [
            "Manual ISO and shutter",
            "Auto focus",
            "Locked white balance",
            "Zoom request"
        ])
        #expect(requestedRows.map(\.requestKind) == [
            .manualRequested,
            .manualRequested,
            .manualRequested,
            .manualRequested
        ])
        #expect(requestedRows.allSatisfy { $0.isExecutable })
        #expect(requestedRows.allSatisfy { $0.reason == nil })
    }

    @Test func manualControlSummaryMapsViolationsToPublicSafeFieldRows() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsLockedExposure: false,
            supportsCustomExposure: false,
            supportsAutoFocus: false,
            supportsFocusPointOfInterest: false,
            supportsLockedWhiteBalance: false,
            exposureBiasRange: .init(minimum: 0, maximum: 0),
            isoRange: .init(minimum: 100, maximum: 100),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 60.0, maximum: 1.0 / 60.0),
            zoomRange: .init(minimum: 1, maximum: 3)
        )
        let summary = CameraManualControlSummary(
            resolution: CameraManualControlIntent(
                targetDeviceID: "secret-stale-device",
                exposure: .custom(iso: 50, shutterDurationSeconds: 2),
                focus: .autoFocus(pointOfInterest: .init(x: -0.2, y: 1.2)),
                whiteBalance: .deviceGains(.init(red: 0.5, green: 5, blue: .infinity)),
                aperture: .value(2.8),
                zoomFactor: 8
            ).resolved(against: capability)
        )
        let blockedRows = summary.rows.filter { !$0.isExecutable }
        let publicText = blockedRows
            .flatMap { [$0.title, $0.value, $0.reason ?? ""] }
            .joined(separator: " ")

        #expect(blockedRows.map(\.title) == ["Camera", "Exposure", "Focus", "White balance", "Aperture", "Zoom"])
        #expect(blockedRows.map(\.state) == [
            .blocked,
            .blockedRequested,
            .blockedRequested,
            .blockedRequested,
            .blockedRequested,
            .blockedRequested
        ])
        #expect(blockedRows.allSatisfy { $0.reason != nil })
        for forbidden in ["secret-stale-device", "device-1", "50", "-0.2", "1.2", "2.8", "8"] {
            #expect(!publicText.contains(forbidden))
        }
    }

    @Test func manualControlSummaryDoesNotExposeRawDeviceIdentifiers() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            deviceID: "active file:///private/device https://example.invalid AppAttest proof assetID keyID",
            deviceDisplayName: "Wide /private/display proof keyID",
            deviceTypeRawValue: "built-in-wide /private/type"
        )
        let summary = CameraManualControlSummary(
            resolution: CameraManualControlIntent
                .noChanges(
                    targetDeviceID: "stale file:///private/stale https://example.invalid/token AppAttest proof assetID keyID"
                )
                .resolved(against: capability)
        )
        let publicText = summary.rows
            .flatMap { [$0.title, $0.value, $0.reason ?? ""] }
            .joined(separator: " ")

        for forbidden in ["file://", "/private/", "https://", "AppAttest", "proof", "assetID", "keyID"] {
            #expect(!publicText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func manualControlSummaryIncludesZoomWhenZoomIsTheOnlyAdjustableManualField() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsLockedExposure: false,
            supportsCustomExposure: false,
            supportsLockedFocus: false,
            supportsLockedWhiteBalance: false,
            exposureBiasRange: .init(minimum: 0, maximum: 0),
            isoRange: .init(minimum: 100, maximum: 100),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 60.0, maximum: 1.0 / 60.0),
            zoomRange: .init(minimum: 1, maximum: 5)
        )
        let summary = CameraManualControlSummary(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: nil,
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: 2
            ).resolved(
                against: capability,
                depthSafeZoomRanges: [1...3]
            )
        )
        let zoomRow = try #require(summary.rows.first { $0.kind == .zoom })

        #expect(capability.supportsAnyManualControl)
        #expect(zoomRow.state == .requested)
        #expect(zoomRow.requestKind == .manualRequested)
        #expect(zoomRow.value == "Zoom request")
        #expect(zoomRow.isExecutable)
    }

    @Test func manualControlSummaryRowsDoNotStoreSensitiveInputFields() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let summary = CameraManualControlSummary(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .exposureBias(1.5),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )
        let row = try #require(summary.rows.first { $0.kind == .exposure })
        let storedPropertyNames = Mirror(reflecting: row).children.compactMap(\.label)
        let forbiddenNameFragments = [
            "device",
            "capability",
            "intent",
            "resolution",
            "violation",
            "reader",
            "manifest",
            "proof",
            "key",
            "path",
            "url",
            "raw",
            "range",
            "valueObject",
            "writer",
            "queue"
        ]

        for propertyName in storedPropertyNames {
            for forbiddenFragment in forbiddenNameFragments {
                #expect(!propertyName.localizedCaseInsensitiveContains(forbiddenFragment))
            }
        }
    }
}
