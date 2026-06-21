# Project Scorecard

This document is the human review entry for the current refactor state. It is
meant to help a reader with no prior project context decide where to start,
what is already implemented, and what should be treated as missing.

## Reading Entry

Final acceptance shortcut:

1. Read [Snapshot](#snapshot) for the current score and why it holds.
2. Read [Strict Gaps](#strict-gaps) for what is still not proven.
3. Read [Next Score Lift](#next-score-lift) for the next highest-value work.
4. Use the review paths below only when you need the exact code entry for a
   specific area.

Read in this order when auditing the project from scratch:

1. [../README.md](../README.md) for the product contract, module map, and
   validation commands.
2. [FutureCameraSpecs.md](FutureCameraSpecs.md) for the refactor boundary status
   and future camera feature boundaries.
3. [../TAPCamDemo/README.md](../TAPCamDemo/README.md) for source tree ownership.
4. [../TAPCamDemo/App/README.md](../TAPCamDemo/App/README.md) for startup and
   App Attest runtime wiring.
5. [../TAPCamDemo/CameraCapture/README.md](../TAPCamDemo/CameraCapture/README.md)
   for live capture, output profiles, runtime, and packaging.
6. [../TAPCamDemo/TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md) for
   pending capture signing, export, retry, and cleanup.
7. [../TAPCamDemo/DepthAnalysis/README.md](../TAPCamDemo/DepthAnalysis/README.md)
   for saved HEIC and depth inspection.
8. [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for test coverage
   and automation boundaries.

Startup gate and security preflight review path:

1. Start with this scorecard snapshot to confirm this is a first-launch policy
   readability refactor, not a change to camera startup or App Attest proofing.
2. Read [Startup/FirstLaunch.md](Startup/FirstLaunch.md) for the user-facing
   first-launch sequence and the intentional strict security preflight.
3. Read [../TAPCamDemo/App/README.md](../TAPCamDemo/App/README.md) for app
   module ownership and startup boundaries.
4. Read [../TAPCamDemo/App/StartupGatePolicy.swift](../TAPCamDemo/App/StartupGatePolicy.swift)
   before the coordinator; it is the pure policy entry for required and
   optional startup checks.
5. Read [../TAPCamDemo/App/StartupSecurityPreflightPolicy.swift](../TAPCamDemo/App/StartupSecurityPreflightPolicy.swift)
   for the pure backend security preflight retry, delay, deadline, and timeout
   policy.
6. Read [../TAPCamDemo/App/StartupBackendSecurityPreflight.swift](../TAPCamDemo/App/StartupBackendSecurityPreflight.swift)
   for the HTTPS `/healthz` execution, URL lookup, retry loop, timeout logging,
   and injected test seams.
7. Read [../TAPCamDemo/App/StartupGateCoordinator.swift](../TAPCamDemo/App/StartupGateCoordinator.swift)
   for OS permission reads, location delegate handling, and coordination of the
   backend preflight result.
8. Read [../TAPCamDemo/App/WelcomeStartupSetupView.swift](../TAPCamDemo/App/WelcomeStartupSetupView.swift)
   only after the policy and coordinator, because it is layout and user
   interaction plumbing.
9. Read [../TAPCamDemoTests/StartupGateCoordinatorTests.swift](../TAPCamDemoTests/StartupGateCoordinatorTests.swift)
   for the pure startup policy, preflight retry/timeout policy, and injected
   coordinator coverage.

App Attest UI presentation review path:

1. Start with this scorecard snapshot to confirm this is a user-visible
   presentation hardening pass, not real-device App Attest/backend acceptance.
2. Read [../TAPCamDemo/App/AppAttestRuntimeController.swift](../TAPCamDemo/App/AppAttestRuntimeController.swift)
   for credential lifecycle and the raw key id held for readiness checks.
3. Read [../TAPCamDemo/App/AppAttestCredentialPresentation.swift](../TAPCamDemo/App/AppAttestCredentialPresentation.swift)
   for generic failure status text and redacted key ID summaries.
4. Read [../TAPCamDemo/DepthAnalysis/DepthAnalyzerAppAttestSection.swift](../TAPCamDemo/DepthAnalysis/DepthAnalyzerAppAttestSection.swift)
   for the Settings App Attest section. It consumes explicit display fields and
   closures instead of the whole controller.
5. Read [../TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift)
   to confirm Settings passes presentation values, not raw key IDs or raw
   localized errors, into visible text and accessibility labels.
6. Read [../TAPCamDemoTests/AppAttestRuntimeTests.swift](../TAPCamDemoTests/AppAttestRuntimeTests.swift)
   for key ID redaction and generic failure-status tests.

CameraCapture UI readability review path:

1. Start with this scorecard snapshot to confirm this is a camera UI
   composition refactor, not a new EV/ISO/shutter/focus/video/format feature.
2. Read [../TAPCamDemo/CameraCapture/README.md](../TAPCamDemo/CameraCapture/README.md)
   for the UI -> Planning -> Runtime -> Output -> TAP Library layer flow.
3. Read [../TAPCamDemo/CameraCapture/UI/README.md](../TAPCamDemo/CameraCapture/UI/README.md)
   for the CameraCapture UI code map, reading order, and rules.
4. Read [../TAPCamDemo/CameraCapture/UI/CameraViewModel.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel.swift)
   before the SwiftUI files. It owns session, pending store, pending processor,
   capture pipeline, capability state, and status values.
5. Read [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift),
   [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift),
   and [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Debug.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Debug.swift)
   for FOV selection, shutter queueing, and Debug override behavior.
6. Read [../TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift](../TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift),
   [../TAPCamDemo/CameraCapture/UI/CameraRouteContextStore.swift](../TAPCamDemo/CameraCapture/UI/CameraRouteContextStore.swift),
   for route state and route-context persistence.
7. Read [../TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift](../TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift)
   for lifecycle policy, then
   [../TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift](../TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift)
   for SwiftUI lifecycle hook binding.
8. Read [../TAPCamDemo/CameraCapture/UI/CameraView.swift](../TAPCamDemo/CameraCapture/UI/CameraView.swift)
   as the screen shell. It should retain object lifetime, navigation, Settings
   sheet, and top-level capture/open/switch actions.
9. Read [../TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift](../TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift)
   for preview sizing, render-only session handoff, crop metadata callback,
   display-only FOV state, and Debug overlay hosting.
10. Read [../TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift](../TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift)
   for DEBUG-only status, depth source, zoom, and performance overlay layout
   from display-only rows.
11. Read [../TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift](../TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift)
   for the bottom camera chrome. It receives field-level presentation state and
   closures only; it should not receive the view model, route store, App Attest
   controller/client, pending store, capture pipeline, output profile, raw
   identifiers, HEIC bytes, manifests, proofs, or key IDs.
12. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   CameraCapture UI focused tests and their UI/real-device limits.

DepthAnalysis readability review path:

1. Start with this scorecard snapshot to confirm this is saved/pending HEIC
   analysis and saved-photo proof-verification presentation work, not a change
   to live capture, export, or App Attest proof creation.
2. Read [../TAPCamDemo/DepthAnalysis/README.md](../TAPCamDemo/DepthAnalysis/README.md)
   for the module code map, data flow, and manual acceptance path.
3. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisModels.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisModels.swift)
   for the analysis input, metric depth, region, and plane value types.
4. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisInputValidation.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInputValidation.swift)
   for the HEIC byte, primary-image dimension, depth pixel, sample-count, and
   usable-calibration contract.
5. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisReader.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisReader.swift)
   for the HEIC, auxiliary depth, manifest, and calibration decoding path.
6. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisInputLoader.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInputLoader.swift)
   for the source-to-HEIC boundary. It routes Photos and pending captures to
   bytes, then hands those bytes to the depth reader.
7. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift)
   for fixed public-safe album and analysis load-error copy.
8. Read [../TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift](../TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift)
   for TAP Library item loading, pending/exported/Photos merge rules, duplicate
   suppression, route anchors, and item-level cache keys.
9. Read [../TAPCamDemo/DepthAnalysis/DepthAlbumThumbnailPipeline.swift](../TAPCamDemo/DepthAnalysis/DepthAlbumThumbnailPipeline.swift)
   for Photos thumbnail requests, JPEG normalization, in-memory cache lookup,
   protected disk-cache writes, and hashed cache keys.
10. Read [../TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift](../TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift)
   for TAP Library grid UI, route restoration, item selection, and navigation
   into analysis.
11. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionSelectionState.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionSelectionState.swift)
   for rectangular region selection, clamping, stats, local heatmap, and local
   plane estimate state. This is separate from Planes seed growth.
12. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneSelectionState.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneSelectionState.swift)
   for Planes seed, strictness, loading, error, and selected-region state. This
   is separate from async task/request ownership.
13. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionDetector.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionDetector.swift)
   for the plane geometry building and seed-region calculation boundary.
14. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionRequestCoordinator.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionRequestCoordinator.swift)
   for async Planes request cancellation, debounce, request freshness,
   prewarm scheduling, and geometry-cache reuse.
15. Read [../TAPCamDemo/DepthAnalysis/AnalysisTools/README.md](../TAPCamDemo/DepthAnalysis/AnalysisTools/README.md)
   for the Planes algorithm path: projection, estimator facade, fitting,
   seed/BFS growth, and output-product files.
16. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisViewModel.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisViewModel.swift)
   for load coordination and selection-state bridging.
17. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift)
   for analysis mode labels, icons, explanations, and debug-only mode flags.
18. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift)
   after the view model; it is now the source entry and screen shell for
   loading/error state, view-model lifetime, mode-switch side effects, panel
   destination routing, and top-level callbacks.
19. Read [../TAPCamDemo/DepthAnalysis/AppAttestSignatureVerification.swift](../TAPCamDemo/DepthAnalysis/AppAttestSignatureVerification.swift)
   and [../TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift](../TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift)
   for the saved-photo App Attest verification route. The service owns Photos
   HEIC loading, local signed-export validation reuse, backend submission, and
   public-safe report text; the panel renders only fixed status steps.
20. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisStageView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisStageView.swift)
   for the central RGB, heatmap, mask, planes, and point-cloud stage. It
   receives display-ready local analysis values, not sources, manifests,
   proofs, identifiers, Photos handles, pending store handles, geometry caches,
   or export state.
21. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift)
   for bottom mode controls, inspector strip wiring, panel presentation,
   animation, and button-hint routing.
22. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift)
   for the field-level adapter that feeds concrete inspector bodies.
23. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift)
   for the capture metadata summary and DEBUG-only HUD. It summarizes optional
   manifest payload fields and replaces suspicious free-form display strings
   with fixed fallback labels instead of exposing proofs, App Attest key IDs,
   Photos IDs, pending IDs, paths, URLs, tokens, or export state.
24. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelSupport.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelSupport.swift),
   [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorStrip.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorStrip.swift),
   and [../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelLayer.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelLayer.swift)
   for shared panel support, bottom mode/inspector controls, and adaptive panel
   sizing. `AnalysisPanelLayoutMetrics` is the pure height policy; it does not
   replace rendered UI/layout evidence.
25. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift)
   for shared inspector primitives and `DepthRegionStatsPresentation`, the
   shared visible text boundary for rectangular Measurements and Region stats.
25. Read [../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift](../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift)
   for input validation, reader input rejection, Photos/pending source routing,
   pending unavailable mapping, load-error presentation bridging, and
   `DepthAnalysisViewModel.load(source:)` cleanup.
26. Read [../TAPCamDemoTests/TAPDepthAnalysisSelectionTests.swift](../TAPCamDemoTests/TAPDepthAnalysisSelectionTests.swift)
   for rectangular region selection, Planes seed-selection state, and
   `DepthAnalysisViewModel.finishSelection` / `clearSelection` bridging. This
   suite proves local state and bridge behavior only; it does not prove real
   gestures, rendered SwiftUI layout, Photos limited access, App Attest/backend
   acceptance, or real HEIC acceptance.
27. Read [../TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests.swift](../TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests.swift)
   for already-loaded `TAPMetricDepthMap` geometry, camera intrinsics
   guardrails, seed-plane growth, detector cache build/reuse, and async request
   cache/freshness behavior. This suite proves local model behavior only; it
   does not prove Photos or pending-source loading, App Attest proof creation,
   backend verification, final Photos export, real gestures, rendered SwiftUI
   layout, or positive real HEIC acceptance.
28. Read [../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift](../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift)
   for metadata HUD privacy, view-mode labels/routes, panel destinations,
   shared region-stats text, help defaults, interaction flags, and passive
   authorization status text.
29. Read [../TAPCamDemo/DepthAnalysis/Documentation/PlanesTechnicalDesign.md](../TAPCamDemo/DepthAnalysis/Documentation/PlanesTechnicalDesign.md)
   before judging Planes mode behavior. Planes uses seed taps, not rectangular
   region selection.
30. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   model-level DepthAnalysis tests and their real-device/UI limits.

Durable TAP Library route context review path:

1. Start with this scorecard snapshot to see that the change is a route-state
   continuity refactor, not an output-quality or App Attest change.
2. Read [../TAPCamDemo/CameraCapture/UI/README.md](../TAPCamDemo/CameraCapture/UI/README.md)
   for the live route owner and durable context boundary.
3. Read [../TAPCamDemo/TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md)
   for TAP Library item identity and pending-to-owned restore behavior.
4. Read [FutureCameraSpecs.md](FutureCameraSpecs.md) to confirm the route gap
   moved out of P0 future work.
5. Read [../TAPCamDemoTests/TAPLibraryRouteTests.swift](../TAPCamDemoTests/TAPLibraryRouteTests.swift)
   for the focused route-context, pending-to-owned anchor, item merge, and
   thumbnail cache-key privacy tests.
6. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   route test map and real Photos/UI automation limits.

TAP Library queue storage review path:

1. Start with this scorecard snapshot to confirm this is a queue readability
   and local-storage boundary refactor, not a new output format or Photos
   export feature.
2. Read [../TAPCamDemo/TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md)
   for the queue flow, state machine, storage rules, and test index.
3. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecord.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecord.swift)
   for the durable record fields and visible-pending identity.
4. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundlePathPolicy.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundlePathPolicy.swift)
   for capture ID, bundle directory, fixed filename, and record identity
   validation.
5. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift)
   for root directory creation, temporary bundle commits, `bundle.json` IO,
   HEIC/thumbnail reads and writes, and cleanup.
6. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift)
   for queue API semantics, actor serialization, state transitions, failure
   reason normalization, notifications, and diagnostics.
7. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift)
   for protected-data readiness, signing/export routing, retry classification,
   and migration call sites.
8. Read [../TAPCamDemoTests/TAPLibraryStorageTests.swift](../TAPCamDemoTests/TAPLibraryStorageTests.swift)
   for the focused record, path-policy, bundle-storage, migration,
   failure-reason, and candidate-selection tests.
9. Read [../TAPCamDemoTests/TAPCamDemoTestFixtures.swift](../TAPCamDemoTests/TAPCamDemoTestFixtures.swift)
   for the shared deterministic queue fixtures used by storage and processor
   tests.
10. Read [../TAPCamDemoTests/TAPLibraryProcessingTests.swift](../TAPCamDemoTests/TAPLibraryProcessingTests.swift)
   for worker readiness, processing order, retry classification, and
   public-safe processor failure-reason persistence tests.
11. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   test map and boundaries between storage, processing, shared fixtures, and
   the main suite.

Capture output profile and quality review path:

1. Start with this scorecard snapshot to confirm this is a format/quality
   contract readability refactor, not a new JPEG/RAW/quality UI feature.
2. Read [../TAPCamDemo/CameraCapture/Output/README.md](../TAPCamDemo/CameraCapture/Output/README.md)
   for the Output Profile Contract reading order.
3. Read [../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift](../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift)
   for app-level quality naming before AVFoundation settings.
4. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift)
   for the current Release HEIC-depth profile contract and contract-violation
   checks.
5. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift)
   and [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift)
   for the executable catalog, fail-closed future UI request boundary, and
   public-safe future UI status presentation.
6. Read [../TAPCamDemoTests/TAPCaptureOutputProfileTests.swift](../TAPCamDemoTests/TAPCaptureOutputProfileTests.swift)
   for focused format, quality, profile selection, and Runtime request tests.
7. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   Simulator versus real-device codec, quality, file-size, and Photos evidence
   limits.

Capture provenance and final export review path:

1. Start with this scorecard snapshot to confirm this is a proof/export
   readability refactor, not real-device App Attest or Photos acceptance.
2. Read [../TAPCamDemo/CameraCapture/Output/README.md](../TAPCamDemo/CameraCapture/Output/README.md)
   for the output profile, TAP XMP, App Attest proof, and export-validation
   boundary.
3. Read [../TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift](../TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift)
   for the canonical digest model that binds RGB, depth, and metadata.
4. Read [../TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift](../TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift)
   for App Attest assertion creation.
5. Read [../TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift](../TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift)
   for proof injection, pending signing, final signed-export validation, and
   `ValidatedTAPDepthHEIC` construction.
6. Read [../TAPCamDemoTests/TAPCaptureManifestEncodingTests.swift](../TAPCamDemoTests/TAPCaptureManifestEncodingTests.swift)
   and [../TAPCamDemoTests/TAPCaptureContentDigestTests.swift](../TAPCamDemoTests/TAPCaptureContentDigestTests.swift)
   for payload/proof separation and canonical digest stability.
7. Read [../TAPCamDemoTests/TAPCaptureAssertionSignerTests.swift](../TAPCamDemoTests/TAPCaptureAssertionSignerTests.swift)
   and [../TAPCamDemoTests/TAPCaptureProvenanceWriterSigningTests.swift](../TAPCamDemoTests/TAPCaptureProvenanceWriterSigningTests.swift)
   for App Attest assertion shape, public-safe unsigned fallback, and
   pending-signing identity before signer calls.
8. Read [../TAPCamDemoTests/TAPSignedExportValidatorTests.swift](../TAPCamDemoTests/TAPSignedExportValidatorTests.swift)
   for the final export-gate rejection paths before Photos save.
9. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   Simulator versus real-device/App Attest/Photos evidence limits.

Pending worker readiness review path:

1. Start with this scorecard snapshot to confirm this is a TAP Library worker
   preflight, not a UI or lock-screen feature.
2. Read [FutureCameraSpecs.md](FutureCameraSpecs.md) for the P0 protected-data
   readiness boundary.
3. Read [../TAPCamDemo/TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md)
   for the queue flow and worker-readiness explanation.
4. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureWorkerReadiness.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureWorkerReadiness.swift)
   for the pure readiness model.
5. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift)
   for where the worker returns before private artifact reads.
6. Read [../TAPCamDemoTests/TAPLibraryProcessingTests.swift](../TAPCamDemoTests/TAPLibraryProcessingTests.swift)
   for the injected-readiness coverage, processing fakes, retry classification,
   and their real-device/App Attest/Photos limits.

Diagnostic and UI presentation privacy review path:

1. Start with this scorecard snapshot to confirm this is diagnostics and
   user-visible presentation hardening, not a capture or export behavior
   change.
2. Read [../TAPCamDemo/App/AppAttestRuntime.swift](../TAPCamDemo/App/AppAttestRuntime.swift)
   for `TAPDiagnostics.describe` and shared App Attest logging.
3. Read [../TAPCamDemo/App/AppAttestCredentialPresentation.swift](../TAPCamDemo/App/AppAttestCredentialPresentation.swift)
   for generic App Attest Settings failure text and redacted key ID summaries.
4. Read [../TAPCamDemo/CameraCapture/Support/CameraCaptureStatusPresentation.swift](../TAPCamDemo/CameraCapture/Support/CameraCaptureStatusPresentation.swift)
   for public-safe camera status text and Debug metrics failure reasons.
5. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift)
   for public-safe DepthAnalysis, TAP Library album, Planes selection, and
   inspector-visible error text. `DepthAnalysisInspectorErrorMessage` is the
   typed boundary that Region and Plane Filter inspectors accept instead of raw
   `String?` error sinks.
6. Read [../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift)
   for the Debug metadata HUD summary. It only displays public lens/source/zoom
   labels and replaces suspicious manifest display strings with fixed fallback
   labels.
7. Read [../TAPCamDemo/CameraCapture/Support/TAPDepthCaptureError.swift](../TAPCamDemo/CameraCapture/Support/TAPDepthCaptureError.swift)
   for the raw capture error cases whose associated values must not be treated
   as visible copy.
8. Read [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift),
   [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift),
   and [../TAPCamDemo/CameraCapture/UI/CameraViewModel+Debug.swift](../TAPCamDemo/CameraCapture/UI/CameraViewModel+Debug.swift)
   for the status-message call sites.
9. Read [../TAPCamDemo/CameraCapture/Runtime/CapturePipeline.swift](../TAPCamDemo/CameraCapture/Runtime/CapturePipeline.swift)
   for the `CaptureJobMetrics.failureReason` call site consumed by Debug UI.
10. Read [../TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift](../TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift)
   for capture-signing key-id and capture-id log privacy.
11. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureFailureReasonPresentation.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureFailureReasonPresentation.swift)
   for the typed pending failure reasons, fixed public-safe text, and legacy
   normalization rules.
12. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift)
   for the durable `bundle.json` IO and local artifact storage-policy boundary.
13. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift)
   for typed failure-reason normalization and explicit legacy migration.
14. Read [../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift)
   for raw error classification, pending signing/export logs, and the reconcile
   call that triggers legacy failure-reason migration.
15. Read [../TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift](../TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift)
   for Photos asset lookup logs.
16. Read [../TAPCamDemoTests/TAPCameraStatusPresentationTests.swift](../TAPCamDemoTests/TAPCameraStatusPresentationTests.swift)
   for camera status text and Debug metrics failure-reason redaction tests.
