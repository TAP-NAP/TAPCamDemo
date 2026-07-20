# Camera UX Stage-One Shell And Control Wiring Trace

## Goal

Implement the first reviewable camera UX shell after the product grilling pass:

- Use the agreed `CameraControlsDesign.md` layout vocabulary.
- Do not keep dual exposure-mode states; ISO, shutter, EV, and AF/MF are direct
  controls.
- Keep the Dynamic Island shoulder clean: Settings on the right shoulder, no
  persistent left-shoulder status.
- Put Flash and Live Photo in the `viewfinder top toolbar`.
- Move LiDAR Focus Assist into Settings.
- Keep the `PHOTO` / `VIDEO` mode selector in the `mode selector slot`; keep
  `VIDEO` visible but unavailable in this stage.
- Move guides into Settings and render the selected guide over the preview.
- Add first-stage Settings switches for EV reset, depth hints, and keep-awake.
- Keep the main-app camera screen awake only while the camera is active.
- Connect the work to the project scoring system.

This slice implements global EV bias writes, per-capture flash mode handoff,
basic tap focus, long-press AE/AF lock, and first-stage direct ISO/shutter/lens
position controls. It also implements temporary focus EV as an additive offset
on top of the global EV. It does not implement adjustable aperture,
LiDAR-assisted focus behavior, video capture, Live Photo capture, external C2PA
compatibility, or the locked-camera extension.

## User Constraints

- Shooting must not be blocked by capture trust or depth status UI.
- Trusted/depth state should not be a persistent capture-surface distraction.
- If no depth is returned, the app should still save and analyze the capture
  as a no-depth TAP capture in a later behavior slice.
- `TAP Depth verified` must not be used; capture verification and depth
  availability are separate.
- Global EV and temporary focus EV are additive.
- Pro/P-M exposure modes should not be used; ISO and shutter are direct
  controls.
- Fixed aperture should be visible as a gray read-only value.
- LiDAR Focus Assist defaults off and controls only TAP-owned assist behavior.
- LiDAR Focus Assist lives in Settings rather than the capture-surface toolbar.
- C2PA is out of scope for this implementation slice.

## AI Tool Use

- Used `build-ios-apps:ios-app-intents` for the first system-facing score and
  handoff surface: one fixed-destination open-app intent, inline latest-score
  and selected-score intents, a small capture-score entity, and app shortcuts.
- Used `build-ios-apps:swiftui-ui-patterns` for SwiftUI state, component, and
  Settings/Form guidance.
- No subagents were spawned.

## Implementation Summary

### Camera Controls Design

- Promoted `Docs/CameraControlsDesign.md` as the accepted first-stage camera
  controls UI contract.
- Linked the design contract from `Docs/FutureCameraSpecs.md`.

### Viewfinder Chrome

- Added `CameraViewfinderChromeView` for:
  - Dynamic Island right shoulder Settings button.
  - Top-toolbar flash cycle/menu.
  - Top-toolbar Live Photo entry beside flash.
- Added `CameraUXPreferences` for guide, EV reset, depth hint, keep-awake,
  LiDAR Focus Assist, flash, Live Photo, AF/MF, and mode-strip policy.
- Updated the capture surface hint to fade at the viewfinder edge instead of
  sliding from the bottom.
- Hid the system status bar so EV and Settings use the Dynamic Island shoulder
  area.

### EV And Flash Wiring

- Added global EV adjustment UI behind the left-shoulder EV control.
- Persists global EV across background return and resets it once per cold
  launch when `Reset EV on App Launch` remains enabled.
- Routes global EV changes through `CameraManualControlIntent`,
  `CaptureSessionController`, and `CameraControlService`; SwiftUI does not
  construct Runtime command plans or lock `AVCaptureDevice` directly.
- Restores continuous auto exposure, focus, and white balance when leaving
  custom exposure or MF, then reapplies the current global EV bias when needed.
- Carries the selected flash mode into `CaptureSourceContext` and
  `SingleCamPhotoSettingsFactory` so `AVCapturePhotoSettings.flashMode` is set
  when the active photo output supports the requested mode.

### Lower Toolbar Adjustment Controls

