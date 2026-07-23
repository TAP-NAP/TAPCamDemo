# Future Camera Specs

This is the reading entry for planned camera work. The current priority is
refactoring for readability and extension points, not adding user-visible
features.

## How To Read This Boundary Status

Start here, then jump to the module README or code entry named by each item.
Each item states the boundary that should exist before new UI or product
behavior is added.

| Topic | Code entry |
| --- | --- |
| App-level photo quality policy | [../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift](../TAPCamDemo/CameraCapture/Output/CapturePhotoQualityPolicy.swift) |
| Output profile catalog | [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileCatalog.swift) |
| Output profile selection intent and public-safe presentation | [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileSelectionIntent.swift) |
| Output format and quality | [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift) |
| Resolved Runtime output request | [../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift) |
| Output resource plan | [../TAPCamDemo/CameraCapture/Output/CaptureOutputResourcePlan.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputResourcePlan.swift) |
| Output manifest facts policy | [../TAPCamDemo/CameraCapture/Output/CaptureOutputManifestPolicy.swift](../TAPCamDemo/CameraCapture/Output/CaptureOutputManifestPolicy.swift) |
| Manual camera control capability | [../TAPCamDemo/CameraCapture/Planning/CameraControlCapabilitySnapshot.swift](../TAPCamDemo/CameraCapture/Planning/CameraControlCapabilitySnapshot.swift) |
| Manual camera control user intent | [../TAPCamDemo/CameraCapture/Planning/CameraManualControlIntent.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlIntent.swift) |
| Manual camera control field summary | [../TAPCamDemo/CameraCapture/Planning/CameraManualControlSummary.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlSummary.swift) |
| Manual camera control Runtime command plan | [../TAPCamDemo/CameraCapture/Planning/CameraManualControlCommandPlan.swift](../TAPCamDemo/CameraCapture/Planning/CameraManualControlCommandPlan.swift) |
| Manual camera control write boundary | [../TAPCamDemo/CameraCapture/Runtime/CameraControlService.swift](../TAPCamDemo/CameraCapture/Runtime/CameraControlService.swift) |
| Manual camera control device limits | [CameraManualControlDeviceLimits.md](CameraManualControlDeviceLimits.md) |
| Photographer Mode runtime product plan | [CameraProControlsBuildIsolationPlan.md](CameraProControlsBuildIsolationPlan.md) |
| Camera route and album anchor | [../TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift](../TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift) |
| Durable route context | [../TAPCamDemo/CameraCapture/UI/CameraRouteContextStore.swift](../TAPCamDemo/CameraCapture/UI/CameraRouteContextStore.swift) |
| Camera screen lifecycle | [../TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift](../TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift) |
| Camera lifecycle hook binding | [../TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift](../TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift) |
| Camera controls design vocabulary | [CameraControlsDesign.md](CameraControlsDesign.md) |
| App Intents score surface | [../TAPCamDemo/App/TAPCamAppIntents.swift](../TAPCamDemo/App/TAPCamAppIntents.swift) |
| Camera screen shell | [../TAPCamDemo/CameraCapture/UI/CameraView.swift](../TAPCamDemo/CameraCapture/UI/CameraView.swift) |
| Camera UX preferences and mode policy | [../TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift](../TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift) |
| Camera viewfinder chrome | [../TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift](../TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift) |
| Camera lower toolbar and adjustment strip | [../TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift](../TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift) |
| Camera preview stage | [../TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift](../TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift) |
| Camera guide overlay | [../TAPCamDemo/CameraCapture/UI/CameraGuideOverlayView.swift](../TAPCamDemo/CameraCapture/UI/CameraGuideOverlayView.swift) |
| Camera preview debug overlay | [../TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift](../TAPCamDemo/CameraCapture/UI/CameraPreviewDebugOverlayView.swift) |
| Camera bottom controls | [../TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift](../TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift) |
| TAP Library queue record model | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecord.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecord.swift) |
| TAP Library bundle path policy | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundlePathPolicy.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundlePathPolicy.swift) |
| TAP Library bundle filesystem storage | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureBundleStorage.swift) |
| TAP Library queue storage | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift) |
| TAP Library camera writer adapter | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureArtifactWriter.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureArtifactWriter.swift) |
| TAP Library thumbnail helper | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureThumbnailRenderer.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureThumbnailRenderer.swift) |
| TAP Library record coding | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecordCoding.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureRecordCoding.swift) |
| Pending worker readiness | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureWorkerReadiness.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureWorkerReadiness.swift) |
| Pending retry classification | [../TAPCamDemo/TAPLibrary/TAPPendingCaptureRetryClassifier.swift](../TAPCamDemo/TAPLibrary/TAPPendingCaptureRetryClassifier.swift) |
| DepthAnalysis input/source/load tests | [../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift](../TAPCamDemoTests/TAPDepthAnalysisInputTests.swift) |
| DepthAnalysis selection state and ViewModel bridge tests | [../TAPCamDemoTests/TAPDepthAnalysisSelectionTests.swift](../TAPCamDemoTests/TAPDepthAnalysisSelectionTests.swift) |
| DepthAnalysis plane geometry, detector, and request-coordinator tests | [../TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests.swift](../TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests.swift) |
| DepthAnalysis error presentation tests | [../TAPCamDemoTests/DepthAnalysisErrorPresentationTests.swift](../TAPCamDemoTests/DepthAnalysisErrorPresentationTests.swift) |
| DepthAnalysis presentation/privacy tests | [../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift](../TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift) |
| OSLog privacy harness tests | [../TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests.swift](../TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests.swift) |
| Capture output profile tests | [../TAPCamDemoTests/TAPCaptureOutputProfileTests.swift](../TAPCamDemoTests/TAPCaptureOutputProfileTests.swift) |
| TAP Library route and item tests | [../TAPCamDemoTests/TAPLibraryRouteTests.swift](../TAPCamDemoTests/TAPLibraryRouteTests.swift) |
| TAP Library storage tests | [../TAPCamDemoTests/TAPLibraryStorageTests.swift](../TAPCamDemoTests/TAPLibraryStorageTests.swift) |
| TAP Library processing tests | [../TAPCamDemoTests/TAPLibraryProcessingTests.swift](../TAPCamDemoTests/TAPLibraryProcessingTests.swift) |
| Manifest payload/proof separation tests | [../TAPCamDemoTests/TAPCaptureManifestEncodingTests.swift](../TAPCamDemoTests/TAPCaptureManifestEncodingTests.swift) |
| Capture content digest tests | [../TAPCamDemoTests/TAPCaptureContentDigestTests.swift](../TAPCamDemoTests/TAPCaptureContentDigestTests.swift) |
| App Attest capture assertion tests | [../TAPCamDemoTests/TAPCaptureAssertionSignerTests.swift](../TAPCamDemoTests/TAPCaptureAssertionSignerTests.swift) |
| Pending-signing provenance writer tests | [../TAPCamDemoTests/TAPCaptureProvenanceWriterSigningTests.swift](../TAPCamDemoTests/TAPCaptureProvenanceWriterSigningTests.swift) |
| Signed export validator tests | [../TAPCamDemoTests/TAPSignedExportValidatorTests.swift](../TAPCamDemoTests/TAPSignedExportValidatorTests.swift) |
| Shared test fixtures | [../TAPCamDemoTests/TAPCamDemoTestFixtures.swift](../TAPCamDemoTests/TAPCamDemoTestFixtures.swift) |
| Startup gate policy | [../TAPCamDemo/App/StartupGatePolicy.swift](../TAPCamDemo/App/StartupGatePolicy.swift) |
| Startup security preflight retry policy | [../TAPCamDemo/App/StartupSecurityPreflightPolicy.swift](../TAPCamDemo/App/StartupSecurityPreflightPolicy.swift) |
| Startup backend security preflight | [../TAPCamDemo/App/StartupBackendSecurityPreflight.swift](../TAPCamDemo/App/StartupBackendSecurityPreflight.swift) |
| Diagnostic and UI presentation privacy | [../TAPCamDemo/App/AppAttestRuntime.swift](../TAPCamDemo/App/AppAttestRuntime.swift), [../TAPCamDemo/App/AppAttestCredentialPresentation.swift](../TAPCamDemo/App/AppAttestCredentialPresentation.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift) |
| DepthAnalysis presentation/privacy boundary | [../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisErrorPresentation.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift), [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift) |
| DepthAnalysis photo input loader | [../TAPCamDemo/DepthAnalysis/DepthAnalysisInputLoader.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInputLoader.swift) |
| DepthAnalysis region selection state | [../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionSelectionState.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionSelectionState.swift) |
| DepthAnalysis plane selection state | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneSelectionState.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneSelectionState.swift) |
| DepthAnalysis plane request coordinator | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionRequestCoordinator.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionRequestCoordinator.swift) |
| DepthAnalysis plane-region detector | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionDetector.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneRegionDetector.swift) |
| Depth album item provider | [../TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift](../TAPCamDemo/DepthAnalysis/DepthAlbumItemProvider.swift) |
| Depth album thumbnails | [../TAPCamDemo/DepthAnalysis/DepthAlbumThumbnailPipeline.swift](../TAPCamDemo/DepthAnalysis/DepthAlbumThumbnailPipeline.swift) |
| DepthAnalysis screen shell | [../TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift) |
| DepthAnalysis view modes | [../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisViewMode.swift) |
| DepthAnalysis central stage | [../TAPCamDemo/DepthAnalysis/DepthAnalysisStageView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisStageView.swift) |
| DepthAnalysis bottom controls | [../TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisControlsView.swift) |
| DepthAnalysis panel content adapter | [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorPanelContent.swift) |
| DepthAnalysis debug metadata HUD | [../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift) |
| DepthAnalysis panel support | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelSupport.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelSupport.swift) |
| DepthAnalysis inspector strip | [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorStrip.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorStrip.swift) |
| DepthAnalysis adaptive panel layer | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelLayer.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPanelLayer.swift) |
| DepthAnalysis inspector shared support | [../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift) |
| DepthAnalysis measurements inspector | [../TAPCamDemo/DepthAnalysis/DepthAnalysisMeasurementsInspectorContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisMeasurementsInspectorContent.swift) |
| DepthAnalysis legend inspector | [../TAPCamDemo/DepthAnalysis/DepthAnalysisLegendInspectorContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisLegendInspectorContent.swift) |
| DepthAnalysis region inspector | [../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionInspectorContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisRegionInspectorContent.swift) |
| DepthAnalysis plane inspector | [../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneFilterInspectorContent.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneFilterInspectorContent.swift) |
| DepthAnalysis overlay and cloud inspectors | [../TAPCamDemo/DepthAnalysis/DepthAnalysisOverlayCloudInspectors.swift](../TAPCamDemo/DepthAnalysis/DepthAnalysisOverlayCloudInspectors.swift) |
| Capture runtime | [../TAPCamDemo/CameraCapture/Runtime/README.md](../TAPCamDemo/CameraCapture/Runtime/README.md) |
| Packaging and manifest | [../TAPCamDemo/CameraCapture/Output/README.md](../TAPCamDemo/CameraCapture/Output/README.md) |
| Startup gate | [Startup/FirstLaunch.md](Startup/FirstLaunch.md) |
| App Attest | [AppAttest/README.md](AppAttest/README.md) |
| Current score and strict gaps | [ProjectScorecard.md](ProjectScorecard.md) |