17. Read [../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift](../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift)
   for DepthAnalysis reader input rejection, Photos/pending loading, pending
   unavailable mapping, and fixed reader/Photos loader visible error text.
18. Read [../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift](../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift)
   for DepthAnalysis metadata HUD, view-mode, panel route, region-stats,
   help, interaction, and authorization presentation/privacy tests.
19. Read [../TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests.swift](../TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests.swift)
   for the source-level harness that enforces private OSLog interpolation for
   capture ids, asset ids, manifest ids, credential names, key ids, and invalid
   bundle names, plus explicit privacy and reviewed-public-label checks.
20. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   public error-summary, Settings presentation, camera status presentation,
   DepthAnalysis error presentation, inspector visible-error presentation,
   pending queue failure-reason presentation, and remaining OSLog
   runtime-capture evidence gaps.

Output format and quality review path:

1. Start with this scorecard snapshot to confirm this is an output-contract
   refactor, not a JPEG/RAW/quality-slider feature.
2. Read [FutureCameraSpecs.md](FutureCameraSpecs.md) for the rule that future
   format and quality work must start with a profile, validator, manifest, and
   packaging story before UI.
3. Read [../TAPCamDemo/CameraCapture/README.md](../TAPCamDemo/CameraCapture/README.md)
   for the handoff from Planning to Runtime to Output.
4. Read [../TAPCamDemo/CameraCapture/Output/README.md](../TAPCamDemo/CameraCapture/Output/README.md)
   for the executable Release HEIC-depth contract.
5. Read [../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift](../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift)
   for the app-level quality policy before it resolves to AVFoundation values.
6. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift)
   for the current Release catalog.
7. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift)
   for the pure future request boundary that selects a catalog profile without
   creating one.
8. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift)
   for the current HEVC-depth profile and contract rules.
9. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift)
   for the resolved Runtime output token and photo-output capability snapshot.
10. Read [../TAPCamDemo/CameraCapture/Output/CaptureOutputManifestPolicy.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputManifestPolicy.swift)
   for the Release manifest facts the final export gate must revalidate.
11. Read [../TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift](../TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift)
   for the final signed-export gate that applies that policy to the signed
   bytes before Photos save.
12. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   tests that prove the Simulator-level contract has not drifted.

Manual camera control model and test review path:

1. Start with this scorecard snapshot to confirm this is a pure Planning model,
   not a finished manual camera UI.
2. Read [FutureCameraSpecs.md](FutureCameraSpecs.md) for the capability ->
   intent -> Runtime service boundary.
3. Read [../TAPCamDemo/CameraCapture/Planning/README.md](../TAPCamDemo/CameraCapture/Planning/README.md)
   before opening the Swift files.
4. Read [../TAPCamDemo/CameraCapture/Planning/CameraControlCapabilitySnapshot.swift](../TAPCamDemo/CameraCapture/Planning/CameraControlCapabilitySnapshot.swift)
   to see what the active device says it can support.
5. Read [../TAPCamDemo/CameraCapture/Planning/CameraManualControlIntent.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlIntent.swift)
   to see how future UI requests are represented, rejected, and summarized
   through `CameraManualControlResolutionPresentation`.
6. Read [../TAPCamDemo/CameraCapture/Planning/CameraManualControlSummary.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlSummary.swift)
   for the field-row model future SwiftUI controls should consume.
7. Read [../TAPCamDemo/CameraCapture/Planning/CameraManualControlCommandPlan.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlCommandPlan.swift)
   for the internal Runtime command bridge; it is not public UI text or
   persistence state.
8. Read [../TAPCamDemo/CameraCapture/Runtime/README.md](../TAPCamDemo/CameraCapture/Runtime/README.md)
   to verify that Runtime remains the session-queue write boundary.
9. Read [../TAPCamDemoTests/TAPCameraManualControlIntentTests.swift](../TAPCamDemoTests/TAPCameraManualControlIntentTests.swift),
   [../TAPCamDemoTests/TAPCameraManualControlPresentationTests.swift](../TAPCamDemoTests/TAPCameraManualControlPresentationTests.swift),
   [../TAPCamDemoTests/TAPCameraManualControlSummaryTests.swift](../TAPCamDemoTests/TAPCameraManualControlSummaryTests.swift),
   [../TAPCamDemoTests/TAPCameraManualControlCommandPlanTests.swift](../TAPCamDemoTests/TAPCameraManualControlCommandPlanTests.swift),
   [../TAPCamDemoTests/TAPCameraManualControlBoundaryGuardTests.swift](../TAPCamDemoTests/TAPCameraManualControlBoundaryGuardTests.swift),
   and [../TAPCamDemoTests/TAPCameraControlServiceTests.swift](../TAPCamDemoTests/TAPCameraControlServiceTests.swift)
   for the focused capability, intent, presentation, summary, command-plan,
   source-boundary, status-copy, and Runtime validation tests.
10. Read [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) for the
   pure model tests and their limits.

## Snapshot

Date: 2026-06-21

Score formula for this goal: Professional camera capabilities 10%, core depth
plus App Attest 20%, extensibility 20%, security 25%, readability 15%, docs
clarity 10%. Overall is a weighted refactor-readiness score, not a simple
average.

