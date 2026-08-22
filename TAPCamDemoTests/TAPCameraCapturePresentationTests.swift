//
//  TAPCameraCapturePresentationTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import TAPCamDemo

struct TAPCameraCapturePresentationTests {
    @Test func settingsSessionReconfigurationPolicyCoalescesCaptureChanges() {
        var policy = CameraSettingsSessionReconfigurationPolicy()

        let firstPresentedChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: true)
        let secondPresentedChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: true)
        #expect(!firstPresentedChangeReconfigures)
        #expect(!secondPresentedChangeReconfigures)
        #expect(policy.hasPendingReconfiguration)
        let firstDismissalReconfigures = policy.settingsDidDismiss()
        #expect(firstDismissalReconfigures)
        #expect(!policy.hasPendingReconfiguration)
        let secondDismissalReconfigures = policy.settingsDidDismiss()
        let outsideSettingsChangeReconfigures =
            policy.capturePreferenceDidChange(isSettingsPresented: false)
        #expect(!secondDismissalReconfigures)
        #expect(outsideSettingsChangeReconfigures)
    }

    @Test func captureLifecycleCoordinatorKeepsPendingSigningWarmupAndRetryPoliciesExplicit() {
        #expect(CaptureLifecycleCoordinator.initialCameraActions(startsAutomatically: true) == [.startCamera])
        #expect(CaptureLifecycleCoordinator.initialCameraActions(startsAutomatically: false) == [])

        #expect(CaptureLifecycleCoordinator.launchCredentialActions(startsAutomatically: true) == [
            .warmPendingCaptureSigningCredential
        ])
        #expect(CaptureLifecycleCoordinator.launchCredentialActions(startsAutomatically: false) == [
            .retryPendingCaptures
        ])

        #expect(CaptureLifecycleCoordinator.viewDidAppearActions() == [.startChromeOrientation])
        #expect(CaptureLifecycleCoordinator.viewDidDisappearActions() == [
            .stopChromeOrientation,
            .stopCamera
        ])

        #expect(CaptureLifecycleCoordinator.depthAlbumPresentationActions(isPresented: false) == [
            .resumeAfterAnalysis,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.depthAlbumPresentationActions(
            isPresented: false,
            preparesVideoMode: true
        ) == [
            .resumeAfterAnalysis,
            .prepareVideoMode,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.depthAlbumPresentationActions(isPresented: true) == [])

        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .active) == [
            .loadRecentTAPLibraryPreview,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(
            for: .active,
            shouldReturnToCameraOnForeground: true
        ) == [
            .restoreCameraRoute,
            .loadRecentTAPLibraryPreview,
            .retryPendingCaptures
        ])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .inactive) == [])
        #expect(CaptureLifecycleCoordinator.scenePhaseActions(for: .background) == [])

        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: true,
            isPreparing: false
        ) == [.retryPendingCaptures])
        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: false,
            isPreparing: false
        ) == [])
        #expect(CaptureLifecycleCoordinator.credentialPreparationActions(
            wasPreparing: true,
            isPreparing: true
        ) == [])

        #expect(CaptureLifecycleCoordinator.pendingCaptureRetryActions(isCredentialPreparationActive: false) == [.retryPendingCaptures])
        #expect(CaptureLifecycleCoordinator.pendingCaptureRetryActions(isCredentialPreparationActive: true) == [])
        #expect(CaptureLifecycleCoordinator.pendingCaptureRetryActions(
            isCredentialPreparationActive: false,
            isCameraBusy: true
        ) == [])

        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .active))
        #expect(CaptureLifecycleCoordinator.shouldRestoreCamera(
            for: .active,
            shouldReturnToCameraOnForeground: true
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .inactive))
        #expect(!CaptureLifecycleCoordinator.shouldRestoreCamera(for: .background))

        #expect(CaptureLifecycleCoordinator.shouldResumeCameraAfterDepthAlbumPresentationChange(isPresented: false))
        #expect(!CaptureLifecycleCoordinator.shouldResumeCameraAfterDepthAlbumPresentationChange(isPresented: true))

        #expect(CaptureLifecycleCoordinator.shouldRetryPendingCaptures(isCredentialPreparationActive: false))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCaptures(isCredentialPreparationActive: true))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCaptures(
            isCredentialPreparationActive: false,
            isCameraBusy: true
        ))

        #expect(CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: true,
            isPreparing: false
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: false,
            isPreparing: false
        ))
        #expect(!CaptureLifecycleCoordinator.shouldRetryPendingCapturesAfterCredentialPreparationChange(
            wasPreparing: true,
            isPreparing: true
        ))
    }

    @Test func shutterHapticsPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterHapticsEnabled)
        #expect(!CameraFeedbackPreferences.shutterHapticsEnabledKey.isEmpty)
    }

    @Test @MainActor func sharedCameraHapticsEnableAudioInputAllowanceOnlyWhenEnabled() {
        var audioInputAllowanceAttempts = 0
        let controller = CameraHapticFeedbackController {
            audioInputAllowanceAttempts += 1
        }

        controller.setEnabled(false)
        controller.prepareForCameraInteraction()
        #expect(controller.hasPreparedCameraInteraction)
        #expect(!controller.isEnabled)
        #expect(audioInputAllowanceAttempts == 0)

        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(audioInputAllowanceAttempts == 0)

        controller.cameraAudioInputDidChange(isActive: true)
        #expect(audioInputAllowanceAttempts == 1)

        controller.prepareForCameraInteraction()
        #expect(audioInputAllowanceAttempts == 1)
    }

    @Test func shutterSoundPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterSoundEnabled)
        #expect(!CameraFeedbackPreferences.shutterSoundEnabledKey.isEmpty)
    }

    @Test func releaseCapturePoliciesStayFixedWhileDebugOverridesRemainAvailable() {
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.speed.rawValue,
            allowsDebugOverride: true
        ) == .speed)
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.balanced.rawValue,
            allowsDebugOverride: true
        ) == .balanced)
        #expect(CameraPhotoQualityPreference.resolvedForRuntime(
            rawValue: CameraPhotoQualityPreference.speed.rawValue,
            allowsDebugOverride: false
        ) == .quality)

        #expect(!CameraDepthAvailabilityHintPreferences.resolvedShowsHints(
            storedValue: false,
            allowsDebugOverride: true
        ))
        #expect(CameraDepthAvailabilityHintPreferences.resolvedShowsHints(
            storedValue: false,
            allowsDebugOverride: false
        ))

        #expect(CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: false,
            suppressionSupported: true
        ))
        #expect(!CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: false,
            suppressionSupported: false
        ))
        #expect(!CameraFeedbackPreferences.shouldSuppressShutterSound(
            storedIsEnabled: true,
            suppressionSupported: true
        ))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func proVideoIsAProductionPathWithNoDebugPreference() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let controllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let preferencesSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift"
        )
        let videoViewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel+VideoCapture.swift"
        )

        #expect(!settingsSource.contains("PRO Video Graph Probe"))
        #expect(!settingsSource.contains("CameraProVideoResearchPreferences"))
        #expect(!preferencesSource.contains("CameraProVideoResearchPreferences"))
        #expect(!cameraSource.contains("isProVideoResearchEnabled"))
        #expect(!cameraSource.contains("proVideoResearchPreferenceEnabled"))
        #expect(!cameraSource.contains("Video is unavailable in PRO mode"))
        #expect(!cameraSource.contains("PRO mode is available for photos"))
        #expect(cameraSource.contains("viewModel.isPhotographerModeActive"))
        #expect(cameraSource.contains("viewModel.isRearCameraActive"))
        #expect(cameraSource.contains("if selectedMode == .video"))
        #expect(cameraSource.contains("await viewModel.teardownPreparedVideoModeIfNeeded()"))
        #expect(cameraSource.contains("await viewModel.prepareVideoModeIfNeeded()"))

        #expect(controllerSource.contains("TAPVideoGraphOutputRouter"))
        #expect(controllerSource.contains("? manualFocusPreviewStream.videoOutput"))
        #expect(controllerSource.contains("preparedGraph.outputRouter.activate(recorder)"))
        #expect(!controllerSource.contains("preparedGraph.dataOutputSynchronizer.setDelegate"))
        #expect(videoViewModelSource.contains("guard await prepareVideoModeIfNeeded()"))
        #expect(videoViewModelSource.contains("handleVideoRecordingWriterFailure"))
        #expect(videoViewModelSource.contains("cancelVideoRecordingAfterWriterFailure"))
    }

    @Test func resourceInitializationRequiresCameraInteractionAndUsableCatalog() {
        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .ready)

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: true,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.cameraSession))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: false,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.firstPreview))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: false,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true
        ) == .preparing(.primaryControls))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: false,
            hasUsableLibraryCatalog: true
        ) == .preparing(.haptics))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: false
        ) == .preparing(.libraryCatalog))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .denied,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: false,
            isDepthCaptureReady: false,
            hasPresentedFirstPreview: false,
            hasSafePrimaryControls: false,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: false
        ) == .preparing(.cameraAuthorization))

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPresentedFirstPreview: true,
            hasSafePrimaryControls: true,
            hasPreparedHaptics: true,
            hasUsableLibraryCatalog: true,
            isSceneActive: false
        ) == .preparing(.cameraSession))
    }

    @Test func cameraRouteForegroundPreferenceDefaultsToDisabled() throws {
        let suiteName = "TAPCameraCapturePresentationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(!CameraRoutePreferences.defaultReturnToCameraOnForeground)
        #expect(!CameraRoutePreferences.returnToCameraOnForegroundKey.isEmpty)
        #expect(!CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))

        userDefaults.set(true, forKey: CameraRoutePreferences.returnToCameraOnForegroundKey)

        #expect(CameraRoutePreferences.returnToCameraOnForeground(in: userDefaults))
    }

    @Test @MainActor func foregroundCameraRouteRestoreRequiresEnabledPreferenceAndPriorInactivePhase() throws {
        let coordinator = CaptureLifecycleCoordinator()

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .inactive,
            returnsToCameraOnForeground: true
        ))
        #expect(coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: true
        ))

        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .background,
            returnsToCameraOnForeground: false
        ))
        #expect(!coordinator.foregroundRouteRestorePolicy(
            for: .active,
            returnsToCameraOnForeground: false
        ))
    }

    @Test func cameraCaptureControlsStateLocksLibraryWhileCaptureWrites() throws {
        let readyState = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: false,
            selectedMode: .photo,
            isRecordingMovie: false,
            isPreparingMovie: false,
            isPhotographerModeActive: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        #expect(readyState.canOpenTAPLibrary)
        #expect(readyState.recentThumbnailOpacity == 1)
        #expect(readyState.tapLibraryAccessibilityLabel == "Open TAPCamDepth album")
        #expect(readyState.tapLibraryHelpText == "Open TAPCamDepth album.")

        let writingState = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: true,
            selectedMode: .photo,
            isRecordingMovie: false,
            isPreparingMovie: false,
            isPhotographerModeActive: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        #expect(!writingState.canOpenTAPLibrary)
        #expect(writingState.recentThumbnailOpacity == 0.42)
        #expect(writingState.tapLibraryAccessibilityLabel == "Finishing capture write")
        #expect(writingState.tapLibraryHelpText == "TAP Library will be available after the current capture finishes writing.")
    }

    @Test func cameraCaptureControlsStateDoesNotNameSensitiveInputs() throws {
        let state = CameraCaptureControlsState(
            isShutterEnabled: true,
            isLibraryWriteInProgress: false,
            selectedMode: .photo,
            isRecordingMovie: false,
            isPreparingMovie: false,
            isPhotographerModeActive: false,
            isInteractionLocked: false,
            adjustmentControlState: nil,
            basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "id",
            "capture",
            "asset",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func videoRecordingTimecodeFormatsElapsedAndLimit() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let state = CameraVideoRecordingTimecodeState(
            startedAt: startedAt,
            maximumDuration: 180
        )

        #expect(state.displayText(at: startedAt) == "0:00 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(1.9)) == "0:01 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(181)) == "3:00 / 3:00")
        #expect(state.displayText(at: startedAt.addingTimeInterval(-1)) == "0:00 / 3:00")
    }

    @Test func videoRecordingTimecodeFormatsHourDurations() {
        #expect(CameraVideoRecordingTimecodeState.formatted(seconds: 3_661) == "1:01:01")
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func videoRecordingTimecodeUsesLeafNativeUpdateBoundary() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraVideoRecordingTimecodeView.swift"
        )

        #expect(source.contains("UIViewRepresentable"))
        #expect(source.contains("override var intrinsicContentSize"))
        #expect(source.contains("timecodeLabel.text = text"))
        #expect(!source.contains("TimelineView"))
        #expect(!source.contains("@Published"))
    }

    @Test func cameraPreviewStageStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewStageState(
            nativePreviewAspectRatio: 3.0 / 4.0,
            focalLengthOptions: [],
            shouldShowFocalLengthSelector: false,
            guideOverlayPreference: .ruleOfThirds,
            previewCropRectNormalized: CropRectNormalized(x: 0.1, y: 0.2, width: 0.8, height: 0.6),
            temporaryFocusEVOffset: 0.3,
            focusMode: .auto,
            focusRuntimeEvent: nil,
            focusMagnifierPreference: .brief,
            focusLoupePulseID: nil,
            viewfinderEdgeToastMessage: nil,
            contentRotation: .zero,
            isCameraPathTransitioning: false,
            previewReadinessGeneration: 0
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraPreviewFocusPointMapsThroughVisibleCrop() throws {
        let localPoint = CameraPreviewFocusPoint(x: 0.25, y: 0.75)
        let mappedPoint = localPoint.mappedThroughVisibleCrop(
            CropRectNormalized(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        )
        let nonFinitePoint = CameraPreviewFocusPoint(x: .nan, y: .infinity)

        #expect(abs(mappedPoint.x - 0.3) < 0.0001)
        #expect(abs(mappedPoint.y - 0.65) < 0.0001)
        #expect(CameraPreviewFocusPoint(x: -1, y: 2) == CameraPreviewFocusPoint(x: 0, y: 1))
        #expect(nonFinitePoint == CameraPreviewFocusPoint(x: 0.5, y: 0.5))
    }

    @Test func cameraFocusLockRequestSeparatesDisplayAndCapturePoints() throws {
        let displayPoint = CameraPreviewFocusPoint(x: 0.25, y: 0.75)
        let capturePoint = CameraPreviewFocusPoint(x: 0.3, y: 0.65)
        let lockCurrent = CameraFocusLockRequest.lockCurrent(displayPoint: displayPoint)
        let refocusAndLock = CameraFocusLockRequest.refocusAndLock(
            displayPoint: displayPoint,
            capturePoint: capturePoint
        )

        #expect(lockCurrent.displayPoint == displayPoint)
        #expect(lockCurrent.capturePoint == nil)
        #expect(refocusAndLock.displayPoint == displayPoint)
        #expect(refocusAndLock.capturePoint == capturePoint)
    }

    @Test func cameraFocusTargetOverlayStatePersistsUntilRuntimeInvalidation() throws {
        let point = CameraPreviewFocusPoint(x: 0.25, y: 0.75)
        let focusing = CameraFocusTargetOverlay.focusing(at: point)
        let initialFocusCycle = focusing.applyingRuntimeEvent(.focusStarted)
        let focused = try #require(focusing.applyingRuntimeEvent(.focusSettled))
        let invalidatedBySubjectChange = focused.applyingRuntimeEvent(.subjectAreaChanged)
        let invalidatedByRuntimeFocusCycle = focused.applyingRuntimeEvent(.focusStarted)
        let locked = focused.lockedOverlay()
        let ignoredRuntimeCycle = locked.applyingRuntimeEvent(.focusStarted)
        let movedLockPoint = CameraPreviewFocusPoint(x: 0.8, y: 0.2)
        let movedLocked = focused.lockedOverlay(at: movedLockPoint)
        let previewSize = CGSize(width: 300, height: 400)
        let insideCurrentFrame = focused.contains(
            CameraPreviewFocusPoint(x: 0.25 + 35.0 / 300.0, y: 0.75),
            previewSize: previewSize,
            sideLength: 72
        )
        let outsideCurrentFrame = focused.contains(
            CameraPreviewFocusPoint(x: 0.25 + 37.0 / 300.0, y: 0.75),
            previewSize: previewSize,
            sideLength: 72
        )

        #expect(focusing.point == point)
        #expect(focusing.phase == .focusing)
        #expect(initialFocusCycle == focusing)
        #expect(focused.id == focusing.id)
        #expect(focused.phase == .focused)
        #expect(invalidatedBySubjectChange == nil)
        #expect(invalidatedByRuntimeFocusCycle == nil)
        #expect(locked.phase == .locked)
        #expect(ignoredRuntimeCycle == locked)
        #expect(movedLocked.point == movedLockPoint)
        #expect(movedLocked.phase == .locked)
        #expect(insideCurrentFrame)
        #expect(!outsideCurrentFrame)
    }

    @Test func cameraFocalLengthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraFocalLengthDisplayOption(
            selectionToken: "fov-0",
            displayName: "24 mm Wide",
            numericLabel: "24",
            unitLabel: "mm",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "camera",
            "device",
            "profile",
            "source",
            "depth",
            "zoom",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraGuideOverlayPreferenceDefaultsToOffAndResolvesSafely() throws {
        #expect(CameraGuideOverlayPreference.defaultValue == .off)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "ruleOfThirds") == .ruleOfThirds)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "centerCross") == .centerCross)
        #expect(CameraGuideOverlayPreference.resolved(rawValue: "unexpected") == .off)
        #expect(CameraViewfinderHighlightPreference.defaultValue == .yellow)
        #expect(CameraViewfinderHighlightPreference.resolved(rawValue: "titian") == .titian)
        #expect(CameraViewfinderHighlightPreference.resolved(rawValue: "unexpected") == .yellow)
        #expect(CameraViewfinderHighlightPreference.titian.title == "Titian")
    }

    @Test func cameraCaptureModeOptionEnablesPhotoAndVideo() throws {
        #expect(CameraCaptureModeOption.photo.isAvailableInStageOne)
        #expect(CameraCaptureModeOption.video.isAvailableInStageOne)
        #expect(CameraCaptureModeOption.allCases.map(\.title) == ["PHOTO", "VIDEO"])
        #expect(
            CameraCaptureModeOption.allCases.map(\.accessibilityLabel)
                == ["Photo mode", "Video mode"]
        )
    }

    @Test func cameraChromeControlModesKeepExpectedDefaultsAndCycleOrder() throws {
        #expect(CameraFocusControlMode.auto.toggled == .manual)
        #expect(CameraFocusControlMode.manual.toggled == .auto)
        #expect(CameraFlashControlMode.defaultValue == .auto)
        #expect(CameraFlashControlMode.defaultStartupPolicy == .defaultOn)
        #expect(CameraFlashControlMode.auto.next == .on)
        #expect(CameraFlashControlMode.on.next == .off)
        #expect(CameraFlashControlMode.off.next == .auto)
        #expect(CameraFlashControlMode.auto.captureFlashMode == .auto)
        #expect(CameraFlashControlMode.on.captureFlashMode == .on)
        #expect(CameraFlashControlMode.off.captureFlashMode == .off)
        #expect(CameraViewfinderControlDefaultPolicy.allCases.map(\.title) == [
            "Default Off",
            "Default On",
            "Remember Last State"
        ])
    }

    @Test func viewfinderControlDefaultPoliciesResolveStartupState() throws {
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            lastModeRawValue: CameraFlashControlMode.on.rawValue
        ) == .off)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            lastModeRawValue: CameraFlashControlMode.off.rawValue
        ) == .auto)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastModeRawValue: CameraFlashControlMode.on.rawValue
        ) == .on)
        #expect(CameraFlashControlMode.resolvedStartupMode(
            policyRawValue: "unexpected",
            lastModeRawValue: CameraFlashControlMode.off.rawValue
        ) == .auto)

        #expect(!CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOff.rawValue,
            lastIsEnabled: true
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.defaultOn.rawValue,
            lastIsEnabled: false
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            lastIsEnabled: true
        ))
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(
            policyRawValue: "unexpected",
            lastIsEnabled: true
        ))
    }

    @Test func viewfinderControlStartupPoliciesReadPersistedDefaultsAndLastState() throws {
        let suiteName = "TAPCameraViewfinderDefaultPolicyTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraFlashControlMode.resolvedStartupMode(in: userDefaults) == .auto)
        #expect(!CameraLivePhotoPreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraFlashControlMode.startupPolicyKey
        )
        userDefaults.set(CameraFlashControlMode.on.rawValue, forKey: CameraFlashControlMode.lastModeKey)
        #expect(CameraFlashControlMode.resolvedStartupMode(in: userDefaults) == .on)

        userDefaults.set(
            CameraViewfinderControlDefaultPolicy.rememberLastState.rawValue,
            forKey: CameraLivePhotoPreferences.startupPolicyKey
        )
        userDefaults.set(true, forKey: CameraLivePhotoPreferences.lastEnabledKey)
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(in: userDefaults))

        userDefaults.removeObject(forKey: CameraLivePhotoPreferences.lastEnabledKey)
        userDefaults.set(true, forKey: CameraLivePhotoPreferences.legacyIsEnabledKey)
        #expect(CameraLivePhotoPreferences.resolvedStartupIsEnabled(in: userDefaults))
    }

    @Test func cameraCaptureDataUsePreferencesDefaultToLocationOnMicrophoneOff() throws {
        let suiteName = "TAPCameraCaptureDataUsePreferencesTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraCaptureDataUsePreferences.usesLocationData(in: userDefaults))
        #expect(!CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))

        userDefaults.set(false, forKey: CameraCaptureDataUsePreferences.usesLocationDataKey)
        userDefaults.set(true, forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey)

        #expect(!CameraCaptureDataUsePreferences.usesLocationData(in: userDefaults))
        #expect(CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
    }

    @Test func microphoneDataPreferenceMigratesTheLegacyChoice() throws {
        let suiteName = "TAPCameraMicrophoneLegacyMigrationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(
            true,
            forKey: CameraCaptureDataUsePreferences.legacyUsesMicrophoneDataKey
        )

        #expect(CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
        #expect(
            userDefaults.object(forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey) as? Bool
                == true
        )
        #expect(!CameraCaptureDataUsePreferences.migrateLegacyMicrophonePreferenceIfNeeded(
            in: userDefaults
        ))
    }

    @Test func firstMicrophoneAuthorizationEnablesDataUseOnlyWithoutAPriorChoice() throws {
        let suiteName = "TAPCameraMicrophoneFirstAuthorizationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))
        #expect(CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
        #expect(!CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))

        userDefaults.set(false, forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey)
        userDefaults.set(true, forKey: CameraCaptureDataUsePreferences.legacyUsesMicrophoneDataKey)
        #expect(!CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))
        #expect(!CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
    }

    @Test func firstMicrophoneAuthorizationPreservesAnExplicitLegacyOptOut() throws {
        let suiteName = "TAPCameraMicrophoneLegacyOptOutTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(
            false,
            forKey: CameraCaptureDataUsePreferences.legacyUsesMicrophoneDataKey
        )

        #expect(!CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded(
            in: userDefaults
        ))
        #expect(!CameraCaptureDataUsePreferences.usesMicrophoneData(in: userDefaults))
        #expect(
            userDefaults.object(forKey: CameraCaptureDataUsePreferences.usesMicrophoneDataKey) as? Bool
                == false
        )
    }

    @Test func cameraAdjustmentControlStatePublishesCapabilityGatedRanges() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            minimumFocusDistanceMillimeters: 125,
            isoRange: .init(minimum: 64, maximum: 1_250),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 8_000.0, maximum: 0.5)
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: .iso,
            exposureMode: .auto(globalBias: 0.3),
            focusMode: .manual,
            draft: .init(iso: 400.4, shutterDurationSeconds: 1.0 / 125.0, lensPosition: 0.456)
        )
        let shutterPosition = state.exposure.shutterPosition(for: 1.0 / 120.0)
        let resolvedShutter = state.exposure.shutterDuration(forPosition: shutterPosition)

        #expect(state.exposure.isAvailable)
        #expect(state.focus.isAvailable)
        #expect(state.exposure.isoRange == 64...1_250)
        #expect(state.activeControl == .iso)
        #expect(state.exposure.evTitle == "EV")
        #expect(state.exposure.evValue == "+0.3")
        #expect(state.exposure.isoBadge == "A")
        #expect(state.exposure.shutterBadge == "A")
        #expect(abs(resolvedShutter - (1.0 / 125.0)) < 0.0001)
        #expect(state.exposure.isoScale.label(for: 400.4) == "400")
        #expect(state.exposure.shutterScale.label(for: 1.0 / 120.0) == "1/125")
        #expect(state.exposure.isoAutomationState == .automatic)
        #expect(state.exposure.shutterAutomationState == .automatic)
        #expect(state.focus.lensPositionLabel(for: 0.456) == "0.46")
        #expect(state.focus.lensPositionValue == "0.46")
        #expect(state.focus.automationState == .manual)
        #expect(state.focus.badge == "M")
    }

    @Test func cameraAdjustmentControlStateShowsMeterForCustomExposure() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .custom(meterOffset: -0.7),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )

        #expect(state.exposure.isCustom)
        #expect(state.exposure.evTitle == "Meter")
        #expect(state.exposure.evValue == "-0.7")
        #expect(state.exposure.isoBadge == "M")
        #expect(state.exposure.shutterBadge == "M")
    }

    @Test func cameraAdjustmentControlStateDisablesUnsupportedRows() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsCustomExposure: false,
            supportsCustomLensPosition: false,
            minimumFocusDistanceMillimeters: nil,
            isoRange: .init(minimum: 100, maximum: 100),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 60.0, maximum: 1.0 / 60.0)
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .auto(globalBias: 0),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )

        #expect(!state.exposure.isAvailable)
        #expect(!state.focus.isAvailable)
        #expect(state.focus.lensPositionValue == "0.50")
    }

    @Test func cameraAdjustmentControlStateCanDisableManualFocusDespiteCapabilitySupport() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            supportsLockedFocus: true,
            supportsCustomLensPosition: true
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .auto(globalBias: 0),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability),
            allowsManualFocusControl: false
        )

        #expect(capability.focus.supportsManualLensPosition)
        #expect(!state.focus.isAvailable)
    }

    @Test func cameraAdjustmentControlStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability()
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: .focus,
            exposureMode: .auto(globalBias: 0),
            focusMode: .manual,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data",
            "device"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }
    @Test func cameraFirstStagePreferencesExposeExplicitStorageKeysAndDefaults() throws {
        #expect(CameraEVPreferences.defaultResetOnAppLaunch)
        #expect(!CameraEVPreferences.resetOnAppLaunchKey.isEmpty)
        #expect(CameraEVPreferences.defaultGlobalBias == 0)
        #expect(!CameraEVPreferences.globalBiasKey.isEmpty)
        #expect(CameraEVPreferences.minimumGlobalBias < CameraEVPreferences.maximumGlobalBias)
        #expect(CameraPhotoQualityPreference.defaultValue == .quality)
        #expect(!CameraPhotoQualityPreference.storageKey.isEmpty)
        #expect(CameraFlashControlMode.defaultValue == .auto)
        #expect(CameraFlashControlMode.defaultStartupPolicy == .defaultOn)
        #expect(!CameraFlashControlMode.startupPolicyKey.isEmpty)
        #expect(CameraFlashControlMode.defaultLastMode == .auto)
        #expect(!CameraFlashControlMode.lastModeKey.isEmpty)
        #expect(CameraDepthAvailabilityHintPreferences.defaultShowsHints)
        #expect(!CameraDepthAvailabilityHintPreferences.showsHintsKey.isEmpty)
        #expect(CameraFocusMagnifierPreference.defaultValue == .brief)
        #expect(!CameraFocusMagnifierPreference.storageKey.isEmpty)
        #expect(CameraLivePhotoPreferences.defaultStartupPolicy == .rememberLastState)
        #expect(!CameraLivePhotoPreferences.startupPolicyKey.isEmpty)
        #expect(!CameraLivePhotoPreferences.defaultLastEnabled)
        #expect(!CameraLivePhotoPreferences.lastEnabledKey.isEmpty)
        #expect(CameraIdleTimerPreferences.defaultKeepScreenAwake)
        #expect(!CameraIdleTimerPreferences.keepScreenAwakeKey.isEmpty)
    }

    @Test func cameraEVPreferenceClampsAndResetsPerLaunchWhenEnabled() throws {
        let suiteName = "TAPCameraEVPreferenceTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(CameraEVPreferences.clampedBias(-99) == CameraEVPreferences.minimumGlobalBias)
        #expect(CameraEVPreferences.clampedBias(99) == CameraEVPreferences.maximumGlobalBias)
        #expect(CameraEVPreferences.clampedBias(.nan) == CameraEVPreferences.defaultGlobalBias)

        userDefaults.set(true, forKey: CameraEVPreferences.resetOnAppLaunchKey)
        userDefaults.set(1.2, forKey: CameraEVPreferences.globalBiasKey)
        userDefaults.set(-1, forKey: CameraEVPreferences.launchResetProcessIDKey)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == 0)
        #expect(userDefaults.double(forKey: CameraEVPreferences.globalBiasKey) == 0)

        CameraEVPreferences.persistGlobalBias(1.4, in: userDefaults)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == 1.4)
    }

    @Test func cameraEVPreferenceCanPersistAcrossColdLaunchWhenResetDisabled() throws {
        let suiteName = "TAPCameraEVPersistTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(false, forKey: CameraEVPreferences.resetOnAppLaunchKey)
        userDefaults.set(-0.7, forKey: CameraEVPreferences.globalBiasKey)

        #expect(CameraEVPreferences.resolvedLaunchBias(in: userDefaults) == -0.7)
    }

    @Test func cameraBasicEVControlStateClampsAndFormatsCompactValue() throws {
        let negative = CameraBasicEVControlState(bias: -99, isStripVisible: true)
        let zero = CameraBasicEVControlState(bias: 0.01, isStripVisible: false)
        let positive = CameraBasicEVControlState(bias: 1.24, isStripVisible: false)

        #expect(negative.bias == CameraEVPreferences.minimumGlobalBias)
        #expect(negative.compactValue == "-2.0")
        #expect(negative.isStripVisible)
        #expect(zero.compactValue == "0.0")
        #expect(positive.compactValue == "+1.2")
    }

    @Test func cameraTemporaryFocusEVPreferenceClampsOffset() throws {
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(-99) == CameraTemporaryFocusEVPreferences.minimumOffset)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(99) == CameraTemporaryFocusEVPreferences.maximumOffset)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(.nan) == 0)
        #expect(CameraTemporaryFocusEVPreferences.clampedOffset(0.7) == 0.7)
    }

    @Test func captureScoreSummaryUsesPublicSafeCaptureFacts() throws {
        let signedDepthScore = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .quality,
            signatureStatus: .signed(keyID: "secret-key-id")
        )
        let noDepthPendingScore = CaptureScoreSummary.make(
            depthAvailability: .unavailable,
            fileContainer: .jpeg,
            photoQualityLevel: .speed,
            signatureStatus: .pending(reason: "secret pending reason")
        )

        #expect(signedDepthScore.value == 100)
        #expect(signedDepthScore.detail == "Depth available · HEIC · Quality · Capture signed · Analysis ready")
        #expect(noDepthPendingScore.value < signedDepthScore.value)
        #expect(noDepthPendingScore.detail.contains("Depth unavailable"))
        for text in [
            signedDepthScore.detail,
            signedDepthScore.accessibilityText,
            noDepthPendingScore.detail,
            noDepthPendingScore.accessibilityText
        ] {
            for forbidden in ["secret", "key-id", "captureID", "asset", "file://", "/private/"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }

    @Test func captureScoreIntentServicePublishesLatestPublicSafeSnapshot() async throws {
        let olderScore = CaptureScoreSummary.make(
            depthAvailability: .unavailable,
            fileContainer: .jpeg,
            photoQualityLevel: .speed,
            signatureStatus: .pending(reason: "private reason")
        )
        let latestScore = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .quality,
            signatureStatus: .signed(keyID: "private-key")
        )
        let olderRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "raw-older-capture",
            capturedAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            photoQualityLevel: .speed,
            captureScoreSummary: olderScore
        )
        let latestRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "raw-latest-capture",
            capturedAt: Date(timeIntervalSince1970: 20),
            status: .exported,
            assetLocalIdentifier: "raw-asset-id",
            captureScoreSummary: latestScore
        )
        let service = CaptureScoreIntentService(
            records: {
                [olderRecord, latestRecord]
            },
            token: { rawValue in
                "token-\(rawValue.hashValue.magnitude)"
            }
        )

        let snapshot = try #require(try await service.latestScore())

        #expect(snapshot.summary == latestScore)
        #expect(snapshot.statusLabel == "Exported")
        #expect(snapshot.subtitle == "100/100 · Strong · Exported")
        #expect(!snapshot.id.contains("raw-latest-capture"))
        #expect(!snapshot.dialogText.contains("raw-latest-capture"))
        #expect(!snapshot.dialogText.contains("raw-asset-id"))
        #expect(!snapshot.dialogText.localizedCaseInsensitiveContains("private-key"))

        let matchedSnapshots = try await service.scoreSnapshots(matching: [snapshot.id])
        #expect(matchedSnapshots == [snapshot])
    }

    @Test func captureScoreQuerySuggestsRecentPublicSafeEntities() async throws {
        let score = CaptureScoreSummary.make(
            depthAvailability: .available,
            fileContainer: .heic,
            photoQualityLevel: .balanced,
            signatureStatus: .signed(keyID: "private-key")
        )
        let records = (0..<6).map { index in
            TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "raw-capture-\(index)",
                capturedAt: Date(timeIntervalSince1970: Double(index)),
                status: .exported,
                captureScoreSummary: score
            )
        }
        let query = CaptureScoreQuery(service: CaptureScoreIntentService(
            records: {
                records
            },
            token: { rawValue in
                "token-\(rawValue.hashValue.magnitude)"
            }
        ))

        let suggestedEntities = try await query.suggestedEntities()

        #expect(suggestedEntities.count == 5)
        #expect(suggestedEntities.map(\.snapshot.capturedAt) == records.reversed().prefix(5).map(\.capturedAt))
        for entity in suggestedEntities {
            #expect(!entity.snapshot.subtitle.isEmpty)
            #expect(!entity.id.contains("raw-capture"))
            #expect(!entity.snapshot.dialogText.contains("raw-capture"))
            #expect(!entity.snapshot.dialogText.localizedCaseInsensitiveContains("private-key"))
        }
    }

    @Test func tapCamIntentHandoffStoreConsumesOnlyFreshDestinationRequests() throws {
        let suiteName = "TAPCamIntentHandoffTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = TAPCamIntentHandoffStore(userDefaults: userDefaults)
        let now = Date(timeIntervalSince1970: 1_000)

        store.saveHandoff(TAPCamIntentHandoff(destination: .tapLibrary, requestedAt: now))
        #expect(store.loadAndClearHandoff(now: now.addingTimeInterval(20))?.destination == .tapLibrary)
        #expect(store.loadAndClearHandoff(now: now.addingTimeInterval(21)) == nil)

        store.saveHandoff(TAPCamIntentHandoff(
            destination: .camera,
            requestedAt: now.addingTimeInterval(-TAPCamIntentHandoff.defaultTimeToLive - 1)
        ))
        #expect(store.loadAndClearHandoff(now: now) == nil)
    }

    @Test func cameraIdleTimerPolicyOnlyDisablesIdleTimerForActiveVisibleCamera() throws {
        #expect(CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: false,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: false,
            isSettingsPresented: false,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: true,
            isLibraryPresented: false
        ))
        #expect(!CameraIdleTimerPolicy.shouldDisableIdleTimer(
            keepScreenAwake: true,
            isCameraViewVisible: true,
            isActiveScene: true,
            isSettingsPresented: false,
            isLibraryPresented: true
        ))
    }

    @Test func cameraViewfinderChromeStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraViewfinderChromeState(
            flashMode: .auto,
            isFlashAvailable: true,
            isLivePhotoAvailable: false,
            isLivePhotoEnabled: false,
            proModeState: .standard,
            basicEVState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
            contentRotation: .zero
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "capture",
            "asset",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "profile",
            "route",
            "pending",
            "data"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    #if DEBUG
    @Test func cameraPreviewDebugStateDoesNotNameCaptureSecurityOrOutputInputs() throws {
        let state = CameraPreviewDebugState(
            isDepthReady: true,
            activeCameraDisplayName: "Debug camera",
            statusMessage: "Debug status",
            recentMetrics: [],
            queuedJobCount: 0,
            depthOptions: [],
            showsZoomControl: false,
            zoomOptions: [],
            selectedZoomFactor: 1,
            fovLabel: "24mm",
            sliderRange: 1...1,
            isSliderEnabled: false,
            manualControlLines: []
        )
        let fieldNames = Mirror(reflecting: state).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "attest",
            "client",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "store",
            "pipeline",
            "route",
            "data",
            "session",
            "controller",
            "capability",
            "plan",
            "profile",
            "format",
            "device"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugDepthDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugDepthDisplayOption(
            selectionToken: "debug-depth-0",
            displayName: "Wide",
            iconName: "camera",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }

    @Test func cameraDebugZoomDisplayOptionDoesNotNameHardwarePlanningInputs() throws {
        let option = CameraDebugZoomDisplayOption(
            selectionToken: "debug-zoom-0",
            displayName: "1x",
            isSelected: true,
            isEnabled: true
        )
        let fieldNames = Mirror(reflecting: option).children.compactMap(\.label).joined(separator: " ")
        let forbiddenTokens = [
            "device",
            "profile",
            "source",
            "format",
            "capture",
            "asset",
            "photo",
            "heic",
            "proof",
            "manifest",
            "key",
            "plan"
        ]

        for token in forbiddenTokens {
            #expect(!fieldNames.localizedCaseInsensitiveContains(token))
        }
    }
    #endif
}
