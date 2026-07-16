# `video` Branch Refactor Audit

Date: 2026-07-15

Review target: `video` (`cf2c3e8ec4858011a68daeddd10eb0a68404a3de`)

Baseline: `refacteor_under_review` (`26df33a18b3571a2b4d0372bfd2f8c8e86264cf0`)

Merge base: `26df33a18b3571a2b4d0372bfd2f8c8e86264cf0`

## Executive verdict

**Verdict: request changes before merging. Provisional weighted score: 8.0 / 10.**

The branch adds a credible end-to-end TAP Video path: capture, streaming
container work, depth metadata, signing/validation, Photos import/readback,
Library poster/original fetching, custom playback, 2D depth overlay, diagnostics,
fixtures, and substantial tests. The implementation also preserves important
bounded-memory and validation contracts.

The merge should nevertheless be blocked on structural refactoring. The branch
adds 14,583 lines of production Swift and concentrates the most complex behavior
into several 700-3,000-line files. Playback, recording, PhotoKit request
bridging, Library state, diagnostics, and test fixtures have grown faster than
their ownership boundaries. The result compiles and has strong functional
coverage, but it no longer meets the repository's previous claims of 10.0
extensibility and 9.9 readability.

No confirmed unreachable Release-only production path was found. The fixture
harness and codec benchmark are correctly compile-gated with `#if DEBUG` or
`DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS`. The main problems are duplicated
infrastructure, stale central documentation, overly broad types, unstable
SwiftUI composition, and test code that asserts source spelling instead of
behavior.

## Scope and evidence

The audit uses the requested merge-base diff, not the current branch tip against
an unrelated checkout state.

| Measure | Result |
| --- | ---: |
| Changed files | 158 |
| Total diff | +69,381 / -2,411 |
| Vendored zstd C source | 66 files, +47,407 lines |
| Non-vendor diff | 92 files, +21,974 / -2,411 |
| Production Swift diff | 53 files, +14,583 / -2,199 |
| Test Swift diff | 21 files, +4,835 / -178 |
| Changed production Swift files over 300 lines | 28 |
| Changed production Swift files over 500 lines | 20 |
| Changed production Swift files over 1,000 lines | 11 |

The vendored zstd source is pinned to 1.5.7, records its source archive SHA-256,
and is not counted as application readability debt. It is still 68% of all
added lines, so raw diff size must not be used as an application-code metric.

Static checks on the changed production Swift files reported:

| SwiftLint rule | Current findings in changed files |
| --- | ---: |
| `file_length` | 22 |
| `type_body_length` | 25 |
| `function_body_length` | 53 |
| `cyclomatic_complexity` | 17 |
| `function_parameter_count` | 15 |

These counts describe the current versions of changed files; some violations
predate this branch. The branch-created video files and the large positive line
deltas below are independently sufficient to establish the new structural debt.

Validation completed during this audit:

- Shared scheme contains `TAPCamDemoTests` and preserves
  `TAPCAM_XCTEST_HOST=1`.
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme
  TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17'` passed with
  `** TEST BUILD SUCCEEDED **`.
- `git diff --check refacteor_under_review...video` passed.
- This audit did not rerun full XCTest, UI automation, ETTrace, memgraph, or a
  physical-device capture/playback matrix. Existing trace documents remain
  supporting evidence, not newly reproduced evidence.

## Scorecard

This uses the exact weights in `Docs/ProjectScorecard.md`: professional camera
capabilities 10%, core depth plus App Attest 20%, extensibility 20%, security
25%, readability 15%, and docs clarity 10%.

