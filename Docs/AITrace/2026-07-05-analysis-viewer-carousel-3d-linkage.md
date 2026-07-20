# Analysis Viewer Carousel And 3D Linkage

Date: 2026-07-05

## Goal

Implement the agreed Analysis viewer redesign: make Analysis behave like a
native photo viewer, keep bottom chrome stable during photo switching, preload
neighboring photos, show thumbnail/progress while original assets load, and
link 2D Plane selection into the native 3D projection.

## Constraints

- Bottom controls stay visible and stable: share, `2D`, `3D`, credential,
  delete.
- Photo switching must not clear the whole screen or rebuild the toolbar.
- The main photo stays centered and aspect-fit; fit-size horizontal drag
  switches photos, zoomed drag pans the current photo.
- 2D Release UI exposes only RGB plus heatmap overlay. Mask remains internal or
  debug-only.
- 2D Plane seed selection is stored per photo and follows that photo through
  carousel navigation.
- 3D uses native iOS rendering. Release copy says `3D projection`, not point
  cloud.
- 3D initial camera follows the TAPCamVerifier capture-camera contract.
- Selected 2D Plane pixels must be visible in 3D and blink unless Reduce Motion
  is enabled.
- The renderer boundary must leave room for a future Metal replacement.

## AI Tools And References

- Used the `build-ios-apps:swiftui-ui-patterns` skill for SwiftUI state
  ownership and stable composition guidance.
- Used the TAPCamDemo Xcode validation memory skill for the local
  `build-for-testing` validation path.
- Referenced the local `/Users/harold/TAPCamVerifier/src/geometry` code for the
  capture-camera reset and intrinsics-to-projection-matrix contract. Live GitHub
  fetch did not return content in this run, so the implementation source was the
  local verifier checkout.

## Files Changed

- `TAPCamDemo/DepthAnalysis/DepthAnalysisCarouselState.swift`
  - Adds `DepthAnalysisCarouselStore`, `AnalysisPhotoSlot`, and
    `DepthAnalysisProgressivePhotoLoader`.
  - Owns `previous/current/next` slot state, thumbnail-first loading, Photos
    original progress, decoded input, and per-photo Plane request coordination.
- `TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift`
  - Replaces single `currentSource -> input = nil` reload behavior with a
    stable shell and carousel.
  - Keeps selected tool and bottom chrome alive while the current slot changes.
  - Shows slot thumbnails/progress in the main photo and tool placeholders.
  - Removes the 2D Mask segmented mode and binds Plane selection to the current
    slot.
- `TAPCamDemo/DepthAnalysis/AnalysisTools/DepthPointCloudPreview.swift`
  - Adds capture-camera projection helpers, display-oriented projection frame,
    RGB sampling, Plane highlight mask, and selected-plane SceneKit overlay.
  - Uses camera-space vertices, rotates geometry and projection intrinsics to
    the visible photo orientation, and keeps RGB sampling plus Plane membership
    in raw/native pixel space.
  - An early custom-node interaction experiment made the projected model
    disappear, so the first pass temporarily kept SceneKit interaction separate
    while projection math was stabilized.
  - A later fixed-scale interaction experiment left a root-node rotation state
    that rewrote `DepthProjectionRoot.eulerAngles` during every update, making
    the projected RGB points appear flat. That state and the reset token path
    were removed. The current renderer leaves depth projection, RGB color, and
    the custom SceneKit interaction root as separate concerns.
  - Adds a DEBUG / `TAP_ENABLE_RELEASE_DIAGNOSTICS` SceneKit probe for the
    real-device zoom-jump investigation. It logs scalar payload, viewport,
    touch, motion, camera/root transform, controller target, and projection
    matrix state without logging Photos asset identifiers or image bytes.
  - Real-device probe evidence showed that SceneKit's default camera controller
    changes `pointOfView` on touch and resets the capture-camera projection
    matrix to a default perspective matrix. It also showed one capture with
    finite `9999m` depth sentinels that pushed `targetDepth` to hundreds of
    meters. The fix keeps SceneKit as the renderer, disables default camera
    control, adds a fixed-scale one-finger rotation gesture on an interaction
    root, preserves motion parallax on the projection root, and filters
    non-renderable far-depth sentinels before building 3D payloads.
  - A follow-up real-device pass showed that the vertex dump still had real
    depth range (`sceneZ` spanning about `1.369m`) while the visual could look
    flat in capture-camera front view. The interaction pivot now matches the
    verifier's `targetDepth` model: the interaction root sits at the median
    renderable depth and the geometry root applies the inverse offset, so the
    initial view still aligns with the photo but user orbit rotates around the
    model instead of around the capture-camera origin.
  - 3D gestures are now isolated from the analysis drawer page. The SceneKit
    surface owns one-finger orbit, two-finger pan, pinch scale, two-finger roll,
    and double-tap reset. Ancestor scroll views wait for the 3D pan recognizers
    to fail, so dragging inside the model should not scroll the page.
  - Real-device validation then showed the two-finger roll direction felt
    reversed. The roll mapping was changed to subtract
    `UIRotationGestureRecognizer.rotation`, with a focused unit test covering
    the natural screen-roll direction.
