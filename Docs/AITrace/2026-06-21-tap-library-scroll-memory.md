# TAP Library Scroll Memory Trace

## Shared Goal

Implement the TAP Library browsing journey without creating a second route
system:

- Returning from a selected photo's analysis page restores the same in-session
  TAP Library scroll offset.
- Returning from TAP Library to Camera clears that precise offset naturally with
  the picker view.
- Camera still defaults to the capture surface on a fresh route.
- Foreground return can force Camera only after more than 10 seconds away, and
  only when the user enables the Settings preference.

## User Constraints

- Keep purpose-specific code in the purpose-specific owner.
- Do not store exact scroll offsets in durable route context.
- Keep `CameraRouteStore` and `CameraRouteContextStore` focused on route state
  and tokenized item-anchor fallback.
- Add a trace so reviewers can see how AI-assisted work changed the project.
- Score this plan directly, rather than treating the global project score as the
  main acceptance metric.

## AI Tooling

- Main agent used the iOS SwiftUI UI patterns skill for state ownership and
  SwiftUI-native scroll guidance.
- Main agent consulted the Codex Security diff-scan skill for a scoped final
  review of the changed code paths. No full multi-phase security scan or
  subagents were opened for this implementation turn.
- No security plugin write actions were needed because this change does not add
  network, filesystem, raw Photos identifier, capture identifier, or HEIC/proof
  data persistence paths.

## Implementation Decisions

- `DepthAlbumPickerView` owns the precise in-session scroll offset with local
  `@State` and SwiftUI `ScrollPosition`.
- `onScrollGeometryChange` records the current vertical content offset while the
  picker is visible.
- Tapping an item captures the current offset before navigation into
  `DepthAnalysisView`.
- Returning to the picker restores the precise offset first; the existing route
  anchor remains only as first-open fallback.
- `CameraRoutePreferences` owns the foreground-return preference key, default,
  and 10-second threshold.
- The Settings toggle defaults off, so users opt in before foreground return can
  force the Camera route.

## Files Changed

- `TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift`: view-local precise
  scroll memory and return restoration.
- `TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift`: explicit
  foreground route-restore policy input.
- `TAPCamDemo/CameraCapture/UI/CameraViewLifecycleModifier.swift`: background
  timestamp tracking and Settings-backed policy wiring.
- `TAPCamDemo/CameraCapture/UI/CameraRouteStore.swift`: route preference
  constants only; no precise scroll state.
- `TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift`: user toggle.
- `TAPCamDemoTests/TAPCameraCapturePresentationTests.swift`: lifecycle and
  preference tests.
- `TAPCamDemoTests/TAPLibraryRouteTests.swift`: boundary tests for local scroll
  state versus durable route context.

## Plan-Specific Score Rubric

Score this plan out of 10 during review:

- 3.0: returning from analysis restores the TAP Library's precise in-session
  vertical offset.
- 2.0: returning from TAP Library to Camera clears the precise offset without
  writing it to route context.
- 2.0: foreground return policy respects the 10-second threshold and the
  default-off Settings preference.
- 1.5: ownership boundaries stay readable: precise offset in
  `DepthAlbumPickerView`, route/token fallback in route stores.
- 1.0: tests cover lifecycle policy, preference defaults, and source boundaries.
- 0.5: docs and trace explain the behavior from a zero-context reading path.

## Current Plan Score

Current implementation evidence score: 9.0 / 10.

- Full credit for ownership boundaries, default-off Settings preference, lifecycle
  policy tests, source-boundary tests, and readable trace/docs.
- Partial deduction remains because the exact visual scroll restoration still
  needs attended UI proof on a real album.

## Validation Run

- `git diff --check`
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator'`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`

All three checks passed.

## Remaining Evidence

- Real-device or UI-regression proof is still needed to confirm the visual scroll
  restoration under Photos permission and large-album conditions.
