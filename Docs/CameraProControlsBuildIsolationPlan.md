# Camera Pro Controls Build Isolation Plan

This document records the build-boundary plan for Basic EV and experimental
professional camera controls.

The goal is not to hide unfinished controls at runtime. The goal is to keep the
ordinary product build lightweight by not compiling professional camera-control
state machines, UI orchestration, readback, or debug surfaces unless a dedicated
experimental compilation condition is enabled.

## Compilation Modes

| Build mode | Compilation condition | Compiled camera-control surface |
| --- | --- | --- |
| Ordinary product path | `TAP_ENABLE_PRO_CAMERA_CONTROLS` is not defined | Basic EV only. No Pro Controls UI or professional exposure/focus state machines. |
| Pro camera controls experiment | `DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS` | Pro Controls module. Basic EV entry is not compiled. |
| Invalid product build | `!DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS` | Build must fail. |

There is no runtime `Pro Controls` toggle in Settings. The choice is a compile
time boundary, not a user setting and not a hidden Debug setting.

## Required Build Guard

Add one small always-compiled guard to the main app target:

```swift
#if !DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS
#error("TAP_ENABLE_PRO_CAMERA_CONTROLS must not be enabled in Release builds.")
#endif
```

The guard must live outside the Pro Controls module. If it lives inside files
that are themselves removed from the target or hidden behind Pro-only `#if`
blocks, the protection can be bypassed accidentally.

## Ordinary Product Path: Basic EV

When `TAP_ENABLE_PRO_CAMERA_CONTROLS` is not defined, the app compiles a small
Basic EV module.

Basic EV owns:

- A persistent Face ID / Dynamic Island left-shoulder EV entry.
- A compact current-value display on that entry.
- The active visual state when the EV strip is open.
- The same `mode selector slot` replacement behavior as the current EV strip.
- EV value range, step, default, reset-on-launch policy, and persistence.
- A narrow Runtime write path that only writes exposure target bias.

Basic EV does not:

- Read, calculate, or write ISO.
- Read, calculate, or write shutter duration.
- Enter custom exposure.
- Change focus mode.
- Compile `CameraExposureControlState`.
- Compile Meter, risk-zone, pending-meter-sample, ISO/S priority, or M/M logic.
- Compile Pro readback or Pro debug overlay lines.
- Write App Intents, TAP manifest, Photos metadata, or pending-record schema.

UI behavior:

- The lower toolbar EV button is not present in the ordinary product path.
- The Face ID left-shoulder EV entry is always visible while the camera chrome is
  visible.
- The left-shoulder EV entry follows the Apple Camera-style lightweight text
  treatment: one compact line for `EV` plus the current value, no visible
  background, no border, no capsule/card/chip shape, no shadow/material, and no
  pressed-state highlight. The hit region may remain larger than the visible
  text through a fixed frame or transparent content shape.
- Non-zero EV is communicated by the compact value itself. Any future emphasis
  must stay text-only, such as a subdued tint or weight change.
- The open-strip active state may use text tint only; it must not add a
  background, outline, or separate selection pill.
- Tapping the entry opens the Basic EV strip in the `mode selector slot`.
- Tapping the entry again closes the strip and restores the `mode selector bar`.
- Shutter, Flash, Live Photo, and preview-only zoom do not automatically close
  the Basic EV strip.
- Opening Settings, leaving the camera, or lifecycle teardown closes the strip.
- Closing the strip does not reset EV; the value remains active until the user
  changes it or the launch reset policy applies.

## Pro Camera Controls Path

When `DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS` is defined, the Basic EV entry is
not compiled. The Pro Controls module owns its own exposure and focus control
surface.

The Pro module may compile:

- Lower toolbar EV/ISO/S/AFMF/aperture entries.
- Pro EV/Meter UI.
- `CameraExposureControlState`.
- ISO priority, shutter priority, and manual exposure state machines.
- Meter baseline, pending meter sample, risk-zone, and readback debug state.
- MF lens-position strip and focus-only tap assist orchestration.

The Pro module remains Debug-only experimental work. It must not enter Release
builds.

## Allowed Shared Code