- Added `CameraAdjustmentControlView` for the first-stage lower toolbar and
  `ticked adjustment strip`.
- Renders capability-gated EV, ISO, shutter, and 0...1 lens-position controls
  when the matching toolbar button is active; unsupported controls are visible
  but disabled.
- Routes control changes through `CameraViewModel`,
  `CameraManualControlIntent`, `CaptureSessionController`, and
  `CameraControlService`.
- Extends `CameraControlCapabilitySnapshot.Focus` with
  `supportsCustomLensPosition` so devices that support locked focus but not
  explicit lens positions cannot receive unsafe 0...1 lens writes.
- Shows only relative lens position plus the camera's reported minimum focus
  distance. The SDK states lens position does not map to an exact physical
  distance and is not consistent across devices.

### Preview And Bottom Controls

- Added `CameraGuideOverlayView` and wired `CameraPreviewStageView` to render
  `Off`, `Rule of Thirds`, or `Center Cross`.
- Added preview tap handling that maps local preview taps through the visible
  crop metadata before sending an AF/AE point-of-interest request through the
  manual-control Runtime boundary.
- Added a tap-focus temporary EV rail. Dragging it writes
  `global EV + temporary focus EV` through the same Runtime exposure-bias path
  without overwriting the persisted global EV value.
- Added long-press preview handling for first-stage AE/AF lock, with a fixed
  focus indicator, persistent locked-state temporary EV rail, and nonblocking
  `AE/AF LOCK` hint.
- Updated `CameraCaptureControlsView` to keep the shutter row raised and render
  a mode strip in the `mode selector slot`, with `VIDEO` greyed out and
  non-entering. The `mode selector bar` and its `PHOTO` / `VIDEO` text do not
  rotate when the device rotates.

### App Intents Score Surface

- Added `TAPCamAppIntents.swift` with a minimal first App Intents pass:
  `OpenTAPCameraIntent`, `ShowLatestCaptureScoreIntent`,
  `ShowCaptureScoreIntent`, `CaptureScoreEntity`, `CaptureScoreQuery`, and
  `TAPCamAppShortcuts`.
- Keeps the open-app route narrow: `OpenTAPCameraIntent` uses a fixed
  `TAPCamIntentDestination` enum for `Camera` or `TAP Library`, stores one
  short-lived `TAPCamIntentHandoff`, and lets `CameraView` consume that handoff
  through `CameraRouteStore` instead of exposing raw route identifiers.
- Keeps the inline score action narrow: `ShowLatestCaptureScoreIntent` reads
  the latest pending/exported record through `CaptureScoreIntentService` and
  returns a public-safe dialog.
- Adds `ShowCaptureScoreIntent` for entity-backed selection in Shortcuts. If no
  entity is selected, it falls back to the latest score; otherwise it returns
  the selected `CaptureScoreEntity` dialog without opening the app.
- Uses `CameraRouteFileContextStore` HMAC-style tokens for
  `CaptureScoreEntity.id`, so AppEntity identifiers do not expose raw
  capture IDs.
- `CaptureScoreQuery` suggests the five most recent score entities only.

### Settings And Lifecycle

- Added Settings rows for `Guides`, `Keep Screen Awake`, `Reset EV on App
  Launch`, `LiDAR Focus Assist`, and `Depth Availability Hints`.
- Moved the keep-awake policy into `CameraViewLifecycleModifier` so
  `CameraView` does not regain lifecycle side-effect hooks.
- Added `CameraIdleTimerPolicy` so tests can prove the app only disables system
  idle sleep while the camera is visible, active, and not covered by Settings
  or TAP Library.

### Scoring

- Added a Camera UX stage-one shell review path to `Docs/ProjectScorecard.md`.
- Added the first analysis-side `DepthAnalysisScoreSummary` scoring boundary.
  It scores loaded depth inputs from valid-depth coverage, manifest
  quality/accuracy, and calibration availability, and gives No Depth a fixed
  low score without surfacing identifiers.
- Updated the professional-camera subscore from `4.1 / 10` to `6.0 / 10`.
- Kept the overall project score at `9.0 / 10` because this slice does not yet
  prove rendered UI behavior, physical camera-control acceptance evidence, or
  the remaining video/Live Photo/locked-camera scope. The scoring model is also
  not yet calibrated against real-device capture sets.

