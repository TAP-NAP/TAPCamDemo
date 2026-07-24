//
//  TAPPhotographerModeRuntimeTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPPhotographerModeRuntimeTests {
    @Test func photographerModeRequiresTheCompleteLiDARManualControlContract() {
        #expect(PhotographerModeAvailability.resolve(eligibleFacts()) == .available)

        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(isRearLiDARDevice: false)
        ) == .unavailable(.rearLiDARUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasOneXDepthFormat: false)
        ) == .unavailable(.oneXDepthFormatUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsPhotoDepthDelivery: false)
        ) == .unavailable(.photoDepthDeliveryUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsCustomExposure: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasAdjustableISORange: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasAdjustableShutterRange: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsLockedFocus: false)
        ) == .unavailable(.manualFocusUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsCustomLensPosition: false)
        ) == .unavailable(.manualFocusUnavailable))
    }

    @Test func photographerModeStateKeepsTransitionAndRecoveredModeExplicit() {
        #expect(PhotographerModeState.activating.isTransitioning)
        #expect(PhotographerModeState.deactivating.isTransitioning)
        #expect(!PhotographerModeState.standard.isTransitioning)
        #expect(!PhotographerModeState.active.isTransitioning)

        #expect(!PhotographerModeState.activating.isActive)
        #expect(PhotographerModeState.deactivating.isActive)
        #expect(PhotographerModeState.active.effectiveMode == .photographer)

        let recoveredStandard = PhotographerModeState.failed(
            recoveredMode: .standard,
            reason: .configurationFailed
        )
        let recoveredPhotographer = PhotographerModeState.failed(
            recoveredMode: .photographer,
            reason: .configurationFailed
        )
        #expect(!recoveredStandard.isActive)
        #expect(recoveredStandard.effectiveMode == .standard)
        #expect(!recoveredStandard.requiresStandardRecovery)
        #expect(recoveredPhotographer.isActive)
        #expect(recoveredPhotographer.effectiveMode == .photographer)
        #expect(!recoveredPhotographer.requiresStandardRecovery)

        let unrecovered = PhotographerModeState.failed(
            recoveredMode: .unconfigured,
            reason: .configurationFailed
        )
        #expect(!unrecovered.isActive)
        #expect(unrecovered.effectiveMode == .unconfigured)
        #expect(unrecovered.requiresStandardRecovery)
    }

    @Test func capabilityMatrixUsesExplicitLiDAROneXInsteadOfAutomaticFOVSelection() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Planning/CapabilityMatrix.swift"
        )

        #expect(source.contains("$0.kind == .lidarDepth"))
        #expect(source.contains("device.deviceType == .builtInLiDARDepthCamera"))
        #expect(source.contains("preferredZoomFactor: 1.0"))
        #expect(source.contains("requiresPreferredZoomSupport: true"))
        #expect(source.contains("selectedZoomFactor: 1.0"))
        #expect(source.contains("supportsCustomExposure"))
        #expect(source.contains("supportsCustomLensPosition"))
    }

    @Test func photographerModeRuntimePathDoesNotDependOnDebugOverrideState() throws {
        let selectionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )
        let capabilitySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Planning/CapabilityMatrix.swift"
        )

        let start = try #require(selectionSource.range(of: "private func configurePhotographerMode("))
        let end = try #require(selectionSource.range(
            of: "private func transitionFromPhotographerModeToStandardRearCamera()",
            range: start.upperBound..<selectionSource.endIndex
        ))
        let photographerRuntime = String(selectionSource[start.lowerBound..<end.lowerBound])

        #expect(!photographerRuntime.contains("isDebugDepthOverrideActive"))
        #expect(!photographerRuntime.contains("makeDebugDepthOverridePlan"))
        #expect(!capabilitySource.contains("#if DEBUG\n    var photographerModeAvailability"))
    }

    @Test func standardRuntimePathExplicitlyExcludesLiDAR() throws {
        let selectionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )
        let capabilitySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Planning/CapabilityMatrix.swift"
        )

        #expect(capabilitySource.contains("func standardDepthProfiles("))
        #expect(capabilitySource.contains("func standardRGBSource(id:"))
        #expect(capabilitySource.contains("return defaultRGBSource"))
        #expect(capabilitySource.contains(".filter { $0.kind != .lidarDepth }"))
        #expect(capabilitySource.contains("rgbSource.device.deviceType != .builtInLiDARDepthCamera"))
        #expect(selectionSource.contains("capabilityMatrix.standardRGBSource(id: selectedRGBSourceID)"))
        #expect(selectionSource.contains("capabilityMatrix.standardDepthProfiles("))
        #expect(selectionSource.contains("$0.device.deviceType != .builtInLiDARDepthCamera"))
        #expect(capabilitySource.contains("$0.device.deviceType != .builtInLiDARDepthCamera"))
    }

    @Test func failedActivationCannotLeaveAStalePhotographerIntent() throws {
        let selectionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )
        let viewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel.swift"
        )

        #expect(selectionSource.contains("suspendedRearModeIntent = recoveredMode == .photographer"))
        #expect(selectionSource.contains("photographerModeState = .unavailable(reason)\n            suspendedRearModeIntent = .standard"))
        #expect(viewModelSource.contains("reconcileInterruptedPhotographerModeTransition()"))
        #expect(viewModelSource.contains("guard photographerModeState.isTransitioning"))
        #expect(viewModelSource.contains("suspendedRearModeIntent = recoveredMode == .photographer"))
    }

    @Test func selectionReconfigurationIsMergedAndRecoveryCanReportNoUsableSession() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )

        #expect(source.contains("hasPendingSelectionReconfiguration = true"))
        #expect(source.contains("finishSelectionConfiguration(generation: generation)"))
        #expect(source.contains("didRestore ? snapshot.photographerMode : .unconfigured"))
        #expect(source.contains("didRestore ? previous.photographerMode : .unconfigured"))
    }

    @Test func frontStandardReconfigurationPreservesSuspendedRearPhotographerIntent() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift"
        )

        #expect(source.contains("if result.device.position == .back {\n                    suspendedRearModeIntent = .standard"))
    }

    @Test func mediaServicesResetEndsAnInFlightPhotographerTransition() throws {
        let controllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let viewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel.swift"
        )

        #expect(controllerSource.contains("AVCaptureSession.runtimeErrorNotification"))
        #expect(controllerSource.contains("AVCaptureSessionErrorKey"))
        #expect(controllerSource.contains("AVError.Code.mediaServicesWereReset.rawValue"))
        #expect(controllerSource.contains("AVCaptureSession.wasInterruptedNotification"))
        #expect(controllerSource.contains("AVCaptureSession.interruptionEndedNotification"))
        #expect(controllerSource.contains("waitUntilSessionQueueIsResponsive"))
        #expect(viewModelSource.contains("handleCaptureSessionRuntimeFailure"))
        #expect(viewModelSource.contains("guard failure.isMediaServicesReset"))
        #expect(viewModelSource.contains("!isVideoRecording"))
        #expect(viewModelSource.contains("!isPreparingVideoMode"))
        #expect(viewModelSource.contains("isConfiguringSession || activeSessionConfiguration != nil"))
        #expect(viewModelSource.contains("photographerModeState = .failed("))
        #expect(viewModelSource.contains("hasPendingSelectionReconfiguration = false"))
        #expect(viewModelSource.contains("armCameraPathConfigurationWatchdog"))
        #expect(viewModelSource.contains("Task.sleep(for: .seconds(10))"))
        #expect(viewModelSource.contains("isSessionControllerSuspectedWedged = true"))
        #expect(viewModelSource.contains("beginSessionQueueLivenessProbeIfNeeded"))
        #expect(viewModelSource.contains("await controller.waitUntilSessionQueueIsResponsive()"))
    }

    private func eligibleFacts(
        isRearLiDARDevice: Bool = true,
        hasOneXDepthFormat: Bool = true,
        supportsPhotoDepthDelivery: Bool = true,
        supportsCustomExposure: Bool = true,
        hasAdjustableISORange: Bool = true,
        hasAdjustableShutterRange: Bool = true,
        supportsLockedFocus: Bool = true,
        supportsCustomLensPosition: Bool = true
    ) -> PhotographerModeCapabilityFacts {
        PhotographerModeCapabilityFacts(
            isRearLiDARDevice: isRearLiDARDevice,
            hasOneXDepthFormat: hasOneXDepthFormat,
            supportsPhotoDepthDelivery: supportsPhotoDepthDelivery,
            supportsCustomExposure: supportsCustomExposure,
            hasAdjustableISORange: hasAdjustableISORange,
            hasAdjustableShutterRange: hasAdjustableShutterRange,
            supportsLockedFocus: supportsLockedFocus,
            supportsCustomLensPosition: supportsCustomLensPosition
        )
    }
}