## Priority Rules

1. Readability and extensibility come before new capture features.
2. New camera capabilities need model/service boundaries before SwiftUI controls.
3. Unsupported device features must be capability-gated.
4. Security and provenance must remain part of the output contract.
5. Locked-screen capture must follow Apple's extension lifecycle; do not design
   around keeping the camera awake indefinitely while locked.

## P0 Boundary Status

This table mixes completed boundaries with remaining evidence gaps. It is a
status map for refactor-first work, not a promise that every row is unfinished.

| Item | Why it comes first | Done when |
| --- | --- | --- |
| Output profile boundary | Format, codec, depth embedding, still-photo dimensions, and quality must have one readable entry before new output UI exists. | `CaptureOutputProfileCatalog.release` names the executable Release profile list. `CaptureOutputProfile.releasePhotoDepthHEIC` and `CaptureOutputProfile.releasePhotoDepthJPEG` name the reviewed HEIC/JPG depth contracts, reject cross-container fallback and invalid depth/quality/dimension combinations, and resolve into one `ResolvedCaptureOutputProfile` execution token before AVFoundation settings are built. `CaptureOutputProfileResolution` keeps that Runtime handoff and `CapturePhotoOutputCapabilitySnapshot` validation separate from the catalog. `CapturePhotoQualityPolicy.releaseQuality` maps to AVFoundation `.quality`, but explicitly does not guarantee byte size or compression ratio. `CaptureOutputManifestPolicy` maps the same reviewed Release profiles to the manifest capture fields the final export gate revalidates before Photos save. Provider, package, packager, and manifest code consume the resolved token instead of re-reading raw profile fields. |
| Output profile selection intent | Future format or quality controls need one fail-closed request boundary before UI can choose a profile. | `CaptureOutputProfileSelectionIntent` resolves default or explicit profile requests against `CaptureOutputProfileCatalog`, returns readable developer violations for invalid catalogs, missing profiles, or invalid selected profiles, and `CaptureOutputProfileSelectionPresentation` gives future UI fixed public-safe status text without raw profile ids. The selection boundary does not create profiles, persist preferences, write manifests, touch App Attest, call Photos, or change Runtime settings. |
| Output resource plan | Future RAW, arbitrary non-TAP media, sidecar, or C2PA work needs a resource-level contract before adding packagers or export paths. | `CaptureOutputResourcePlan.releasePhotoDepthHEIC` and `.releasePhotoDepthJPEG` name the current Release photo resources: primary photo, Apple auxiliary depth, TAP manifest, and App Attest capture proof. TAP Video owns a separate MP4/KLV resource and validation contract. The photo plans mark which resources are required before export and which are covered by the App Attest content digest. The current Live Photo path extends the artifact after capture with one fixed paired MOV resource and routes it through `depth-manifest:v2` plus `content-binding:v3`; it does not turn the still-photo resource plan into a general multi-resource fallback. `ResolvedCaptureOutputProfile.resourcePlan` reuses the embedded photo-depth packaging validator before returning this plan, so future output work cannot use the resource map as a shortcut around the validated TAP depth photo contract. The current manifest proof array stays exactly one App Attest proof; future C2PA must not be appended without a schema, digest, and validator update. It stores no bytes, paths, URLs, Photos identifiers, key IDs, capture IDs, manifests, or AVFoundation objects. |
| Manual control capability snapshot | EV, ISO, shutter, focus, white balance, aperture, and zoom UI need a stable read model before any controls mutate the camera session. | `CameraControlCapabilitySnapshot` describes active-device support flags and ranges, including separate custom lens-position support and minimum focus distance. It is attached to `SessionConfigurationResult` but does not write controls. |
| Manual control user intent model | Future controls need a readable value for "what the user asked for" before UI state, persistence, or AVFoundation writes exist. | `CameraManualControlIntent` represents no-op versus explicit auto, locked, EV bias, custom ISO plus shutter, focus point, white-balance gains, aperture, and zoom requests. It resolves against `CameraControlCapabilitySnapshot`, reports violations, imports no AVFoundation, writes no session state, persists nothing, and adds no UI. |
| Manual control status presentation | Future manual-control UI needs public-safe status text before raw resolution errors become visible. | `CameraManualControlResolutionPresentation` summarizes no-op, ready, and blocked states with fixed control-group labels only. It does not expose raw device identifiers, requested numeric values, AVFoundation objects, manifests, proofs, paths, URLs, App Attest fields, or write commands. |
| Manual control field-row summary | Future EV, ISO, shutter, focus, white-balance, aperture, and zoom rows need one readable source before SwiftUI controls exist. | `CameraManualControlSummary` turns a resolved intent into fixed field rows with separate request semantics (`unchanged`, `explicitAuto`, `manualRequested`) and execution states (`unchanged`, `requested`, `blocked`, `blockedRequested`). It keeps raw device identifiers, requested numeric values, AVFoundation objects, manifests, proofs, paths, URLs, App Attest fields, ranges, and write commands out of the row data. |
| Manual control Runtime command plan | Future manual-control controls need one non-UI bridge between validated intent and the session-queue writer before SwiftUI or persistence exists. | `CameraManualControlCommandPlan` turns only executable resolutions into ordered Runtime-executable pure-value commands. Blocked resolutions produce no commands. It carries the target device id and control-surface signature so a future Runtime writer can reject stale-camera or stale-capability writes; it does not write AVFoundation, persist settings, log values, expose public UI copy, or hold device/session/writer/queue/proof/path/App Attest handles. |
| Manual control focused tests | Manual controls need a stable review path before persistence or real-device writes are treated as accepted. | `TAPCameraManualControlIntentTests`, `TAPCameraManualControlPresentationTests`, `TAPCameraManualControlSummaryTests`, `TAPCameraManualControlCommandPlanTests`, `TAPCameraManualControlBoundaryGuardTests`, `TAPCameraControlServiceTests`, and `TAPCameraCapturePresentationTests` own deterministic capability, intent, public-safe presentation, field-row summary, command-plan, source-boundary, Pro-control state, status-copy, and Runtime validation coverage. These tests prove the model, UI-state, and Runtime boundary shape only; they do not prove physical-device EV, ISO, shutter, focus, white-balance, aperture, or zoom behavior. |
| Manual control write service | Manual controls need one session-safe device-write boundary before SwiftUI can request writes. | `CameraControlService` owns baseline focus, virtual-camera switching, raw zoom writes, `CameraManualControlCommandPlan` application, and Auto-mode restore for exposure/focus/white-balance with global EV bias reapplied. It is registered to Runtime's serial session queue, rejects queue-outside control writes, rejects blocked command plans, and rejects stale target camera ids before locking the device. The current UI uses it for global EV exposure-bias writes and first-stage ISO/S exposure writes plus lens-position writes; white-balance and aperture UI remain future work. |
| Photographer Mode runtime boundary | Standard and professional capture paths must remain explicit while both surfaces ship in the Release app. | Standard never opts into LiDAR and keeps the existing session, Basic EV, and lens selector. The rightmost `PRO` entry appears on the Flash/Live Photo row only when an eligible rear LiDAR 24mm / 1x path preserves depth and supports custom ISO/S plus MF. PRO v1 is photo-only; active PRO hides Basic EV and the lens selector, and shows `EV / ISO / S / AF/MF / ƒ`. The state machine is `unavailable / standard / activating / active / deactivating / failed`. Activation, deactivation, rear-PRO-to-front, and front-to-rear-PRO retain the last frame under frosted glass and lock interaction until the destination session is ready. Front temporarily suspends rear PRO intent rather than turning it off. Settings resolves `Default Off / Default On / Remember Last State`, with Default Off and safe Standard fallback. Release and Debug share this product boundary; only diagnostics remain Debug-only. The implementation and validation contract is recorded in [CameraProControlsBuildIsolationPlan.md](CameraProControlsBuildIsolationPlan.md). |
| Startup gate policy model | The first-launch gate must read as product policy before UI or permission plumbing. | `StartupGatePolicy` names the strict backend security preflight, camera, and photo library checks as required and location plus microphone as optional. `StartupSecurityPreflightPolicy` owns the pure retry, delay, deadline, and timeout decisions for the backend security preflight. `StartupBackendSecurityPreflight` owns the `/healthz` execution and injected query seams. `StartupGateCoordinator` still owns OS status reads and requests. |
| TAP Library queue model split | Pending records, bundle path policy, bundle filesystem storage, foreground writer adapter, thumbnails, and JSON policy need separate reading entrances before future resource bundles or output variants exist. | `TAPPendingCaptureRecord` owns status, identity, export-time location, selected photo container, container-specific unsigned/signed filenames, and visible-pending state. `TAPPendingCaptureStore.markExported` clears the persisted queue location after Photos accepts the asset, while keeping `assetLocalIdentifier` and thumbnail index data. `TAPPendingCaptureBundlePathPolicy` validates capture IDs and keeps the current `unsigned.heic`, `signed.heic`, `unsigned.jpg`, `signed.jpg`, and `thumbnail.jpg` artifact allow-list exact before disk access. `TAPPendingCaptureBundleStorage` owns directory creation, temporary bundles, bundle moves/removes, `bundle.json` IO, artifact reads/writes, and cleanup through the path and local-storage policies. `TAPPendingCaptureStore` owns queue-facing state transitions, queries, failure-reason normalization, notifications, and actor serialization. `TAPPendingCaptureArtifactWriter`, `TAPPendingCaptureThumbnailRenderer`, and `TAPPendingCaptureRecordCoding` own their own adapter/helper policy without changing Release behavior. |
| Local artifact storage policy | Pending photo artifacts, signed photo artifacts, records, and thumbnails need one protection/cleanup story. | `TAPLocalArtifactStoragePolicy.privatePhotoArtifact` is the shared write/protection entry for pending bundles and analysis thumbnail caches, with retention documented in TAP Library and Depth Analysis READMEs. |
| Pending worker readiness | Protected-data and future locked-camera behavior need one small worker preflight before private pending artifacts are read. | `TAPPendingCaptureWorkerReadiness` owns the first pending-worker gate. It allows reads only when protected data is available and otherwise returns before reconciliation, signing, export, retry mutation, or failure-reason updates. UI messaging and real-device protected-data validation remain future work. |
| Diagnostic and UI presentation privacy | Logs, user-visible status text, and durable queue failure text need public/private policy before more capture modes and provenance systems add identifiers. | `TAPDiagnostics.describe` emits a public-safe error summary. `AppAttestCredentialPresentation` emits generic Settings failure text and redacted key ID summaries. `CameraCaptureStatusPresentation` emits public-safe camera status text and Debug metrics failure reasons, with focused tests in `TAPCameraStatusPresentationTests`. `DepthAnalysisErrorPresentation` emits fixed album, analysis load, and Planes selection errors instead of raw Photos, pending, reader, path, asset, capture-ID, or local analysis errors. `DepthAnalysisInspectorErrorMessage` is the only error-message type accepted by concrete Region and Plane Filter inspectors; it allows fixed Region/Planes messages and falls back from hostile strings before SwiftUI labels render them. `CaptureMetadataSummary` emits a Debug-only metadata HUD summary from public lens/source/zoom fields and falls back to fixed labels when manifest display strings look like paths, URLs, proofs, App Attest key IDs, capture IDs, asset IDs, manifest IDs, or token values. `TAPDepthAnalysisPresentationTests` keeps metadata summary, view-mode routes, debug-only mode flags, panel destinations, shared region-stats text, help defaults, interaction flags, and passive authorization status text deterministic and public-safe. `TAPPendingCaptureRetryClassifier` classifies retry state from typed Foundation error domains/codes instead of localized messages. `TAPPendingCaptureFailureReasonPresentation` emits public-safe persisted queue failure reasons, typed write reasons, and legacy normalization. App Attest credential names/key ids, capture ids, manifest ids, and Photos asset ids are OSLog-private. `TAPDiagnosticsOSLogPrivacyTests` source-scans critical log call sites so every reviewed interpolation declares privacy, capture ids, asset ids, manifest ids, credential names, key ids, and invalid bundle names stay `.private`, reviewed scalar labels stay `.public`, and public `error=` fields use `TAPDiagnostics.describe(error)`. Public logs, Settings text, camera status text, Debug failure text, album/analyzer/Planes error text, current queue failure reasons, migrated legacy queue failure reasons, inspector error labels, and the Debug metadata HUD keep only operational state such as status, route, retry count, byte counts, fixed request paths, scalar network hints, redacted key summaries, fixed retry messages, fixed analyzer failure text, and public camera/source/zoom labels. Proof bodies, assertion objects, photo bytes, GPS values, thumbnails, raw route identifiers, localized errors, failing URLs, raw network paths, backend payloads, full key IDs, raw capture/manifest IDs, Photos asset IDs, and associated error reasons stay out of public diagnostics, user-visible status, queue retry classification, album/analyzer/Planes errors, inspector error labels, queue failure text, and Debug metadata HUD text. Legacy bundle cleanup is explicit and runs when the pending worker reconciles after protected-data readiness; unopened old bundles may still contain old raw strings on disk until that migration runs. |
| Oversized analysis files | The analysis screen is too broad for safe feature work. | `DepthAnalysisView`, `DepthAnalysisStageView`, `DepthAnalysisControlsView`, `AnalysisInspectorPanelContent`, view-mode model, debug metadata HUD, panel support, inspector strip, adaptive panel layer, view model, photo input loader, input validation, rectangular region-selection state, Planes seed-selection state, async plane-region request coordinator, plane-region detector, Planes estimator facade, plane fitting helpers, seed/BFS growth helpers, region output-product helpers, shared inspector support, shared region-stats presentation, measurements inspector, legend inspector, region inspector, plane inspector, overlay/cloud inspectors, overlays, viewport mapping, TAP Library item provider, and TAP Library thumbnail pipeline are split into focused files with pure tests for source routing, reader input rejection, input byte/pixel/sample/calibration hardening, temporary-unavailable mapping, load-error presentation bridging, region selection products, Planes seed/strictness/detection presentation state, async plane request freshness/cache reuse, plane geometry cache reuse, coordinate conversion, view-mode labels/debug flags, per-mode inspector route lists, typed public-safe inspector errors, shared region-stats text, pure adaptive panel height metrics, Debug metadata HUD public-safe text, item merge/dedupe/partial-failure behavior, route anchors, and Photos/owned/pending thumbnail cache-key privacy. `TAPDepthAnalysisInputTests` owns the input/source/load boundary tests. `TAPDepthAnalysisSelectionTests` owns local rectangular region selection, Planes seed-selection state, and ViewModel finish/clear selection bridge tests. `TAPDepthAnalysisPlaneRegionTests` owns local plane geometry, detector, estimator/growth, and request-coordinator tests. Remaining gaps are metadata HUD/rendered adaptive panel/inspector body layout automation evidence, real-device Photos/TAP Library evidence, and broader UI regression evidence. |
| TAP Library route state | Album return position is product state, not incidental SwiftUI state. | `CameraRouteStore` owns camera/album presentation and foreground return. `CameraRouteContextStore` owns best-effort durable scroll restoration with protected HMAC tokens rather than raw Photos or pending-capture identifiers. Durable filters and UI regression evidence remain future work. |
| Camera lifecycle coordinator | Scene phase, foreground return, pending-capture signing credential warmup, and pending-queue retry triggers should not be buried in the screen layout before locked-camera or protected-data behavior expands. | `CaptureLifecycleCoordinator` owns camera-screen lifecycle event policy. `CameraViewLifecycleModifier` owns only SwiftUI `.task`, `.onAppear`, `.onDisappear`, and `.onChange` hook binding. `CameraView` owns layout, object lifetime, navigation, sheet presentation, and top-level actions. Route state stays in `CameraRouteStore`, capture state stays in `CameraViewModel`, and pending worker protected-data readiness stays in `TAPPendingCaptureWorkerReadiness`. |
| Pre-capture configuration snapshot | Shutter-time preview crop must not make the UI reinterpret Runtime, output, or provenance facts. | `PreCaptureConfigurationBuilder` owns the only shutter-time copy of `SessionConfigurationResult`. It updates `capturePlan.cropPolicy.cropRectNormalized` and `selectionContext.cropRectNormalized` from the current preview crop, preserves `outputProfile`, `resolvedOutput`, device, display name, preview aspect ratio, and manual-control capability facts, and keeps custom raw Release zoom factors alive. |
| Camera chrome, preview-stage, and Debug overlay boundaries | Runtime Photographer Mode, guides, format/quality controls, and diagnostics need safe UI containers. | `CameraViewfinderChromeView` owns the Dynamic Island shoulder Settings control, Standard Basic EV entry, and the top `[Flash] [Live Photo] Spacer [PRO]` toolbar from field-level presentation state and closures only. Settings owns Flash, Live Photo, and Photographer Mode startup policies (`Default Off` / `Default On` / `Remember Last State`); entering the camera resolves each policy into a request, while actual PRO readiness comes only from runtime capability and session state. `CameraCaptureControlsView` owns the bottom chrome and mode-selector slot: Standard can replace the slot with Basic EV; active PRO shows the EV/ISO/shutter/focus/aperture lower toolbar and professional strips. `CameraPreviewStageView` owns preview sizing, render-only `AVCaptureSession` handoff, crop metadata callback routing, Standard-only FOV chips, Settings-owned guide overlay hosting, the viewfinder edge toast, the MF focus loupe, frosted session-transition hosting, and the Debug overlay host. `CameraGuideOverlayView` renders guide choices without touching capture planning or exported pixels. `CameraPreviewDebugOverlayView` owns Debug-only status/depth/zoom/performance overlay layout from display-only rows and local expanded/collapsed state, with focused coverage in `TAPCameraCapturePresentationTests`. These views do not receive device-selection authority, `CameraRouteStore`, App Attest clients, pending stores, capture pipelines, output profiles, raw identifiers, photo bytes, manifests, proofs, or key IDs. |
| Provenance writer boundary | TAP XMP, App Attest, and future C2PA should not be hard-wired into UI or storage code. | `TAPCaptureProvenanceWriter` owns TAP XMP, App Attest proof writing, and final signed-export validation. Pending signing validates the queue record `captureID` before proofing; export re-reads the signed HEIC or JPG and checks source type, manifest schema/id, `CaptureOutputManifestPolicy` Release facts, proof envelope, proof digest binding, and auxiliary depth before Photos save. |