| Area | Score | Strict read |
| --- | ---: | --- |
| Professional camera capabilities | 7.4 / 10 | Real video capture, Library, poster, playback, audio transport, and registered 2D depth overlay now exist. Device/format breadth and repeatable performance acceptance remain incomplete. |
| Core depth plus App Attest | 9.0 / 10 | Streaming KLV depth metadata, bounded decode/validation, content binding, proof writing, Photos readback, and failure coverage materially extend the depth core. Production backend acceptance and a broader physical-device matrix remain separate gates. |
| Extensibility | 6.8 / 10 | Protocols and policies exist, but core implementation boundaries collapse into 700-3,000-line files. Duplicate PhotoKit request state machines and duplicate AVAsset track-facts readers create drift risk. |
| Security | 9.4 / 10 | File-based hashing, fixed proof-slot handling, bounded frame sizes, streaming validation, pinned zstd provenance, and public-safe diagnostics are strong. The score is held below the old 9.6 because the new video surface is much larger and needs a repeated Release/device validation matrix. |
| Readability | 5.2 / 10 | The branch leaves 11 changed production Swift files above 1,000 lines and materially grows several of them; it also adds long functions, large types, two duplicated chrome branches, broad `ObservableObject` invalidation, and extensive source-string tests. |
| Docs clarity | 9.2 / 10 | PRD and AITrace coverage are detailed, but the central scorecard is stale: it is dated 2026-07-07 and still says video/general video is missing. |

Weighted result: `(7.4×10%)+(9.0×20%)+(6.8×20%)+(9.4×25%)+
(5.2×15%)+(9.2×10%) = 7.95`, rounded to **8.0 / 10**.

The previous `9.0 / 10` snapshot cannot be carried forward unchanged. It was
written before this branch and explicitly treated general video as absent.

## Blocking findings

### P1 — Playback is a 2,983-line feature module disguised as one view file

Evidence:

- `TAPVideoDepthPlaybackView.swift` grew from approximately 1,248 lines at the
  baseline to 2,983 lines.
- It contains screen composition, navigation and deletion, share preparation,
  foreground/background fetch policy, transport/audio-session ownership,
  a playback view model, metadata probing, metadata delegate handling, depth
  decode, heatmap rendering, byte parsing, and orientation conversion.
- `TAPVideoDepthPlaybackView` spans roughly 496 nontrivial lines;
  `TAPVideoDepthPlaybackViewModel` spans roughly 889; and
  `TAPVideoDepthMetadataOutput` spans roughly 307.
- `readNearestFrame` has cyclomatic complexity 21 and a function body around
  120 lines.

Why this matters:

- A change to decode admission, share/delete behavior, Library fetch recovery,
  or SwiftUI layout requires editing and recompiling the same file.
- The top-level view owns seven `@Published` values through one
  `ObservableObject`. Every publication can invalidate the entire screen even
  when only the loading badge or gap notice changed.
- `videoChrome` swaps between two complete `DepthViewerChromeView` trees and
  repeats nearly every argument. This creates identity churn when the player
  becomes ready and guarantees maintenance drift between loading and ready
  chrome.
- Most visual sections are computed `some View` helpers rather than dedicated
  view types, preventing narrow observation, isolated previews, and small
  compile units.

Required refactor:

1. Keep `TAPVideoDepthPlaybackView.swift` as a screen shell under 250-300 lines.
2. Extract `TAPVideoPlaybackSession` for fetch, player, lifecycle, and resource
   cleanup.
3. Extract `TAPVideoPlaybackTransportModel/View` into its own file.
4. Extract `TAPVideoDepthPipeline`, `TAPVideoDepthMetadataReader`,
   `TAPVideoDepthMetadataOutput`, `TAPDepthFrameDecoder`, and
   `TAPDepthFrameRenderer` by responsibility.
5. Replace the two full chrome branches with one stable chrome tree whose
   accessory content and enabled state vary locally.
6. Because the deployment target is iOS 18.6, prefer `@Observable` stored in
   `@State` and pass narrow value inputs into dedicated subviews. Do not add
   another wrapper view model merely to relocate the same state.

Acceptance:

