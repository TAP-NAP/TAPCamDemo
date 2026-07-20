# 2026-06-21 Assert Verification Panel Sync Trace

## Current Goal

Sync the `assert` branch's App Attest capture-signature verification panel into
the current branch without broad-merging unrelated branch history.

The score standard for this work is
[../ProjectScorecard.md](../ProjectScorecard.md). Any code or documentation
change in this pass should improve or preserve the current scorecard position:
readability from zero context, Release HEIC-depth behavior, App Attest proof
boundaries, private identifier handling, and validated test evidence.

## User Constraints Captured

- Final acceptance is manual reading of the code and documents from zero prior
  context.
- Every important change needs a readable entry point and a short explanation of
  why that boundary exists.
- Security-audit and iOS-development capabilities should be used where they add
  evidence, especially around App Attest, Photos export, SwiftUI presentation,
  and simulator validation.
- Work should finish within bounded iterations, with no more than three total
  implementation iterations for the shared goal.
- Subagents should be closed when their scoped review is no longer needed.
- The trace should record how AI helped the work, but should not store secrets,
  raw App Attest key IDs, raw capture IDs, Photos asset identifiers, backend
  payloads, HEIC bytes, or private paths outside this checkout.

## AI Working Method

1. Read the current branch first, including the scorecard and existing module
   READMEs, so integration follows the current architecture instead of copying a
   branch diff mechanically.
2. Inspect the `assert` branch verification-panel implementation and split it
   into current-branch boundaries if needed.
3. Keep UI presentation separate from raw proof, backend, Photos, and HEIC bytes
   so reviewers can verify that private material does not leak into visible
   SwiftUI text.
4. Run focused tests for the changed verification/presentation behavior before
   broader simulator validation.
5. Update this trace with the files changed, validation commands, score impact,
   and any intentionally unfinished evidence gaps.

## Current Session Log

- Started from the active goal: pull the `assert` branch verification-panel work
  into `refacteor_under_review` while referencing the score standard.
- Added this AI trace entry before implementation so reviewers can follow the
  work from goal, to code movement, to validation.
- Root README now points directly to this trace file and to
  [../ProjectScorecard.md](../ProjectScorecard.md) as the scoring standard.
- Selectively ported the verification-panel idea instead of copying the `assert`
  branch file: verification is split into a service/report model and a SwiftUI
  panel, and visible text omits raw backend URLs, raw request/response JSON,
  App Attest key IDs, assertion objects, capture IDs, digest values, Photos asset
  IDs, and pending capture IDs.

## Subagent State

No subagent is currently open. The main agent read the SwiftUI view-refactor
skill before splitting UI/service responsibilities, and read the Codex Security
diff-scan workflow to keep the verification-panel diff anchored to changed
security-relevant files. A formal security diff scan remains optional until
code validation is complete.

## Validation Status

- Score standard path: recorded.
- Current goal: recorded.
- AI work trace folder: [README.md](README.md) plus this session file.
- Code-level validation: focused suites, OSLog privacy harness, full Simulator
  suite, and whitespace check passed.

## Implementation Notes To Fill During Sync

Record the implementation in this section as it happens:

- Files changed: root README, AI trace docs, DepthAnalysis verification service,
  verification panel, panel routing, focused tests, DepthAnalysis README, test
  README, and scorecard reading path.
- Tests run:
  - `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPAppAttestSignatureVerificationTests -only-testing:TAPCamDemoTests/TAPDepthAnalysisPresentationTests`
  - `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPDiagnosticsOSLogPrivacyTests`
  - `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17'`
  - `git diff --check`
- Security/iOS review notes: UI and service are split; the panel does not render
  raw backend, proof, digest, Photos, or pending identifiers. The service reuses
  the final signed-export validator before submitting the stored App Attest
  signing material to the configured backend.
- Score impact: held at `8.7 / 10`. This improves the local verification and
  presentation boundary, but does not add real Photos asset verification, real
  backend acceptance, rendered panel layout, or real-device App Attest evidence.
- Remaining evidence gaps: real backend acceptance, real Photos asset
  verification, and rendered panel layout.