| Area | Score | Strict read |
| --- | ---: | --- |
| Professional camera capabilities | 3.6 / 10 | FOV chips, front/back switch, touch-down shutter, debug zoom/depth, default foreground return to camera, best-effort durable TAP Library scroll/return context, a read-only manual-control capability snapshot, a pure manual-control intent model, and an internal queue-guarded manual-control application boundary exist. User-facing EV, ISO, shutter, focus, white-balance, aperture controls, guides, video, Live Photo, RAW/ProRAW, lock-screen launch, durable album filters, and UI regression coverage are still missing. |
| Core depth plus App Attest capture | 7.5 / 10 | Capture requires depth data, keeps Apple HEIC depth embedding, rejects JPEG fallback for the Release HEIC profile, stages unsigned private artifacts, signs queued output with App Attest before Photos export, revalidates the signed HEIC before Photos, and exposes App Attest entitlements in the checkout. Real-device/backend acceptance still needs stronger evidence. |
| Extensibility | 10.0 / 10 | `CapturePhotoQualityPolicy`, `CaptureOutputProfileCatalog`, `CaptureOutputProfileSelectionIntent`, `CaptureOutputProfileSelectionPresentation`, `CaptureOutputProfile`, `ResolvedCaptureOutputProfile`, `CapturePhotoOutputCapabilitySnapshot`, `CaptureOutputResourcePlan`, capture planning, `PreCaptureConfigurationBuilder`, `CameraControlCapabilitySnapshot`, `CameraManualControlIntent`, `CameraManualControlResolutionPresentation`, `CameraManualControlSummary`, `CameraManualControlCommandPlan`, `CameraControlService`, provenance writer, pending record model, pending bundle path policy, pending bundle storage, pending store, pending artifact writer, pending processing policy, worker readiness, retry classifier, pending failure-reason presentation, startup gate policy, startup security preflight retry policy, backend preflight execution boundary, diagnostic/UI presentation privacy, App Attest credential presentation, CameraCapture status presentation, CameraCapture screen shell, CameraCapture preview stage, CameraCapture Debug overlay, CameraCapture controls view, DepthAnalysis input loader, DepthAnalysis input validation, DepthAnalysis error presentation, DepthAnalysis rectangular region-selection state, DepthAnalysis plane-selection state, DepthAnalysis plane-region detector, DepthAnalysis plane-region request coordinator, Planes estimator facade, plane fitting helpers, seed/BFS growth helpers, region output-product helpers, DepthAnalysis item provider, DepthAnalysis thumbnail pipeline, DepthAnalysis view-mode model, stage view, controls view, panel content adapter, debug metadata HUD, panel support, inspector strip, adaptive panel layer, pure panel height metrics, shared region-stats presentation, inspector content files, `CameraRouteStore`, `CameraRouteContextStore`, `CaptureLifecycleCoordinator`, and module READMEs give future work clear seams. Output quality policy/profile catalog/selection/presentation/resolved execution token/photo-output capability snapshot/contract violations, resource-plan validation through the resolved embedded HEIC-depth packaging gate, final export validation, tokenized route context, worker readiness, startup preflight policy, App Attest UI presentation, CameraCapture public-safe status presentation, TAP Library queue record/path-policy/bundle-storage/store/adapter/helper boundaries, public-safe persisted failure reasons, CameraCapture field-level controls state, pre-capture crop snapshot, CameraCapture preview-stage state, display-only FOV chips, display-only Debug depth/zoom rows, DepthAnalysis source routing, input byte/pixel/sample/calibration contracts, fixed album/analyzer/Planes error presentation, rectangular selection products, Planes seed/strictness presentation state, async plane request freshness/cache reuse, plane geometry building/seed-region calculation, view-mode labels/debug flags, per-mode inspector route lists, panel support, pure adaptive panel metrics, shared region-stats presentation, inspector field-level inputs, merge/dedupe/partial-failure rules, cache-key privacy, thumbnail protection, manual-control intent resolution, public-safe presentation, field-row summary, Runtime command plan, and queue-guarded Runtime command application now make future JPEG/RAW/quality, route-state, protected-data, diagnostics, startup security, App Attest status UI, camera status UI, pending queue UI, analysis-reader, region-analysis, plane-analysis, camera chrome, preview overlays, stage/control/panel UI, and manual-control work explicit. Manual-control SwiftUI controls, persistence, durable album filters, protected-data UI policy, and rendered UI/layout regression evidence are still not extracted. Multi-resource output modeling now has a pure resource-plan boundary, but real RAW/Live Photo/video/C2PA packagers, validators, and readers are still absent. |
| Security | 9.2 / 10 | Startup security preflight remains strict, signed export does not silently fall back to unsigned, digests cover RGB/depth/metadata, local artifacts have a shared protection policy, AppAttestKit is pinned to a reviewed revision, App Attest entitlements are visible, the Release output profile rejects non-HEVC HEIC drift, output profile selection presentation redacts raw catalog/profile ids before future UI text, provider/package/manifest paths consume one resolved output execution token, the final Photos gate re-reads signed bytes, revalidates Release output facts, and is source-guarded against the current required resource plan before Photos save, `ValidatedTAPDepthHEIC` is minted only by the provenance writer, and focused provenance tests now cover digest stability, App Attest assertion shape, pending-signing identity, single-proof enforcement, and export-gate rejection paths. Durable route context stores fixed-length HMAC tokens instead of raw Photos or capture identifiers, the pending worker has an explicit protected-data readiness gate before private artifact reads and legacy failure-reason reconciliation, pending bundle paths validate ASCII capture IDs, reject hidden bundle names, keep the current artifact filename allow-list exact, and reject `bundle.json` records whose capture ID does not match the bundle directory, pending bundle storage routes record/artifact IO through the path and local-storage policies, exported queue records clear precise location after Photos export, pending retry classification now uses a named typed-error classifier instead of localized-description matching and has tests for single plus multiple typed underlying errors, DepthAnalysis bounds HEIC byte count, primary-image dimensions, depth-map pixel count, sample count, row stride, and projection calibration before local analysis tools allocate per-pixel products, DepthAnalysis thumbnail cache keys for Photos, owned exports, and pending records are hashed while disk writes stay protected, DepthAnalysis, TAP Library album, and Planes selection error copy now uses fixed public-safe text instead of raw Photos, reader, local analysis, URL, path, asset, or capture identifiers, concrete Region and Plane Filter inspectors accept typed `DepthAnalysisInspectorErrorMessage` values instead of raw `String?` error sinks, shared region-stats presentation is source-guarded to accept numeric `TAPDepthRegionStats` instead of source/error/manifest/identifier/proof inputs, manual-control resolution presentation redacts stale device ids and requested raw values into fixed control groups, manual-control command plans build no commands for blocked resolutions, keep target device ids and control-surface signatures only for Runtime stale guards, redact string/debug output, and store no session/writer handles, Runtime manual-control application rejects blocked plans, stale camera ids, stale control surfaces, and unsupported commands before locking the device, and the Debug metadata HUD summary falls back to fixed labels when optional manifest display fields look like paths, URLs, proofs, App Attest key IDs, capture IDs, asset IDs, manifest IDs, or token values. Public diagnostics omit raw localized errors, failing URLs, network paths, and capture/proof identifiers, Settings App Attest status uses generic failure text plus redacted key ID summaries and backend public summaries instead of full key IDs, raw backend URLs, or raw localized errors, camera status plus Debug metrics failure text use public-safe presentation instead of raw localized errors or associated capture/manifest/path/URL/key/proof reasons, the OSLog source privacy harness enforces private interpolation for capture ids, Photos asset ids, manifest ids, credential names, key ids, and invalid bundle names in critical log call sites, inspector source checks prevent raw Region/Plane error-string sinks from returning, shutter-time unsigned signature status uses fixed public fallback text, and TAP Library persisted failure reasons now use typed fixed retry text, store-level write normalization, read-side legacy normalization, and explicit legacy bundle migration that skips invalid bundles while continuing valid migrations. C2PA, positive real-depth fixtures, Photos acceptance evidence, unified-log runtime capture evidence, unopened legacy bundle cleanup evidence, legacy exported-location cleanup evidence, thumbnail retention policy, and real-device signing/protected-data/backend evidence still need stronger proof. |
| Readability | 9.9 / 10 | Large view work has been split, startup naming now says gate/preflight instead of generic network permission, `StartupGatePolicy` names required versus optional first-launch checks, `StartupSecurityPreflightPolicy` names retry/deadline decisions, `StartupBackendSecurityPreflight` names network execution before the `NSObject` coordinator, CameraCapture screen shell, lifecycle hook modifier, preview stage, Debug overlay, display-only FOV state, display-only Debug depth/zoom state, field-level bottom controls view, route/lifecycle stores, DepthAnalysis input loading, input validation, error presentation, inspector visible-error message boundary, rectangular region selection, Planes seed-selection state, async plane request coordination, plane-region detection, Planes estimator facade/fitting/growth/output files, item loading, thumbnails, view-mode metadata, stage view, controls view, panel content adapter, public-safe debug HUD summary, panel support, inspector strip, adaptive panel layer, pure adaptive panel metrics, shared region-stats presentation, and inspector bodies now have named loader/validation/presentation/state/coordinator/detector/provider/pipeline/stage/control/content files outside the analysis and album picker UI. `CameraView.body` now reads as navigation, Settings sheet, screen surface, and one named lifecycle hook adapter while lifecycle policy remains in `CaptureLifecycleCoordinator`. Output policy now reads as quality policy -> catalog -> selection intent -> profile contract -> resolved Runtime execution token -> pre-capture crop snapshot -> provider/package/manifest -> provenance writer, manual-control support reads as capability snapshot -> user intent -> resolution -> public-safe summary -> field-row summary -> Runtime-executable pure command plan -> source-boundary guards -> queue-guarded Runtime write boundary, and TAP Library now reads as route context -> item merge -> record model -> path policy -> bundle storage -> actor store -> artifact writer -> thumbnail renderer -> protected-data readiness -> retry classification -> failure-reason presentation. `TAPPendingCaptureBundleStorage` owns directory enumeration, record JSON IO, HEIC/thumbnail IO, and cleanup, while `TAPPendingCaptureStore` owns queue semantics, state transitions, actor serialization, notifications, and diagnostics. DepthAnalysis input/source/load, DepthAnalysis selection state and ViewModel selection bridge, DepthAnalysis plane geometry/detector/request coordination, DepthAnalysis error presentation, DepthAnalysis presentation/privacy, inspector visible-error presentation, adaptive panel metrics, shared region-stats presentation, capture metadata summary presentation, capture output profile, capture provenance, CameraCapture presentation, camera status presentation, manual-control intent, manual-control presentation, manual-control summary, manual-control command-plan, manual-control boundary, manual-control Runtime service, TAP Library route, storage, and processing tests now have separate suites plus shared deterministic fixtures instead of living inside the broad mixed test file. Remaining readability gaps include rendered UI/layout evidence gaps and some scorecard sections that require long strict-read rows. This score is only about source readability and entry points; it is not a claim that product behavior, UI automation, or real-device evidence is complete. |
| Docs clarity | 9.9 / 10 | The root README, module READMEs, FutureCameraSpecs, startup docs, App Attest docs, CameraCapture UI and DepthAnalysis read-only versus attended acceptance paths, CameraCapture view-model/route/lifecycle-policy/lifecycle-hook/view/preview-stage/debug-overlay/controls/status-presentation paths, TAP Library route-context/item/storage/writer/thumbnail/worker/retry-classifier/failure-reason paths, DepthAnalysis input-validation/input-loader/error-presentation/inspector-error-boundary/metadata-HUD/adaptive-panel-metrics/region-stats-presentation/region-state/plane-selection/request-coordinator/detector/provider/picker/view/stage/controls/panel/inspector paths, output quality policy/catalog/selection/resolved-token/contract docs, startup-policy, startup-preflight retry, route-context, manual-control summary/command-plan/focused-test path, worker-readiness, queue-storage, output-profile/quality, provenance/export-gate, logging/status/retry/failure-reason privacy review paths, score formula, and test README explain what exists versus what is deferred. The DepthAnalysis README now points input/source/load-state review to `TAPDepthAnalysisInputTests`, selection-state review to `TAPDepthAnalysisSelectionTests`, plane geometry/request review to `TAPDepthAnalysisPlaneRegionTests`, includes an Inspector/HUD Presentation Map with adaptive panel metrics and shared region-stats presentation, and the test README separates DepthAnalysis input/source/load, DepthAnalysis selection state and ViewModel bridge, DepthAnalysis plane geometry/detector/request coordination, DepthAnalysis error presentation, DepthAnalysis presentation/privacy, inspector visible-error presentation, adaptive panel metrics, region-stats presentation, metadata HUD presentation, capture output profile, capture provenance, CameraCapture presentation, camera status presentation, manual-control, TAP Library route, storage, processing, and shared fixture coverage for manual reading. Remaining docs gaps include dense scorecard rows, limited visual reading aids for large flows, and evidence gaps that are documented but not yet backed by real-device or rendered UI automation artifacts. |

