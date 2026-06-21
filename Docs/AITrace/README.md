# AI Collaboration Trace

This folder records how AI-assisted work changed the project. It is a reading
aid for reviewers who want to trace why code and docs moved, which AI tools were
used, and how each iteration was validated.

It is not a raw transcript dump. Keep the trace readable by recording decisions,
constraints, files touched, subagent or plugin roles, validation commands, and
open follow-ups.

## Read First

1. [2026-06-21-assert-verification-panel-sync.md](2026-06-21-assert-verification-panel-sync.md)
   records the current `assert` branch verification-panel sync goal, how AI work
   is being traced, and which validation evidence is still pending.
2. [2026-06-21-refactor-trace.md](2026-06-21-refactor-trace.md) records the
   current readability/security refactor goal, iteration history, AI tool use,
   validation status, and next-round candidates.
3. [../ProjectScorecard.md](../ProjectScorecard.md) defines the score formula,
   strict gaps, current score, and from-scratch reading order.
4. [../FutureCameraSpecs.md](../FutureCameraSpecs.md) explains the refactor
   boundary status before future camera features are added.

## What To Record

Each trace file should answer these questions:

- What was the shared goal for this AI-assisted work?
- Which user constraints shaped the work?
- Which AI plugins, skills, or subagents were used, and for what scoped job?
- Which files changed, and what decision does each change support?
- Which validation commands ran?
- What remains intentionally unfinished?

Do not record secrets, raw App Attest key IDs, raw capture IDs, Photos asset
identifiers, backend payloads, HEIC bytes, private paths outside this checkout,
or unreviewed model reasoning. Keep the trace focused on auditable engineering
decisions.
