# TAP Library Scroll Memory Trace

## Shared Goal

Implement the TAP Library browsing journey without creating a second route
system:

- Returning from a selected photo's analysis page restores the same in-session
  TAP Library scroll neighborhood with a two-row correction for the observed
  return offset.
- Returning from analysis does not cold-reload the TAP Library snapshot merely
  because the picker appears again.
- Every fresh TAP Library entry from Camera starts at the top of the grid.
- Returning from TAP Library to Camera clears that precise offset naturally with
  the picker view.
- Signed pending captures do not scan every Photos asset before their first
  export; full Photos asset recovery is reserved for interrupted `.exporting`
  records.
- Camera still defaults to the capture surface on a fresh route.
- Foreground return can force Camera only after more than 10 seconds away, and
  only when the user enables the Settings preference.

## User Constraints

- Keep purpose-specific code in the purpose-specific owner.
- Do not store exact scroll offsets in durable route context.
- Keep `CameraRouteStore` and `CameraRouteContextStore` focused on route state
  and tokenized item-anchor fallback.
- Use cached in-view album snapshots for back navigation; explicit TAP Library
  change notifications still refresh the snapshot.
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
- Returning to the picker restores that local offset, adjusted by two grid rows
  in the same direction as SwiftUI's `contentOffset.y` correction, so the user
  lands near the previous browsing context rather than compounding the observed
  two-row drift.
- Fresh TAP Library entries do not consume route anchors for scroll restoration;
  new entries start at the top. Route anchors remain tokenized context, not a
  fresh-entry scroll command.
- `DepthAlbumPickerViewModel.loadIfNeeded()` reuses the already attempted album
  snapshot when the picker appears again after analysis-page back navigation,
  including non-empty, empty, and failed first-load states.
- TAP Library change notifications still call `scheduleRefresh()`, but item-list
  refreshes no longer consume the pending precise return offset while analysis is
  still presented.
- `TAPPendingCaptureProcessingPolicy` prioritizes `.signed` / `.exporting` work
  ahead of fresh `.pending` / `.signing` work so already signed captures do not
  wait behind newer signing candidates.
- `PhotoLibraryPendingCaptureExporter` skips the expensive
  `PhotoLibraryWriter.depthAssetIdentifier` full-album scan for normal `.signed`
  first export. It only runs that recovery scan when a record is already
  `.exporting`, where the app may be recovering from an interrupted Photos save.
- `CameraRoutePreferences` owns the foreground-return preference key, default,
  and 10-second threshold.
- The Settings toggle defaults off, so users opt in before foreground return can
  force the Camera route.

## Files Changed

- `TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift`: view-local precise
  scroll memory, two-row return-offset correction, cached first load, top-start
  fresh entries, item selection route, and return restoration after detail-page
  pop.
- `TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessingPolicy.swift`: signed/export
  priority and exporting-only existing-asset recovery policy.
- `TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift`: injectable exporter
  actions and guard that avoid first-export full-album Photos scans.
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
  state versus durable route context, plus cached album snapshot behavior.
- `TAPCamDemoTests/TAPLibraryStorageTests.swift`: queue priority and
  exporting-only recovery policy tests.
- `TAPCamDemoTests/TAPLibraryProcessingTests.swift`: signed/export-first
  processor ordering expectation plus behavior tests for first-export scan
  skipping and interrupted-export recovery scanning.

## Plan-Specific Score Rubric

Score this plan out of 10 during review:

- 3.0: returning from analysis restores the TAP Library's precise in-session
  vertical neighborhood with the two-row correction applied in the right
  direction without item-refreshes consuming the pending return offset.
- 2.0: returning from TAP Library to Camera clears the precise offset without
  writing it to route context.
- 2.0: foreground return policy respects the 10-second threshold and the
  default-off Settings preference.
- 1.5: ownership boundaries stay readable: precise offset and album snapshot
  cache in `DepthAlbumPickerView`, route/token fallback in route stores, and
  signed/export queue policy in TAP Library.
- 1.0: tests cover lifecycle policy, preference defaults, source boundaries,
  cached album load, queue priority, and exporting-only recovery scan behavior.
- 0.5: docs and trace explain the behavior from a zero-context reading path.

## Current Plan Score

Current implementation evidence score: 9.5 / 10.

- Full credit for ownership boundaries, default-off Settings preference, lifecycle
  policy tests, source-boundary tests, cached non-empty/empty/error snapshot
  tests, fresh-entry top-start source guard, two-row correction policy test,
  queue-priority tests, behavior-level exporter scan-boundary tests, and readable
  trace/docs.
- Partial deduction remains because the exact visual scroll restoration still
  needs attended UI proof on a real album, and the Photos scan reduction still
  needs real-device log confirmation under a large album.

## Validation Run

- `git diff --check`
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator'`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryProcessingTests -only-testing:TAPCamDemoTests/TAPLibraryStorageTests -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryProcessingTests`

Latest follow-up changes from the same conversation:

- Removed fresh-entry route-anchor scroll restoration from
  `DepthAlbumPickerView`; each new TAP Library presentation now starts at the
  top.
- Corrected the two-row return-scroll policy direction. `contentOffset.y`
  increases as the grid moves downward, so the return correction adds two grid
  rows instead of subtracting them; subtracting compounded the observed two-row
  drift into roughly four rows.

All listed checks passed.

## Remaining Evidence

- Real-device or UI-regression proof is still needed to confirm the visual scroll
  restoration under Photos permission and large-album conditions.
- Real-device log proof is still needed to confirm normal `.signed` first export
  no longer emits a long run of `originalPhotoData request start/success` before
  `export status updated`.