## Reading Entry For This Change

1. `Docs/CameraControlsDesign.md`
2. `TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift`
3. `TAPCamDemo/CameraCapture/UI/CameraViewfinderChromeView.swift`
4. `TAPCamDemo/CameraCapture/UI/CameraPreviewStageView.swift`
5. `TAPCamDemo/CameraCapture/UI/CameraGuideOverlayView.swift`
6. `TAPCamDemo/CameraCapture/UI/FocalLengthSelectorView.swift`
7. `TAPCamDemo/CameraCapture/UI/CameraAdjustmentControlView.swift`
8. `TAPCamDemo/CameraCapture/UI/CameraCaptureControlsView.swift`
9. `TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift`
10. `TAPCamDemo/App/TAPCamAppIntents.swift`
11. `TAPCamDemo/App/TAPCamIntentHandoff.swift`
12. `TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift`
13. `TAPCamDemoTests/TAPCameraCapturePresentationTests.swift`
14. `TAPCamDemo/DepthAnalysis/DepthAnalysisMetadataHUD.swift`
15. `TAPCamDemoTests/TAPDepthAnalysisPresentationTests.swift`
16. `Docs/ProjectScorecard.md`

## Plan Score

Score for this implementation slice: **9.0 / 10**.

What is strong:

- The agreed camera layout now has code and documentation anchors.
- Global EV writes through the existing manual-control Runtime boundary.
- Flash mode now reaches per-shot `AVCapturePhotoSettings` when supported.
- Leaving custom exposure or MF restores Auto exposure/focus behavior.
- Basic tap focus sends AF/AE point-of-interest requests through
  `CameraManualControlIntent` and `CameraControlService`.
- Temporary focus EV is additive with global EV and does not mutate the
  persisted global EV setting.
- Long press requests AE/AF lock through the same Runtime boundary and keeps
  the temporary EV rail visible beside the locked focus indicator.
- The lower toolbar now renders first-stage ISO, shutter, and lens-position
  controls and applies supported values through the existing manual-control
  Runtime boundary.
- Custom lens position support is capability-gated separately from generic
  locked-focus support.
- Settings owns guides and first-stage camera preferences.
- The keep-awake behavior has a pure policy test and stays out of Settings,
  TAP Library, and background scene states.
- Disabled future modes are visible without entering unfinished flows.
- The scorecard now has a review path for this camera UX slice.
- The first local analysis score has model coverage and public-safe visible
  text constraints.
- The App Intents pass exposes one fixed-destination open-app action, one inline
  latest-score action, one selected-score action, and one narrow capture-score
  entity instead of mirroring the app navigation tree.
- App Intents metadata extraction and focused presentation tests pass on the
  current simulator.
- The latest detail iteration score is **9.1 / 10**. It fixed the agreed
  mode-selector rotation behavior, retained EV adjustment after AE/AF lock, and
  added a short-lived App Intent handoff path without widening the system-facing
  model.
- The selected-score App Intents iteration score is **9.2 / 10**. It moves from
  latest-only score lookup to entity-backed recent-score selection while keeping
  raw capture, asset, file, photo-byte, proof, and key material out of the
  system-facing model.

Why it is not higher:

- LiDAR Focus Assist is only a Settings preference; no focus strategy is wired.
- The scoring model is a local heuristic, not calibrated product scoring.
- App Intents have compile/test evidence, but not real Shortcuts/Siri invocation
  evidence.
- No rendered UI automation or physical camera-control acceptance evidence was
  added in this slice.

Current project score after this App Intents iteration:

- Professional camera capabilities: **6.1 / 10**.
- Overall weighted score: **9.0 / 10**.

The project score stays at 9.0 after rounding. The latest-score intent,
selected-score intent, and fixed-destination open handoff improve
discoverability and route clarity, but they do not resolve production App
Attest/backend acceptance, physical
camera-control evidence, Shortcuts/Siri runtime evidence, score calibration, or
rendered UI regression evidence.

## Validation

