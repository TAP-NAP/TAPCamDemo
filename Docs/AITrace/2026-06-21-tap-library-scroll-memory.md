# TAP Library Scroll Memory Trace

## Shared Goal

Implement the TAP Library browsing journey without creating a second route
system:

- Returning from a selected photo's analysis page restores by the clicked item:
  the picker records the item identity plus its viewport position, then rebuilds
  the scroll offset from the current item list after the analysis page pops.
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

- `DepthAlbumPickerView` owns a view-local return bookmark with the clicked item
  id, route anchor, and the item's y-position inside the scroll viewport.
- Per-item `onGeometryChange` records visible item positions in the scroll
  viewport while the picker is visible.
- Tapping an item captures the clicked item's bookmark before navigation into
  `DepthAnalysisView`.
- Returning to the picker resolves the bookmark against the current item list.
  It first matches the exact item id, then falls back to matching route-anchor
  capture or Photos asset identity so a pending item can still restore after it
  becomes an owned exported item.
- The target scroll offset is computed from the current item row and the saved
  viewport y-position. Raw content offset and fixed row-count correction are no
  longer the source of truth.
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
  scroll bookmark, clicked-item viewport position tracking, cached first load,
  top-start fresh entries, item selection route, and return restoration after
  detail-page pop.
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
  vertical neighborhood by resolving the clicked-item bookmark, without
  item-refreshes consuming the pending return bookmark.
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

Current implementation evidence score: 9.6 / 10.

- Full credit for ownership boundaries, default-off Settings preference, lifecycle
  policy tests, source-boundary tests, cached non-empty/empty/error snapshot
  tests, fresh-entry top-start source guard, clicked-item bookmark restore tests,
  queue-priority tests, behavior-level exporter scan-boundary tests, and readable
  trace/docs.
- Partial deduction remains because the clicked-item bookmark still needs
  attended UI proof on a real album, and the Photos scan reduction still needs
  real-device log confirmation under a large album.

## Validation Run

- `git diff --check`
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator'`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryProcessingTests -only-testing:TAPCamDemoTests/TAPLibraryStorageTests -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryRouteTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryProcessingTests`
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=ADC347E0-6819-4898-810F-8FBBFCECE294' -only-testing:TAPCamDemoTests/TAPLibraryRouteTests` after replacing row correction with clicked-item bookmark restore.
- `git diff --check` after adding the folder-wide AI Trace scoring rule.

Latest follow-up changes from the same conversation:

- Removed fresh-entry route-anchor scroll restoration from
  `DepthAlbumPickerView`; each new TAP Library presentation now starts at the
  top.
- Replaced raw-offset plus row-count correction with a clicked-item return
  bookmark. The bookmark stores the selected item's id, route anchor, and
  viewport y-position, then computes the target offset from the current item row
  after returning from analysis.
- Added a folder-wide AI Trace rule requiring future scored-plan changes to
  record the applicable rubric, current score, and why the score changed or
  stayed the same. This process-documentation update keeps the current plan
  score at 9.6 / 10 because the remaining deductions still require real-device
  UI and Photos-scan evidence.

All listed checks passed.

## Remaining Evidence

- Real-device or UI-regression proof is still needed to confirm the visual scroll
  restoration under Photos permission and large-album conditions.
- Real-device log proof is still needed to confirm normal `.signed` first export
  no longer emits a long run of `originalPhotoData request start/success` before
  `export status updated`.