- No video SwiftUI view file over 300 lines.
- No playback domain type over 350 lines.
- The player-ready transition does not replace the root chrome identity.
- Instruments SwiftUI capture shows no new long view-body updates and documents
  update counts for loading progress, playback time, 2D gap, and mode changes.

### P1 — Recorder and validator mix state machine, encoding, manifest, and inspection

Evidence:

- `TAPVideoRecorder.swift` is 1,703 lines and the recorder type spans roughly
  1,089 lines.
- The recorder owns more than 40 mutable state fields covering writer state,
  RGB/audio/depth counters, calibration, gaps, synchronization, diagnostics,
  manifest assembly, and finish continuation ownership.
- `appendDepthSample` is about 142 lines with complexity 15;
  `makeManifest` is about 121 lines; `spatialRegistration` is about 120 lines
  with complexity 18.
- `TAPVideoDepthTrackValidator.validate` is about 210 lines with complexity 22.
- `TAPVideoRecordedFileFacts.load` and
  `TAPVideoPlaybackFixtureRecordedFacts.load` separately load tracks, duration,
  format descriptions, nominal frame rate, dimensions, codec fourcc, and track
  timing. Their `trackTiming` helpers are materially the same.

Why this matters:

- A recorder state transition cannot be reviewed independently of manifest
  assembly or AVAsset postflight inspection.
- Duplicate track inspection is already diverging: the production reader
  handles optional audio and metadata, while the fixture reader embeds a
  separate exact-track policy.
- The validator's single function interleaves container composition, manifest
  consistency, reader setup, KLV decode, calibration accounting, memory budget,
  and timeline validation. Negative-path additions will keep increasing its
  complexity.

Required refactor:

1. Introduce a value-semantic `TAPVideoRecordingMetrics` aggregate for counters,
   first/last timestamps, depth gaps, and calibration coverage.
2. Extract `TAPVideoWriterSession` for `AVAssetWriter` input lifecycle and
   append/finalize behavior.
3. Extract `TAPVideoDepthMetadataEncoder` for pack/compress/KLV/adaptor append.
4. Extract a pure `TAPVideoManifestAssembler` that consumes request,
   configuration, metrics, and inspected file facts.
5. Create one `TAPMediaTrackFactsReader` used by recorder postflight, validator,
   and fixture generation; apply different policies after facts are read.
6. Split validator stages into container, media-track, metadata-format, sample,
   calibration, and timeline validators. Preserve streaming one-frame memory
   behavior.
7. Replace `outputDelegateStorage` plus `preconditionFailure` with an ownership
   pattern that cannot represent an uninitialized delegate after construction.

Acceptance:

- Recorder core type under 500 lines and validator entry under 60 lines.
- No duplicated `trackTiming` or AVAsset facts-loading implementation.
- Complexity at or below 10 per validation/recording function, except for an
  explicitly reviewed pure policy function.
- Existing byte-budget, sample-count, gap, calibration, proof, and readback
  tests remain green.

### P1 — Four PhotoKit request bridges duplicate the same concurrency state machine

Evidence:

`LibraryMediaFetching.swift` is 1,145 lines. Four private bridge classes repeat
the same structure:

- `PhotoKitResourceDataRequestBridge` at line 534;
- `PhotoKitResourceFileRequestBridge` at line 658;
- `PhotoKitDisplayImageRequestBridge` at line 811;
- `PhotoKitLivePhotoRequestBridge` at line 966.

Each owns an `NSLock`, request ID, checked continuation, cancellation flag,
finished flag, progress normalization, request installation race, cancellation,
and finish-once logic.

Why this matters:

The duplicated code is concurrency code, not harmless presentation boilerplate.
A cancellation or continuation-resume fix must be applied four times. The two
resource bridges are especially close; their meaningful difference is the sink
(`Data` accumulator versus `FileHandle`).

Required refactor:

1. Split protocol/models, `PhotoKitLibraryMediaFetcher`, resource bridges,
   image bridge, Live Photo bridge, and error mapping into separate files.
