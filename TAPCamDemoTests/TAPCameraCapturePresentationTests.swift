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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraUISmokeTestAnchorsStayExplicit() throws {
        let appSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift")
        let controlsSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift")
        let overlaySource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift")
        let uiTestSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemoUITests/ShutterCaptureSmokeTests.swift")

        #expect(appSource.contains("TAPCAM_UI_TEST_REAL_APP"))
        #expect(controlsSource.contains(#".accessibilityIdentifier("camera.capture.shutter")"#))
        #expect(overlaySource.contains(#".accessibilityIdentifier("camera.capture.status")"#))
        #expect(uiTestSource.contains(#"app.launchEnvironment["TAPCAM_UI_TEST_REAL_APP"] = "1""#))
        #expect(uiTestSource.contains(#"app.buttons["camera.capture.shutter"]"#))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraControlsUITestHarnessIsDebugOnlyAndClicksProductionControlView() throws {
        let appSource = try TAPCamDemoTestSourceInspection.source(relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift")
        let harnessSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/CameraControlsUITestHarnessView.swift"
        )
        let uiTestSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemoUITests/CameraControlsRegressionUITests.swift"
        )

        #expect(appSource.contains("#if DEBUG"))
        #expect(!appSource.contains("TAP_ENABLE_PRO_CAMERA_CONTROLS"))
        #expect(appSource.contains("isCameraControlsUITestHarness"))
        #expect(appSource.contains("TAPCAM_UI_TEST_CAMERA_CONTROLS"))
        #expect(appSource.contains("--tapcam-camera-controls-ui-test-harness"))
        #expect(appSource.contains("CameraControlsUITestHarnessView()"))
        #expect(harnessSource.contains("#if DEBUG"))
        #expect(harnessSource.contains("CameraCaptureControlsView("))
        #expect(harnessSource.contains("CameraAdjustmentControlState("))
        #expect(harnessSource.contains("camera.controlsHarness.status"))
        #expect(harnessSource.contains("camera.controlsHarness.togglePro"))
        #expect(!harnessSource.contains("AVCaptureDevice"))
        #expect(!harnessSource.contains("CameraControlService"))
        #expect(uiTestSource.contains("TAPCAM_UI_TEST_CAMERA_CONTROLS"))
        #expect(uiTestSource.contains("--tapcam-camera-controls-ui-test-harness"))
        #expect(uiTestSource.contains(#"tapButton("camera.lowerToolbar.ev""#))
        #expect(uiTestSource.contains(#"tapButton("camera.lowerToolbar.iso""#))
        #expect(uiTestSource.contains(#"tapButton("camera.lowerToolbar.shutter""#))
        #expect(uiTestSource.contains(#"tapButton("camera.lowerToolbar.focus""#))
        #expect(uiTestSource.contains("camera.tickedAdjustmentStrip"))
        #expect(uiTestSource.contains("assertFrame(shutter.frame, equals: proShutterFrame"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraCaptureControlsReserveProfessionalToolbarAboveStableShutterRow() throws {
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift"
        )
        let bodyStart = try #require(controlsSource.range(of: "var body: some View"))
        let toolbarSlotDeclaration = try #require(controlsSource.range(of: "private var professionalToolbarSlot"))
        let bodySource = String(controlsSource[bodyStart.lowerBound..<toolbarSlotDeclaration.lowerBound])
        let professionalToolbarSlotCall = try #require(bodySource.range(of: "professionalToolbarSlot"))
        let bottomControlsCall = try #require(bodySource.range(of: "bottomControls"))
        let modeSelectorCall = try #require(bodySource.range(of: "modeSelectorSlot"))

        #expect(professionalToolbarSlotCall.lowerBound < bottomControlsCall.lowerBound)
        #expect(bottomControlsCall.lowerBound < modeSelectorCall.lowerBound)
        #expect(bodySource.contains(".padding(.bottom, 4)"))
        #expect(controlsSource.contains("static let professionalToolbarSlotHeight: CGFloat = 38"))
        #expect(controlsSource.contains(".frame(height: Metrics.professionalToolbarSlotHeight)"))
        #expect(controlsSource.contains(".opacity(state.isPhotographerModeActive ? 1 : 0)"))
        #expect(controlsSource.contains(".allowsHitTesting(state.isPhotographerModeActive)"))
        #expect(controlsSource.contains(".accessibilityHidden(!state.isPhotographerModeActive)"))
        #expect(!controlsSource.contains(".move(edge: .bottom)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func recentLibraryControlKeepsPlaceholderInTheStableThumbnailSlot() throws {
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift"
        )
        let thumbnailSection = try #require(
            TAPCamDemoTestSourceInspection.substring(
                in: controlsSource,
                from: "private var recentPhotoThumbnail",
                to: "private enum Metrics"
            )
        )

        #expect(
            thumbnailSection.contains(
                "recentLibraryPresentation?.showsPlaceholderSymbol ?? true"
            )
        )
        #expect(thumbnailSection.contains(#""photo.on.rectangle""#))
        #expect(thumbnailSection.contains(".frame(width: 58, height: 58)"))
        #expect(!thumbnailSection.contains(".task"))
        #expect(!thumbnailSection.contains(".onAppear"))
        #expect(!thumbnailSection.contains(".onDisappear"))
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

    @Test func shutterSoundPreferenceDefaultsToEnabled() throws {
        #expect(CameraFeedbackPreferences.defaultShutterSoundEnabled)
        #expect(!CameraFeedbackPreferences.shutterSoundEnabledKey.isEmpty)
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraInitialReadinessGateBlocksFirstInstallUntilCameraIsInteractive() throws {
        let startupSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/StartupGateView.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let readinessSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraInitialReadinessGate.swift"
        )

        #expect(startupSource.contains("isPreparingFirstInstallCameraReadiness"))
        #expect(startupSource.contains("initialReadinessGate: .firstInstall {"))
        #expect(startupSource.contains("completeFirstInstallSetupAfterCameraReadiness"))
        #expect(cameraSource.contains("initialReadinessGate: CameraInitialReadinessGate = .disabled"))
        #expect(cameraSource.contains("CameraInitialReadinessOverlayView("))
        #expect(cameraSource.contains("initialReadinessState.blocksInteraction"))
        #expect(cameraSource.contains("activeSessionConfiguration != nil"))
        #expect(readinessSource.contains("nonisolated enum CameraInteractiveReadinessState"))
        #expect(readinessSource.contains("hasActiveSessionConfiguration, isDepthCaptureReady, hasPreparedHaptics"))
        #expect(readinessSource.contains(#".accessibilityIdentifier("camera.initialReadiness.overlay")"#))
    }

    @Test func initialCameraReadinessRequiresSessionDepthAndPreparedHaptics() {
        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPreparedHaptics: true,
            statusMessage: "Ready"
        ) == .ready)

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .authorized,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: true,
            isDepthCaptureReady: true,
            hasPreparedHaptics: false,
            statusMessage: "Ready"
        ).blocksInteraction)

        #expect(CameraInteractiveReadinessState.resolve(
            isGateEnabled: true,
            didCompleteGate: false,
            cameraAuthorizationStatus: .denied,
            isConfiguringSession: false,
            hasActiveSessionConfiguration: false,
            isDepthCaptureReady: false,
            hasPreparedHaptics: true,
            statusMessage: "Camera access denied"
        ) == .failed(message: "Camera access denied", canOpenSettings: true))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func foregroundCameraRouteRestoreDisablesNavigationAnimation() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift"
        )

        #expect(source.contains("restoreCameraRouteWithoutAnimation"))
        #expect(source.contains("transaction.animation = nil"))
        #expect(source.contains("transaction.disablesAnimations = true"))
        #expect(source.contains("withTransaction(transaction)"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraPreviewFocusTargetOverlayUsesPressStartForLongPressLock() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let cameraViewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )

        #expect(source.contains("CameraFocusTargetOverlay"))
        #expect(source.contains("showFocusTargetOverlay(at: localPoint, isLocked: false)"))
        #expect(source.contains("showFocusTargetOverlay(at: request.displayPoint, isLocked: true)"))
        #expect(source.contains("scheduleLongPressLock(at: pressStartPoint, previewSize: previewSize)"))
        #expect(source.contains("guard let request = longPressLockRequest("))
        #expect(source.contains("for: pressStartPoint,"))
        #expect(source.contains("previewSize: previewSize"))
        #expect(source.contains(".lockCurrent(displayPoint: focusTargetOverlay.point)"))
        #expect(source.contains(".refocusAndLock(displayPoint: pressStartPoint, capturePoint: capturePoint)"))
        #expect(source.contains("focusTargetOverlay.contains("))
        #expect(source.contains("sideLength: Metrics.focusIndicatorSide"))
        #expect(!source.contains("LongPressGesture(minimumDuration: 0.45)"))
        #expect(!source.contains("latestPressStartPoint"))
        #expect(!source.contains("let localPoint = focusTargetOverlay?.point ?? latestPressStartPoint"))
        #expect(source.contains("focusTargetOverlay.lockedOverlay(at: point)"))
        #expect(source.contains("onLockFocusAndExposure(request)"))
        #expect(source.contains("handleFocusRuntimeEvent"))
        #expect(source.contains("hideFocusTargetOverlay()"))
        #expect(!source.contains("onRefocusTarget"))
        #expect(source.contains("focusExposureScrub"))
        #expect(source.contains(".simultaneousGesture(focusExposureScrub())"))
        #expect(source.contains("DragGesture(minimumDistance: Metrics.focusExposureScrubMinimumDistance, coordinateSpace: .local)"))
        #expect(source.contains("guard state.focusMode == .auto,\n                      focusTargetOverlay != nil else"))
        #expect(source.contains("shouldSuppressNextTapFocus = true"))
        #expect(source.contains("onFinishTemporaryFocusEVAdjustment()"))
        #expect(source.contains("onClearFocusSession()"))
        #expect(source.contains("onAdjustTemporaryFocusEV(focusExposureScrubOffset"))
        #expect(!source.contains(".gesture(focusExposureScrub(for:"))
        #expect(!source.contains("private func focusExposureScrub(for overlay:"))
        #expect(!source.contains("FocusEVControl"))
        #expect(!source.contains("focusIndicator: FocusIndicator"))
        #expect(!source.contains("scheduleFocusTargetOverlayDismissal"))
        #expect(!source.contains("nonLockedFocusTargetLifetimeMilliseconds"))
        #expect(!source.contains(".milliseconds(1_100)"))
        #expect(!source.contains(".milliseconds(4_000)"))
        #expect(!source.contains("onLockFocusAndExposure(capturePoint)"))
        #expect(!source.contains("showFocusTargetOverlay(at: CameraPreviewFocusPoint(x: 0.5, y: 0.5), isLocked: true)"))
        #expect(source.contains("Text(\"AE/AF LOCK\")"))
        #expect(cameraViewSource.contains("private func lockFocusAndExposure(_ request: CameraFocusLockRequest)"))
        #expect(!cameraViewSource.contains("showViewfinderHint(\"AE/AF LOCK\")"))
        #expect(cameraViewSource.contains("case .lockCurrent:"))
        #expect(cameraViewSource.contains("await viewModel.lockFocusAndExposure()"))
        #expect(cameraViewSource.contains("case .refocusAndLock(_, let capturePoint):"))
        #expect(cameraViewSource.contains("await viewModel.lockFocusAndExposure(at: capturePoint)"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraFocusRuntimeEventsDriveOverlayValidity() throws {
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let viewModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewModel.swift"
        )
        let controllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let controlServiceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CameraControlService.swift"
        )

        #expect(previewSource.contains("state.focusRuntimeEvent"))
        #expect(previewSource.contains("focusTargetOverlay.applyingRuntimeEvent(event.kind)"))
        #expect(previewSource.contains("guard let nextOverlay = focusTargetOverlay.applyingRuntimeEvent(event.kind) else"))
        #expect(previewSource.contains("hideFocusTargetOverlay()"))
        #expect(!previewSource.contains("onRefocusTarget"))
        #expect(viewModelSource.contains("@Published var focusRuntimeEvent"))
        #expect(viewModelSource.contains("setFocusRuntimeEventHandler"))
        #expect(controllerSource.contains("AVCaptureDevice.subjectAreaDidChangeNotification"))
        #expect(controllerSource.contains(#"device.observe(\.isAdjustingFocus"#))
        #expect(controlServiceSource.contains("device.isSubjectAreaChangeMonitoringEnabled = true"))
        #expect(controlServiceSource.contains("device.isSubjectAreaChangeMonitoringEnabled = false"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraFocusLockBadgeDoesNotMoveFrameAnchor() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let viewStart = try #require(source.range(of: "private struct FocusIndicatorView: View"))
        let viewEnd = try #require(source.range(of: "private struct FocusEVAdjustmentView: View"))
        let viewSource = String(source[viewStart.lowerBound..<viewEnd.lowerBound])

        #expect(viewSource.contains("private var lockBadge: some View"))
        #expect(viewSource.contains("let highlightColor: Color"))
        #expect(viewSource.contains(".stroke(isLocked ? highlightColor : .white"))
        #expect(viewSource.contains(".foregroundStyle(highlightColor)"))
        #expect(viewSource.contains(".offset(y: -(Metrics.focusIndicatorSide / 2 + Metrics.lockBadgeVerticalGap))"))
        #expect(viewSource.contains(".frame(width: Metrics.focusIndicatorSide, height: Metrics.focusIndicatorSide)"))
        #expect(!viewSource.contains("VStack(spacing: 7)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraTemporaryFocusEVControlAvoidsLargeCapsuleBackground() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let viewStart = try #require(source.range(of: "private struct FocusEVAdjustmentView: View"))
        let viewSource = String(source[viewStart.lowerBound...])

        #expect(viewSource.contains("let highlightColor: Color"))
        #expect(viewSource.contains(#"Image(systemName: "sun.max.fill")"#))
        #expect(viewSource.contains(".foregroundStyle(highlightColor)"))
        #expect(viewSource.contains(".allowsHitTesting(false)"))
        #expect(viewSource.contains(".animation(.easeOut(duration: 0.12), value: offset)"))
        #expect(viewSource.contains("static let focusEVRailWidth: CGFloat = 20"))
        #expect(viewSource.contains("static let focusEVEdgeGap: CGFloat = 2"))
        #expect(viewSource.contains("static let focusEVRailTravel: CGFloat = 116"))
        #expect(viewSource.contains("static let focusEVMarkerSide: CGFloat = 17"))
        #expect(viewSource.contains("static let focusExposureScrubMinimumDistance: CGFloat = 8"))
        #expect(viewSource.contains("Metrics.focusEVMarkerSide / 2 - CGFloat(normalized * Metrics.focusEVRailTravel)"))
        #expect(!viewSource.contains("ForEach(0..<7"))
        #expect(!viewSource.contains(#"Image(systemName: "sun.max")"#))
        #expect(!viewSource.contains("let onAdjust: (Double) -> Void"))
        #expect(!viewSource.contains("DragGesture(minimumDistance: 0)"))
        #expect(!viewSource.contains("static let focusEVRailTopInset"))
        #expect(!viewSource.contains("let railY = y - Metrics.focusEVRailTopInset"))
        #expect(!viewSource.contains("Text(label)"))
        #expect(!viewSource.contains("EV 0.0"))
        #expect(!viewSource.contains("String(format: \"%+0.1f\", offset)"))
        #expect(!viewSource.contains("Capsule().fill(highlightColor"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraTemporaryFocusEVScrubDoesNotResetFocusRuntime() throws {
        let cameraViewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let adjustStart = try #require(cameraViewSource.range(of: "private func adjustTemporaryFocusEVOffset"))
        let finishStart = try #require(cameraViewSource.range(of: "private func finishTemporaryFocusEVAdjustment"))
        let clearStart = try #require(cameraViewSource.range(of: "private func clearFocusSession"))
        let selectControlStart = try #require(cameraViewSource.range(of: "private func selectAdjustmentControl", range: clearStart.upperBound..<cameraViewSource.endIndex))
        let adjustSource = String(cameraViewSource[adjustStart.lowerBound..<finishStart.lowerBound])
        let finishSource = String(cameraViewSource[finishStart.lowerBound..<clearStart.lowerBound])
        let clearSource = String(cameraViewSource[clearStart.lowerBound..<selectControlStart.lowerBound])

        #expect(adjustSource.contains("let clampedOffset = CameraTemporaryFocusEVPreferences.clampedOffset(offset)"))
        #expect(adjustSource.contains("guard clampedOffset != temporaryFocusEVOffset else"))
        #expect(adjustSource.contains("temporaryFocusEVOffset = clampedOffset"))
        #expect(adjustSource.contains("try? await Task.sleep(for: .milliseconds(70))"))
        #expect(adjustSource.contains("await viewModel.applyEffectiveAutoExposureBiasToActiveConfiguration(effectiveAutoExposureBias)"))
        #expect(finishSource.contains("temporaryFocusEVApplyTask?.cancel()"))
        #expect(finishSource.contains("await viewModel.applyEffectiveAutoExposureBiasToActiveConfiguration(effectiveAutoExposureBias)"))
        #expect(clearSource.contains("temporaryFocusEVOffset = 0"))
        #expect(clearSource.contains("temporaryFocusEVApplyTask?.cancel()"))
        #expect(clearSource.contains("viewModel.restoreAutoCameraControls(globalExposureBias: globalEVBias)"))
        #expect(!adjustSource.contains("focusAtPreviewPoint"))
        #expect(!adjustSource.contains("lockFocusAndExposure"))
        #expect(!adjustSource.contains("hideFocusTargetOverlay"))
        #expect(!finishSource.contains("focusAtPreviewPoint"))
        #expect(!finishSource.contains("lockFocusAndExposure"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraFocusControlGroupRotatesContentLikeFocalLengthSelector() throws {
        let focalLengthSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/FocalLengthSelectorView.swift"
        )
        let adjustmentSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift"
        )
        let captureControlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift"
        )

        #expect(focalLengthSource.contains("CenterAnchoredChromeRotation"))
        #expect(adjustmentSource.contains("let contentRotation: Angle"))
        #expect(adjustmentSource.contains("CameraToolbarButtonContent("))
        #expect(adjustmentSource.contains("CameraTickedSliderRow("))
        #expect(!adjustmentSource.contains("Slider(value: valueBinding"))
        #expect(captureControlsSource.contains("CenterAnchoredChromeRotation"))
        #expect(!adjustmentSource.contains(".rotationEffect(contentRotation)\n        .foregroundStyle(.white)"))
        #expect(!adjustmentSource.contains(".rotationEffect(contentRotation)\n        .accessibilityIdentifier(\"camera.tickedAdjustmentStrip\")"))
        #expect(!captureControlsSource.contains(".rotationEffect(state.contentRotation)\n        }"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraCenterAnchoredChromeRotationUsesStableFrameCenter() throws {
        let orientationSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraChromeOrientationController.swift"
        )
        let chromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift"
        )
        let adjustmentSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift"
        )

        #expect(orientationSource.contains("struct CenterAnchoredChromeRotation"))
        #expect(orientationSource.contains(".rotationEffect(rotation, anchor: .center)"))
        #expect(orientationSource.contains(".frame(width: width, height: height, alignment: .center)"))
        #expect(chromeSource.contains("CenterAnchoredChromeRotation"))
        #expect(adjustmentSource.contains("CenterAnchoredChromeRotation"))
    }

    @Test func cameraTickedSliderActiveTickIsTheOnlyDominantVisualState() {
        let minor = CameraTickedSliderTickVisualState.minor
        let major = CameraTickedSliderTickVisualState.major
        let center = CameraTickedSliderTickVisualState.center
        let active = CameraTickedSliderTickVisualState.active

        #expect(!minor.usesHighlightColor)
        #expect(!major.usesHighlightColor)
        #expect(!center.usesHighlightColor)
        #expect(active.usesHighlightColor)
        #expect(CameraTickedSliderTickVisualState.allCases.filter(\.usesHighlightColor) == [.active])

        #expect(minor.width < major.width)
        #expect(major.width < center.width)
        #expect(center.width < active.width)
        #expect(minor.height < major.height)
        #expect(major.height < center.height)
        #expect(center.height < active.height)
        #expect(minor.enabledOpacity < major.enabledOpacity)
        #expect(major.enabledOpacity < center.enabledOpacity)
        #expect(center.enabledOpacity < active.enabledOpacity)
        #expect(active.disabledOpacity < active.enabledOpacity)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraTickedAdjustmentStripUsesCenteredActiveTickAndSharedHaptics() throws {
        let adjustmentSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift"
        )
        let basicEVSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraBasicEVControlView.swift"
        )
        let sliderSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraTickedSliderRow.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let hapticSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraHapticFeedbackController.swift"
        )

        #expect(adjustmentSource.contains("tickValueStep: CameraEVPreferences.adjustmentStep"))
        #expect(adjustmentSource.contains("isEVIntegerHapticsEnabled: true"))
        #expect(adjustmentSource.contains("CameraTickedSliderRow("))
        #expect(basicEVSource.contains("CameraTickedSliderRow("))
        #expect(sliderSource.contains("portraitAdjustmentCenterline"))
        #expect(sliderSource.contains("activeTick"))
        #expect(sliderSource.contains("visualState: .active"))
        #expect(sliderSource.contains("visualState.usesHighlightColor"))
        #expect(sliderSource.contains("CameraTickedSliderTickVisualState"))
        #expect(sliderSource.contains("CameraTickedSliderTickMark("))
        #expect(sliderSource.contains("tickX(for: index, count: descriptors.count, width: proxy.size.width)"))
        #expect(sliderSource.contains("CGFloat(normalizedValue) * trackWidth"))
        #expect(sliderSource.contains(#".accessibilityIdentifier("camera.tickedAdjustmentStrip.activeTick")"#))
        #expect(!sliderSource.contains("valueCursor"))
        #expect(!sliderSource.contains("cursorTriangle"))
        #expect(!sliderSource.contains("CameraTriangleCursorShape"))
        #expect(sliderSource.contains("@Environment(\\.cameraHapticFeedbackController)"))
        #expect(sliderSource.contains("hapticFeedbackController.adjustmentChanged(style: adjustmentHapticStyle(for: value))"))
        #expect(sliderSource.contains("return .zeroTick"))
        #expect(sliderSource.contains("return .integerTick"))
        #expect(sliderSource.contains("return .selection"))
        #expect(!sliderSource.contains("UISelectionFeedbackGenerator"))
        #expect(!sliderSource.contains("UIImpactFeedbackGenerator"))
        #expect(hapticSource.contains("final class CameraHapticFeedbackController"))
        #expect(hapticSource.contains("UISelectionFeedbackGenerator"))
        #expect(hapticSource.contains("UIImpactFeedbackGenerator(style: .heavy)"))
        #expect(hapticSource.contains("UIImpactFeedbackGenerator(style: .medium)"))
        #expect(hapticSource.contains("enum CameraAdjustmentHapticStyle"))
        #expect(hapticSource.contains("case zeroTick"))
        #expect(hapticSource.contains("case integerTick"))
        #expect(hapticSource.contains("case selection"))
        #expect(cameraSource.contains("@StateObject private var hapticFeedbackController"))
        #expect(cameraSource.contains(".environment(\\.cameraHapticFeedbackController, hapticFeedbackController)"))
        #expect(cameraSource.contains("hapticFeedbackController.prepareForCameraInteraction()"))
        #expect(cameraSource.contains("hapticFeedbackController.shutterAccepted()"))
        #expect(!cameraSource.contains("UIImpactFeedbackGenerator(style: .medium)"))
        #expect(sliderSource.contains("lastHapticStepIndex"))
        #expect(sliderSource.contains("triggerSelectionHapticIfNeeded"))
        #expect(sliderSource.contains("position(x: portraitAdjustmentCenterline"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraModeSelectorBarDoesNotRotateOuterOrInnerContent() throws {
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift"
        )
        let modeStripStart = try #require(controlsSource.range(of: "private var modeStrip: some View"))
        let lowerToolbarStart = try #require(controlsSource.range(of: "@ViewBuilder\n    private var lowerToolbar"))
        let modeStripSource = String(controlsSource[modeStripStart.lowerBound..<lowerToolbarStart.lowerBound])

        #expect(modeStripSource.contains("ForEach(CameraCaptureModeOption.allCases)"))
        #expect(modeStripSource.contains("Text(LocalizedStringKey(mode.title))"))
        #expect(!modeStripSource.contains("rotationEffect"))
        #expect(controlsSource.contains("CameraLowerToolbarPlaceholderView"))
        #expect(!controlsSource.contains(#"ForEach(["EV", "ISO", "S", "AF", "ƒ"]"#))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraControlsDesignIsSingleCameraUXDesignSource() throws {
        let futureSpecsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "Docs/FutureCameraSpecs.md"
        )
        let controlsDesignSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "Docs/CameraControlsDesign.md"
        )
        let aiTraceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "Docs/AITrace/2026-06-30-camera-ux-stage-one-shell.md"
        )

        #expect(controlsDesignSource.contains("FOV selector bar"))
        #expect(controlsDesignSource.contains("Rotation Rules"))
        #expect(controlsDesignSource.contains("mode selector bar"))
        #expect(controlsDesignSource.contains("portrait adjustment centerline"))
        #expect(controlsDesignSource.contains("active tick"))
        #expect(controlsDesignSource.contains("不叠加三角形、圆点或其他独立游标"))
        #expect(controlsDesignSource.contains("value cursor"))
        #expect(controlsDesignSource.contains("focus target overlay"))
        #expect(controlsDesignSource.contains("focus frame anchor"))
        #expect(controlsDesignSource.contains("focus validity"))
        #expect(controlsDesignSource.contains("lock badge"))
        #expect(controlsDesignSource.contains("subject area changed"))
        #expect(controlsDesignSource.contains("runtime focus invalidation"))
        #expect(controlsDesignSource.contains("必须隐藏 `focus target overlay`"))
        #expect(controlsDesignSource.contains("```mermaid"))
        #expect(controlsDesignSource.contains("stateDiagram-v2"))
        #expect(controlsDesignSource.contains("Focused --> None: subject area changed"))
        #expect(controlsDesignSource.contains("Focused --> None: isAdjustingFocus == true"))
        #expect(!controlsDesignSource.contains("refocusing"))
        #expect(controlsDesignSource.contains("focus exposure scrub"))
        #expect(controlsDesignSource.contains("center-anchored chrome rotation"))
        #expect(controlsDesignSource.contains("manual focus tap assist"))
        #expect(controlsDesignSource.contains("按钮 frame、`PHOTO / VIDEO` 文字都不旋转"))
        #expect(controlsDesignSource.contains("`focus companion EV rail` 继续显示且不自动消失"))
        #expect(controlsDesignSource.contains("不显示 `EV` 字样、当前 EV 数值或刻度"))
        #expect(controlsDesignSource.contains("两者边缘间距优先使用 2pt"))
        #expect(controlsDesignSource.contains("太阳游标的中心必须落在 rail 的中点上"))
        #expect(controlsDesignSource.contains("用户只看到细线和黄色太阳 `value cursor`"))
        #expect(controlsDesignSource.contains("不使用固定时间自动隐藏"))
        #expect(controlsDesignSource.contains("不能改变对焦框位置"))
        #expect(!controlsDesignSource.contains("两者边缘间距优先使用 6pt"))
        #expect(!controlsDesignSource.contains("中间刻度上"))
        #expect(futureSpecsSource.contains("[CameraControlsDesign.md](CameraControlsDesign.md)"))
        #expect(aiTraceSource.contains("Docs/CameraControlsDesign.md"))
        #expect(!futureSpecsSource.contains("CameraUXPlan.md"))
        #expect(!aiTraceSource.contains("CameraUXPlan.md"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraViewfinderChromeKeepsFocusExperimentsOutOfReleaseSettingsAndPairsFlashWithLivePhoto() throws {
        let chromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )

        #expect(chromeSource.contains("private var topToolbar: some View"))
        #expect(chromeSource.contains("let topSafeAreaInset: CGFloat"))
        #expect(!chromeSource.contains("GeometryReader"))
        #expect(chromeSource.contains("flashButton"))
        #expect(chromeSource.contains("private var flashButtonIcon: some View"))
        #expect(chromeSource.contains(#"Image(systemName: state.flashMode.systemImage)"#))
        #expect(chromeSource.contains(".symbolRenderingMode(.palette)"))
        #expect(chromeSource.contains(".foregroundStyle(.white, highlightColor)"))
        #expect(chromeSource.contains(".foregroundStyle(highlightColor)"))
        #expect(!chromeSource.contains(#"Text("a")"#))
        #expect(!chromeSource.contains("flashBaseSystemImage"))
        #expect(chromeSource.contains("livePhotoButton"))
        #expect(chromeSource.contains("static let viewfinderButtonSize: CGFloat = 44"))
        #expect(chromeSource.contains(#".accessibilityIdentifier("camera.chrome.flash")"#))
        #expect(chromeSource.contains(#".accessibilityIdentifier("camera.chrome.livePhoto")"#))
        #expect(!chromeSource.localizedCaseInsensitiveContains("LiDAR"))
        #expect(settingsSource.contains("@AppStorage(CameraViewfinderHighlightPreference.storageKey)"))
        #expect(settingsSource.contains("@AppStorage(CameraFlashControlMode.startupPolicyKey)"))
        #expect(settingsSource.contains("@AppStorage(CameraLivePhotoPreferences.startupPolicyKey)"))
        #expect(settingsSource.contains("@AppStorage(CameraCaptureDataUsePreferences.usesLocationDataKey)"))
        #expect(settingsSource.contains("@AppStorage(CameraCaptureDataUsePreferences.usesMicrophoneDataKey)"))
        #expect(settingsSource.contains(#"Picker("Flash Default", selection: $flashStartupPolicyRawValue)"#))
        #expect(settingsSource.contains(#"Picker("Live Photo Default", selection: $livePhotoStartupPolicyRawValue)"#))
        #expect(settingsSource.contains("Use Location Data"))
        #expect(settingsSource.contains("Use Microphone Data"))
        #expect(settingsSource.contains("Get Permission"))
        #expect(settingsSource.contains("CameraViewfinderControlDefaultPolicy.allCases"))
        #expect(!settingsSource.contains(#"Picker("Default Flash""#))
        #expect(!settingsSource.contains(#"Toggle(isOn: $isLivePhotoEnabled)"#))
        #expect(settingsSource.contains(#"Picker("Highlight Color", selection: $viewfinderHighlightRawValue)"#))
        #expect(settingsSource.contains("CameraViewfinderHighlightPreference.allCases"))
        #expect(settingsSource.contains(".fill(preference.color)"))
        #expect(settingsSource.contains(#"Section("Debug Camera Controls")"#))
        #expect(settingsSource.contains("#if DEBUG\n    @AppStorage(CameraFocusMagnifierPreference.storageKey)"))
        #expect(!settingsSource.contains("CameraLiDARFocusAssistPreferences"))
        let viewfinderSectionStart = try #require(settingsSource.range(of: "private var viewfinderSettingsSection"))
        let cameraBehaviorSectionStart = try #require(settingsSource.range(of: "private var cameraBehaviorSection"))
        let viewfinderSection = String(settingsSource[viewfinderSectionStart.lowerBound..<cameraBehaviorSectionStart.lowerBound])
        #expect(!viewfinderSection.contains("Focus Magnifier"))
        #expect(!viewfinderSection.contains("LiDAR Focus Assist"))
        #expect(!settingsSource.contains(#"Section("Focus")"#))
        #expect(!settingsSource.contains(#"Section("Roadmap")"#))
        #expect(!settingsSource.contains("Shutter Position"))
        #expect(!settingsSource.contains("Second Shutter"))
        #expect(!settingsSource.contains("Landscape Control Split"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraViewfinderHighlightPreferenceFlowsThroughUserVisibleChrome() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let chromeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift"
        )
        let controlsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift"
        )
        let stageSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let debugZoomSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/DebugZoomControlView.swift"
        )

        #expect(cameraSource.contains("@AppStorage(CameraViewfinderHighlightPreference.storageKey)"))
        #expect(cameraSource.contains("@AppStorage(CameraFlashControlMode.startupPolicyKey)"))
        #expect(cameraSource.contains("@AppStorage(CameraFlashControlMode.lastModeKey)"))
        #expect(cameraSource.contains("@State private var isLivePhotoEnabled: Bool"))
        #expect(cameraSource.contains("@AppStorage(CameraLivePhotoPreferences.startupPolicyKey)"))
        #expect(cameraSource.contains("@AppStorage(CameraLivePhotoPreferences.lastEnabledKey)"))
        #expect(cameraSource.contains("@AppStorage(CameraCaptureDataUsePreferences.usesMicrophoneDataKey)"))
        #expect(cameraSource.contains("private var shouldCaptureLivePhotoAudio: Bool"))
        #expect(cameraSource.contains("AVCaptureDevice.authorizationStatus(for: .audio) == .authorized"))
        #expect(cameraSource.contains("livePhotoAudioInputConfigured == true"))
        #expect(cameraSource.contains("captureSessionPreferenceDidChange"))
        #expect(cameraSource.contains("applyPendingSettingsSessionReconfiguration"))
        #expect(cameraSource.contains("applyFlashStartupPolicy"))
        #expect(cameraSource.contains("applyLivePhotoStartupPolicy"))
        #expect(cameraSource.contains("persistRememberedViewfinderControlStateIfNeeded"))
        #expect(cameraSource.components(separatedBy: "== .rememberLastState").count >= 3)
        #expect(cameraSource.contains("lastFlashModeRawValue = flashMode.rawValue"))
        #expect(cameraSource.contains("lastLivePhotoEnabled = isLivePhotoEnabled"))
        #expect(!cameraSource.contains("@AppStorage(CameraLivePhotoPreferences.isEnabledKey)"))
        #expect(cameraSource.contains("private var viewfinderHighlightColor: Color"))
        #expect(cameraSource.components(separatedBy: "highlightColor: viewfinderHighlightColor").count >= 4)
        #expect(chromeSource.contains("let highlightColor: Color"))
        #expect(chromeSource.contains(#"Image(systemName: state.flashMode.systemImage)"#))
        #expect(chromeSource.contains(".symbolRenderingMode(.palette)"))
        #expect(chromeSource.contains(".foregroundStyle(.white, highlightColor)"))
        #expect(chromeSource.contains(".foregroundStyle(highlightColor)"))
        #expect(chromeSource.contains(".foregroundStyle(state.isLivePhotoEnabled ? highlightColor : .white)"))
        #expect(!chromeSource.contains(#"Text("a")"#))
        #expect(!chromeSource.contains("flashBaseSystemImage"))
        #expect(controlsSource.contains("let highlightColor: Color"))
        #expect(controlsSource.contains("highlightColor: highlightColor"))
        #expect(stageSource.contains("let highlightColor: Color"))
        #expect(stageSource.contains(".foregroundStyle(highlightColor)"))
        #expect(stageSource.contains(".stroke(isLocked ? highlightColor : .white"))
        #expect(!debugZoomSource.contains("CameraViewfinderHighlightPreference"))
        #expect(!debugZoomSource.contains("highlightColor"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraViewLaysOutTopToolbarBeforeViewfinderInsteadOfOverlayingIt() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let chromeRange = try #require(cameraSource.range(of: "viewfinderChrome(topSafeAreaInset:"))
        let previewRange = try #require(cameraSource.range(of: "cameraPreviewStage"))

        #expect(cameraSource.contains("topSafeAreaInset: proxy.safeAreaInsets.top"))
        #expect(chromeRange.lowerBound < previewRange.lowerBound)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraViewfinderEdgeToastStaysAtTopEdge() throws {
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )
        let toastOverlayStart = try #require(previewSource.range(of: ".overlay(alignment: .top) {\n                viewfinderEdgeToast"))
        let controlsOverlayStart = try #require(previewSource.range(of: ".overlay(alignment: .bottom) {\n                viewfinderControls"))
        let designSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "Docs/CameraControlsDesign.md"
        )

        #expect(toastOverlayStart.lowerBound < controlsOverlayStart.lowerBound)
        #expect(previewSource.contains("viewfinderEdgeToast\n                    .padding(.top, 14)"))
        #expect(!previewSource.contains("viewfinderEdgeToast\n                    .padding(.bottom, 14)"))
        #expect(designSource.contains("贴取景器上边缘内侧，水平居中"))
        #expect(!designSource.contains("贴取景器下边缘内侧，水平居中"))
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
        let shutterPosition = state.exposure.normalizedShutterPosition(for: 1.0 / 125.0)
        let resolvedShutter = state.exposure.shutterDuration(forNormalizedPosition: shutterPosition)

        #expect(state.exposure.isAvailable)
        #expect(state.focus.isAvailable)
        #expect(state.exposure.isoRange == 64...1_250)
        #expect(state.activeControl == .iso)
        #expect(state.exposure.evTitle == "EV")
        #expect(state.exposure.evValue == "+0.3")
        #expect(state.exposure.isoBadge == "A")
        #expect(state.exposure.shutterBadge == "A")
        #expect(abs(resolvedShutter - (1.0 / 125.0)) < 0.0001)
        #expect(state.exposure.isoLabel(for: 400.4) == "400")
        #expect(state.exposure.shutterLabel(for: 1.0 / 120.0) == "1/120")
        #expect(state.focus.lensPositionLabel(for: 0.456) == "0.46")
        #expect(state.focus.lensPositionValue == "0.46")
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func cameraAdjustmentDraftMemoryRestoresPerControlKeyWithoutPersistence() throws {
        let capability = TAPCamDemoTestFixtures.sampleManualControlCapability(
            minimumFocusDistanceMillimeters: 125,
            isoRange: .init(minimum: 64, maximum: 1_250),
            shutterDurationRangeSeconds: .init(minimum: 1.0 / 8_000.0, maximum: 0.5)
        )
        let state = CameraAdjustmentControlState(
            capability: capability,
            activeControl: nil,
            exposureMode: .auto(globalBias: 0),
            focusMode: .auto,
            draft: CameraAdjustmentControlState.defaultDraft(from: capability)
        )
        var memory = CameraAdjustmentControlDraftMemory()

        let wideDraft = memory.store(
            CameraAdjustmentControlDraft(
                iso: 640,
                shutterDurationSeconds: 1.0 / 240.0,
                lensPosition: 0.28
            ),
            for: "wide-control",
            state: state
        )

        #expect(memory.storedDraftCount == 1)
        #expect(memory.draft(for: "wide-control", state: state) == wideDraft)

        let teleDefault = memory.draft(for: "tele-control", state: state)
        #expect(teleDefault == CameraAdjustmentControlDraft.fallback.clamped(to: state))
        #expect(memory.storedDraftCount == 2)

        let clampedWideDraft = memory.store(
            CameraAdjustmentControlDraft(
                iso: 9_999,
                shutterDurationSeconds: 99,
                lensPosition: -1
            ),
            for: "wide-control",
            state: state
        )

        #expect(clampedWideDraft.iso == 1_250)
        #expect(clampedWideDraft.shutterDurationSeconds == 0.5)
        #expect(clampedWideDraft.lensPosition == 0)
        #expect(memory.draft(for: "wide-control", state: state) == clampedWideDraft)
        #expect(memory.draft(for: "tele-control", state: state) == teleDefault)

        let adjustmentControlSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift"
        )
        #expect(adjustmentControlSource.contains("CameraAdjustmentControlDraftMemory"))
        #expect(!adjustmentControlSource.contains("@AppStorage"))
        #expect(!adjustmentControlSource.contains("UserDefaults"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func manualFocusTapAssistIsAnAlwaysOnProMFInteraction() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift"
        )

        #expect(cameraSource.contains("manualFocusTapAssistAtPreviewPoint"))
        #expect(cameraSource.contains("await viewModel.performManualFocusTapAssist(at: point)"))
        #expect(cameraSource.contains("manualFocusAssistToken == nil"))
        #expect(settingsSource.contains("#if DEBUG\n    @AppStorage(CameraFocusMagnifierPreference.storageKey)"))
        #expect(!settingsSource.contains("TAP_ENABLE_PRO_CAMERA_CONTROLS"))
        let debugSectionStart = try #require(settingsSource.range(of: "private var debugCameraControlsSection"))
        let debugSectionEnd = try #require(settingsSource.range(of: "private var debugAppAttestSections"))
        let debugCameraControlsSection = String(settingsSource[debugSectionStart.lowerBound..<debugSectionEnd.lowerBound])
        #expect(debugCameraControlsSection.contains(#"Picker("Focus Magnifier", selection: $focusMagnifierRawValue)"#))
        #expect(!debugCameraControlsSection.contains("LiDAR Focus Assist"))
        #expect(!settingsSource.contains("CameraLiDARFocusAssistPreferences"))
        #expect(!debugCameraControlsSection.contains("Manual Focus Tap Assist"))
        #expect(!settingsSource.contains("CameraManualFocusTapAssistPreferences"))
        #expect(previewSource.contains("onManualFocusTapAssist(capturePoint)"))
        #expect(previewSource.contains("showManualFocusTapMarker(at: localPoint)"))
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

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func tapCamAppIntentsExposeCameraLibraryAndCaptureScoreShortcuts() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/TAPCamAppIntents.swift"
        )

        #expect(source.contains("enum TAPCamIntentDestination: String, AppEnum"))
        #expect(source.contains("struct OpenTAPCameraIntent: AppIntent"))
        #expect(source.contains("struct ShowLatestCaptureScoreIntent: AppIntent"))
        #expect(source.contains("struct ShowCaptureScoreIntent: AppIntent"))
        #expect(source.contains("struct CaptureScoreEntity: AppEntity"))
        #expect(source.contains("struct TAPCamAppShortcuts: AppShortcutsProvider"))
        #expect(source.contains("@Parameter(title: \"Destination\")"))
        #expect(source.contains("@Parameter(title: \"Capture Score\")"))
        #expect(source.contains("scoreEntity = await CaptureScoreQuery().defaultResult()"))
        #expect(source.contains("TAPCamIntentHandoffStore().saveHandoff"))
        #expect(source.contains("static let openAppWhenRun = true"))
        #expect(source.contains("static let openAppWhenRun = false"))
        #expect(source.contains(#""Open TAP Camera in \(.applicationName)""#))
        #expect(source.contains(#""Open TAP Library in \(.applicationName)""#))
        #expect(source.contains(#""Show TAP capture score in \(.applicationName)""#))
        #expect(source.contains(#""Show a TAP capture score in \(.applicationName)""#))
        #expect(source.contains("CameraRouteFileContextStore().token(for: rawValue)"))
        #expect(!source.contains("assetLocalIdentifier"))
        #expect(!source.contains("fileURL"))
        #expect(!source.contains("photoData"))
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