Overall score: **8.7 / 10**.

This score is intentionally strict and uses the weighting model above.
The app has a credible depth plus App Attest capture core, but it is not yet
close to a professional camera feature set.
The latest score holds steady after selectively syncing the `assert` branch's
verification-panel work into the current DepthAnalysis architecture. The new
saved-photo verification route is split into a service/report model and a
SwiftUI panel: the service reuses the final signed-export validator before
submitting the stored App Attest signing material to the configured backend, and
the panel renders fixed public-safe status steps instead of raw backend URLs,
request/response JSON, key IDs, assertion objects, capture IDs, digest values,
Photos asset IDs, or pending capture IDs. Focused privacy tests, OSLog privacy
tests, and the full Simulator test suite passed. The score does not rise because
the new evidence is still local/unit/Simulator evidence; real Photos asset
verification, real backend acceptance, rendered panel layout, and real-device
App Attest evidence remain missing.

## Current Strengths

- Depth capture is treated as required data, not as a best-effort side effect.
- App Attest proofing is on the pending export path and failures stay queued.
- Saved Photos analysis now has an App Attest capture-signature verification
  route that reuses local signed-export validation before backend verification
  and keeps visible verification text public-safe.
- `TAPPendingCaptureWorkerReadiness` makes protected-data readiness explicit
  before the pending worker reads private HEIC bundles, manifests, proofs,
  Photos export identifiers, or queue records.
- `TAPDiagnostics.describe` is now a public-safe error summary boundary.
  `TAPDiagnosticsOSLogPrivacyTests` source-scans critical logging files so
  capture ids, manifest ids, credential names, App Attest key ids, Photos asset
  ids, and invalid bundle names stay private in the capture/proof/export path.
- `AppAttestCredentialPresentation` and `AppAttestBackendPresentation` are now
  the public-safe Settings presentation boundaries for App Attest credential
  status, key IDs, and backend status. User-visible failure text is generic,
  Settings displays only redacted key ID summaries and backend public summaries,
  and the runtime retains the full key ID plus backend URL for readiness checks,
  requests, and credential health tokens.
- `CameraCaptureStatusPresentation` is now the public-safe camera status
  boundary for `CameraViewModel.statusMessage` and
  `CaptureJobMetrics.failureReason`. Camera status and Debug metrics failure
  text no longer display raw `localizedDescription`, capture IDs, manifest IDs,
  URLs, paths, App Attest key IDs, proofs, or associated error reasons.
- `TAPPendingCaptureRetryClassifier` is now the pending queue retry-status
  boundary. It classifies network retry from typed Foundation error domains and
  codes, including underlying errors, rather than raw localized strings.
- `TAPPendingCaptureFailureReasonPresentation` is now the public-safe persisted
  failure-reason boundary for new pending queue records. The worker still uses
  raw errors for retry classification and `TAPDiagnostics.describe`, but
  `bundle.json` failure text stores fixed network/retry messages instead of raw
  URLs, paths, IDs, key IDs, proofs, or associated error reasons.
- TAP Library pending storage now has separate path, filesystem, and actor
  entries. `TAPPendingCaptureBundlePathPolicy` rejects hidden and non-ASCII
  capture IDs, fixed artifact filenames stay policy-owned, and
  `TAPPendingCaptureBundleStorage` owns bundle directories, record JSON IO,
  artifact IO, and cleanup without inheriting `MainActor` isolation.
- TAP Library exported records now minimize precise location data. The queue
  keeps location until Photos export can use it, then `markExported` clears the
  persisted queue copy while retaining the Photos asset id and thumbnail index.
- DepthAnalysis TAP Library item loading is isolated in
  `DepthAlbumItemProvider`. Pending, exported-owned, and Photos-only items now
  have a readable merge/dedupe/sort boundary with model tests for partial Photos
  failure and route anchors.
