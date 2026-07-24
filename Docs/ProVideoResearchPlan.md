# PRO Video Validation and Production Contract

## Decision Status

The rear-LiDAR PRO Video probe has been accepted as sufficient evidence to
begin product development. PRO Video is now a Release capability rather than a
Debug preference.

The product path captures TAP depth video from the eligible rear
`BuiltInLiDARDepthCamera` at fixed 24mm / 1x. Standard mode never opts into
LiDAR, and front-camera selection never exposes PRO or MF.

The former `PRO Video Graph Probe` Settings toggle and
`CameraProVideoResearchPreferences` key no longer exist. The temporary
PRO-specific graph-stage and first-RGB-format probes were removed after device
acceptance. Production keeps ordinary failure, drop, writer, and finalization
diagnostics without retaining the research-only graph trace.

## Product Graph

The active PRO Photo graph contains:

```text
rear LiDAR input
  + AVCapturePhotoOutput
  + one preview-sized AVCaptureVideoDataOutput shared by MF and VIDEO
```

Entering VIDEO adds:

```text
the existing shared RGB output
  + AVCaptureDepthDataOutput
  + optional AVCaptureAudioDataOutput / audio input
```

The prepared recording graph creates and retains one
`AVCaptureDataOutputSynchronizer` and one stable software router before
`commitConfiguration`. The router drains synchronized RGB/Depth while VIDEO is
ready but idle, returns the shared RGB sample to the MF loupe, and activates the
recorder on the same callback queue when the shutter is pressed. The
synchronizer delegate and queue never change while the graph is live.

This corrects both first-recording failures observed in device logs:

- the older prepared path attached its synchronizer only after outputs were
  already live;
- the next iteration kept the synchronizer but switched its delegate and queue
  from warmup to recording while also running separate MF and recording RGB
  outputs. The first recording then delivered no RGB/Depth until stop and
  finalized at `duration=0.000000`.

## UI Contract

- `PHOTO` and `VIDEO` are available in Standard and eligible rear PRO.
- The rightmost `PRO` button remains visible in VIDEO.
- Standard VIDEO -> PRO VIDEO and PRO VIDEO -> Standard VIDEO use the same
  frosted asynchronous camera-path transition as Photo.
- The frost remains until both the destination camera session and requested
  video graph are ready.
- Switching between rear PRO and front while VIDEO is selected tears down the
  old prepared graph, changes camera path, and prepares the destination VIDEO
  graph before releasing the frost.
- PRO Video keeps `EV / ISO / S / AF/MF / ƒ`; the lens selector remains hidden.
- A VIDEO warmup failure returns to PHOTO with concise feedback.

## Manual Controls During Recording

Physical-device testing confirmed EV, ISO, S, MF slider, and the MF loupe remain
operational while recording.

MF tap assist resolves AF/MF routing in `CameraView`, the owner of the current
focus mode. Both preview callbacks enter the same parent handler, preventing a
one-frame-old SwiftUI child state from routing the first MF tap through the AF
path. MF tap assist remains focus-only: it performs one AF cycle at the tapped
point and locks `AVCaptureDevice.currentLensPosition` without changing exposure.

## Writer Failure Contract

The UI must not remain in a fake recording state after `AVAssetWriter` fails.

1. `TAPVideoRecorder` reports the first writer failure once.
2. `CaptureSessionController` detaches the failed recording graph.
3. `CameraViewModel` cancels recording triggers and clears
   `isVideoRecording`.
4. The failed temporary workspace is aborted; no corrupt artifact is ingested.
5. VIDEO warmup is rebuilt so the next recording starts from a valid graph.

The original first-recording content cannot be recovered after a writer
failure. The synchronizer-lifetime fix prevents the known trigger; the failure
contract prevents silent loss if another writer error occurs.

## Historical Validation Evidence

The research phase used `TAPProVideoGraphState`, the `TAPVideo.PRO` signpost
category, `pro_video_graph` logs, and a first-RGB-format checkpoint to verify
the single-RGB graph on physical hardware. Those probe-only surfaces are not
part of the production runtime.

