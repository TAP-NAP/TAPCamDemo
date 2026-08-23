# DepthAnalysis and TAP Library

This module owns the in-app TAP Library, the current photo/video Viewer, local
depth analysis, Share preparation, and Delete coordination. Product behavior is
defined by [ProductContract.md](../../Docs/ProductContract.md), especially the
Library/Viewer and owned-capture verification boundaries.

## Current Product Surface

- TAP Library merges pending captures, exported records, and eligible Photos
  assets into one identity-stable collection.
- The photo Viewer presents the approved `RAW`, `2D`, and `3D` controls. Those
  labels are product modes; internal renderers may use narrower RGB, heatmap,
  mask, plane, and point-cloud values.
- The video Viewer uses the same Library route and owns playback, depth overlay,
  Share, and Delete.
- Share offers direct media and, when the local integrity gate succeeds, a
  temporary `.tapnap` package through the system share sheet.
- Delete respects pending-store and Photos ownership. Device confirmation and
  Photos permission semantics remain acceptance work, not unit-test claims.
- Owned captures do not mount a backend Verify button, service, panel, or
  report. External package verification remains a separate product boundary.

No code in this module may display raw loader errors, paths, Photos identifiers,
capture identifiers, proof bytes, App Attest key IDs, or backend diagnostics.

## Runtime Flow

```text
TAP Library item
  -> DepthAnalysisCarouselState creates one immutable entry and AnalysisPhotoSlot
  -> DepthAnalysisInputLoader / TAPVideoPlaybackSession load the selected media
  -> DepthAnalysisStageView renders the current photo mode, or video playback
  -> DepthAnalysisShareCoordinator validates the exact visible resource locally
  -> system share sheet receives one file URL
```

Each photo carousel entry owns its own `AnalysisPhotoSlot` and retained
selection state, so loading another entry does not mutate a shared view model.

## Active Code Map

### Library and routing

| Responsibility | Code |
| --- | --- |
| Library item and source identity | [DepthAnalysisAlbumContext.swift](DepthAnalysisAlbumContext.swift), [DepthAlbumItemProvider.swift](DepthAlbumItemProvider.swift) |
| Library view/model | [DepthAlbumPickerView.swift](DepthAlbumPickerView.swift), [DepthAlbumPickerViewModel.swift](DepthAlbumPickerViewModel.swift) |
| Native paging and route handoff | [TAPLibraryNativePagingView.swift](TAPLibraryNativePagingView.swift), [DepthAlbumRouteAdapter.swift](DepthAlbumRouteAdapter.swift) |
| Thumbnail work | [DepthAlbumThumbnailPipeline.swift](DepthAlbumThumbnailPipeline.swift) |
| Viewer carousel identity/state | [DepthAnalysisCarouselState.swift](DepthAnalysisCarouselState.swift) |

### Photo Viewer and analysis

| Responsibility | Code |
| --- | --- |
| Current Viewer root | [DepthAnalysisView.swift](DepthAnalysisView.swift) |
| Current stage rendering | [DepthAnalysisStageView.swift](DepthAnalysisStageView.swift) |
| RAW/2D/3D controls and chrome | [DepthAnalysisControlsView.swift](DepthAnalysisControlsView.swift), [DepthAnalysisViewerChromeView.swift](DepthAnalysisViewerChromeView.swift) |
| Per-entry state | [AnalysisPhotoSlot.swift](AnalysisPhotoSlot.swift) and its `+Analysis`, `+DisplayFetch`, and `+Selection` extensions |
| Input loading and public-safe validation | [DepthAnalysisInputLoader.swift](DepthAnalysisInputLoader.swift), [DepthAnalysisInputValidation.swift](DepthAnalysisInputValidation.swift), [DepthAnalysisReader.swift](DepthAnalysisReader.swift) |
| Visible error mapping | [DepthAnalysisErrorPresentation.swift](DepthAnalysisErrorPresentation.swift) |
| Region and plane selection | [DepthAnalysisRegionSelectionState.swift](DepthAnalysisRegionSelectionState.swift), [DepthAnalysisPlaneSelectionState.swift](DepthAnalysisPlaneSelectionState.swift) |
| Plane request freshness | [DepthAnalysisPlaneRegionRequestCoordinator.swift](DepthAnalysisPlaneRegionRequestCoordinator.swift) |
| Plane estimation and rendering | [AnalysisTools/DepthPlaneEstimator.swift](AnalysisTools/DepthPlaneEstimator.swift), [DepthAnalysisPlaneRegionDetector.swift](DepthAnalysisPlaneRegionDetector.swift) |
| Heatmap, mask, and point cloud tools | [AnalysisTools/README.md](AnalysisTools/README.md) |

The former drawer/detent inspector island was unmounted and has been removed.
Do not restore its top-level Heatmap/Mask modes, inspector strip, or panel shell
without an owner-approved product and prototype task.

