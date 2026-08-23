# TAP-0092 Repository Cleanup Manifest

- Task: [`TAP-0092`](ProjectBoard.md#tap-0092--clean-up-brittle-tests-unmounted-legacy-code-and-redundant-repository-information)
- Status: `Validated — stopped after three consecutive score increases`
- Baseline: `main@42c5e9355cbcdf9e6a0d7c7f750aeb4ef54ecb6f`
- Execution date: `2026-08-23`
- Session: `/root` on the shared `main` checkout
- Product behavior change: `None`
- Visible UX/UI change: `None`
- Commit or push: `None`
- Evidence: [TAP-0092 cleanup evidence](TAP-0092CleanupEvidence.md)

This manifest records the bounded cleanup authorized by the product owner. The
Product Contract remains the behavior authority and the Project Board remains
the lifecycle authority. Git is the archive for deleted implementation and
historical prose.

## Safety Boundary

Delete only when reverse references and contract ownership show that an item is
unmounted, disabled, legacy-only, speculative, source-spelling-only, or fake
Simulator evidence. Retain:

- current Camera, TAP Library, Viewer, RAW/2D/3D, Share, Delete, and capture
  behavior;
- fail-closed signing, local integrity, App Attest runtime, privacy, recovery,
  state-machine, persistence, and cross-project format gates;
- physical-device tests that exercise real Camera/Photos artifacts, while
  excluding them from Simulator pass counts;
- compatibility readers and migration tests until a coordinated reset or
  compatibility decision removes the production reader atomically; and
- every current public/security schema version, even when another independent
  schema happens to use a larger number.

## Fixed Repository-Health Score

The same formula was used for all three iterations:

```text
repository score = 0.50D + 18(R / 3) + 22(Q / 137) + 10V
```

- `D = max(0, 100 - (2C + 5B + A/5 + H/100 + M + 5L + 2T + 100O))`
- `C`: known current-truth contradictions in the audited documentation set
- `B`: broken local Markdown targets
- `A`: brittle Markdown line-number anchors
- `H`: active historical/task-specific prose lines in the frozen audit set
- `M`: redundant single-inbound micro-documents not yet migrated
- `L`: retained legacy compatibility families awaiting an explicit decision
- `T`: unmarked pre-release TODO families
- `O`: lost current public/security obligations
- `R`: completed production closures out of the three frozen closures
- `Q`: removed low-value tests out of the frozen 137-test set
- `V`: 1 only when build, focused retained gates, references, links, and
  obligation checks show no new cleanup regression

| Checkpoint | D | R | Q | V | Score | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Frozen start | 20.0 | 0 | 0 | 1 | 20.0 | Baseline |
| Iteration 1 | 20.0 | 1 | 8 | 1 | 27.3 | Increase 1 |
| Iteration 2 | 20.0 | 2 | 9 | 1 | 33.4 | Increase 2 |
| Iteration 3 | 68.2 | 3 | 137 | 1 | 84.1 | Increase 3; stop |

The final documentation score uses `C=3`, `B=0`, `A=0`, `H=277`, `M=8`,
`L=3`, `T=0`, and `O=0`. The remaining contradictions are the old streaming
statement in the Camera pipeline micro-doc, the incomplete photo-only Pending
Queue description in the TAP Library README, and the stale queue-state summary
in [PACKAGING.md](../TAPCamDemo/CameraCapture/Documentation/PACKAGING.md). They are recorded instead of expanded into a fourth
iteration because the owner's stop rule is satisfied.

## Iteration 1 — Owned-Capture Backend Verify

Deleted the unmounted owned-capture backend Verify closure:

- `DepthAnalysis/AppAttestSignatureVerification.swift`
- `DepthAnalysis/AppAttestSignatureVerificationPanel.swift`
- the exclusive `PhotoLibraryWriter.SignatureVerificationResources` adapter
- `TAPAppAttestSignatureVerificationTests.swift` (8 tests)

The current Share path still performs local byte/content-binding validation and
still has explicit negative backend-dependency and privacy gates. External
verification remains owned by its separate product/cross-project tasks.

Validation: Debug Simulator test build passed; focused Share, local-resource,
and privacy run executed 60 tests with 58 passed and the same two baseline
failures.

## Iteration 2 — Speculative Output Resource Plan

Deleted `CameraCapture/Output/CaptureOutputResourcePlan.swift` and four tests
that only exercised that future planning model. It had no runtime caller and
incorrectly required auxiliary depth for a current no-depth-valid capture.
Current `CaptureOutputProfile`, package, manifest, signing, and final
pre-Photos validators remain.

Validation: Debug Simulator test build passed; focused output-profile and
signed-export run passed 39 of 39 tests.

## Iteration 3 — Legacy Analysis and Fake Evidence

Deleted the unmounted former DepthAnalysis drawer/inspector island, its exclusive
model/presentation slices, and `DepthAnalysisViewModel.swift`. The current Viewer
uses immutable carousel entries and `AnalysisPhotoSlot`; one active-slot
public-safe load-failure regression was added at that seam.

Also deleted:

- the never-mounted Debug metadata/score HUD;
- the Debug camera-control UI-test harness and its app launch branch;
- the false shutter UI smoke test that accepted `Capture failed` as success;
- screenshot-only/non-asserting UI performance cases;
- remaining frozen source-spelling, exact-copy/layout, fake/no-op, and orphan
  tests; and
- test-target-only marketing/build version assignments.

The two physical-device artifact audits remain in the source target but their
test declarations are excluded when compiling for Simulator. They prove local
Camera/Photos artifact handling with a synthetic signer; they do not prove App
Attest hardware/backend trust.

## Test Disposition

Baseline source declarations: `822`. Final source declarations: `670`, a net
reduction of `152`. The Simulator now exposes `668` executable tests: `664`
Unit tests plus `4` retained TAP Video interaction UI tests. The two retained
physical-device tests are not declared on Simulator.

The net reduction contains all `137` frozen low-value candidates, `16`
additional tests exclusive to deleted production islands, and one new current-
seam regression. Static gates were retained where source inspection is the
correct boundary for privacy, forbidden dependencies, public format binding,
streaming memory bounds, or final fail-closed ordering.

## Documentation Disposition

Updated the root, App, CameraCapture, Output, DepthAnalysis, and Tests READMEs to
describe current ownership and stable validation entry points. Removed old
prototype QA generations, stale manifest evidence, obsolete startup/acceptance
narrative, former inspector/ViewModel/Verify maps, repeated test inventories,
and all 47 brittle `#L` links from the plane design document.

Removed 94 localization keys whose exact literal came only from the deleted
Verify/inspector/HUD sources and had zero exact literal reference in current
Swift. Interpolated, App Intent, dynamic, and unrelated catalog keys were not
part of that closure.

Local Markdown target validation reports zero missing targets. Eight
CameraCapture micro-documents remain because their unique current obligations
must be migrated before deletion; this is represented by `M=8` above.

## Version Decisions and Pre-release TODO

TAP-0092 retained app version `0.2 (2)` and the then-current parallel schema
matrix. The owner subsequently superseded that format decision in `TAP-0093`:
the app version remains unchanged while every distinct current public/security
family starts at its own v1, and old development artifacts are unsupported.

Before the first public/open-source release:

1. Deliberately freeze or update app marketing/build version `0.2 (2)` once.
2. Freeze the public/security schema matrix, or perform one coordinated
   TAPCamVerifier and fixture migration. Resolved by `TAP-0093`.
3. Choose the developer-container reset/compatibility policy and an explicit
   Pending Capture schema policy before deleting HEIC aliases, global
   maintenance migrations, or startup compatibility fallbacks. Resolved by
   `TAP-0093`: clear development data; do not migrate it.
4. Consolidate prototype revision labels into one current approved revision
   without changing visual behavior.

These four marked families make `T=0`; marking a TODO is not permission to
perform the migration in TAP-0092.

## Retained Follow-ups

- Physical-device App Attest production acceptance remains TAP-0046.
- Debug-support isolation and large-suite file organization remain TAP-0029.
- TAP-0093 removed the startup fallback and Pending persistence migration
  families after the owner chose a clear-container pre-release policy. The
  owner subsequently removed the Verifier's old ZIP input, generic ZIP routing,
  and missing/invalid-sidecar fallback in favor of current `.tapnap` plus its v1
  sidecar.
- The known Share stale-callback, OSLog reviewed-label, Simplified Chinese
  catalog, and unsigned-Simulator Keychain failures are recorded in the evidence
  ledger; none is caused by a deleted path.

No fourth cleanup iteration is authorized by this pass: three consecutive score
increases have been reached.