The accepted architecture is protected by source-inspection and streaming
tests. Ordinary video diagnostics still cover failures, drops, writer state,
finalization, and artifact counts where they are needed by the shipping
pipeline.

## Regression Matrix

Run on each supported LiDAR Pro model with microphone data both off and on:

| Scenario | Minimum cycles | Acceptance |
| --- | ---: | --- |
| Cold launch -> PRO -> VIDEO -> first recording | 10 | First recording finalizes and enters Library every cycle. |
| PRO Photo <-> PRO Video | 20 | No black frame, wedge, or missing prepared graph. |
| Standard VIDEO <-> PRO VIDEO | 10 | Frost persists until the destination VIDEO graph is ready. |
| PRO Video start -> 5 s record -> stop | 10 | Nonzero RGB and stored Depth; no writer failure. |
| AF tap during recording | 10 taps | Focus settles without graph interruption. |
| MF first tap during recording | 10 entries | The first tap after entering MF performs tap assist. |
| MF slider during recording | 10 pulls | Latest-wins writes continue without recorder stall. |
| VIDEO -> front -> rear PRO | 10 | Suspended rear intent and frosted transition remain correct. |

## Current Single-RGB Architecture

Physical-device evidence showed that the two-output design could starve the
first recording, so PRO Video now uses the preferred fan-out architecture:

```text
rear LiDAR input
  + PhotoOutput
  + shared RGB + synchronized Depth + optional Audio
       |
       +--> stable software router
              +--> MF loupe
              +--> recorder while active
```

The main preview remains 1x. MF loupe fan-out must not create a second session,
second PreviewLayer, second RGB data output, or hardware zoom mutation.

## Cross-Mode Data-Flow Constraint

The single-RGB rule applies at the capture-source level, not only while the
record button is active.

- PHOTO and VIDEO are presentation/recording modes over one active source
  generation.
- MF loupe is an auxiliary consumer of that generation, not a reason to create
  another camera stream.
- Entering VIDEO attaches Depth/Audio and activates recorder routing around the
  canonical RGB output.
- Leaving VIDEO detaches those consumers and restores MF delivery without
  replacing the source identity.
- Switching Standard/PRO or rear/front creates a new source generation; all old
  consumer callbacks become stale.

Future histogram, focus peaking, waveform, analysis, or telemetry consumers
must attach behind the software router. They may have independent processing
queues and drop policies, but they may not add another RGB output or block the
canonical capture callback.

Returning from TAP Library is also a source-restoration transaction. The
selected `VIDEO` UI state does not prove that the VIDEO capture graph survived
the library presentation. The return path must restore the active camera
source first, prepare the selected VIDEO graph second, and release the
viewfinder frost only after both operations succeed. If VIDEO preparation
fails, the UI returns to PHOTO instead of leaving an unbounded loading state.
Pending signing/export retries continue after restoration, but they are not
part of camera readiness and must not hold the frost.

## Recorded Artifact Trust and Signing Boundary

Once the recorder has finalized the app-owned MP4 and pending ingest has
accepted its capture/package identity, that file is the source artifact to
sign. Signing must not first ask a second AVFoundation reader to decide whether
the app's own RGB, audio, depth, calibration, or timeline semantics are healthy.

The production order is:

1. locate the single fixed proof slot and decode the TAP Video manifest;
2. match the pending record's capture ID and package ID;
3. reset only the proof slot and hash the exact MP4 bytes outside that slot;
4. create and write the proof for that content binding;
5. re-read the proof, recompute the same byte binding, and require
   `contentDigest` plus `signingBinding` to match before export;
6. repeat the byte-binding check after Photos original-resource readback.

`TAPVideoDepthTrackValidator` remains an explicit semantic health/analysis
capability. It may inspect actual tracks after proof authentication, but it does
not gate signing, normal Photos export, or Photos binding readback.

An unsigned app-produced video is not classified `failedTerminal` because a
manifest/health rule rejected it. Terminal video integrity states are reserved
for a persisted signed artifact whose proof/identity no longer matches its
bytes, an externally mutated pre-sign binding, or the existing capture-time
missing-depth contract.
