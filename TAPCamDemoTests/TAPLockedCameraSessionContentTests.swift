//
//  TAPLockedCameraSessionContentTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

@Suite("Locked camera session content")
struct TAPLockedCameraSessionContentTests {
    @Test
    func pathPolicyUsesPendingCompatibleDirectCaptureLayout() {
        let sessionURL = URL(fileURLWithPath: "/tmp/locked-session", isDirectory: true)
        let captureID = "capture-123"
        let captureDirectory = TAPCamLockedSessionContentPathPolicy.captureDirectory(
            sessionContentURL: sessionURL,
            captureID: captureID
        )

        #expect(captureDirectory == sessionURL.appendingPathComponent(captureID, isDirectory: true))
        #expect(TAPCamLockedSessionContentPathPolicy.metadataURL(in: captureDirectory).lastPathComponent == "metadata.json")
        #expect(TAPCamLockedSessionContentPathPolicy.unsignedPhotoURL(in: captureDirectory).lastPathComponent == "unsigned.heic")
        #expect(!captureDirectory.pathComponents.contains("captures"))
        #expect(TAPCamLockedSessionContentPathPolicy.flatHEICFileName(captureID: captureID) == "TAPCam-capture-123.heic")
        #expect(TAPCamLockedSessionContentPathPolicy.flatHEICURL(sessionContentURL: sessionURL, captureID: captureID) == sessionURL.appendingPathComponent("TAPCam-capture-123.heic"))
    }

    @Test
    func importerRecognizesDirectLegacyAndFlatHEICCaptureLayouts() throws {
        let root = try TemporaryDirectory()
        let directCaptureID = "direct-capture"
        let legacyCaptureID = "legacy-capture"
        let flatCaptureID = "flat-capture"
        let lens = makeLensRecord()

        try writeCapture(
            captureID: directCaptureID,
            captureDirectory: TAPCamLockedSessionContentPathPolicy.captureDirectory(
                sessionContentURL: root.url,
                captureID: directCaptureID
            ),
            lens: lens,
            photoFileName: TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName,
            artifactKind: TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind,
            depthDataPresent: true
        )

        try writeCapture(
            captureID: legacyCaptureID,
            captureDirectory: TAPCamLockedSessionContentPathPolicy
                .legacyCapturesDirectory(sessionContentURL: root.url)
                .appendingPathComponent(legacyCaptureID, isDirectory: true),
            lens: lens,
            photoFileName: "photo.heic",
            artifactKind: nil,
            depthDataPresent: nil
        )
        try Data([0x04, 0x05, 0x06]).write(
            to: TAPCamLockedSessionContentPathPolicy.flatHEICURL(
                sessionContentURL: root.url,
                captureID: flatCaptureID
            ),
            options: [.atomic]
        )

        let probes = LockedCaptureSessionContentImporter.inspectCaptures(in: root.url)
        let probesByID = Dictionary(uniqueKeysWithValues: probes.map { ($0.metadata.captureID, $0) })
        let directProbe = try #require(probesByID[directCaptureID])
        let legacyProbe = try #require(probesByID[legacyCaptureID])
        let flatProbe = try #require(probesByID[flatCaptureID])

        #expect(probes.count == 3)
        #expect(directProbe.layout == "direct")
        #expect(directProbe.metadata.photoFileName == "unsigned.heic")
        #expect(directProbe.metadata.depthDataPresent == true)
        #expect(legacyProbe.layout == "legacy-captures")
        #expect(legacyProbe.metadata.photoFileName == "photo.heic")
        #expect(flatProbe.layout == "flat-heic")
        #expect(flatProbe.metadata.photoFileName == "TAPCam-flat-capture.heic")
        #expect(flatProbe.metadata.artifactKind == TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind)
    }

