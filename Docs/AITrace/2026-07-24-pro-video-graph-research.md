# PRO Video Graph Research Trace

## Shared Goal

Turn the agreed PRO Video direction into an auditable research contract and add
the smallest Debug-only code needed to collect physical-device graph evidence.
Do not ship PRO Video or weaken the existing Photographer Mode v1 photo-only
Release boundary.

The controlling engineering plan is
[../ProVideoResearchPlan.md](../ProVideoResearchPlan.md).

## User Constraints

- Standard mode keeps its original path and never opts into LiDAR.
- Only Photographer / PRO mode may select rear LiDAR.
- PRO remains fixed at 24mm / 1x with no lens selector.
- PRO/front transitions keep the frosted presentation and suspended rear intent.
- Front MF remains excluded because earlier custom lens-position experiments
  could black-screen or freeze.
- Trace and formal documentation precede product implementation.
- The first code is research instrumentation, not an implicit Release launch.

## Decision

The first probe does not pre-emptively redesign the graph. It enables the
existing TAP Video warmup only after rear PRO is active, so the device can
answer whether the current PRO Photo + MF loupe graph can also add recording
RGB, required video Depth, and optional audio outputs.

This is intentionally diagnostic:

- success provides a baseline for repeated warmup/record/teardown testing;
- `canAddOutput` failure identifies the exact graph stage;
- frame/drop evidence determines whether a successful graph is sustainable;
- failure or unacceptable drops trigger the preferred single-recording-RGB
  fan-out design described in the research plan.

## Code Changes

- `CameraProVideoResearchPreferences` owns one stable preference key whose
  default is off.
- Debug Settings exposes `PRO Video Graph Probe` with explicit non-product copy.
- `CameraView` resolves the preference to `false` outside `DEBUG`, preserves the
  normal PRO/VIDEO rejection in Release, and automatically returns to PHOTO
  when research warmup fails.
- `CameraViewModel.prepareVideoModeIfNeeded()` now returns its actual warmup
  outcome so the research UI does not claim VIDEO readiness after failure.
- `CaptureSessionController` emits staged graph snapshots including active
  formats, output counts, MF-output presence, and `canAddOutput` results.
- `TAPVideoPerformanceTrace` owns stable PRO-research and first-RGB-format
  signposts.
- `TAPVideoRecorderDiagnostics` reports the delivered first RGB buffer
  dimensions and pixel format, complementing the existing first Depth sample
  diagnostic.
- `TAPDiagnosticsOSLogPrivacyTests` now reviews the new graph scalar labels and
  includes `CameraManualFocusPreviewStream` in its complete logging-file list.
  The loupe renderer failure path passes the concrete error directly through
  `TAPDiagnostics.describe(error)` instead of logging an intermediate string.

No plugin, skill, or subagent was used. The work was performed against the
current `codex/pro-mode` checkout and its existing AVFoundation/runtime seams.

## Release Isolation

The persisted preference is not authority. `CameraView` has a compile-time
`#if DEBUG` resolver and returns `false` in Release. The normal
`Video is unavailable in PRO mode` branch remains the default product path.

The probe does not change:

- Photographer Mode eligibility;
- Standard camera selection;
- front-camera manual-focus gating;
- TAP Video requirement for nonzero stored Depth samples;
- signed video manifest schema;
- camera startup preference behavior.

## Validation

Automated validation:

- The first requested Simulator destination, `iPhone 17`, was not installed.
  Xcode reported the available destination as `iPhone 17 Pro`, iOS 26.5; no
  source change was made for that environment-only failure.
- `xcodebuild build-for-testing` for `iPhone 17 Pro`, iOS 26.5 passed.
- `TAPCameraCapturePresentationTests` passed, including the default-off
  preference and Debug/Release source-boundary checks.
- `TAPCameraProModeChromeTests` and `TAPPhotographerModeRuntimeTests` passed.
- The first OSLog privacy run correctly failed because the new public scalar
  labels were not reviewed and the current MF-loupe logging file was absent
  from the complete source list. After updating the harness and typed error
  formatting, all `TAPDiagnosticsOSLogPrivacyTests` passed.
- A generic iOS Simulator Release build passed, proving the Release-false
  resolver compiles outside `DEBUG`.
- `git diff --check` passed after the code and documentation edits.

Physical-device evidence remains intentionally open. Required cycles and fields
are listed in [../ProVideoResearchPlan.md](../ProVideoResearchPlan.md).

## Score

The project score does not increase for this change. The probe improves
observability and decision quality but does not satisfy a Release feature gate
or physical-device acceptance criterion.