## P1 Feature Specs

These are deferred until the needed P0 boundary exists.

| Feature | Required boundary first |
| --- | --- |
| Default camera route and foreground return | `CameraRouteStore`, `CameraRouteContextStore`, `CaptureLifecycleCoordinator`, `CameraViewLifecycleModifier`, and `TAPPendingCaptureWorkerReadiness` exist; remaining work is durable filter context, protected-data UI messaging, UI regression coverage, and real-device scene/protected-data validation. |
| Manual EV/ISO/shutter/focus controls | Standard uses the Face ID left-shoulder Basic EV entry and its narrow exposure-target-bias-only write path. Photographer Mode is a Release runtime surface: only an eligible rear LiDAR 24mm / 1x photo path gets the PRO lower toolbar and professional state machines. Active PRO hides Basic EV and the lens selector, while Standard never selects LiDAR. Basic preview tap focus maps through visible crop metadata before sending focus and metering requests; temporary focus EV writes an additive bias on top of global EV without overwriting the persisted global value; long press requests an AF/AE lock surface while non-`A/A` exposure states preserve the user's exposure intent. ISO and shutter use the two-button `A/A`, `M/A`, `A/M`, and `M/M` model documented in `CameraControlsDesign.md`; MF exposes a 0...1 lens-position strip plus an always-on focus-only tap assist through the same Runtime boundary. The assist waits for request-local AF settling, then locks `currentLensPosition` inside the same serialized MF transport; the shutter remains disabled until the locked readback is honest. `CameraExposureControlState` owns the PRO exposure-priority model, `meter baseline`, `pending meter sample`, EV recalculation, read-only `Meter`, stale generation/device/signature rejection, and risk-zone ranges, but is used only while PRO is active. `CameraManualControlReadbackSnapshot` and Debug-only overlay strings provide readback evidence without OSLog, persistence, manifest, or Photos metadata. `Focus Magnifier` remains a Debug setting controlling only loupe visibility/duration; tap assist is no longer a setting. ISO/shutter/focus drafts are remembered per active control device during the current app lifecycle without UserDefaults/AppStorage persistence. The exposure plan deliberately adds no standalone re-meter control; only legal focus-driven metering triggers update the `meter baseline` or read-only `Meter` input. PRO uses `unavailable / standard / activating / active / deactivating / failed`; all PRO and rear/front session transitions use frosted last-frame UI and block interactions until ready. Front temporarily suspends rear PRO intent. Startup policy is `Default Off / Default On / Remember Last State`, with safe Standard fallback. Device limitations are recorded in [CameraManualControlDeviceLimits.md](CameraManualControlDeviceLimits.md), and the runtime product boundary in [CameraProControlsBuildIsolationPlan.md](CameraProControlsBuildIsolationPlan.md). Remaining work is physical camera-control validation, formula-sign confirmation, UX tuning for AF completion metering/risk-zone thresholds, broader device-matrix evidence, and rendered transition/UI regression evidence. |
| Adjustable image format and quality | HEIC/JPG format selection is implemented through reviewed Release profiles and a Settings picker, with HEIC still the default and no hidden fallback. Settings also exposes `Speed` / `Balanced` / `Quality` photo prioritization tiers; Runtime resolves them into the selected TAP depth-photo profile, records the manifest quality string, and persists the pending-record quality so signing/export validates the same profile later. Runtime now chooses the largest standard supported still-photo dimensions for the selected camera/format. Live Photo adds a narrow v2/v3 paired-MOV extension, while TAP Video has a separate MP4/KLV/manifest/signing/playback contract. Remaining work is RAW/ProRAW, arbitrary non-TAP video formats, 24 MP deferred photo delivery, real-device Live Photo/TAP Video evidence, real-device quality evidence, and UI regression coverage. |
| Analysis scoring | `DepthAnalysisScoreSummary` now provides a local 0-100 analysis score from valid-depth coverage, manifest depth quality/accuracy, and calibration availability. No Depth has a fixed low score and visible analysis message. Remaining work is score calibration against real-device captures, product placement outside the DEBUG metadata HUD, and any scoring dimensions that depend on future video/Live Photo/RAW outputs. |
| App Intents score surface | `TAPCamAppIntents` exposes the smallest first system surface: `OpenTAPCameraIntent` uses a fixed destination enum plus a short-lived `TAPCamIntentHandoff` to open Camera or TAP Library through `CameraRouteStore`, `ShowLatestCaptureScoreIntent` returns the latest public-safe capture score inline, `ShowCaptureScoreIntent` can show a selected `CaptureScoreEntity`, and `CaptureScoreEntity`/`CaptureScoreQuery` use HMAC-style tokens instead of raw capture IDs while suggesting the five most recent scores. Remaining work is real Shortcuts/Siri invocation evidence, widget/control reuse decisions, and richer calibrated score history UI once the product scoring model is calibrated. |
| TAP Video capture | Implemented capture mode, synchronized RGB/audio/depth callbacks, bounded KLV metadata encoding, MP4 manifest/proof validation, pending/export/readback, Library poster, and local foreground-only RAW/2D playback. AirPlay, PiP, and background playback are intentionally unsupported. Automated regression, performance profiling, and broader device/format coverage are deferred to a later explicit refactor. |
| Viewfinder guides | Settings-owned `Off` / `Rule of Thirds` / `Center Cross` overlay now renders through the preview-stage boundary, independent from capture planning and exported pixels. Remaining work is rendered UI evidence and any future guide types. |
| Locked camera launch | Separate `LockedCameraCapture` extension target and real-device spike. |
| C2PA provenance | Provenance writer/verifier boundary and signing trust model. |

