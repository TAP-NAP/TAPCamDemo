# TAPCamDemo

TAPCamDemo is an iPhone-only SingleCam app for photo-depth and TAP Video
capture. It resolves each supported field of view to one Apple-compatible RGB
source, depth source, active format, and depth-safe raw zoom; stages one reviewed
artifact in the private Pending Capture Queue; then signs, validates, exports,
and reads it back without blocking foreground capture.

## Documentation

[TAPCam documentation](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/README.md) covers the
[product requirements](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/ProductContract.md),
[App Attest backend interface](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/BackendContract.md), and
[Planes geometry design](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/PlanesTechnicalDesign.md).
The [interactive prototype](https://github.com/TAP-NAP/TAPCamPrototype/blob/main/README.md) illustrates screens
and user flows; its [manifest](https://github.com/TAP-NAP/TAPCamPrototype/blob/main/Prototype/manifest.json)
records visual revisions and fixtures.

Shared Still/Live/Video manifest, container, binding, proof, KLV, transport, and
verification conventions come only from the pinned
[TAPArtifactContracts index](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/CONTRACTS.md).
This repository implements those contracts; it does not restate their bytes.

The adopted optional `CALD` and `TAPCAMTELEMETRY1` extensions preserve per-frame
calibration, filtering observations and bounded device motion under the existing
content binding. Their v1 format identifiers remain unchanged.

## Runtime path

```mermaid
flowchart LR
    App["App\nsetup + route + App Attest"] --> Camera["CameraCapture\nplan + SingleCam + package"]
    Camera --> Queue["PendingCaptureQueue\nprivate pending queue"]
    Queue --> Photos["Photos\nvalidated export"]
    Photos --> Media["TAPLibrary/Media\nPhotoKit resources"]
    Queue --> Catalog["TAPLibrary/Catalog\nreconcile + publish"]
    Media --> Catalog
    Catalog --> Grid["TAPLibrary/Grid\nTAP Library screen"]
    Grid --> Viewer["TAPLibrary/Viewer\nphoto/video browsing"]
    Media --> Viewer
    Viewer --> Analysis["DepthAnalysis\ndepth maps + planes + 3D"]
```

The capture transaction is:

```text
user intent
  -> pure CameraCapture/Planning plan
  -> CameraCapture/Runtime serial AVCaptureSession configuration
  -> paired AVCapturePhoto or finalized TAP Video
  -> CameraCapture/Output unsigned reviewed artifact
  -> PendingCaptureQueue atomic pending ingest
  -> serialized App Attest proof + final-byte validation
  -> Photos save + original-resource readback validation
  -> TAPLibrary catalog / grid / photo and video browsing
  -> DepthAnalysis tools for selected depth data
```

## Implementation ownership

| Area | Owns | Start with |
| --- | --- | --- |
| `TAPCamDemo/App` | application entry and composition | `TAPCamDemoApp.swift` |
| `App/Startup` | launch routing, setup, permission checks, and initialization gates | `StartupGateView.swift`, `StartupGateCoordinator.swift` |
| `App/Attestation` | DeviceCheck credential registration, health checks, and local key handles | `AppAttestRuntimeController.swift`, `NativeAppAttestClient.swift` |
| `App/Settings` | settings presentation, language, and data-use preferences | `DepthAnalyzerSettingsView.swift`, `AppLanguage.swift` |
| `App/Intents` | system shortcuts and app-entry handoff | `TAPCamAppIntents.swift`, `TAPCamIntentHandoff.swift` |
| `CameraCapture/Planning` | pure capability, pairing, output-intent, FOV/zoom, and manual-control plans | `CapturePlan.swift`, `CapabilityMatrix.swift` |
| `CameraCapture/Runtime` | the only `AVCaptureSession` mutation, capture requests, device writes, TAP Video recording, cached capture location | `CaptureSessionController.swift`, `CapturePipeline.swift`, `TAPVideoRecorder.swift`, `LocationProvider.swift` |
| `CameraCapture/Output` | reviewed output profiles, packaging, shared-contract encoders/writers, final signed-export gates | `CaptureOutputProfile.swift`, `EmbeddedPhotoPackager.swift`, `TAPCaptureProvenanceWriter.swift` |
| `CameraCapture/UI` | Viewfinder presentation and user intent; no capture-plan or proof ownership | `CameraView.swift`, `CameraViewModel.swift` |
| `PendingCaptureQueue` | private capture ingest/storage, one serialized signing/export worker, retry, readback, cleanup | `Storage/TAPPendingCaptureStore.swift`, `Processing/TAPPendingCaptureProcessor.swift` |
| `TAPLibrary/Grid` | the TAP Library screen and item navigation | `TAPLibraryView.swift`, `TAPLibraryViewModel.swift` |
| `TAPLibrary/Catalog` | merge pending and Photos records, reconcile removed exports, observe changes, publish ordered snapshots | `LibraryMediaStore.swift`, `LibraryCatalogReconciler.swift` |
| `TAPLibrary/Media` | resource identities, originals, thumbnails, PhotoKit requests and cancellation | `LibraryMediaFetching.swift`, `PhotoKit/PhotoKitLibraryMediaFetcher.swift` |
| `TAPLibrary/Viewer` | paging/zoom, photo and video playback, Share/Delete, browsing state | `Photo/DepthAnalysisView.swift`, `Playback/TAPVideoPlaybackSession.swift` |
| `DepthAnalysis` | depth decoding/validation, heatmaps, planes, point clouds, registered video depth | `DepthAnalysisReader.swift`, `DepthAnalysisStageView.swift`, `Video/TAPVideoDepthPipeline.swift` |
| `Diagnostics` | shared logging, capture timing, and bounded video performance traces | `TAPDiagnostics.swift`, `CaptureJobMetrics.swift`, `TAPVideoPerformanceTrace.swift` |

TAP Library is the user-facing gallery; Pending Capture Queue owns unfinished
capture processing. Within TAPLibrary, Grid and Viewer consume Catalog and Media;
Viewer also uses DepthAnalysis tools. Synthetic viewer fixtures live in
`TAPLibrary/Viewer/Fixtures` and compile only in Debug builds.

## Build and validation

Choose an already Booted iPhone Simulator and use its UDID:

```sh
xcrun simctl list devices booted
```

Run the three-item TAP Video structure gate:

```sh
Scripts/lint-tap-video-refactor.sh
```

Compile the shared test products:

```sh
xcodebuild build-for-testing \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>'
```

Run deterministic unit/app-hosted tests without entering setup or camera startup:

```sh
xcodebuild test-without-building \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>' \
  -only-testing:TAPCamDemoTests
```

Use `test` instead of `test-without-building` to build and run together. Add
`-only-testing:TAPCamDemoTests/<SuiteName>` for focused work and always verify
the executed count; a successful zero-test filter is not evidence.

UI automation is separate:

```sh
xcodebuild test \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>' \
  -only-testing:TAPCamDemoUITests
```

A Simulator pass proves only the exercised deterministic or UI boundary. It
does not prove physical Camera/Photos/depth, App Attest hardware/backend,
iCloud, haptics, thermal behavior, native performance, or attended acceptance.
Use the relevant [acceptance section](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/Acceptance.md) and
record declared, executed, passed, failed, and skipped counts.

The shared extension parser vectors are mirrored in
`TAPCamDemoTests/Fixtures/tap-video-extensions-v1.json` and loaded from the test
bundle by `TAPVideoManifestTests`. Compare that file byte-for-byte with
[`examples/vectors/tap-video-extensions-v1.json`](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/examples/vectors/tap-video-extensions-v1.json)
when updating the contract pin; do not regenerate expected bytes from the parser.