- DepthAnalysis visible error copy is isolated in
  `DepthAnalysisErrorPresentation`. Album load failures, Photos-only album
  failures, pending unavailable analysis loads, reader failures, Photos data
  loader failures, and Planes selection failures now map to fixed public-safe
  text before reaching SwiftUI.
- DepthAnalysis HEIC input loading is isolated in `DepthAnalysisInputLoader`.
  Photos and pending sources now have a readable source-to-bytes-to-reader
  boundary with model tests for source routing, pending temporary-unavailable
  mapping, generic reader failures, and view-model presentation.
- DepthAnalysis input hardening is isolated in
  `TAPDepthAnalysisInputValidation`. The loader and reader reject oversized
  local HEIC inputs, invalid depth-map dimensions, sample-count mismatches,
  missing finite positive samples, unsafe row stride, and unusable camera
  calibration before heatmap, mask, geometry cache, or Plane-growth paths can
  allocate per-pixel products. Missing calibration still permits RGB, Heatmap,
  and Valid Mask analysis while Point Cloud and Planes fail closed.
- DepthAnalysis plane-region calculation is isolated in
  `DepthAnalysisPlaneRegionDetector`. Plane geometry building and seed-region
  growth are local analysis work with model tests for cache building and
  matching-cache reuse.
- DepthAnalysis plane estimation is split into a small `TAPPlaneEstimator`
  facade plus fitting, seed/BFS growth, and region-output helper files. The
  public entry points and thresholds stay stable, while readers can now inspect
  least-squares/RANSAC math, seed growth, and final runs/contours/grid metrics
  independently.
- DepthAnalysis async Planes request lifecycle is isolated in
  `DepthAnalysisPlaneRegionRequestCoordinator`. Request cancellation,
  freshness, strictness debounce, prewarm task scheduling, and image-local
  geometry-cache reuse are now outside the ViewModel with focused async tests.
  The coordinator does not hold sources, manifests, HEIC bytes, proofs, App
  Attest key ids, Photos handles, pending store handles, or export state.
- DepthAnalysis Planes seed-selection state is isolated in
  `DepthAnalysisPlaneSelectionState`. Strictness clamping, seed clamping,
  loading, selected-region, failure, fixed public-safe error presentation, and
  clear transitions are local UI state with focused tests. The state model does
  not hold geometry caches, async tasks, asset identifiers, capture identifiers,
  decoded proofs, App Attest key ids, Photos handles, pending store handles, or
  export state.
- DepthAnalysis rectangular region selection is isolated in
  `DepthAnalysisRegionSelectionState`. Selection clamping, region stats, local
  heatmap generation, and local rectangular plane estimates are now pure local
  state with focused tests. The state model does not hold asset identifiers,
  capture identifiers, decoded proofs, App Attest key ids, Photos handles,
  pending store handles, or export state.
- DepthAnalysis screen composition is now split into a source-entry shell,
  central stage, bottom controls, and field-level panel content adapter.
  `DepthAnalysisView` owns loading/error state, view-model lifetime, top-level
  callbacks, and panel route state; `DepthAnalysisStageView` owns visual modes
  and gestures; `DepthAnalysisControlsView` owns inspector-strip and panel
  presentation; `AnalysisInspectorPanelContent` is the only bridge from
  screen-owned field values to concrete inspector bodies.
- DepthAnalysis inspector UI is split into shared support, measurements,
  legend, region, plane filter, overlay, and point-cloud info content files.
  The stage, controls, panel adapter, and concrete inspector bodies receive
  field-level image, depth, stats, selection, mode, binding, and summary values
  instead of full sources, manifests, proofs, Photos identifiers, pending
  capture identifiers, App Attest key ids, geometry caches, or export state.
- DepthAnalysis view-mode metadata, debug metadata HUD, panel support, bottom
  inspector strip, and adaptive panel shell are split out of the main analysis
  view. The visible HUD is compiled only in DEBUG and receives only a capture
  metadata summary built from optional manifest payload fields, while the strip
  and panel shell receive route/model values, bindings, and content closures.
- DepthAnalysis thumbnail cache work is isolated in
  `DepthAlbumThumbnailPipeline`. Photos, owned-export, and pending thumbnail
  cache keys are hashed, disk writes reuse the shared private photo-artifact
  storage policy, and the album grid no longer mixes thumbnail loader/cache
  internals with route and navigation UI.
- Output format and quality have a code-level contract in
  `CapturePhotoQualityPolicy`, `CaptureOutputProfileCatalog`,
  `CaptureOutputProfileSelectionIntent`,
  `CaptureOutputProfileSelectionPresentation`, and `CaptureOutputProfile`,
  including explicit invalid combinations for duplicate profile ids, a missing
  default profile, empty or missing profile selection, JPEG fallback, missing
  required depth, and requested quality above configured max. The selection
  presentation gives future UI fixed public-safe text instead of raw catalog or
  profile identifiers.
- The startup gate now names the backend health/security check as product
  policy rather than an iOS network permission prompt. `StartupGatePolicy`
  is the pure code entry for required security preflight, camera, and photo
  library checks; location stays optional. `StartupSecurityPreflightPolicy`
  keeps backend retry, delay, deadline, and timeout decisions testable outside
  the `NSObject` coordinator. `StartupBackendSecurityPreflight` keeps HTTPS
  `/healthz` execution separate from both pure policy and OS permission
  coordination.
- AppAttestKit is pinned to the current reviewed revision instead of a moving
  branch requirement.
- `TAPCamDemo.entitlements` makes App Attest environment configuration visible
  to reviewers.
- `CameraRouteStore` makes the camera/TAP Library route, foreground return, and
  album anchor testable instead of incidental SwiftUI Boolean state.
- `CameraRouteContextStore` gives TAP Library route context a small durable
  boundary. It persists only HMAC restore tokens with file protection, validates
  restore against the current item list, and can map a pending capture anchor to
  the owned photo item after export.
- `CaptureLifecycleCoordinator` makes scene-phase, TAP Library return, App
  Attest readiness, and pending-queue retry triggers explicit.
  `CameraViewLifecycleModifier` now owns the SwiftUI `.task`, `.onAppear`,
  `.onDisappear`, and `.onChange` hook binding so `CameraView.body` no longer
  carries the lifecycle modifier chain.
- Camera bottom chrome is isolated in `CameraCaptureControlsView`. It receives
  field-level presentation state and action closures for Settings, TAP Library,
  shutter, and camera switch, while `CameraView` keeps App Attest client access,
  route store ownership, capture action orchestration, lifecycle forwarding, and
  Settings presentation. The controls state has tests for TAP Library lockout
  while writes finish and for avoiding raw-id/proof/store/data-shaped fields.
- Camera preview composition is isolated in `CameraPreviewStageView`. It owns
  preview sizing, render-only session handoff, crop metadata callback routing,
  Release FOV overlay, and the Debug overlay host. Release FOV chips now use
  display-only state so the stage and selector do not receive camera profiles,
  depth profiles, raw device identifiers, or capture plans.
- Camera Debug overlay composition is isolated in
  `CameraPreviewDebugOverlayView`. It owns DEBUG-only status, depth-source,
  zoom, performance, and expanded/collapsed overlay presentation from
  display-only rows while `CameraView` keeps the real Debug device options and
  zoom profiles.
- Foreground capture still ends at `TAPPendingCaptureArtifactWriter`; lifecycle
  coordination does not create a capture pipeline or export unsigned HEICs to
  Photos.