The accepted first-stage camera controls UI decisions are captured in
[CameraControlsDesign.md](CameraControlsDesign.md). That document defines the
Dynamic Island shoulder layout, Flash/Live/Spacer/PRO top toolbar, always-visible
Standard Basic EV, PRO-only lower parameter toolbar, mode selector bar,
Standard-only FOV selector bar, ticked adjustment
strip, rotation rules, global and temporary EV behavior, AF/MF gestures,
TAPCam-owned metering state, ISO/shutter exposure-priority rules, Debug-only LiDAR Focus Assist, no-depth fallback
behavior, Settings-owned guide and format controls, and the main-app-only
screen-awake boundary.

The professional manual-control device-limit decision is captured in
[CameraManualControlDeviceLimits.md](CameraManualControlDeviceLimits.md). It
keeps the current one-device iPhone 15 Pro evidence scoped, explains why missing
ISO/shutter/MF support on the tested Triple Camera path is an Apple active-device
capability limit, fixes PRO v1 to an eligible LiDAR 24mm / 1x photo path, and
keeps true source switching in the future roadmap.

The Standard versus Photographer Mode runtime split is captured in
[CameraProControlsBuildIsolationPlan.md](CameraProControlsBuildIsolationPlan.md).
It keeps Standard on the original non-LiDAR path with Basic EV and the lens
selector, enables the full professional surface only for eligible rear LiDAR,
defines frosted asynchronous transitions and front-camera suspension, and makes
the startup preference independent from actual session readiness.

