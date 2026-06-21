# 2026-06-21 AI Refactor Trace

## Shared Goal

Current goal: make TAPCamDemo readable from zero prior context, preserve the
current Release behavior, and prepare small extension seams for future image
format, quality, camera-control, security, and documentation work.

The current Release behavior must stay unchanged:

- Capture writes one HEIC with primary RGB, Apple auxiliary depth/disparity, and
  a TAP XMP manifest.
- Shutter-time capture stages unsigned private artifacts in TAP Library.
- The pending worker signs queued output with App Attest before Photos export.
- Final export re-reads the signed HEIC bytes and fails closed before Photos if
  the container, manifest, proof, digest, or auxiliary depth contract drifts.

Non-goal for this trace: adding visible JPEG/RAW/quality controls, Live Photo,
video, C2PA, or professional manual-camera UI.

## User Constraints

- Final acceptance is manual reading of all code and docs from zero context.
- Provide reading entry points and explain why each boundary exists.
- Use security-audit and iOS-development capabilities where relevant.
- Run in bounded iterations, score the project after each iteration, and stop
  after at most three iterations.
- Close subagents that are no longer needed.
- Keep code and docs compact enough to read; do not add broad feature scope.

## AI Tool Use

| Role | Scope | Result |
| --- | --- | --- |
| Main Codex agent | Read code/docs, make scoped patches, run local validation, maintain reading paths. | Owns final integration and score updates. |
| Codex Security skill review | Read security-scan workflow rules and used a scoped export-gate review instead of a full repository scan. | Confirmed final export must keep signed-byte reread, manifest schema/id checks, Release output facts, exactly-one App Attest proof, digest binding, and auxiliary depth validation. |
| iOS debugger/build skill review | Read iOS simulator build/debug workflow. | Used focused `xcodebuild test` on iOS Simulator for signed export validation. |
| Hooke subagent | Read-only security review of Release output facts and signed export invariants. | Recommended keeping `CaptureOutputManifestPolicy` small and not turning `CaptureOutputResourcePlan` into a byte/manifest validator. |
| Planck subagent | Read-only iOS naming review around App Attest startup and capture lifecycle. | Recommended a final naming cleanup so readers do not think foreground shutter capture blocks on network/App Attest signing. |
| Carver subagent | Read-only docs compression review. | Recommended compressing scorecard and future-spec entry layers without deleting evidence. |

All three subagents were closed after their conclusions were captured.

## Iteration 1

Focus: make output profile, resolved Runtime handoff, and quality policy easier
to read without changing Release capture behavior.

Important changes:

- Added `CaptureOutputProfileResolution.swift` for
  `ResolvedCaptureOutputProfile` and photo-output capability validation.
- Kept `CaptureOutputProfileCatalog.swift` focused on the executable Release
  catalog.
- Added `CapturePhotoQualityPolicy` language that AVFoundation `.quality` is a
  prioritization request, not a file-size or compression-ratio guarantee.
- Updated output docs, future camera specs, scorecard, and focused tests.

Validation completed in that iteration:

- Focused capture output profile tests passed.
- Full `xcodebuild test` passed.
- `git diff --check` passed.

Score after iteration 1: `8.7 / 10`.

## Iteration 2

Focus: remove inline Release manifest field comparisons from the final Photos
gate while preserving the same fail-closed signed-export behavior.

Important changes:

- Added `CaptureOutputManifestPolicy.swift` as the manifest-side view of the
  reviewed Release output facts.
- Updated `TAPCaptureProvenanceWriter.validateSignedExportHEIC` so final export
  still validates container, manifest schema/id, Release manifest facts,
  exactly-one App Attest proof, auxiliary depth, and digest binding in order.
- Added `captureOutputManifestPolicyRejectsReleaseFactDrift` to keep the policy
  unit-testable.
- Kept writer integration tests that prove Release output policy drift is
  rejected before Photos save.
- Updated output README, future camera specs, scorecard reading path, and tests
  README so a reader can find the new policy.
- Added this AI trace folder and linked it from the root documentation path.

Validation completed:

```bash
xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPSignedExportValidatorTests
```

Result: passed. The suite covered manifest policy drift, resource-plan source
guarding, non-HEIC rejection, proof rejection, manifest mismatch, missing
auxiliary depth, and multiple-proof rejection.

```bash
xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17'
```

Result: passed.

```bash
git diff --check
```

Result: passed with no whitespace errors.

## Iteration 3

Focus: make the camera lifecycle read as pending-capture maintenance instead of
foreground shutter dependency on App Attest or network work.

Important changes:

- Renamed the foreground capture client label to `pendingCaptureWorkerClient` so
  `CameraView.capture(...)` no longer reads as synchronous App Attest signing.
- Kept foreground capture passing `assertionSigner: nil`; signing/export remain
  pending-worker responsibilities after an unsigned HEIC is written.
- Renamed camera lifecycle actions to `warmPendingCaptureSigningCredential` and
  `retryPendingCaptures`.
- Renamed App Attest runtime tests from startup wording to pending-capture
  signing warmup wording.
- Added a short final-acceptance shortcut at the top of `ProjectScorecard`.
- Synced startup, CameraCapture, UI, future-spec, and test docs to use the same
  pending-signing vocabulary.

Validation completed:

```bash
xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests -only-testing:TAPCamDemoTests/AppAttestRuntimeTests
```

Result: passed.

```bash
xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17'
```

Result: passed.

```bash
git diff --check
```

Result: passed with no whitespace errors.

## Remaining Evidence Gaps

- Real-device App Attest and backend acceptance.
- Real Photos acceptance with positive real-depth HEIC evidence.
- Rendered UI/layout regression evidence.
- C2PA, RAW/Live Photo/video/multi-camera support.
- Professional manual camera controls as visible product features.
