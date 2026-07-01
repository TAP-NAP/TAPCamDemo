# AI Collaboration Trace

This folder records how AI-assisted work changed the project. It is a reading
aid for reviewers who want to trace why code and docs moved, which AI tools were
used, and how each iteration was validated.

It is not a raw transcript dump. Keep the trace readable by recording decisions,
constraints, files touched, subagent or plugin roles, validation commands, and
open follow-ups.

## Read First

1. [2026-07-02-manual-control-device-limits.md](2026-07-02-manual-control-device-limits.md)
   records the decision that missing ISO/shutter/MF support on the tested
   iPhone 15 Pro camera path is an Apple active-device capability limit, not a
   TAPCam UI gap; it also separates Phase 1 preview-only LiDAR zoom from the
   future source-switching roadmap.
2. [2026-06-30-camera-ux-stage-one-shell.md](2026-06-30-camera-ux-stage-one-shell.md)
   records the first-stage camera UX shell and control wiring, including the
   agreed `CameraControlsDesign` vocabulary, Dynamic Island shoulder chrome,
   global EV writes, flash handoff, basic tap focus, temporary focus EV, AE/AF
   lock, direct ISO/shutter/lens-position controls, Settings-owned guides and
   LiDAR Focus Assist, keep-awake policy, non-rotating disabled mode selector,
   No Depth output behavior, first-stage analysis scoring, App Intents
   latest/selected-score surface plus Camera/TAP Library handoff, and scorecard
   update.
3. [2026-06-22-multi-format-photo-implementation.md](2026-06-22-multi-format-photo-implementation.md)
   records the implementation for HEIC/JPG TAP depth photo output, max photo
   dimensions, Settings preference, storage/provenance/analysis generalization,
   validation status, and the plan-specific score.
4. [2026-06-22-multi-format-photo-research.md](2026-06-22-multi-format-photo-research.md)
   records the research for HEIC/JPEG output support, max photo dimensions, and
   how selected-camera capabilities should shape the implementation plan.
5. [2026-06-21-tap-library-scroll-memory.md](2026-06-21-tap-library-scroll-memory.md)
   records the current TAP Library scroll-memory plan, the foreground-return
   preference decision, and the plan-specific score rubric for this user journey.
6. [2026-06-21-assert-verification-panel-sync.md](2026-06-21-assert-verification-panel-sync.md)
   records the current `assert` branch verification-panel sync goal, how AI work
   is being traced, and which validation evidence is still pending.
7. [2026-06-21-refactor-trace.md](2026-06-21-refactor-trace.md) records the
   current readability/security refactor goal, iteration history, AI tool use,
   validation status, and next-round candidates.
8. [../ProjectScorecard.md](../ProjectScorecard.md) defines the score formula,
   strict gaps, current score, and from-scratch reading order.
9. [../FutureCameraSpecs.md](../FutureCameraSpecs.md) explains the refactor
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