## Security Notes From Audit

- Pending photo artifacts and thumbnails should use an explicit protection class
  unless post-lock processing is deliberately required.
- Thumbnail caches use protected app-private cache writes and hashed filenames
  through `DepthAlbumThumbnailPipeline`; they still need a retention and purge
  story because they are derived from private photos.
- App Attest dependency updates are pinned to the current reviewed revision;
  advance the revision only after reviewing upstream changes.
- App Attest entitlement configuration is visible in `TAPCamDemo.entitlements`;
  real-device/backend acceptance remains an attended validation step.
- Pending signing must fail instead of exporting when the queue record
  `captureID` and embedded TAP manifest `payload.id` do not match.
- Pending bundle capture IDs must remain ASCII, non-hidden directory names.
  Future import, repair, or migration work must not reintroduce leading-dot
  bundle names or Unicode path semantics that the bundle enumerator may skip or
  interpret differently across filesystems.
- Pending queue records should not retain a second precise GPS copy after
  Photos export succeeds. Keep location long enough for
  `PhotoLibraryWriter.saveDepthPhoto`, then persist the exported record without
  latitude or longitude.
- For configurable formats, keep
  `TAPCaptureProvenanceWriter.validateSignedExportPhoto` as the final Photos
  gate. It checks manifest id, proof presence, proof digest binding, Release
  output facts, auxiliary depth, and actual HEIC/JPG source type immediately
  before Photos save. Remaining evidence work is positive real-depth HEIC/JPG
  fixtures plus attended real-device Photos/App Attest acceptance.