    @Test
    func pendingStoreIngestsLockedCaptureIntoPendingBundle() async throws {
        let root = try TemporaryDirectory()
        let sessionURL = root.url.appendingPathComponent("LockedSession", isDirectory: true)
        let pendingRootURL = root.url.appendingPathComponent("Pending", isDirectory: true)
        let captureID = "direct-capture"
        let lens = makeLensRecord()
        let captureDirectory = TAPCamLockedSessionContentPathPolicy.captureDirectory(
            sessionContentURL: sessionURL,
            captureID: captureID
        )
        try writeCapture(
            captureID: captureID,
            captureDirectory: captureDirectory,
            lens: lens,
            photoFileName: TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName,
            artifactKind: TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind,
            depthDataPresent: true
        )

        let probe = try #require(LockedCaptureSessionContentImporter.inspectCaptures(in: sessionURL).first)
        let store = TAPPendingCaptureStore(rootURL: pendingRootURL)
        let record = try await store.ingestLockedCapture(TAPPendingLockedCaptureImport(
            captureID: probe.metadata.captureID,
            capturedAt: probe.metadata.capturedAt,
            unsignedPhotoURL: probe.photoURL,
            metadata: probe.metadata
        ))

        #expect(record.captureID == captureID)
        #expect(record.status == .pending)
        #expect(record.photoFileContainer == .heic)
        #expect(record.photoQualityLevel == .quality)
        #expect(record.unsignedPhotoFilename == "unsigned.heic")
        #expect(record.signedPhotoFilename == nil)
        #expect(record.captureScoreSummary.value > 0)
        #expect(try await store.unsignedPhotoData(captureID: captureID) == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func pendingStoreLockedCaptureImportIsIdempotentForExistingCaptureID() async throws {
        let root = try TemporaryDirectory()
        let sessionURL = root.url.appendingPathComponent("LockedSession", isDirectory: true)
        let pendingRootURL = root.url.appendingPathComponent("Pending", isDirectory: true)
        let captureID = "idempotent-capture"
        let lens = makeLensRecord()
        let captureDirectory = TAPCamLockedSessionContentPathPolicy.captureDirectory(
            sessionContentURL: sessionURL,
            captureID: captureID
        )
        try writeCapture(
            captureID: captureID,
            captureDirectory: captureDirectory,
            lens: lens,
            photoFileName: TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName,
            artifactKind: TAPCamLockedSessionContentPathPolicy.unsignedTAPArtifactKind,
            depthDataPresent: true
        )

        let probe = try #require(LockedCaptureSessionContentImporter.inspectCaptures(in: sessionURL).first)
        let store = TAPPendingCaptureStore(rootURL: pendingRootURL)
        let importRequest = TAPPendingLockedCaptureImport(
            captureID: probe.metadata.captureID,
            capturedAt: probe.metadata.capturedAt,
            unsignedPhotoURL: probe.photoURL,
            metadata: probe.metadata
        )

        let first = try await store.ingestLockedCapture(importRequest)
        let second = try await store.ingestLockedCapture(importRequest)

        #expect(second.captureID == first.captureID)
        #expect(second.packageID == first.packageID)
        #expect(second.status == first.status)
        #expect(second.unsignedPhotoFilename == first.unsignedPhotoFilename)
        #expect(try await store.allRecords().map(\.captureID) == [captureID])
        #expect(try await store.unsignedPhotoData(captureID: captureID) == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func pendingStoreRejectsDepthHEICStagingBeforeFinalArtifact() async throws {
        let root = try TemporaryDirectory()
        let sessionURL = root.url.appendingPathComponent("LockedSession", isDirectory: true)
        let pendingRootURL = root.url.appendingPathComponent("Pending", isDirectory: true)
        let captureID = "staging-capture"
        let lens = makeLensRecord()
        let captureDirectory = TAPCamLockedSessionContentPathPolicy.captureDirectory(
            sessionContentURL: sessionURL,
            captureID: captureID
        )
        try writeCapture(
            captureID: captureID,
            captureDirectory: captureDirectory,
            lens: lens,
            photoFileName: TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName,
            artifactKind: TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind,
            depthDataPresent: true
        )

        let probe = try #require(LockedCaptureSessionContentImporter.inspectCaptures(in: sessionURL).first)
        let store = TAPPendingCaptureStore(rootURL: pendingRootURL)

        await #expect(throws: TAPDepthCaptureError.self) {
            try await store.ingestLockedCapture(TAPPendingLockedCaptureImport(
                captureID: probe.metadata.captureID,
                capturedAt: probe.metadata.capturedAt,
                unsignedPhotoURL: probe.photoURL,
                metadata: probe.metadata
            ))
        }
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func appContextPublisherProjectsEnabledMainAppFOVOptions() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/LockedCameraAppContextPublisher.swift"
        )

        #expect(source.contains("capabilityMatrix.focalLengthOptions().filter(\\.isEnabled)"))
        #expect(source.contains("capabilityMatrix.defaultFocalLengthOption"))
        #expect(source.contains("CameraOutputFormatPreference.defaultValue.rawValue"))
        #expect(source.contains("CameraPhotoQualityPreference.defaultValue.rawValue"))
        #expect(source.contains("CameraLivePhotoPreferences.resolvedStartupIsEnabled()"))
        #expect(source.contains("CameraFlashControlMode.resolvedStartupMode().rawValue"))
        #expect(source.contains("No depth-capable lock-screen lens is available. Unlock to continue."))
        #expect(!source.contains("debugDepthDeviceOptions()"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func startupSchedulesLockedSessionContentUpdatesAsAsyncImportWork() throws {
        let startupSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/StartupGateView.swift"
        )
        let appSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift"
        )
        let importerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/LockedCaptureSessionContentImporter.swift"
        )

        #expect(appSource.contains("@StateObject private var lockedCaptureImportRuntime"))
        #expect(appSource.contains("lockedCaptureImportRuntime.start()"))
        #expect(importerSource.contains("final class LockedCaptureSessionContentImportRuntime"))
        #expect(importerSource.contains("await LockedCaptureSessionContentImportScheduler().run()"))
        #expect(startupSource.contains("publishCurrentContextIfAvailable()"))
        #expect(!startupSource.contains("await LockedCaptureSessionContentImportScheduler().run()"))
        #expect(!startupSource.contains("reason: \"scene_active\""))
        #expect(startupSource.contains("beginDelayingAppearance()"))
        #expect(startupSource.contains("endDelayingAppearance()"))
        #expect(startupSource.contains("reason: \"locked_camera_transition\""))
        #expect(importerSource.contains("for await update in manager.sessionContentUpdates"))
        #expect(importerSource.contains("markSessionContentUpdateObserved()"))
        #expect(importerSource.contains(".importAvailableSessionContent(reason: \"session_content_update\")"))
        #expect(importerSource.contains("actor LockedCaptureSessionContentImportCoordinator"))
        #expect(importerSource.contains("waitForInitialSessionContentUpdateIfNeeded"))
        #expect(importerSource.contains("locked_camera_session_content_update kind=added"))
        #expect(importerSource.contains("locked_camera_session_content_update kind=removed"))
    }

    @Test
    func lockedCameraHandoffRoutesKnownActions() throws {
        let directCameraActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        directCameraActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPCamera
        ]
        let savedCameraActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        savedCameraActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPCamera,
            TAPCamLockedCameraHandoff.reasonKey: "saved"
        ]
        let directLibraryActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        directLibraryActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPLibrary
        ]
        let libraryActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        libraryActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPLibraryAfterLockedCapture
        ]
        let awaitingImportActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        awaitingImportActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPLibraryAwaitingLockedImport
        ]
        let openOnlyActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        openOnlyActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.openTAPMainAppOnly
        ]
        let systemOnlyOpenActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        let regenerateActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        regenerateActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: TAPCamLockedCameraHandoff.regenerateLockedCameraContext
        ]
        let unknownActivity = NSUserActivity(activityType: TAPCamLockedCameraHandoff.activityType)
        unknownActivity.userInfo = [
            TAPCamLockedCameraHandoff.tapActionKey: "unknown"
        ]

        #expect(TAPCamIntentHandoff(lockedCameraActivity: directCameraActivity)?.destination == .camera)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: directCameraActivity)?.shouldRegenerateLockedCameraContext == false)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: directCameraActivity)?.shouldDelayAppearanceForLockedContent == false)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: savedCameraActivity)?.destination == .camera)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: savedCameraActivity)?.shouldDelayAppearanceForLockedContent == true)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: directLibraryActivity)?.destination == .tapLibrary)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: libraryActivity)?.destination == .tapLibrary)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: awaitingImportActivity)?.destination == .tapLibraryAwaitingLockedImport)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: openOnlyActivity)?.destination == .camera)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: openOnlyActivity)?.shouldDelayAppearanceForLockedContent == false)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: systemOnlyOpenActivity) == nil)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: regenerateActivity)?.destination == .camera)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: regenerateActivity)?.shouldRegenerateLockedCameraContext == true)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: unknownActivity)?.destination == .camera)
        #expect(TAPCamIntentHandoff(lockedCameraActivity: NSUserActivity(activityType: "other")) == nil)
        if TAPCamDemoTestSourceInspection.isSourceTreeAvailable {
            let intentSource = try TAPCamDemoTestSourceInspection.source(
                relativePath: "TAPCamLockedCameraIntents/TAPCamLockedCameraIntent.swift"
            )
            #expect(intentSource.contains("static let activityType = NSUserActivityTypeLockedCameraCapture"))
            #expect(!intentSource.contains("openOnlyActivityType"))
            #expect(intentSource.contains("static let openTAPCamera = \"openTAPCamera\""))
            #expect(intentSource.contains("static let openTAPLibrary = \"openTAPLibrary\""))
            #expect(intentSource.contains("openTAPLibraryAwaitingLockedImport"))
            #expect(intentSource.contains("openTAPMainAppOnly"))
            #expect(intentSource.contains("locked_camera_intent_perform"))
        }
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func lockedCameraExtensionBundleIDsStayAlignedWithHistoricalWorkingTargets() throws {
        let projectSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo.xcodeproj/project.pbxproj"
        )

        #expect(projectSource.contains("PRODUCT_BUNDLE_IDENTIFIER = \"TAP-NAP.TAPCamDemo.LockedCapture\";"))
        #expect(projectSource.contains("PRODUCT_BUNDLE_IDENTIFIER = \"TAP-NAP.TAPCamDemo.Controls\";"))
        #expect(!projectSource.contains("PRODUCT_BUNDLE_IDENTIFIER = \"TAP-NAP.TAPCamDemo.LockedCameraCapture\";"))
        #expect(!projectSource.contains("PRODUCT_BUNDLE_IDENTIFIER = \"TAP-NAP.TAPCamDemo.LockedCameraControl\";"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func lockedSessionImportIsFlagDrivenNotEveryLibraryOpen() throws {
        let startupSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/StartupGateView.swift"
        )
        let appSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift"
        )
        let routeStoreSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift"
        )
        let librarySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let importerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/LockedCaptureSessionContentImporter.swift"
        )
        let notificationsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/TAPLibrary/TAPLibraryNotifications.swift"
        )
        #expect(appSource.contains("lockedCaptureImportRuntime.start()"))
        #expect(startupSource.contains("publishCurrentContextIfAvailable()"))
        #expect(!startupSource.contains("importLockedSessionContent(reason: \"startup\""))
        #expect(!startupSource.contains("reason: \"scene_active\""))
        #expect(!startupSource.contains("locked_camera_handoff_begin_delaying_appearance"))
        #expect(startupSource.contains("beginDelayingAppearance()"))
        #expect(startupSource.contains("endDelayingAppearance()"))
        #expect(startupSource.contains("locked_camera_handoff_route_no_context_refresh"))
        #expect(startupSource.contains(".onContinueUserActivity(TAPCamLockedCameraHandoff.activityType)"))
        #expect(startupSource.contains("locked_camera_handoff_ignored"))
        #expect(!startupSource.contains(".onContinueUserActivity(TAPCamLockedCameraHandoff.openOnlyActivityType)"))
        #expect(routeStoreSource.contains("@Published private(set) var pendingLockedImportReason"))
        #expect(routeStoreSource.contains("@Published private(set) var isAwaitingLockedCaptureImport"))
        #expect(routeStoreSource.contains("awaitingLockedCaptureImport: Bool = false"))
        #expect(routeStoreSource.contains("finishAwaitingLockedCaptureImport()"))
        #expect(routeStoreSource.contains("consumePendingLockedImportReason()"))
        #expect(librarySource.contains("let lockedImportReason = routeStore.consumePendingLockedImportReason()"))
        #expect(librarySource.contains("if let lockedImportReason"))
        #expect(librarySource.contains("routeStore.isAwaitingLockedCaptureImport"))
        #expect(librarySource.contains("Waiting for locked captures"))
        #expect(librarySource.contains(".tapCamLockedCaptureImportDidAddPendingCaptures"))
        #expect(librarySource.contains("routeStore.finishAwaitingLockedCaptureImport()"))
        #expect(cameraSource.contains("presentTAPLibrary()"))
        #expect(cameraSource.contains("case .tapLibraryAwaitingLockedImport"))
        #expect(cameraSource.contains("presentTAPLibrary(awaitingLockedCaptureImport: true)"))
        #expect(cameraSource.contains("awaitingLockedCaptureImport: Bool = false"))
        #expect(cameraSource.contains("routeStore.finishAwaitingLockedCaptureImport()"))
        #expect(!cameraSource.contains("presentTAPLibrary(lockedImportReason: \"locked_camera_handoff_route\")"))
        #expect(librarySource.contains("func loadForPresentation(lockedImportReason: String? = nil)"))
        #expect(librarySource.contains("loadForPresentation(lockedImportReason: lockedImportReason)"))
        #expect(librarySource.contains("shouldShowLoading"))
        #expect(librarySource.contains("Importing locked captures..."))
        #expect(cameraSource.contains(".tapCamIntentHandoffDidChange"))
        #expect(!cameraSource.contains("presentTAPLibraryAndImportLockedContent"))
        #expect(!cameraSource.contains("tap_library_open"))
        #expect(importerSource.contains("locked_camera_session_import_wait_for_initial_update"))
        #expect(importerSource.contains("lateSessionContentImportReasons"))
        #expect(importerSource.contains("locked_camera_session_import_late_poll"))
        #expect(importerSource.contains("locked_camera_session_import_late_poll_timeout"))
        #expect(importerSource.contains("locked_camera_handoff"))
        #expect(!importerSource.contains("\"tap_library_load\""))
        #expect(!importerSource.contains("\"tap_library_open\""))
        #expect(notificationsSource.contains("tapCamLockedCaptureImportDidAddPendingCaptures"))
        #expect(importerSource.contains("if summary.didImportCaptures"))
        #expect(importerSource.contains("name: .tapCamLockedCaptureImportDidAddPendingCaptures"))
        #expect(cameraSource.contains(".tapCamLockedCaptureImportDidAddPendingCaptures"))
        #expect(cameraSource.contains("retryPendingCapturesAfterLockedImport()"))
        #expect(cameraSource.contains("lifecycleCoordinator.retryPendingCaptures"))
        #expect(cameraSource.contains("appAttestController: appAttestController"))
    }

    @Test
    func lockedCameraContextSelectsExplicitLensOrFirstRecord() {
        let first = makeLensRecord(id: "lens-24", numericLabel: "1", zoomFactor: 1)
        let second = makeLensRecord(id: "lens-48", numericLabel: "2", zoomFactor: 2)

        let explicitContext = TAPCamLockedCameraContext(
            selectedLensID: second.id,
            lenses: [first, second]
        )
        let fallbackContext = TAPCamLockedCameraContext(
            selectedLensID: "missing",
            lenses: [first, second]
        )
        let emptyContext = TAPCamLockedCameraContext(lenses: [])

        #expect(explicitContext.selectedLens == second)
        #expect(fallbackContext.selectedLens == first)
        #expect(emptyContext.selectedLens == nil)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func lockedExtensionLensSelectorUsesAppContextRecordsAndRebuildsSession() throws {
        let rootSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCaptureRootView.swift"
        )
        let controllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCaptureCameraController.swift"
        )
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCapturePreviewHost.swift"
        )
        #expect(rootSource.contains("ForEach(controller.availableLenses)"))
        #expect(rootSource.contains("controller.selectLens(lens)"))
        #expect(rootSource.contains("controller.selectedLensID == lens.id"))
        #expect(rootSource.contains(".disabled(isSelected || !controller.state.canCapture)"))
        #expect(rootSource.contains("lockedAlbumPlaceholderIcon"))
        #expect(!rootSource.contains("TAPCamLockedCameraHandoff.openTAPLibraryAfterLockedCapture"))
        #expect(!rootSource.contains("TAPCamLockedCameraHandoff.openTAPLibraryAwaitingLockedImport"))
        #expect(!rootSource.contains("tapAction: TAPCamLockedCameraHandoff.openTAPLibrary,"))
        #expect(!rootSource.contains("tapAction: TAPCamLockedCameraHandoff.openTAPCamera,"))
        #expect(!rootSource.contains("TAPCamLockedCameraHandoff.openTAPNeutralRuntimeImport"))
        #expect(!rootSource.contains("TAPCamLockedCameraHandoff.openTAPLibraryRuntimeImport"))
        #expect(!rootSource.contains("e2b_flat_heic_runtime_import_after_saved_capture"))
        #expect(!rootSource.contains("e2b_flat_heic_runtime_import_placeholder"))
        #expect(!rootSource.contains("controller.recordStatusPlaceholderTap(session: session)"))
        #expect(rootSource.contains("controller.openHostApplicationSystemOnly(session: session)"))
        #expect(!rootSource.contains("activityType: TAPCamLockedCameraHandoff.openOnlyActivityType"))
        #expect(!rootSource.contains("TAPCamLockedCameraHandoff.openTAPMainAppOnly"))
        #expect(!rootSource.contains("app_activity_open_only_placeholder"))
        #expect(rootSource.contains("Open TAPCam"))
        #expect(!rootSource.contains(".disabled(!controller.lastCaptureSucceeded)"))
        #expect(rootSource.contains(".disabled(!controller.state.canCapture)"))
        #expect(rootSource.contains("TAPCamLockedCameraHandoff.regenerateLockedCameraContext"))
        #expect(controllerSource.contains("open_application_system_only_prepare"))
        #expect(controllerSource.contains("open_application_system_only_call"))
        #expect(controllerSource.contains("open_application_prepare"))
        #expect(controllerSource.contains("open_application_minimal_handoff"))
        #expect(controllerSource.contains("isMinimalRuntimeImportHandoff"))
        #expect(controllerSource.contains("openTAPMainAppOnly"))
        #expect(controllerSource.contains("prepareForHostApplicationHandoff"))
        #expect(controllerSource.contains("open_application_teardown_begin"))
        #expect(controllerSource.contains("open_application_teardown_end"))
        #expect(controllerSource.contains("videoOutput.setSampleBufferDelegate(nil, queue: nil)"))
        #expect(controllerSource.contains("captureSession.removeOutput(output)"))
        #expect(controllerSource.contains("captureSession.removeInput(input)"))
        #expect(rootSource.contains("controller.isPreviewHostVisible"))
        #expect(previewSource.contains("dismantleUIView"))
        #expect(previewSource.contains("previewLayer.session = nil"))
        #expect(previewSource.contains("removeInteraction(captureEventInteraction)"))
        #expect(controllerSource.contains("@Published private(set) var availableLenses"))
        #expect(controllerSource.contains("@Published private(set) var selectedLensID"))
        #expect(controllerSource.contains("availableLenses = context.lenses"))
        #expect(controllerSource.contains("func selectLens(_ lens: TAPCamLockedCameraLensRecord)"))
        #expect(controllerSource.contains("availableLenses.contains(where: { $0.id == lens.id })"))
        #expect(controllerSource.contains("reason: \"lens_selected\""))
        #expect(!controllerSource.contains("CameraCapabilityResolver.discover"))
        #expect(!rootSource.contains("CameraCapabilityResolver.discover"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func lockedExtensionLogsLaunchSceneRootAndPreviewLifecycle() throws {
        let extensionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/TAPCamLockedCameraCaptureExtension.swift"
        )
        let controlSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraControlExtension/TAPCamLockedCameraControlExtension.swift"
        )
        let intentSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraIntents/TAPCamLockedCameraIntent.swift"
        )
        let rootSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCaptureRootView.swift"
        )
        let previewSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCapturePreviewHost.swift"
        )
        let controllerSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/LockedCaptureCameraController.swift"
        )

        #expect(controlSource.contains("locked_camera_control_widget_init"))
        #expect(controlSource.contains("locked_camera_control_widget_button_label_init"))
        #expect(controlSource.contains("TAPCamLockedCameraControlBundle"))
        #expect(controlSource.contains("TAPCamOpenAppControlExtension"))
        #expect(controlSource.contains("TAP-NAP.TAPCamDemo.open-app"))
        #expect(controlSource.contains("TAPCamOpenAppFromLockScreenIntent"))
        #expect(controlSource.contains("locked_camera_open_app_control_widget_init"))
        #expect(intentSource.contains("struct TAPCamOpenAppFromLockScreenIntent: AppIntent"))
        #expect(intentSource.contains("static let openAppWhenRun = true"))
        #expect(intentSource.contains("static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }"))
        #expect(intentSource.contains("locked_camera_open_app_intent_perform"))
        #expect(extensionSource.contains("locked_camera_scene_content_invoked"))
        #expect(rootSource.contains("locked_camera_root_lifecycle event="))
        #expect(rootSource.contains("locked_camera_root_scene_phase_changed"))
        #expect(previewSource.contains("preview_host_make_ui_view"))
        #expect(previewSource.contains("preview_host_update_ui_view"))
        #expect(previewSource.contains("preview_view_layout width="))
        #expect(previewSource.contains("preview_capture_event phase="))
        #expect(controllerSource.contains("previewInWindow="))
        #expect(controllerSource.contains("lastFrameAge="))
        #expect(controllerSource.contains("first_frame_watchdog_waiting"))
        #expect(controllerSource.contains("frame_watchdog_recovery_attempt"))
        #expect(controllerSource.contains("maximumFrameRecoveryAttempts"))
        #expect(controllerSource.contains("Viewfinder did not deliver a frame."))
        #expect(controllerSource.contains("Unlock to continue."))
        #expect(controllerSource.contains("photo_capture_poc_defaults"))
        #expect(controllerSource.contains("livePhotoForcedOff=true"))
        #expect(controllerSource.contains("network=false"))
        #expect(controllerSource.contains("settings.flashMode = .off"))
    }

    @Test
    func lockedCameraViewStateKeepsRootVisibleUntilExplicitUnavailable() {
        let starting = TAPCamLockedCameraViewState.starting("Preparing viewfinder.")
        let live = TAPCamLockedCameraViewState.live("Viewfinder live.")
        let capturing = TAPCamLockedCameraViewState.capturing("Writing photo.")
        let recovering = TAPCamLockedCameraViewState.recovering("Restarting viewfinder.")
        let unavailable = TAPCamLockedCameraViewState.unavailable("Unlock to continue.")

        #expect(starting.showsPreview)
        #expect(starting.showsStatusOverlay)
        #expect(starting.isRecovering)
        #expect(!starting.canCapture)

        #expect(live.showsPreview)
        #expect(!live.showsStatusOverlay)
        #expect(!live.isRecovering)
        #expect(live.canCapture)

        #expect(capturing.showsPreview)
        #expect(capturing.showsStatusOverlay)
        #expect(capturing.isRecovering)
        #expect(!capturing.canCapture)

        #expect(recovering.showsPreview)
        #expect(recovering.showsStatusOverlay)
        #expect(recovering.isRecovering)
        #expect(!recovering.canCapture)

        #expect(!unavailable.showsPreview)
        #expect(unavailable.showsStatusOverlay)
        #expect(unavailable.isUnavailable)
        #expect(!unavailable.canCapture)
    }

    @Test
    func lockedRawCaptureMetadataPersistsLensPositionForImportPackaging() throws {
        let lens = makeLensRecord()
        let metadata = TAPCamLockedRawCaptureMetadata(
            captureID: "metadata-position",
            capturedAt: Date(timeIntervalSince1970: 100),
            artifactKind: TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind,
            lens: lens,
            photoFileName: TAPCamLockedSessionContentPathPolicy.unsignedHEICFileName,
            byteCount: 3,
            depthDataPresent: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TAPCamLockedRawCaptureMetadata.self, from: data)

        #expect(decoded.captureDevicePosition == "back")
        #expect(decoded.artifactKind == TAPCamLockedSessionContentPathPolicy.depthHEICStagingArtifactKind)
    }

    private func makeLensRecord(
        id: String = "com.example.lens.24mm",
        numericLabel: String = "1",
        zoomFactor: Double = 1
    ) -> TAPCamLockedCameraLensRecord {
        TAPCamLockedCameraLensRecord(
            id: id,
            displayName: "Main 24mm",
            numericLabel: numericLabel,
            unitLabel: "x",
            equivalentFocalLength35mmMillimeters: 24,
            captureDeviceUniqueID: "device-1",
            captureDeviceTypeRawValue: "AVCaptureDeviceTypeBuiltInDualWideCamera",
            captureDevicePosition: "back",
            zoomFactor: zoomFactor
        )
    }

    private func writeCapture(
        captureID: String,
        captureDirectory: URL,
        lens: TAPCamLockedCameraLensRecord,
        photoFileName: String,
        artifactKind: String?,
        depthDataPresent: Bool?
    ) throws {
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02, 0x03]).write(
            to: captureDirectory.appendingPathComponent(photoFileName),
            options: [.atomic]
        )

        let capturedAt = captureID == "direct-capture"
            ? Date(timeIntervalSince1970: 1)
            : Date(timeIntervalSince1970: 2)
        let metadata = TAPCamLockedRawCaptureMetadata(
            captureID: captureID,
            capturedAt: capturedAt,
            artifactKind: artifactKind,
            lens: lens,
            photoFileName: photoFileName,
            byteCount: 3,
            depthDataPresent: depthDataPresent,
            depthDataType: depthDataPresent == true ? 1751411059 : nil,
            isDepthDataFiltered: depthDataPresent,
            resolvedPhotoWidth: depthDataPresent == true ? 4032 : nil,
            resolvedPhotoHeight: depthDataPresent == true ? 3024 : nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(
            to: TAPCamLockedSessionContentPathPolicy.metadataURL(in: captureDirectory),
            options: [.atomic]
        )
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPLockedCameraSessionContentTests", isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        url = parentURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
