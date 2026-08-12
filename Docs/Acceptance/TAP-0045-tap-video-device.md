# TAP-0045 — TAP Video Device, Zero-Depth, Performance, And iCloud

- Status: `Draft — blocked until matrix and budgets are approved`
- Related Delivery: `TAP-0011`, `TAP-0057`
- Contract: `ProductContract §3.3`
- Build/Commit: `To be frozen before execution`
- Device/iOS Matrix: `Owner decision required`
- Human Confirmation: `Pending`

This procedure does not invent performance targets. Before execution, the owner
must approve the supported device/iOS/audio matrix, iteration counts, CPU/RSS/
dirty-memory/disk/thermal/drop and codec p50/p95 budgets, iCloud-only method,
and registration tolerance. The historical registration candidate is at most
one display pixel; it is not active until approved for this run.

AirPlay, Picture in Picture, and background playback are explicit non-goals and
are neither steps nor failure conditions.

## Preconditions

- A candidate build includes the zero-depth correction and current TAP Video
  capture/sign/export/readback/playback chain.
- Each device has enough storage/power and a recorded initial thermal state.
- Logs expose recorder/drop/writer/finalization, tracks/KLV, manifest/proof,
  export/readback, RSS/thermal, codec, and registration facts.
- Real iCloud-only media is available; inability to make an original genuinely
  remote is Blocked, not simulated success.
- Zero-depth uses a reproducible real scene or an owner-reviewed device-only
  hook that keeps true RGB/audio. Writer failure uses a reviewed safe hook.
- **Owner live:** attend capture, transitions, zero-depth, playback, and iCloud
  interaction.

## Reset And Install

1. Install the frozen signed build and record commit, device/iOS, signing
   environment, storage, memory, and thermal baseline.
2. Use a dedicated named test-media set; do not automatically delete Photos
   assets during acceptance.
3. Disable Low Power Mode and begin each performance group at the approved
   thermal state.
4. Run independent logs for Microphone data Off and On; On also requires OS
   authorization. Cold-launch cases must truly terminate the process.

## A. PRO Video Regression

For each approved LiDAR Pro and audio state, execute the owner-approved counts;
the current proposed minimum matrix is:

1. Cold launch → PRO → VIDEO → first recording: 10 cycles.
2. PRO Photo ↔ PRO Video: 20 cycles.
3. Standard VIDEO ↔ PRO VIDEO: 10 cycles.
4. Record for five seconds and stop: 10 cycles.
5. During recording: AF tap 10 times; first MF tap assist after re-entry 10
   times; full MF slider movement 10 times.
6. VIDEO → front → rear PRO: 10 cycles.
7. After every cycle, inspect frost, recording state, TAP Library entry, and the
   next recording readiness. Automation may repeat actions, but owner-observed
   physical execution is still required.

Expected: no first-recording starvation, zero-duration RGB, black screen,
wedge, false recording state, or missing prepared graph.

## B. Artifact And Writer Truth

1. For representative recordings inspect original MP4, manifest, proof,
   RGB/audio/KLV tracks, depth coverage, and drop counters.
2. Microphone Off produces no audio; On produces real audio; manifest and tracks
   agree.
3. Signed/exported/readback bytes bind correctly; the TAP Library poster and
   foreground RAW/registered 2D paths behave according to available facts.
4. Trigger one reviewed writer failure. The UI leaves recording immediately,
   the failed workspace never enters the Pending Capture Queue, the graph
   rebuilds, and the next recording succeeds.

## C. Zero-Depth Contract

1. Produce a valid RGB/optional-audio recording with zero stored depth.
2. **Owner live:** stop and observe one non-blocking Depth unavailable message.
3. Confirm the artifact is retained, the manifest reports zero/missing depth,
   and the record proceeds through Pending Capture Queue signing, Photos export,
   and original-resource readback.
4. **Owner live:** RAW playback works in TAP Library. 2D may be unavailable when
   depth/registration is absent, but the record must not become terminal.

## D. Duration, Codec, Memory, And Thermal

1. Under the approved matrix, record 15, 60, and 180 seconds at least three
   times per duration.
2. Capture RSS, dirty memory, disk bytes, RGB/depth/audio drops, compression
   ratio, encode p50/p95, and thermal state.
3. No RGB/audio drop may be hidden; every depth gap/drop is reflected in
   counters/manifest. Steady-state RSS must not grow linearly with duration and
   all values must meet the pre-approved budgets.
4. Run exact-byte codec round trip plus decode p50/p95 over the approved real
   depth corpus.
5. For representative 180-second media run RAW/2D play, seek, dismiss, and an
   approved symbolicated CPU trace.
6. Repeat open → 2D play → dismiss five times and capture a memgraph ownership
   report. Trace-file size is not heap evidence; whole-video `Data` and repeated
   viewer retention require explanation.

## E. Registration

1. Capture known landmarks and inspect the same-frame RGB/registered-depth
   display.
2. Measure display-space landmark error against the tolerance approved before
   execution. Do not revise the tolerance after observing the result.

## F. Real iCloud-Only Lifecycle

1. Prove a signed TAP Video original is not local.
2. **Owner live:** open it. Poster/low-resolution preview remains visible and
   progress is singular and non-regressing.
3. Swipe away and return during download; stale callbacks cannot replace the
   current item. Dismiss during download; the request cancels with no later UI
   mutation.
4. Reopen, finish download, and confirm RAW plus registered 2D when available.
5. Produce a real offline terminal download error, restore connectivity, and
   exercise the visible recovery path.

## Required Evidence

- Per-device/audio cycle tables and all recorder/drop/writer/finalization logs.
- Representative MP4/manifest/proof/readback audits and complete zero-depth
  state transition plus recording.
- Raw 15/60/180-second metric samples, codec corpus/results, symbolicated CPU
  trace, memgraph ownership report, and registration measurement.
- Proof of real iCloud-only state plus progress/cancel/stale-callback recovery
  recording.
- **Owner live:** written acceptance of capture, transition, zero-depth message,
  playback, iCloud UX, and final metric report.

## Verdict

- **Pass:** the approved matrix and budgets complete with zero regression-cycle
  failures, end-to-end non-blocking zero-depth, truthful artifacts, acceptable
  resource behavior, registration, and iCloud lifecycle; the owner accepts.
- **Fail:** starvation/black screen/wedge/false recording; zero-depth discard or
  terminal state; hidden media facts; linear or over-budget resources;
  unexplained ownership; registration beyond tolerance; or regressing,
  uncancellable, stale iCloud updates.
- **Blocked:** any matrix/budget is unapproved; required device/corpus/storage/
  iCloud state/hook/diagnostics is missing; the owner cannot attend; or only
  Simulator/automation evidence is available.