2. Extract a small, tested request-lifecycle primitive that owns request-ID
   installation, cancellation, and exactly-once continuation completion.
3. Model resource chunk handling as a sink strategy (`DataSink` and
   `FileSink`) rather than duplicating the entire bridge.
4. Keep PhotoKit-specific result interpretation in the image and Live Photo
   adapters; do not force unrelated callback shapes into one giant generic.

Acceptance:

- One tested implementation of request install/cancel/finish race handling.
- Resource-to-Data and resource-to-file paths share lifecycle logic.
- Cancellation-before-install, cancellation-after-install, error-after-cancel,
  degraded image, iCloud-only probe, and write-failure tests remain explicit.

### P1 — TAP Library expansion refills previously extracted large boundaries

Evidence:

- `DepthAnalysisCarouselState.swift` is now 1,450 lines; `AnalysisPhotoSlot`
  spans roughly 782 lines and publishes ten state surfaces.
- `DepthAlbumPickerView.swift` is 893 lines and contains both the screen and a
  roughly 252-line cell implementation.
- `TAPPendingCaptureStore.swift` grew to 872 lines; its actor spans roughly 727
  lines and now coordinates photo, video, locked import, migration, cleanup,
  queue semantics, and notifications.
- `TAPPendingCaptureProcessor.swift` is 688 lines with multiple 57-79-line
  functions.

Why this matters:

The baseline scorecard praised extracted provider, thumbnail, storage, and
worker boundaries. The video branch adds behavior by growing the orchestration
types again, so the architecture is moving back toward god stores and god
state objects.

Required refactor:

- Split `AnalysisPhotoSlot` into display-fetch state, analysis state, and
  selection state while keeping one item identity.
- Extract Library grid cell and route adapter as dedicated views/types.
- Keep one serialized pending-record repository, but move video workspace,
  exported-asset recovery, migration, and cleanup into focused collaborators.
- Make `TAPPendingCaptureProcessor` an orchestration pipeline whose signing,
  export, readback, and cleanup stages are injected operations.

### P1 — The central scorecard is stale and currently gives a false project read

Evidence:

- `Docs/ProjectScorecard.md` is dated 2026-07-07.
- It still lists video/general video as missing in the capability row, strict
  gaps, and future-work text.
- It still reports overall 9.0, extensibility 10.0, and readability 9.9 despite
  this branch adding 11 changed production Swift files over 1,000 lines.

Required refactor:

- Update the scorecard only after the structural refactor and validation gates.
- Add a TAP Video reading path that starts at capture request/session, then
  writer/depth encoding, manifest/provenance, pending/export, Library fetch,
  playback/depth pipeline, and tests.
- Keep static, Simulator, physical-device, ETTrace, and memgraph evidence
  explicitly separate.

## Non-blocking but important findings

### P2 — Source-string tests are overused and make refactoring artificially expensive

The branch adds approximately 170 new `source.contains(...)` style assertions
across changed/new tests: 89 in `TAPDepthAnalysisPresentationTests`, 38 in
`TAPCameraCapturePresentationTests`, 36 in `LibraryMediaTests`, and 7 in
`TAPVideoReleaseSourceGuardTests`.

The large playback source-contract test asserts implementation spelling such as
property names, exact APIs, exact helper names, and the absence of earlier names.
Those tests discourage the exact file and type extraction required by this
audit, even when behavior remains unchanged.

Keep source scanning only for enforceable architectural/security bans that are
hard to express at runtime, such as prohibiting whole-MP4 `Data(contentsOf:)`
loads or legacy artifact names. Replace layout, transport, mode, lifecycle,
and accessibility spelling assertions with policy tests, injected service
tests, previews/snapshot checks, or XCUI behavior.

Target: reduce the branch-added source-string assertions by at least 80%, and
split test files so each suite stays near 400 lines.

### P2 — The codec benchmark produces a disconnected “production selection”

