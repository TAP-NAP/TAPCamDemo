//
//  TAPCameraManualControlIntentTests.swift
//  TAPCamDemoTests
//

import Testing
@testable import TAPCamDemo

struct TAPCameraManualControlIntentTests {
    @Test func cameraControlCapabilitySnapshotNamesFutureManualControlBoundaries() throws {
        let snapshot = TAPCamDemoTestFixtures.sampleManualControlCapability()

        #expect(snapshot.supportsAnyManualControl)
        #expect(snapshot.exposure.hasManualRange)
        #expect(snapshot.exposure.exposureBiasRange.isAdjustable)
        #expect(!snapshot.aperture.isAdjustable)
        #expect(snapshot.zoom.range.maximum == 15)
    }

    @Test func manualControlIntentNoChangesIsPureNoOpState() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent.noChanges(targetDeviceID: capability.deviceID)

        let resolution = intent.resolved(against: capability)

        #expect(resolution.isExecutable)
        #expect(resolution.intent == intent)
        #expect(resolution.violations.isEmpty)
    }

    @Test func manualControlIntentDistinguishesNoOpFromExplicitAuto() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .continuousAuto,
            focus: .continuousAuto,
            whiteBalance: .continuousAuto,
            aperture: nil,
            zoomFactor: nil
        )

        let resolution = intent.resolved(against: capability)

        #expect(resolution.isExecutable)
        #expect(intent != .noChanges(targetDeviceID: capability.deviceID))
    }

    @Test func manualControlIntentAcceptsCapabilityBackedValues() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .custom(iso: 100, shutterDurationSeconds: 1.0 / 120.0),
            focus: .autoFocus(pointOfInterest: .init(x: 0.5, y: 0.6)),
            whiteBalance: .locked,
            aperture: nil,
            zoomFactor: 2
        )

        let resolution = intent.resolved(
            against: capability,
            depthSafeZoomRanges: [1...3]
        )

        #expect(resolution.isExecutable)
        #expect(resolution.violations.isEmpty)
    }

    @Test func manualControlIntentAcceptsExposureBiasWithinRange() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .exposureBias(1.5),
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        #expect(intent.resolved(against: capability).isExecutable)
    }

    @Test func manualControlIntentRejectsUnsupportedAndOutOfRangeValues() throws {
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
            targetDeviceID: "stale-device",
            exposure: .custom(iso: 50, shutterDurationSeconds: 2),
            focus: .autoFocus(pointOfInterest: .init(x: -0.2, y: 1.2)),
            whiteBalance: .deviceGains(.init(red: 0.5, green: 5, blue: .infinity)),
            aperture: .value(2.8),
            zoomFactor: 8
        )

        let violations = intent.resolved(against: capability).violations

        #expect(violations.contains(.targetDeviceMismatch(expected: "stale-device", actual: capability.deviceID)))
        #expect(violations.contains(.customExposureUnsupported))
        #expect(violations.contains(.isoOutOfRange(value: 50, minimum: 100, maximum: 100)))
        #expect(violations.contains(.shutterDurationOutOfRange(value: 2, minimum: 1.0 / 60.0, maximum: 1.0 / 60.0)))
        #expect(violations.contains(.autoFocusUnsupported))
        #expect(violations.contains(.focusPointUnsupported))
        #expect(violations.contains(.focusPointOutOfBounds(x: -0.2, y: 1.2)))
        #expect(violations.contains(.lockedWhiteBalanceUnsupported))
        #expect(violations.contains(.apertureAdjustmentUnsupported))
        #expect(violations.contains(.zoomOutOfRange(value: 8, minimum: 1, maximum: 3)))
    }

    @Test func manualControlIntentRejectsExposureBiasWhenRangeIsNotAdjustable() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            exposureBiasRange: .init(minimum: 0, maximum: 0)
        )
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .exposureBias(0.5),
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        #expect(intent.resolved(against: capability).violations == [.exposureBiasUnsupported])
    }

    @Test func manualControlIntentRejectsCustomLensPositionWhenUnsupported() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsCustomLensPosition: false
        )
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: nil,
            focus: .locked(lensPosition: 0.4),
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: nil
        )

        #expect(intent.resolved(against: capability).violations == [.customLensPositionUnsupported])
    }

    @Test func manualControlIntentRejectsNonFiniteManualValues() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: .exposureBias(.infinity),
            focus: .locked(lensPosition: .infinity),
            whiteBalance: .deviceGains(.init(red: .infinity, green: 2, blue: 2)),
            aperture: .value(.infinity),
            zoomFactor: .infinity
        )

        let violations = intent.resolved(against: capability).violations

        #expect(violations.contains(.exposureBiasOutOfRange(value: .infinity, minimum: -2, maximum: 2)))
        #expect(violations.contains(.lensPositionOutOfRange(.infinity)))
        #expect(violations.contains(.whiteBalanceGainOutOfRange(value: .infinity, minimum: 1, maximum: 4)))
        #expect(violations.contains(.apertureValueNotFinite(.infinity)))
        #expect(violations.contains(.zoomOutOfRange(value: .infinity, minimum: 1, maximum: 15)))
    }

    @Test func manualControlIntentRejectsZoomOutsideDepthSafeRanges() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let intent = CameraManualControlIntent(
            targetDeviceID: capability.deviceID,
            exposure: nil,
            focus: nil,
            whiteBalance: nil,
            aperture: nil,
            zoomFactor: 4
        )

        let violations = intent.resolved(
            against: capability,
            depthSafeZoomRanges: [1...3, 5...7]
        ).violations

        #expect(violations == [.zoomOutsideDepthSafeRanges(4)])
    }
}
