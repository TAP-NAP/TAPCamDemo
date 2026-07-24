# PRO Video First-Recording Starvation

Date: 2026-07-24

## Goal

Fix two related real-device failures after promoting PRO Video:

- the frosted `Starting PRO` transition could remain visible for an
  unacceptably long time;
- the first recording made the UI unresponsive, delivered no frames while it
  appeared active, and produced no usable video.

## Device Evidence

The supplied device log showed:

1. rear LiDAR session configuration completed;
2. PRO Video warmup reached `warmup-ready`;
3. a prepared graph was discarded and rebuilt once;
4. recording began with `warmupReused=true`;
5. no RGB or Depth callback arrived during the apparent recording;
6. only after stop was requested did one RGB and one Depth sample arrive;
7. finalization reported `duration=0.000000`, `rgbFrames=1`, and
   `depthSamples=1`;
8. the artifact was rejected as `invalidVideoArtifact`.

The active warmup graph also reported `videoOutputs=2` and
`hasMFPreview=true`: the LiDAR source was driving one RGB output for the MF
loupe and a second RGB output for recording.

The earlier research trace had already specified the correct fallback:
unacceptable first-recording behavior should promote the single-recording-RGB
fan-out design. The production implementation had not yet applied that
boundary.

## Root Cause

Two data-lifecycle hazards overlapped:

- PRO attached two `AVCaptureVideoDataOutput` instances to the same LiDAR
  source;
- `AVCaptureDataOutputSynchronizer` was retained across warmup, but pressing
  the shutter replaced its delegate and callback queue while the outputs were
  live.

The iOS SDK header states that the synchronizer overrides each participating
output's individual delegate and owns their callbacks. Reassigning that live
synchronizer was therefore not a software-only state change.

The graph could report structurally ready after `commitConfiguration` while
its recording consumer still received no data. This explains why the UI state
said recording and why the gesture gate timed out even though the first valid
sample was delayed until teardown.

## Incident Classification

This was a data-flow ownership incident, not primarily an animation or button
state defect.

- **Trigger:** PHOTO/VIDEO/MF were modeled as separate output owners instead of
  consumers of one active source generation.
- **Amplifier:** the live synchronizer changed delegate and queue at the
  warmup/recording boundary.
- **Visible symptom:** long `Starting PRO`, system gesture timeout, and an
  apparently recording but unresponsive UI.
- **Artifact symptom:** first samples arrived only during stop, producing a
  zero-duration invalid artifact.
- **Why the first fix was incomplete:** it stabilized synchronizer creation
  time but still allowed delegate replacement and two RGB outputs.

The preventative rule is now recorded in `CameraControlsDesign.md` and
`CameraProControlsBuildIsolationPlan.md`: all auxiliary consumers bind to one
source generation and fan out after one canonical RGB output.

## Controlling Fix

PRO Video now uses one RGB hardware output:

```text
rear LiDAR
  + PhotoOutput
  + shared RGB output
  + synchronized Depth output
  + optional Audio output
          |
          +--> TAPVideoGraphOutputRouter
                  +--> MF loupe
                  +--> recorder while active
```

- `CameraManualFocusPreviewStream.videoOutput` remains the only PRO RGB data
  output.
- VIDEO adds Depth and optional Audio, not a second RGB output.
- `TAPVideoGraphOutputRouter` is installed before graph commit.
- Its callback queue remains stable through warmup, recording, and teardown.
- Starting recording activates a recorder pointer inside the router; it does
  not call `setDelegate` on the live synchronizer.
- The recorder serializes writer and depth work on that same callback queue.
- Shared RGB samples continue to feed the MF loupe during recording.
- Teardown clears the router, detaches Depth/Audio, restores the MF output
  delegate, and restores its preview connection rotation.
- The shutter revalidates prepared VIDEO state before allocating its temporary
  capture workspace. A PRO start cannot silently fall back to a second RGB
  output.

## Historical Device Evidence

The acceptance run for rear PRO Video recorded:

- `rgb-output-shared`
- `videoOutputs=1`
- `warmup-ready`
- `warmup-reused`
- `video rgb output first sample` shortly after the shutter
- `video depth output first sample` shortly after the shutter
- nonzero final duration and multiple RGB/Depth samples

The following is a regression:

- `videoOutputs=2` in a PRO stage;
- first samples appearing only after `video recording stop requested`;
- `duration=0.000000`;
- `invalidVideoArtifact` after a nominal recording.

In that historical trace, `warmup-ready` meant the graph committed
successfully; it was not proof of first-sample delivery. The probe-only stages
and first-RGB-format log are no longer emitted. If future device evidence shows
a transition stall, add a bounded current-generation first-sample readiness
gate for that investigation; do not add another output, repeat graph
reconstruction, or swap live delegates.

## Validation

- Debug simulator `build-for-testing`: passed.
- Release generic iOS Simulator build: passed.
- Focused serialized tests passed:
  - `TAPCameraCapturePresentationTests`
  - `TAPCameraProModeChromeTests`
  - `TAPDiagnosticsOSLogPrivacyTests`
  - `TAPVideoStreamingTests`
- `git diff --check`: passed.

Simulator validation cannot exercise LiDAR delivery or prove first-frame
latency. The controlling acceptance gate remains repeated physical-device cold
launch -> PRO -> VIDEO -> first recording cycles.

## Addendum: TAP Library Return Stall

### Symptom

After opening TAP Library from PRO VIDEO and returning to the camera, the
frosted `Starting PRO` transition could remain visible indefinitely.

### Root Cause

The library presentation correctly paused the camera session. Its dismissal
only ran `resumeAfterAnalysis()`, which restored the selected rear PRO source.
The UI still held `selectedMode == .video`, but the prepared VIDEO graph had
been discarded with the paused session. The transition gate intentionally
waited for VIDEO warmup before releasing the frost, yet no return-path owner
requested that warmup.

This was a lifecycle orchestration gap: UI selection state was mistaken for
capture-graph readiness.

### Correction

`CaptureLifecycleCoordinator` now models library dismissal as an ordered
restoration transaction:

1. resume the selected camera source;
2. prepare VIDEO when the selected presentation mode requires it;
3. report a typed `cameraReady`, `videoReady`, or `failed` result to the view;
4. release the camera-path transition only after the required graph is ready;
5. retry pending signing/export work independently, without including it in
   the viewfinder readiness gate.

If VIDEO preparation fails, the UI returns to PHOTO and releases the
transition instead of leaving an unbounded loading screen.

The physical-device acceptance run used temporary library-return and PRO graph
diagnostics to verify this sequence. Those logs and signposts were removed
after acceptance; the restoration policy and regression test remain.

The regression policy is covered by
`TAPCameraCapturePresentationTests.depthAlbumPresentationActions`.