- `TAPCaptureProvenanceWriter.validateSignedExportHEIC` is the final export
  gate. It re-reads the signed bytes, checks the HEIC source type, manifest
  schema and capture ID, Release output facts, exactly one App Attest proof,
  proof digest/binding, and Apple auxiliary depth before the Photos writer can
  save the file. `ValidatedTAPDepthHEIC` is constructed only inside the
  provenance writer file, so ordinary module code cannot mint the trusted
  Photos-save wrapper directly.
- `CameraControlCapabilitySnapshot` gives future manual controls a stable read
  model before any user-facing control writer or UI is added.
- `CameraManualControlIntent` gives future EV, ISO, shutter, focus, white
  balance, aperture, and zoom UI a pure user-intent model before any state is
  persisted or any device is mutated. It distinguishes no-op requests from
  explicit auto requests, checks stale device ids, and returns readable
  violations instead of silently clamping unsupported values.
- `CameraControlService` centralizes and queue-guards current device writes for
  baseline focus, virtual-camera switching, and raw zoom without adding
  manual-control UI.
- Runtime now resolves an output profile once into `ResolvedCaptureOutputProfile`
  before building `AVCapturePhotoSettings`. Provider, package, packager, and
  manifest code consume that same execution token, so future format/quality work
  has a readable place to add profile catalog entries without letting UI mutate
  AVFoundation settings directly or letting package code reinterpret raw profile
  fields.
- `CaptureOutputResourcePlan` names the logical resources in the reviewed
  Release output: primary photo, Apple auxiliary depth, TAP manifest, and App
  Attest capture proof. It records which resources are required for export and
  which are covered by the App Attest content digest without carrying bytes,
  paths, URLs, Photos identifiers, key IDs, capture IDs, manifests, or
  AVFoundation objects.
- `PreCaptureConfigurationBuilder` owns the shutter-time preview-crop snapshot.
  It updates crop metadata in both the active capture plan and selection context
  while preserving Runtime's output profile, resolved output token, device, and
  control-capability facts.
- `CaptureOutputProfileSelectionIntent` gives future format or quality UI a
  pure, fail-closed request boundary. It selects only reviewed catalog profiles
  and does not create profiles, persist preferences, write manifests, touch
  Photos, or change App Attest proof semantics.
  `CaptureOutputProfileSelectionPresentation` is the matching public-safe text
  boundary for missing or invalid profile requests.
- README files sit next to the source modules they describe.

## Strict Gaps

- DepthAnalysis now has an input loader, rectangular region-selection state,
  Planes seed-selection state, async plane-region request coordinator,
  plane-region detector, input validation, album item provider, thumbnail
  pipeline, merged-item boundary, screen shell, central stage, controls view,
  and field-level panel adapter. The picker is mostly grid, route restoration,
  selection, and navigation; the view model no longer reads Photos or pending
  storage directly and no longer owns rectangular region-product calculation,
  synchronous Planes seed/result presentation, async plane request lifecycle, or
  plane-region calculation internals. The Planes estimator now has facade,
  fitting, seed/BFS growth, and output-product files. Remaining gaps are
  rendered UI/layout automation evidence for the metadata HUD, stage, adaptive
  panel, and inspector bodies, plus real-device Photos limited-access/deletion
  and UI regression evidence for the TAP Library flow.
- TAP Library route context is now durable for best-effort scroll restoration,
  but there is no durable filter model, UI regression coverage, or real-device
  Photos limited-access/deletion evidence yet.
- Camera route, screen lifecycle policy, lifecycle hook binding, preview-stage
  composition, Debug overlay composition, and bottom chrome policy now have
  `CameraRouteStore`, `CaptureLifecycleCoordinator`,
  `CameraViewLifecycleModifier`, `CameraPreviewStageView`,
  `CameraPreviewDebugOverlayView`, and `CameraCaptureControlsView`, and the
  pending worker has a protected-data readiness model. Remaining gaps are
  durable album filters, protected-data UI messaging, real-device
  protected-data validation, and UI regression evidence for the camera chrome,
  preview stage, and Debug overlay.
- Output format/quality is still not user configurable. The current work keeps
  one Release HEIC-depth profile and one unsigned-to-signed HEIC export path;
  JPEG, RAW, Live Photo, video, or user-visible quality levels still need new
  profiles, validators, manifest rules, packaging paths, signing/verifier
  contracts, readers, and tests.
- Manual camera controls now have a read-only capability snapshot, a pure
  intent model, a public-safe resolution presentation, a field-row summary, a
  Runtime-executable pure command plan, and an internal queue-guarded Runtime
  application boundary, but still need SwiftUI controls, persistence policy,
  real-device validation, and UI regression coverage before EV, ISO, shutter,
  focus, white balance, or aperture should be user-facing.
- Lock-screen launch needs a separate extension target and real-device
  validation. Keeping the app awake indefinitely while locked should not be the
  design assumption.
- App Attest entitlement setup is visible and build-checked, but still needs
  attended real-device validation against the Apple Developer account and
  backend. The saved-photo verification panel also needs real Photos asset and
  backend acceptance evidence.
- The signed export validator has negative unit coverage for missing, invalid,
  and multiple proof records, but still needs a positive real-depth HEIC fixture
  and attended Photos/App Attest evidence on a physical device.
- C2PA, Live Photo, video, guides, RAW/ProRAW, and MultiCam remain future work.
- Startup security preflight failure reasons are still coarse even though the
  gate itself is now named more clearly.
- Diagnostic logging has unit coverage for the shared public error formatter and
  a source-level OSLog privacy harness for critical call sites, but it still
  lacks real-device unified-log capture evidence.
- TAP Library persisted `failureReason` now has typed store writes, normalized
  reads, explicit migration coverage, and invalid-bundle skip coverage during
  migration; an old bundle that has not been opened or reconciled yet can still
  retain its historical raw string on disk until migration runs.
- TAP Library exported records clear persisted location going forward, but
  already-exported historical bundles with location fields still need a
  migration pass if that legacy data exists on disk.
- The `StartupGateView` `@AppStorage` write path is protected by tested startup
  predicates, but it still lacks a direct UI/view-level regression test.

## Next Score Lift

The next refactor iteration should raise the score most by adding one of these
boundaries before adding user-visible controls:

1. Manual-control SwiftUI controls and persistence policy that consume
   `CameraManualControlIntent`,
   `CameraManualControlResolutionPresentation`,
   `CameraManualControlSummary`, `CameraManualControlCommandPlan`,
   `CameraControlCapabilitySnapshot`, and `CameraControlService` without
   touching AVFoundation directly from SwiftUI.
2. Real-device unified-log redaction evidence for the diagnostics and
   presentation privacy boundaries.
3. Output export evidence: add a positive real-depth HEIC fixture and attended
   Photos/App Attest acceptance notes for the final signed-export gate.
4. App Attest hardening: real-device entitlement/backend acceptance validation,
   including the saved-photo verification panel path.
5. Protected-data UI policy and real-device validation on top of
   `TAPPendingCaptureWorkerReadiness` and `CaptureLifecycleCoordinator`.
6. UI regression and real-device evidence for TAP Library route restoration.
7. Rendered UI/layout regression evidence for CameraCapture controls,
   preview/debug overlays, DepthAnalysis stage, metadata HUD, adaptive panel,
   inspector bodies, and TAP Library route restoration.
