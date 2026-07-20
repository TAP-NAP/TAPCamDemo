# Basic EV And Pro Controls Build Isolation Trace

## Goal

Record the grill outcome for separating ordinary product EV from experimental
professional camera controls at compile time.

## User Constraints

- Stop treating Pro Controls as a runtime setting.
- Use `TAP_ENABLE_PRO_CAMERA_CONTROLS` as the dedicated compilation condition.
- Keep ordinary product builds lightweight.
- Do not compile unused professional state machines into the ordinary product
  build.
- Basic EV and Pro Controls are separate flows, not one runtime-switched mode.
- UI primitives may be shared, but professional state machines and write
  orchestration must not leak into Basic EV.
- Release builds must fail if the Pro Controls flag is enabled.
- Do not change App Intents, metadata, manifest, or pending-record schemas.

## Decision Summary

- Ordinary builds compile Basic EV and exclude Pro Controls.
- Pro experimental builds require `DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS`.
- Pro experimental builds exclude the Basic EV entry.
- There is no Debug Settings `Pro Controls` toggle.
- Basic EV owns its own Face ID left-shoulder entry, compact value display,
  strip behavior, persistence, launch reset, and exposure-bias-only write path.
- The Basic EV left-shoulder entry follows an Apple Camera-style lightweight
  text treatment: compact one-line `EV` plus value, no visible background,
  border, capsule/card/chip shape, shadow/material, or pressed-state highlight.
- Open-strip active state is text tint only. Non-zero EV is communicated by the
  compact value itself unless future UX feedback justifies a text-only emphasis.
- Basic EV must not read, calculate, or write ISO or shutter duration.
- Pro Controls own the lower toolbar, ISO/S/AFMF/aperture entries, Meter,
  risk-zone, readback, and professional exposure/focus state machines.

## Files Updated

- `Docs/CameraProControlsBuildIsolationPlan.md`: new plan and acceptance
  criteria for the Basic EV versus Pro Controls build boundary, now updated with
  implementation status and validation evidence.
- `Docs/CameraControlsDesign.md`: documents Basic EV, the compile-time Pro
  Controls boundary, and the ordinary-product UI behavior.
- `Docs/CameraManualControlDeviceLimits.md`: links device capability limits to
  the separate build-isolation plan without merging the two concerns.
- `Docs/FutureCameraSpecs.md`: records build isolation as a P0 boundary and
  links the plan from the manual-control roadmap.
- `Docs/README.md`: adds the build-isolation plan to the document map.
- `Docs/AITrace/README.md`: indexes this trace.
- `CameraProControlsBuildGuard.swift`: rejects Release builds that define
  `TAP_ENABLE_PRO_CAMERA_CONTROLS`.
- `CameraBasicEVControlView.swift`: adds ordinary-product Basic EV state,
  shoulder entry, compact value, and strip.
- `CameraTickedSliderRow.swift`: adds the shared business-agnostic ticked strip
  primitive.
- `CameraView`, `CameraCaptureControlsView`, `CameraViewfinderChromeView`, and
  `CameraViewModel`: split ordinary Basic EV from Pro Controls at compile time.
- `CameraExposureControlState`, `CameraManualControlReadbackSnapshot`, Pro
  toolbar UI, Pro readback, and Pro debug manual-control lines are guarded by
  `TAP_ENABLE_PRO_CAMERA_CONTROLS`.
- Runtime adds a narrow `applyExposureTargetBias` path for Basic EV.

## Validation

Implemented and validated in both ordinary and Pro-flag configurations:

- `git diff --check`
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

## Open Follow-Ups

- Run real-device EV direction and responsiveness checks.
- Decide whether ordinary Settings should also hide manual-focus-assist related
  settings when Pro Controls are not compiled.
- Add rendered UI evidence for the Basic EV shoulder entry and strip.