## Future Output Profile Checklist

Before any UI exposes image format or quality controls, the implementation must:

- Add a new `CaptureOutputProfileCatalog` entry instead of mutating
  `releasePhotoDepthHEIC` or `releasePhotoDepthJPEG` into a multi-format
  fallback.
- Add or update a `CaptureOutputProfileSelectionIntent` path so UI can only
  select a reviewed catalog profile and fails closed when the profile is
  missing or invalid.
- Add or reuse a `CapturePhotoQualityPolicy` so product quality intent is named
  before Runtime maps it to AVFoundation prioritization.
- Add container and codec policy for the new output type.
- Add or update the `CaptureOutputResourcePlan` so the resource set is explicit
  before packaging or signing code changes.
- Add contract violations that reject invalid depth, quality, codec, or
  container combinations before Runtime settings are created.
- State whether the TAP manifest schema changes, and how a verifier reads the
  new output facts.
- State whether App Attest signing and `CaptureContentDigest` cover one TAP
  depth photo file, multiple resources, RAW data, Live Photo resources, or video
  resources.
- State whether `PhotoLibraryWriter` and Depth Analysis can read the new
  artifact, or deliberately reject it.
- Add tests before exposing UI.

The current visible quality picker maps to AVFoundation
`photoQualityPrioritization`. It is not a file-size, compression-ratio,
resolution, or visual-quality guarantee, and it is not evidence that real-device
visual quality has been accepted.

## Current Platform Checks

- Local SDK checked: iPhoneOS 26.5 exposes `LockedCameraCapture` as an iOS 18+
  extension framework.
- Xcode Documentation Search checked: `AVCapturePhotoSettings` supports per-shot
  `photoQualityPrioritization`; `AVCapturePhotoOutput.maxPhotoQualityPrioritization`
  must be configured high enough before requesting `.quality`.
- C2PA remains future provenance work, not proof that a captured scene is true.