### Share and original resources

| Responsibility | Code |
| --- | --- |
| Share state and stale-result rejection | [DepthAnalysisShareCoordinator.swift](DepthAnalysisShareCoordinator.swift) |
| Popover presentation | [DepthAnalysisSharePopover.swift](DepthAnalysisSharePopover.swift), [DepthViewerShareControl.swift](DepthViewerShareControl.swift) |
| Exact Photos/pending resource lease | [TAPPhotoOriginalResource.swift](TAPPhotoOriginalResource.swift), [DepthAnalysisShareOriginalResource.swift](DepthAnalysisShareOriginalResource.swift) |
| Local integrity gate | [TAPShareIntegritySupport.swift](TAPShareIntegritySupport.swift) |
| `.tapnap` builder | [TAPNAPShareArtifactBuilder.swift](TAPNAPShareArtifactBuilder.swift) |
| TAP Video share builder | [TAPVideoShareArtifactBuilder.swift](TAPVideoShareArtifactBuilder.swift) |
| System activity-sheet bridge | [VerificationExportActivityView.swift](VerificationExportActivityView.swift) |

`VerificationExportActivityView` is an active generic activity-sheet bridge;
its historical name does not mean that owned captures run backend verification.

### Video playback

The video entry point is [TAPVideoDepthPlaybackView.swift](TAPVideoDepthPlaybackView.swift).
Playback ownership and validation are documented in
[Playback/PLAYBACK.md](Playback/PLAYBACK.md). The fixture generator/harness under
`DiagnosticsSupport` is Debug-only test support and is not physical-device or
App Attest evidence.

## Security, Privacy, and Format Boundaries

- Local Share validation checks the exact selected signed original and fails
  closed before `.tapnap` generation. It does not call a backend.
- App Attest hardware/backend acceptance is owned by
  [TAP-0046](../../Docs/Acceptance/TAP-0046-app-attest-production.md); Simulator,
  source scans, and synthetic signers cannot close it.
- Shared artifact families remain independent under the
  [versioning policy](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/VERSIONING.md);
  repository cleanup must not collapse them.
- Temporary Share artifacts are lease-owned and removed after the system share
  lifecycle releases them.
- Analysis geometry is camera-coordinate/local unless a specialized contract
  explicitly says otherwise; it is not a world-space reconstruction claim.

## Validation Entry Points

Keep behavior and contract coverage concentrated in these suites:

- `TAPDepthAnalysisInputTests` for loader/reader/public-safe failure mapping;
- `TAPDepthAnalysisSelectionTests` and `TAPDepthAnalysisPlaneRegionTests` for
  region/plane state, cancellation, cache, and request freshness;
- `TAPDepthAnalysisSharePresentationTests`, `TAPPhotoOriginalResourceTests`,
  and `TAPNAPShareArtifactBuilderTests` for exact-resource identity, local
  integrity, stale work, cleanup, and package bytes;
- `TAPVideoStreamingTests` and playback suites for bounded MP4/KLV parsing,
  timing, cancellation, and render state;
- retained privacy/format/architecture gates for forbidden dependencies and
  source-to-sink boundaries.

Source spelling, exact icon/spacing literals, non-asserting screenshot loops,
and tests of removed inspector/ViewModel code are not regression evidence.

## Human Acceptance

- Library permission and Delete semantics:
  [TAP-0047](../../Docs/Acceptance/TAP-0047-library-permission-delete.md)
- Web-to-native visual parity:
  [TAP-0048](../../Docs/Acceptance/TAP-0048-web-swiftui-parity.md)
- Share handoff:
  [TAP-0082](../../Docs/Acceptance/TAP-0082-share-handoff.md)
- TAP Video device behavior:
  [TAP-0045](../../Docs/Acceptance/TAP-0045-tap-video-device.md)

Automated tests and Simulator runs are supporting diagnostics. They do not
replace attended physical-device verdicts required by those procedures.

## Reading Order

1. Read [ProductContract.md](../../Docs/ProductContract.md) for current product
   behavior and non-goals.
2. Read [DepthAnalysisCarouselState.swift](DepthAnalysisCarouselState.swift),
   [AnalysisPhotoSlot.swift](AnalysisPhotoSlot.swift), and
   [DepthAnalysisStageView.swift](DepthAnalysisStageView.swift) for photo Viewer
   ownership.
3. Read [DepthAnalysisShareCoordinator.swift](DepthAnalysisShareCoordinator.swift)
   and [TAPShareIntegritySupport.swift](TAPShareIntegritySupport.swift) for Share.
4. Read [Playback/PLAYBACK.md](Playback/PLAYBACK.md) for video.
5. Read [Documentation/PlanesTechnicalDesign.md](Documentation/PlanesTechnicalDesign.md)
   only for the current plane-analysis math and coordinate contract.