`TAPDepthCodecBenchmark` computes a `TAPDepthCodecProductionSelection`, but the
actual runtime uses the separately hard-coded
`TAPDepthCompressionProductionPolicy.preferredCodec = .zstd1`. Repository-wide
references show the benchmark is consumed by tests, not by the production
policy.

This is not dead Release code because the file is Debug/diagnostics-gated, but
the name and report field imply an effect that does not exist. Either:

- rename it to `recommendedSelection` and document the manual promotion step;
  or
- generate/review a small pinned policy artifact from accepted device evidence.

Do not let runtime behavior silently choose a codec from a single ad hoc
benchmark run.

### P2 — Debug fixture code belongs in a dedicated support target

`TAPVideoPlaybackFixtureHarness.swift` is correctly wrapped in `#if DEBUG`, but
it is still a 1,103-line file in the application source target and duplicates
production media-facts inspection. Move fixture specifications/generation to a
Debug/test-support target that the Debug app and test targets can import. This
keeps product source maps smaller and prevents fixture-only adapters from
shaping production file organization.

### P2 — Treat vendored zstd as a managed third-party artifact

The pinned source and SHA-256 provenance are good. Add or document a deterministic
update/verification script, exclude `Packages/CZstd/Vendor` from app LOC and
lint dashboards, and keep vulnerability/version review separate from TAPCam
refactoring. Do not manually “clean up” vendored C files.

## Proposed target structure

```text
TAPVideo/
├── Capture/
│   ├── TAPVideoRecordingRequest.swift
│   ├── TAPVideoWriterSession.swift
│   ├── TAPVideoRecordingMetrics.swift
│   ├── TAPVideoDepthMetadataEncoder.swift
│   └── TAPVideoRecorder.swift
├── Container/
│   ├── TAPMediaTrackFacts.swift
│   ├── TAPMediaTrackFactsReader.swift
│   ├── TAPVideoManifestAssembler.swift
│   └── Validation/
│       ├── TAPVideoContainerValidator.swift
│       ├── TAPVideoTrackValidator.swift
│       ├── TAPVideoDepthSampleValidator.swift
│       └── TAPVideoTimelineValidator.swift
├── Library/
│   ├── LibraryMediaFetching.swift
│   ├── PhotoKitLibraryMediaFetcher.swift
│   ├── PhotoKitRequestLifecycle.swift
│   ├── PhotoKitResourceRequest.swift
│   ├── PhotoKitImageRequest.swift
│   └── PhotoKitLivePhotoRequest.swift
├── Playback/
│   ├── TAPVideoDepthPlaybackView.swift
│   ├── TAPVideoViewerChrome.swift
│   ├── TAPVideoPlaybackTransport.swift
│   ├── TAPVideoPlaybackSession.swift
│   ├── TAPVideoPlayerSurface.swift
│   └── Depth/
│       ├── TAPVideoDepthPipeline.swift
│       ├── TAPVideoDepthMetadataReader.swift
│       ├── TAPVideoDepthFrameCache.swift
│       ├── TAPVideoDepthFrameDecoder.swift
│       └── TAPVideoDepthFrameRenderer.swift
└── DiagnosticsSupport/   # Debug/test-support target
    ├── TAPVideoPlaybackFixture.swift
    └── TAPDepthCodecBenchmark.swift
```

The exact folder name is less important than ownership. The key rule is that
screen composition, player lifecycle, depth decoding, container validation,
PhotoKit bridging, and fixtures must not share implementation files.

## Refactor sequence

### R0 — Freeze behavior and measurement

1. Preserve current golden manifest vectors and negative validator tests.
2. Record focused unit/UI commands and current physical-device evidence links.
3. Capture baseline SwiftUI Instruments, Time Profiler, VM Tracker, and memgraph
   for a 15-second video open/play/2D/seek/dismiss loop.
4. Add scoped lint thresholds for new TAP Video files; do not attempt a noisy
   repository-wide style rewrite.

