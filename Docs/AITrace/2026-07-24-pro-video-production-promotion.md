# PRO Video Production Promotion Trace

## Shared Goal

Promote the physically exercised rear-LiDAR PRO Video graph from a
default-off Debug probe into the normal Photo/Video product surface, then fix
the first-recording writer failure and the first MF tap routing defect found
during device testing.

## Accepted Device Evidence

- PRO Video graph warmup reached `warmup-ready`.
- RGB and Depth samples were delivered from the rear LiDAR graph.
- EV, ISO, shutter, MF slider, and MF loupe remained usable while recording.
- A later recording finalized and entered the pending Library flow.
- The first recording followed `warmupReused=true`, then
  `AVAssetWriter.status == .failed` with repeated Depth `outOfBuffers` drops and
  no finalized artifact.
- The first MF viewfinder tap after entering MF could be ignored; later taps
  worked.

The App Attest failure seen after the successful second artifact was a separate
signing/retry issue. It did not explain the first recording's missing artifact.

## Product Decision

- Remove `PRO Video Graph Probe` from Debug Settings.
- Remove the persisted research preference and Release-false resolver.
- Show the rightmost PRO control in PHOTO and VIDEO whenever the eligible rear
  path is available.
- Allow Standard VIDEO <-> PRO VIDEO transitions.
- Keep Standard non-LiDAR and keep front MF unavailable.
- Preserve the frosted transition until the camera path and selected VIDEO
  graph are both ready.

## Runtime Corrections

### Prepared Graph Lifetime

The old prepared path committed RGB/Depth outputs without a synchronizer, then
created `AVCaptureDataOutputSynchronizer` only when recording began. The direct
second-recording path attached its synchronizer before
`commitConfiguration`, which was the decisive lifecycle difference in the
device log.

The first production warmup iteration:

1. creates one synchronizer during warmup;
2. attached `TAPVideoGraphWarmupDrain`;
3. committed the graph while the outputs were actively drained;
4. retained both objects in `PreparedVideoRecordingGraph`;
5. started recording by swapping the synchronizer delegate.

Later real-device evidence showed that step 5 was still unsafe and that the
separate MF and recording RGB outputs could starve the first recording. The
controlling correction is documented in
`2026-07-24-pro-video-first-recording-starvation.md`: PRO now shares one RGB
output and keeps one synchronizer delegate and callback queue for the full graph
lifetime.

### Writer Failure Recovery

`TAPVideoWriterSession` now distinguishes writer failure from ordinary
backpressure. `TAPVideoRecorder` reports the first failure once.
`CameraViewModel` immediately exits recording state, detaches the graph, aborts
the temporary workspace, and rebuilds VIDEO warmup. This prevents a failed
writer from appearing to record until the user presses Stop.

### First MF Tap

The preview child can briefly hold the previous AF/MF value during SwiftUI
reconciliation. Both preview tap callbacks now enter
`CameraView.handleFocusTapAtPreviewPoint`, which resolves the current parent
focus mode before choosing normal AF or MF tap assist.

## Diagnostics

- At promotion time, PRO checkpoints moved from `TAPProVideoGraphProbe` /
  `TAPVideo.PROResearch` to `TAPProVideoGraphState` / `TAPVideo.PRO`.
- After the physical-device acceptance cycle, the PRO-only graph stages,
  format fields, and temporary first-RGB-format probe were removed from the
  shipping runtime. This paragraph records their historical role; it is not a
  current logging contract.
- Ordinary drop, writer, failure, and finalization diagnostics remain.
- Writer failures now surface immediately with public-safe domain/code and a
  private capture ID.

## Validation

Automated validation:

- Debug `xcodebuild build-for-testing` passed for iPhone 17 Pro, iOS 26.5.
- Generic iOS Simulator Release build passed, including the production PRO
  Video path with no Debug preference dependency.
- `TAPCameraCapturePresentationTests` passed, including the production-path
  source contract and removed Settings preference.
- `TAPCameraProModeChromeTests` passed.
- `TAPCameraManualFocusRuntimeTests` passed when run without parallel test
  workers. Four transport tests failed together in the first multi-suite
  parallel run, then passed in both isolated and final serialized runs; this
  was treated as test-worker interference rather than a product pass.
- `TAPDiagnosticsOSLogPrivacyTests`, `TAPVideoStreamingTests`, and
  `AppAttestRuntimeTests` passed.
- `git diff --check` passed.

Simulator validation cannot exercise LiDAR, actual writer startup, or physical
focus hardware. Device acceptance still requires repeating the cold
first-recording and first-MF-tap matrix in `Docs/ProVideoResearchPlan.md`.