The ordinary Basic EV path and the Pro Controls path may share small primitives
only when those primitives do not depend on Pro business state.

Allowed shared code:

- Ticked adjustment strip UI primitive.
- Value cursor and tick rendering.
- EV constants such as minimum, maximum, step, and default.
- Small value-range limiting helpers.
- Small display-format helpers.
- Minimal AVFoundation exposure-bias writer, if it stays unaware of ISO, shutter,
  focus, Meter, readback, and Pro state machines.

Not allowed as shared dependencies for Basic EV:

- `CameraExposureControlState`.
- `CameraAdjustmentControlState` while it includes ISO/S/focus/aperture.
- Pro lower-toolbar control enums.
- Meter, risk-zone, pending-meter-sample, readback, or A/A-M/A-A/M-M/M models.
- Any module whose change for Basic EV would affect Pro Controls behavior or
  vice versa.

## Implementation Plan

1. Add the Release fail-build guard for `TAP_ENABLE_PRO_CAMERA_CONTROLS`.
2. Extract the ticked adjustment strip into a business-agnostic UI primitive if
   the current implementation still references Pro control state.
3. Create the Basic EV module with its own state, persistence, launch reset, UI
   entry, strip orchestration, and exposure-bias write path.
4. Move Pro-only UI, state machines, readback, and debug lines behind
   `#if TAP_ENABLE_PRO_CAMERA_CONTROLS`.
5. Ensure the Basic EV module is excluded when
   `TAP_ENABLE_PRO_CAMERA_CONTROLS` is defined.
6. Add source-inspection tests that protect the build boundary.
7. Add focused UI-state tests for Basic EV strip open/close, persistence, reset,
   compact value display, and lifecycle clearing.
8. Validate real-device EV direction and responsiveness after code changes.

## Implementation Status

The first build-boundary implementation is in place:

- `CameraProControlsBuildGuard.swift` owns the always-compiled Release fail-build
  guard.
- `CameraBasicEVControlView.swift` owns the ordinary-product Basic EV state,
  Face ID left-shoulder entry, compact value, and EV strip.
- `CameraTickedSliderRow.swift` is the shared business-agnostic ticked strip
  primitive.
- `CameraView`, `CameraCaptureControlsView`, and `CameraViewfinderChromeView`
  compile either the ordinary Basic EV surface or the Pro Controls surface.
- `CameraExposureControlState`, `CameraManualControlReadbackSnapshot`, Pro
  toolbar UI, Pro readback, and Pro debug manual-control lines are behind
  `TAP_ENABLE_PRO_CAMERA_CONTROLS`.
- The ordinary Basic EV write path calls the Runtime exposure-target-bias writer
  directly and does not create a professional exposure state machine result.

Validation recorded for this implementation:

- Ordinary build: `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj
  -scheme TAPCamDemo -destination generic/platform=iOS\ Simulator
  -derivedDataPath /private/tmp/TAPCamDemoDerivedData`
- Ordinary focused tests: `xcodebuild test-without-building -project
  TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination
  id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath
  /private/tmp/TAPCamDemoDerivedData
  -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests`
- Pro build: `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj
  -scheme TAPCamDemo -destination generic/platform=iOS\ Simulator
  -derivedDataPath /private/tmp/TAPCamDemoProDerivedData
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG\ TAP_ENABLE_PRO_CAMERA_CONTROLS`
- Pro focused tests: `xcodebuild test-without-building -project
  TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination
  id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath
  /private/tmp/TAPCamDemoProDerivedData
  -only-testing:TAPCamDemoTests/TAPCameraExposureControlStateTests`

## Acceptance Criteria

- Ordinary product build does not compile Pro Controls UI.
- Ordinary product build does not compile professional exposure/focus state
  machines.
- Ordinary product build still supports Basic EV.
- Basic EV writes exposure target bias only.
- Basic EV never reads or writes ISO or shutter duration.
- Pro Controls build does not compile the Basic EV entry.
- Release build fails if `TAP_ENABLE_PRO_CAMERA_CONTROLS` is defined.
- No App Intents, manifest schema, Photos metadata, or pending-record schema
  changes are introduced for Basic EV.