The executable R0 structure gate is
`Scripts/lint-tap-video-refactor.sh`. It applies
`.swiftlint-tap-video.yml` only to the explicit R1-R4 production allowlist and
fails when a function body exceeds 80 lines or cyclomatic complexity exceeds
10. Tests, Debug fixtures, benchmarks, vendored zstd, and unrelated legacy code
remain outside this gate.

Focused unit and attended UI commands are recorded in
`TAPCamDemoTests/README.md`. The current R5 validation reran the focused and full
unit gates; the attended UI suite and physical-device/performance evidence were
not rerun.

### R1 — Extract pure/container infrastructure first

1. Introduce `TAPMediaTrackFactsReader` and remove both duplicate facts readers.
2. Split validator stages without changing validation order or error mapping.
3. Extract recording metrics and pure manifest assembly.
4. Re-run streaming, manifest, provenance, readback, and storage tests.

### R2 — Extract PhotoKit request lifecycle

1. Add finish-once/cancellation race tests around the shared lifecycle primitive.
2. Convert resource Data/file requests to sink strategies.
3. Move image and Live Photo adapters to separate files.
4. Re-run iCloud/local-only, cancellation, stale callback, and poster tests.

### R3 — Refactor playback UI and depth pipeline

1. Create a stable single chrome tree.
2. Move transport to its own observable model and view file.
3. Move fetch/player lifecycle to `TAPVideoPlaybackSession`.
4. Move probe/decode/cache/render/admission into the Depth folder.
5. Convert broad `ObservableObject` surfaces to `@Observable` with narrow view
   dependencies where it reduces invalidation.
6. Replace source-string presentation tests with behavior and rendered UI tests.

### R4 — Split Library and pending orchestration

1. Extract cell/view types from the picker.
2. Split carousel slot responsibilities while retaining stable item identity.
3. Extract video workspace, recovery, migration, and cleanup collaborators from
   the pending store/processor.

### R5 — Re-score and release gate

1. Update `ProjectScorecard.md` and module READMEs.
2. Run build-for-testing and focused/full XCTest on a booted Simulator UDID.
3. Run Release build and inspect the built app's final `Info.plist`.
4. Repeat physical-device capture, signing/export, Photos readback, poster,
   RAW/2D playback, seek, background/PiP, delete, iCloud, and memory-pressure
   acceptance.
5. Compare ETTrace/SwiftUI/VM Tracker/memgraph evidence with the R0 baseline.

## Merge acceptance criteria

- `TAPVideoDepthPlaybackView.swift` at or below 300 lines.
- No new TAP Video production file above 600 lines; exceptions require a named
  pure data/schema rationale.
- No core function above 80 lines or complexity above 10 without an explicit
  reviewed exception.
- One AVAsset track-facts reader and one PhotoKit request lifecycle primitive.
- One stable viewer chrome tree across loading and ready states.
- At least 80% of branch-added source-string presentation assertions removed or
  converted to behavior/policy tests.
- Debug build-for-testing, focused/full unit tests, Release build, final built
  plist inspection, and `git diff --check` pass.
- Physical-device evidence covers capture through Photos readback and Library
  RAW/2D playback.
- SwiftUI Instruments shows update frequency and long body-update evidence;
  ETTrace/Time Profiler and VM Tracker/memgraph show no regression against the
  recorded baseline.
- Recalculated targets: extensibility at least 8.8, readability at least 8.5,
  and weighted overall at least 8.7 before the scorecard claims a score lift.

## External review basis

- Apple, [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): keep view bodies fast, limit dependencies, move non-UI work out of views, reduce update frequency, and validate with the SwiftUI instrument.
- Apple, [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/): reason about dependencies, faster updates, and stable identity.
- Apple, [Media reading and writing](https://developer.apple.com/documentation/avfoundation/media-reading-and-writing): use AVFoundation's sample-level reader/writer boundaries for media inspection and streaming work.
