# AI Collaboration Trace

This folder records how AI-assisted work changed the project. It is a reading
aid for reviewers who want to trace why code and docs moved, which AI tools were
used, and how each iteration was validated.

It is not a raw transcript dump. Keep the trace readable by recording decisions,
constraints, files touched, subagent or plugin roles, validation commands, and
open follow-ups.

## Read First

1. [2026-07-12-video-library-pr7-runtime-evidence.md](2026-07-12-video-library-pr7-runtime-evidence.md)
   records the final Simulator unit/UI/screenshot and five-cycle lifecycle
   evidence, the playback issues found and fixed while exercising the harness,
   the source hard-gate audit, and the ETTrace, memgraph, device, iCloud, Photos,
   thermal, and registration evidence that remains explicitly unmeasured. Its
   2026-07-12 addendum is the controlling viewer decision: Photo and Video share
   Back/Share/Delete plus the `RAW` / `2D` / disabled-video-`3D` capsule, while
   `AVPlayerLayer` and SwiftUI custom transport replace the earlier historical
   `AVPlayerViewController` evidence.
2. [2026-07-11-video-library-refactor-implementation.md](2026-07-11-video-library-refactor-implementation.md)
   records the implementation of canonical Library identity, explicit iCloud
   request state, poster/backfill/cache policy, manifest v2 and bounded BMFF,
   single-artifact signing, Photos readback recovery, the initial system-player
   implementation later superseded by item 1's addendum, runtime fixture
   coverage, validation performed, and device evidence still pending.
3. [2026-07-10-video-library-risk-research.md](2026-07-10-video-library-risk-research.md)
   records the read-only `video` branch review and broader release-readiness
   research: recent-cover identity, iCloud load states, player/depth overlay
   ownership, whole-file memory and disk amplification, raw depth compression,
   manifest truth, Photos round-trip, crash recovery, and the profiling gates
   that remain intentionally unmeasured.
4. [2026-07-06-locked-camera-black-screen-start-running.md](2026-07-06-locked-camera-black-screen-start-running.md)
   records the real-device Locked Camera Capture black-screen investigation:
   the UI flashed and then the secure capture surface stayed black because the
   extension aborted in `AVCaptureSession.startRunning()` before the session
   configuration was committed. It records the crash-log evidence, the fix, and
   the validation evidence after reinstalling to the physical iPhone.
5. [2026-07-05-analysis-viewer-carousel-3d-linkage.md](2026-07-05-analysis-viewer-carousel-3d-linkage.md)
   records the Analysis viewer native-photo redesign implementation, including
   stable bottom chrome, `previous/current/next` carousel slots,
   thumbnail-first Photos loading with original download progress, 2D overlay
   plus per-photo Plane state, native SceneKit 3D projection, RGB color
   back-projection, and 2D Plane selection blinking in 3D.
6. [2026-07-02-live-photo-implementation.md](2026-07-02-live-photo-implementation.md)
   records the app-side Live Photo capture/sign/export implementation, the
   `depth-manifest:v2` plus `content-binding:v3` extension contract, and the
   browser/server repository boundary. It also records the TAPCam
   verification-original export path for still photos and Live Photo ZIP
   packages, plus the HEIC/MOV hash-chain documentation intended to seed later
   verifier work and technical whitepapers.
7. [2026-07-02-basic-ev-pro-controls-build-isolation.md](2026-07-02-basic-ev-pro-controls-build-isolation.md)
   records the decision to separate ordinary Basic EV from experimental Pro
   Controls at compile time, using `TAP_ENABLE_PRO_CAMERA_CONTROLS`, with no
   runtime Pro Controls toggle and a Release fail-build guard.
8. [2026-07-02-manual-control-device-limits.md](2026-07-02-manual-control-device-limits.md)
   records the decision that missing ISO/shutter/MF support on the tested
   iPhone 15 Pro camera path is an Apple active-device capability limit, not a
   TAPCam UI gap; it also separates Phase 1 preview-only LiDAR zoom from the
   future source-switching roadmap.
9. [2026-06-30-camera-ux-stage-one-shell.md](2026-06-30-camera-ux-stage-one-shell.md)
   records the first-stage camera UX shell and control wiring, including the
   agreed `CameraControlsDesign` vocabulary, Dynamic Island shoulder chrome,
   global EV writes, flash handoff, basic tap focus, temporary focus EV, AE/AF
   lock, direct ISO/shutter/lens-position controls, Settings-owned guides and
   LiDAR Focus Assist, keep-awake policy, non-rotating disabled mode selector,
   No Depth output behavior, first-stage analysis scoring, App Intents
   latest/selected-score surface plus Camera/TAP Library handoff, and scorecard
   update.
10. [2026-06-22-multi-format-photo-implementation.md](2026-06-22-multi-format-photo-implementation.md)
   records the implementation for HEIC/JPG TAP depth photo output, max photo
   dimensions, Settings preference, storage/provenance/analysis generalization,
   validation status, and the plan-specific score.
11. [2026-06-22-multi-format-photo-research.md](2026-06-22-multi-format-photo-research.md)
   records the research for HEIC/JPEG output support, max photo dimensions, and
   how selected-camera capabilities should shape the implementation plan.
12. [2026-06-21-tap-library-scroll-memory.md](2026-06-21-tap-library-scroll-memory.md)
   records the current TAP Library scroll-memory plan, the foreground-return
   preference decision, and the plan-specific score rubric for this user journey.
13. [2026-06-21-assert-verification-panel-sync.md](2026-06-21-assert-verification-panel-sync.md)
   records the current `assert` branch verification-panel sync goal, how AI work
   is being traced, and which validation evidence is still pending.
14. [2026-06-21-refactor-trace.md](2026-06-21-refactor-trace.md) records the
   current readability/security refactor goal, iteration history, AI tool use,
   validation status, and next-round candidates.
15. [../ProjectScorecard.md](../ProjectScorecard.md) defines the score formula,
   strict gaps, current score, and from-scratch reading order.
16. [../FutureCameraSpecs.md](../FutureCameraSpecs.md) explains the refactor
   boundary status before future camera features are added.

## What To Record

Each trace file should answer these questions:

- What was the shared goal for this AI-assisted work?
- Which user constraints shaped the work?
- Which AI plugins, skills, or subagents were used, and for what scoped job?
- Which files changed, and what decision does each change support?
- Which scoring rubric applies, what the score is after the change, and why it
  changed or stayed the same?
- Which validation commands ran?
- What remains intentionally unfinished?

Do not record secrets, raw App Attest key IDs, raw capture IDs, Photos asset
identifiers, backend payloads, photo bytes, private paths outside this checkout,
or unreviewed model reasoning. Keep the trace focused on auditable engineering
decisions.
