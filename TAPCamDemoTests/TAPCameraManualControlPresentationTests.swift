//
//  TAPCameraManualControlPresentationTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraManualControlPresentationTests {
    @Test func manualControlResolutionPresentationNamesNoOpWithoutDeviceDetails() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let resolution = CameraManualControlIntent
            .noChanges(targetDeviceID: capability.deviceID)
            .resolved(against: capability)

        let presentation = CameraManualControlResolutionPresentation(resolution: resolution)

        #expect(presentation.status == .noChanges)
        #expect(presentation.title == "No manual control changes")
        #expect(presentation.requestedControlLabels.isEmpty)
        #expect(presentation.blockedControlLabels.isEmpty)
        #expect(!presentation.detail.contains(capability.deviceID))
        #expect(!presentation.detail.contains(capability.deviceDisplayName))
    }

    @Test func manualControlResolutionPresentationNamesRequestedControlGroups() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .exposureBias(1.5),
            focus: .autoFocus(pointOfInterest: .init(x: 0.5, y: 0.6)),
            whiteBalance: .locked,
            aperture: nil,
            zoomFactor: 2
        )

        let presentation = CameraManualControlResolutionPresentation(
            resolution: intent.resolved(
                against: capability,
                depthSafeZoomRanges: [1...3]
            )
        )

        #expect(presentation.status == .ready)
        #expect(presentation.title == "Manual controls ready")
        #expect(presentation.requestedControlLabels == ["Exposure", "Focus", "White balance", "Zoom"])
        #expect(presentation.blockedControlLabels.isEmpty)
    }

    @Test func manualControlResolutionPresentationRedactsBlockedRequestValues() throws {
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
        let intent = CameraManualControlIntent(
            targetDeviceID: "secret-stale-device",
            exposure: .custom(iso: 50, shutterDurationSeconds: 2),
            focus: .autoFocus(pointOfInterest: .init(x: -0.2, y: 1.2)),
            whiteBalance: .deviceGains(.init(red: 0.5, green: 5, blue: .infinity)),
            aperture: .value(2.8),
            zoomFactor: 8
        )

        let presentation = CameraManualControlResolutionPresentation(
            resolution: intent.resolved(against: capability)
        )
        let publicText = ([presentation.title, presentation.detail]
            + presentation.requestedControlLabels
            + presentation.blockedControlLabels)
            .joined(separator: " ")

        #expect(presentation.status == .blocked)
        #expect(presentation.title == "Manual controls unavailable")
        #expect(presentation.requestedControlLabels == ["Exposure", "Focus", "White balance", "Aperture", "Zoom"])
        #expect(presentation.blockedControlLabels == ["Camera", "Exposure", "Focus", "White balance", "Aperture", "Zoom"])
        #expect(!publicText.contains("secret-stale-device"))
        #expect(!publicText.contains(capability.deviceID))
        #expect(!publicText.contains("device-1"))
        #expect(!publicText.contains("50"))
        #expect(!publicText.contains("-0.2"))
        #expect(!publicText.contains("1.2"))
        #expect(!publicText.contains("2.8"))
        #expect(!publicText.contains("8"))
    }

    @Test func manualControlResolutionPresentationRedactsHostileDeviceStrings() throws {
        let hostileActiveDeviceID = "active file:///private/device https://example.invalid AppAttest proof assetID keyID"
        let hostileDisplayName = "Wide /private/display proof keyID"
        let hostileStaleDeviceID = "stale file:///private/stale https://example.invalid/token AppAttest proof assetID keyID"
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            deviceID: hostileActiveDeviceID,
            deviceDisplayName: hostileDisplayName,
            deviceTypeRawValue: "built-in-wide /private/type"
        )
        let resolution = CameraManualControlIntent
            .noChanges(targetDeviceID: hostileStaleDeviceID)
            .resolved(against: capability)

        let presentation = CameraManualControlResolutionPresentation(resolution: resolution)
        let publicText = ([presentation.title, presentation.detail]
            + presentation.requestedControlLabels
            + presentation.blockedControlLabels)
            .joined(separator: " ")

        #expect(!resolution.isExecutable)
        #expect(presentation.status == .blocked)
        #expect(presentation.blockedControlLabels == ["Camera"])
        for forbidden in ["file://", "/private/", "https://", "AppAttest", "proof", "assetID", "keyID"] {
            #expect(!publicText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func manualControlResolutionPresentationDoesNotReuseReaderDescription() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(deviceID: "active-device-secret")
        let intent = CameraManualControlIntent.noChanges(targetDeviceID: "stale-device-secret")
        let resolution = intent.resolved(against: capability)
        let readerDescription = try #require(resolution.violations.first?.readerDescription)
        let presentation = CameraManualControlResolutionPresentation(resolution: resolution)
        let publicText = ([presentation.title, presentation.detail]
            + presentation.requestedControlLabels
            + presentation.blockedControlLabels)
            .joined(separator: " ")

        #expect(readerDescription.contains("stale-device-secret"))
        #expect(readerDescription.contains("active-device-secret"))
        #expect(!publicText.contains("stale-device-secret"))
        #expect(!publicText.contains("active-device-secret"))
    }

    @Test func manualControlResolutionPresentationMarksDepthUnsafeZoomBlocked() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: nil,
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: 4
        )

        let presentation = CameraManualControlResolutionPresentation(
            resolution: intent.resolved(
                against: capability,
                depthSafeZoomRanges: [1...3, 5...7]
            )
        )

        #expect(presentation.status == .blocked)
        #expect(presentation.requestedControlLabels == ["Zoom"])
        #expect(presentation.blockedControlLabels == ["Zoom"])
    }

    @Test func cameraCaptureStatusPresentationKeepsManualControlRuntimeErrorsPublicSafe() throws {
        let messages = [
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraControlCommandPlanNotExecutable,
                context: .debugConfiguration
            ),
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraControlTargetDeviceChanged,
                context: .debugConfiguration
            ),
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraControlTargetSurfaceChanged,
                context: .debugConfiguration
            ),
            CameraCaptureStatusPresentation.message(
                for: TAPDepthCaptureError.cameraControlUnsupportedCommand,
                context: .debugConfiguration
            ),
            CameraCaptureStatusPresentation.failureReason(
                for: TAPDepthCaptureError.cameraControlTargetDeviceChanged
            )
        ]

        #expect(messages == [
            "Camera controls are temporarily unavailable.",
            "Camera controls are temporarily unavailable.",
            "Camera controls are temporarily unavailable.",
            "Camera controls are temporarily unavailable.",
            "Camera controls are temporarily unavailable."
        ])
        for message in messages {
            for forbidden in ["targetDeviceID", "activeDeviceID", "original-camera", "new-camera", "secret"] {
                #expect(!message.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }
}
