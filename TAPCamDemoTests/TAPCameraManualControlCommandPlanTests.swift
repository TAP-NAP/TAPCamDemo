//
//  TAPCameraManualControlCommandPlanTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraManualControlCommandPlanTests {
    @Test func manualControlCommandPlanNamesNoOpWithoutRuntimeCommands() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent
                .noChanges(targetDeviceID: capability.deviceID)
                .resolved(against: capability)
        )

        #expect(plan.state == .noChanges)
        #expect(plan.targetDeviceID == capability.deviceID)
        #expect(plan.commands.isEmpty)
        #expect(!plan.requiresRuntimeWrite)
    }

    @Test func manualControlCommandPlanBuildsExecutableCommandsInRuntimeOrder() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let focusPoint = CameraManualControlIntent.NormalizedPoint(x: 0.5, y: 0.6)
        let whiteBalanceGains = CameraManualControlIntent.WhiteBalanceGains(red: 2, green: 2.5, blue: 3)
        let expectedFocusPoint = CameraManualControlCommandPlan.NormalizedPoint(x: 0.5, y: 0.6)
        let expectedWhiteBalanceGains = CameraManualControlCommandPlan.WhiteBalanceGains(red: 2, green: 2.5, blue: 3)
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .custom(iso: 100, shutterDurationSeconds: 1.0 / 120.0),
                focus: .autoFocus(pointOfInterest: focusPoint),
                whiteBalance: .deviceGains(whiteBalanceGains),
                aperture: nil,
                zoomFactor: 2
            ).resolved(
                against: capability,
                depthSafeZoomRanges: [1...3]
            )
        )

        #expect(plan.state == .executable)
        #expect(plan.targetDeviceID == capability.deviceID)
        #expect(plan.requiresRuntimeWrite)
        #expect(plan.commands == [
            .exposure(.custom(iso: 100, shutterDurationSeconds: 1.0 / 120.0)),
            .focus(.autoFocus(pointOfInterest: expectedFocusPoint)),
            .whiteBalance(.deviceGains(expectedWhiteBalanceGains)),
            .zoomFactor(2)
        ])
    }

    @Test func manualControlCommandPlanDoesNotBuildCommandsForBlockedResolution() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsCustomExposure: false,
            supportsAutoFocus: false,
            supportsFocusPointOfInterest: false,
            zoomRange: .init(minimum: 1, maximum: 3)
        )
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: "stale-device",
                exposure: .custom(iso: 50, shutterDurationSeconds: 2),
                focus: .autoFocus(pointOfInterest: .init(x: -0.2, y: 1.2)),
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: 8
            ).resolved(against: capability)
        )

        #expect(plan.state == .blocked)
        #expect(plan.targetDeviceID == "stale-device")
        #expect(plan.commands.isEmpty)
        #expect(!plan.requiresRuntimeWrite)
    }

    @Test func manualControlCommandPlanStringRepresentationsRedactRuntimeValues() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(deviceID: "secret-device-id")
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .custom(iso: 1_234, shutterDurationSeconds: 0.125),
                focus: .autoFocus(pointOfInterest: .init(x: 0.42, y: 0.73)),
                whiteBalance: .deviceGains(.init(red: 1.25, green: 2.75, blue: 3.5)),
                aperture: nil,
                zoomFactor: 2.25
            ).resolved(
                against: capability,
                depthSafeZoomRanges: [2...3]
            )
        )
        let stringSurfaces = [
            String(describing: plan),
            String(reflecting: plan),
            String(describing: plan.commands),
            String(reflecting: plan.commands),
            plan.commands.map { String(describing: $0) }.joined(separator: " "),
            plan.commands.map { String(reflecting: $0) }.joined(separator: " ")
        ].joined(separator: " ")

        #expect(plan.requiresRuntimeWrite)
        for forbidden in ["secret-device-id", "1234", "0.125", "0.42", "0.73", "1.25", "2.75", "3.5", "2.25"] {
            #expect(!stringSurfaces.contains(forbidden))
        }
    }

    @Test func manualControlCommandPlanDoesNotStoreRuntimeHandlesOrInputModels() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let plan = CameraManualControlCommandPlan(
            resolution: CameraManualControlIntent(
                targetDeviceID: capability.deviceID,
                exposure: .exposureBias(1.5),
                focus: nil,
                whiteBalance: nil,
                aperture: nil,
                zoomFactor: nil
            ).resolved(against: capability)
        )
        let reflectedNames = TAPCamDemoTestSourceInspection.reflectedNames(in: plan)
        let forbiddenNameFragments = [
            "session",
            "writer",
            "queue",
            "manifest",
            "proof",
            "key",
            "path",
            "url",
            "attest",
            "capture",
            "asset",
            "store",
            "photo",
            "heic",
            "intent",
            "capability",
            "resolution",
            "violation",
            "avcapture",
            "cameracontrolservice"
        ]

        #expect(plan.targetDeviceID == capability.deviceID)
        for reflectedName in reflectedNames {
            for forbiddenFragment in forbiddenNameFragments {
                #expect(!reflectedName.localizedCaseInsensitiveContains(forbiddenFragment))
            }
        }
    }
}