- `TAPCamDemo/App/AppAttestRuntime.swift`
  - Adds a `DepthAnalysis` OSLog category for the scoped 3D projection probe.
- `TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests.swift`
  - Registers the 3D probe source file and reviewed public scalar labels so
    new diagnostics stay inside the existing privacy harness.
- `TAPCamDemo/DepthAnalysis/DepthAnalysisPanelSupport.swift`
  - Keeps only the active bottom drawer tools and removes the obsolete 2D mode
    wrapper.
- `TAPCamDemo/DepthAnalysis/DepthAnalysisAlbumContext.swift`
  - Marks the lightweight album context nonisolated for test and carousel use.
- `TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift`
  - Keeps bottom-tool coverage and adds carousel/progressive-slot coverage.
- `TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests.swift`
  - Adds projection-matrix, display-orientation, SceneKit camera-direction, RGB
    sampler, and Plane highlight-mask tests.
- `Docs/DepthAnalysisViewerRedesign.md`
  - Updates the design snapshot into an implemented contract.
- `TAPCamDemo/DepthAnalysis/README.md` and
  `TAPCamDemo/DepthAnalysis/AnalysisTools/README.md`
  - Update the module reading order and 3D geometry contract.

## Validation

- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17'`
  - Passed after fixing imports, Photos progress handler signature, pending
    store actor access, and test expectations.
- `xcodebuild build-for-testing -quiet -derivedDataPath /private/tmp/TAPCamDemoDerivedData-analysis-3d-flatfix-build -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17'`
  - Passed after removing the unverified fixed-scale interaction state. Existing
    Swift 6 captured-`self` warnings remain in `CameraViewModel.swift`.
- `xcodebuild test -quiet -derivedDataPath /private/tmp/TAPCamDemoDerivedData-analysis-3d-flatfix-test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=7BDECB99-1458-466C-BDAE-11866341537B' -only-testing:TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests -only-testing:TAPCamDemoTests/TAPDepthAnalysisPresentationTests`
  - Passed on the booted iPhone 17 simulator.
- `xcodebuild test -quiet -derivedDataPath /private/tmp/TAPCamDemoDerivedData-analysis-3d-gestures -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPDepthAnalysisPlaneRegionTests -only-testing:TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests`
  - Passed after adding 3D gesture-domain isolation, zoom clamp, pan conversion,
    interaction-root position probes, and the pivot-preserving reset contract.

## SDK Evidence

- Xcode SDK `SceneKit.framework/Headers/SCNView.h` says
  `allowsCameraControl` creates a `defaultCameraController`, handles UI events
  for the current point of view, and built-in gestures include pinch zoom,
  camera translation, and camera forward/backward movement.
- Xcode SDK `SceneKit.framework/Headers/SCNCameraController.h` exposes
  `translateInCameraSpaceByX:Y:Z:`, `dollyBy`, `dollyToTarget`, and
  `frameNodes`. The current zoom jump is therefore an interaction-camera issue,
  not evidence that depth-to-XYZ projection is missing.
- Local TAPCamVerifier `src/geometry/geometryViewer.ts` uses a capture-camera
  projection matrix with `OrbitControls.target` set to `z = -targetDepth`. The
  native SceneKit path now mirrors that target-depth pivot without importing
  the browser renderer or exposing point-cloud terminology in Release UI.

## Follow-Ups

- Attended UI validation is still required for real Photos/iCloud progress,
  gesture feel, and native 3D interaction on device or simulator.
- Attended real-device validation should verify that single-finger orbit,
  two-finger pan, pinch, roll, and double-tap reset operate inside the 3D
  surface without scrolling the analysis drawer.
- The SceneKit renderer is intentionally the v1 native path; keep Metal as the
  future replacement point for denser splats, mesh texturing, or performance.
