# TAP-0092 Cleanup Evidence

- Date: `2026-08-23`
- Task: [`TAP-0092`](ProjectBoard.md#tap-0092--clean-up-brittle-tests-unmounted-legacy-code-and-redundant-repository-information)
- Manifest: [TAP-0092 cleanup manifest](TAP-0092CleanupManifest.md)
- Destination: iPhone 17 Pro, iOS 26.5 Simulator,
  `742A3184-E1C7-44FC-99E0-0C8DFE807698`
- Xcode/macOS: Xcode 26.6 / macOS 26.6
- Commit or push: `None`

## Outcome

Three independently validated cleanup iterations increased the fixed repository
score from `20.0` to `27.3`, `33.4`, then `84.1`. The owner stop rule is
satisfied. No mounted product route, visible UX/UI, public format, persistence
reader, or security/privacy obligation was intentionally changed.

## Quantitative Delta

| Measure | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| Production Swift LOC | 72,558 | 69,020 | -3,538 |
| Test Swift LOC | 29,132 | 24,727 | -4,405 |
| Test source declarations | 822 | 670 | -152 |
| Simulator-executable tests | 822 | 668 | -154 |
| Localization catalog keys | 471 | 377 | -94 |
| Brittle Markdown `#L` anchors | 47 | 0 | -47 |
| Missing local Markdown targets | 0 | 0 | 0 |
| Lost current public/security obligations | 0 | 0 | 0 |

The final 668 Simulator tests are 664 Unit tests and four retained TAP Video UI
interaction tests. Two physical-device artifact tests remain in source but are
compiled out of the Simulator test inventory instead of returning early and
being reported as passes.

## Deleted Production Closures

### Iteration 1

- `AppAttestSignatureVerification.swift`
- `AppAttestSignatureVerificationPanel.swift`
- exclusive `PhotoLibraryWriter` signature-verification resource adapter

Reverse-reference result: zero production/test Swift references after deletion.
The active Share/resource loaders retain explicit no-backend-dependency gates.

### Iteration 2

- `CaptureOutputResourcePlan.swift`

Reverse-reference result: zero production/test Swift references after deletion.
Current output profile, package, manifest, signing, and validator code remains.

### Iteration 3

- ten former drawer/inspector files and their exclusive model/presentation
  slices
- `DepthAnalysisViewModel.swift`
- `DepthAnalysisMetadataHUD.swift`
- `CameraControlsUITestHarnessView.swift` and its launch branch

The Viewer still routes through `DepthAnalysisCarouselState`, `AnalysisPhotoSlot`,
`DepthAnalysisStageView`, and the current RAW/2D/3D/Share/Delete controls.
The removed HUD's only construction supplied two nil values, so it never
rendered even in Debug.

## Test Cleanup

Removed all 137 candidates in the frozen low-value set:

- source-spelling and implementation-shape assertions;
- exact copy, order, pixel, and layout assertions with no durable contract;
- fake Debug harness and screenshot-only/non-asserting UI cases;
- orphan-code tests; and
- the owned-capture backend Verify mock/source suite.

Deleted 16 more tests that were exclusive to the additional proven-dead
production islands. Added one current `AnalysisPhotoSlot` public-safe failure
regression. Retained the static security/privacy/architecture gates and current
format, signing, persistence, migration, state-machine, cancellation, and
device-only artifact regressions.

## Validation Runs

| Gate | Result | Result path |
| --- | --- | --- |
| Iteration 1 build-for-testing | Passed | `/private/tmp/TAP0092Iteration1Derived` |
| Iteration 1 focused | 60 total / 58 passed / 2 known failed / 0 skipped | `/private/tmp/TAP0092Iteration1Focused-20260823.xcresult` |
| Iteration 2 build-for-testing | Passed | `/private/tmp/TAP0092Iteration2Derived` |
| Iteration 2 focused | 39 / 39 passed | `/private/tmp/TAP0092Iteration2Focused-20260823.xcresult` |
| Iteration 3 build-for-testing | Passed | `/private/tmp/TAP0092Iteration3Derived` |
| Iteration 3 focused retained gates | 161 total / 159 passed / 2 known failed / 0 skipped | `/private/tmp/TAP0092Iteration3Focused-20260823.xcresult` |
| Iteration 3 full Unit target | 664 total / 655 passed / 9 failed / 0 skipped | `/private/tmp/TAP0092Iteration3FullUnit-20260823.xcresult` |
| Iteration 3 serialized failure diagnostics | 109 total / 105 passed / 4 failed / 0 skipped | `/private/tmp/TAP0092Iteration3FailureDiagnostics-20260823.xcresult` |

The full Unit target's five additional failures were concurrency-sensitive.
They passed in the serialized diagnostic run:

- four `TAPCameraManualFocusRuntimeTests` timeout cases; and
- `LibraryMediaTests.storeChangeObservationIsInertAndIdempotentUntilActivated`.

The four serialized failures are not deletion regressions:

- `TAPDepthAnalysisSharePresentationTests.staleSheetCallbacksCannotDismissANewerShareAttempt`
  was a frozen baseline persistent failure.
- `TAPDiagnosticsOSLogPrivacyTests.osLogInterpolationsDeclareReviewedPrivacy`
  was a frozen baseline persistent reviewed-label drift. The gate remains.
- `TAPLocalizationTests.catalogHasSimplifiedChineseForPrioritySurfaces` was a
  frozen baseline missing-localization failure. The gate remains.
- `StartupInitializationPolicyTests.corruptKeychainDeviceGenerationRepairsInPlace`
  receives `errSecMissingEntitlement` (`-34018`) in the unsigned Simulator test
  build. No startup production or test code in that path was changed.

## Static and Documentation Gates

- Deleted production/test symbols: zero Swift references.
- Deleted active-document paths: zero non-ledger references.
- `Prototype/manifest.json`: valid JSON.
- `git diff --check`: passed.
- Local Markdown targets: zero missing.
- Brittle Markdown line anchors: zero.
- Current public/security obligation loss: zero.
- Localization closure: exactly 94 removed, zero added; catalog JSON,
  `xcstringstool` print/compile, and generated en/zh-Hans plist lint passed.

## Device and App Attest Boundary

`TAPDeviceCaptureArtifactAuditTests` stays device-only. Its signer uses synthetic
test material, so it validates the local Camera-to-Pending-to-Photos artifact
shape but cannot close App Attest trust. Simulator, source scans, mock signers,
and local validators do not replace TAP-0046's physical-device plus production-
backend acceptance procedure.

## Documentation Impact

- Project Board: scope, score stop rule, implementation, validation, residual
  failures, and handoff synchronized by the Board Steward.
- Product Contract: N/A; current behavior and claim boundaries unchanged.
- UI prototype/manifest: historical QA evidence removed; visual revision and
  approved behavior unchanged.
- UI Prototype Contract: N/A; workflow unchanged.
- Module READMEs: root, App, CameraCapture, Output, DepthAnalysis, and Tests
  current-reading paths clarified.
- Specialized contracts: App Attest endpoint prose corrected; public format
  versions retained.
- Acceptance: obsolete TAP-0082 attempt history removed; TAP-0046 device trust
  boundary retained.
- AGENTS.md: N/A; repository workflow unchanged.

## Remaining Risks

Eight CameraCapture micro-documents still require obligation migration before
deletion. Startup, Pending persistence, and legacy verifier-input compatibility
remain reset/cross-project decisions. Four pre-release TODO families are marked
in the manifest. Per the owner's stop rule, these are not expanded into a fourth
cleanup iteration.
