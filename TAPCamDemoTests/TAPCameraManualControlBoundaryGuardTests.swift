//
//  TAPCameraManualControlBoundaryGuardTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCameraManualControlBoundaryGuardTests {
    @Test func manualControlCommandPlanSourceStaysFoundationOnly() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Planning/CameraManualControlCommandPlan.swift"
        )

        #expect(source.contains("import Foundation"))
        for forbidden in [
            "import AVFoundation",
            "import SwiftUI",
            "AVCapture",
            "CameraControlService",
            "lockForConfiguration",
            "UserDefaults",
            "@AppStorage",
            "@Published"
        ] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test func cameraCaptureUIFilesDoNotConstructManualCommandPlansOrReferenceDeviceWriters() throws {
        let sources = try TAPCamDemoTestSourceInspection.swiftSourceRelativePaths(under: "TAPCamDemo/CameraCapture/UI")
            .map { try TAPCamDemoTestSourceInspection.source(relativePath: $0) }
            .joined(separator: "\n")

        for forbidden in [
            "CameraManualControlCommandPlan(resolution:",
            "CameraControlService",
            "applyManualControlCommandPlan",
            "lockForConfiguration",
            "setExposureTargetBias",
            "setExposureModeCustom",
            "setFocusModeLocked",
            "setWhiteBalanceModeLocked"
        ] {
            #expect(!sources.contains(forbidden))
        }
    }

    @Test func cameraControlServiceManualPlanSourceGuardsBeforeDeviceLock() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CameraControlService.swift"
        )
        let applyRange = try #require(source.range(of: "static func applyManualControlCommandPlan"))
        let methodSource = String(source[applyRange.lowerBound...])
        let queueGuard = try #require(methodSource.range(of: "try requireSessionQueueAccess()"))
        let staleGuard = try #require(methodSource.range(of: "try validateManualControlCommandPlan"))
        let noOpGuard = try #require(methodSource.range(of: "guard plan.requiresRuntimeWrite else"))
        let lockCall = try #require(methodSource.range(of: "try device.lockForConfiguration()"))

        #expect(queueGuard.lowerBound < staleGuard.lowerBound)
        #expect(staleGuard.lowerBound < noOpGuard.lowerBound)
        #expect(noOpGuard.lowerBound < lockCall.lowerBound)
        #expect(methodSource.contains("plan.commands.allSatisfy(\\.isRuntimeSupported)"))
    }
}