- `git diff --check` passed.
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -derivedDataPath /private/tmp/TAPCamDemoControlsDesignTests`
  passed after adding the App Intents score surface, fixing App Shortcut
  phrases, deleting the old camera UX planning document, documenting FOV
  selector behavior in `CameraControlsDesign.md`, removing the visible slider
  rail from the ticked adjustment strip, adding the fixed-destination App Intent
  handoff, locking the mode selector bar against rotation, and keeping the EV
  rail visible after AE/AF lock. A later run of the same command passed after
  adding `ShowCaptureScoreIntent` and
  `captureScoreQuerySuggestsRecentPublicSafeEntities`. These runs also exercised
  App Intents metadata extraction for the app target.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoCameraUXFeatureBuildQuiet`
  passed.
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoCameraUXStageOneTest`
  was attempted, but Xcode could not use Simulator devices because the installed
  CoreSimulator framework is out of date: current `1051.54.0`, required
  `1051.55.0`. Xcode also requires a concrete simulator device for running
  tests, so this command did not execute the focused tests.
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoCameraUXStageOneBuild`
  passed. The command still printed the same CoreSimulator version warning while
  building for generic iOS, but the test build succeeded.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoCameraUXFocusBuild`
  passed after adding tap focus and AE/AF lock.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoCameraUXFinalBuild`
  passed after the final documentation and scorecard synchronization.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=00008130-001A4CEE26D0001C -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoDeviceBuild`
  passed on the connected iPhone 15 Pro `harold_android`.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=00008130-001A4CEE26D0001C -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPCameraControlServiceTests '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/cameraUISmokeTestAnchorsStayExplicit()' '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/foregroundCameraRouteRestoreDisablesNavigationAnimation()' -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoDeviceBuild`
  passed on the connected iPhone 15 Pro after skipping two host-only
  source-inspection tests that cannot read checkout source files from the device
  XCTest process.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoProManualBuild`
  passed after adding the Pro manual control surface.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=00008130-001A4CEE26D0001C -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPCameraManualControlIntentTests -only-testing:TAPCamDemoTests/TAPCameraControlServiceTests '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/cameraUISmokeTestAnchorsStayExplicit()' '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/foregroundCameraRouteRestoreDisablesNavigationAnimation()' -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoDeviceBuild`
  passed on the connected iPhone 15 Pro.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoTemporaryEVBuild`
  passed after adding tap-focus temporary EV.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=00008130-001A4CEE26D0001C -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPCameraManualControlIntentTests -only-testing:TAPCamDemoTests/TAPCameraControlServiceTests '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/cameraUISmokeTestAnchorsStayExplicit()' '-skip-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/foregroundCameraRouteRestoreDisablesNavigationAnimation()' -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoDeviceBuild`
  passed on the connected iPhone 15 Pro after temporary focus EV.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoNoDepthBuild`
  passed after adding No Depth output state.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath /private/tmp/TAPCamDemoNoDepthBuild -skip-testing:TAPCamDemoUITests -only-testing:TAPCamDemoTests/TAPSignedExportValidatorTests -only-testing:TAPCamDemoTests/TAPDepthAnalysisInputTests`
  passed on the iOS 26.5 iPhone 17 Pro simulator after adding No Depth signing,
  export validation, and analysis entry behavior.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath /private/tmp/TAPCamDemoNoDepthBuild -skip-testing:TAPCamDemoUITests -only-testing:TAPCamDemoTests/TAPDepthAnalysisPresentationTests`
  passed after adding the local analysis score model.
- `xcodebuild test -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath /private/tmp/TAPCamDemoNoDepthBuild -skip-testing:TAPCamDemoUITests -only-testing:TAPCamDemoTests/TAPDepthAnalysisInputTests`
  passed after updating No Depth score copy.
- A later physical-device focused test run after adding tap-focus temporary EV
  was attempted, but Xcode stopped at destination preflight because the
  connected iPhone was locked: `Unlock harold_android to Continue`. The run was
  interrupted before focused tests executed.

## Open Follow-Ups

- Add Pro manual-control persistence policy, if product wants Pro values to
  survive camera/FOV changes within the same app lifetime.
- Design and validate TAP-owned LiDAR Focus Assist behavior on real hardware,
  especially through glass.
- Add rendered UI regression screenshots for the new camera chrome and mode
  strip.
