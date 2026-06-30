# Camera Controls, Output, And Score Acceptance

Date: 2026-07-01

## Scope

This report preserves the current acceptance evidence for:

- EV, ISO, shutter, AF, and MF camera controls.
- CameraCapture control UI regression through simulated clicks.
- Physical-device capture output, Photos readback, depth, proof slot, manifest policy, and capture score summary.

C2PA remains out of scope for this slice.

## User-Attended Real-Device Acceptance

The EV, ISO, shutter, AF, and MF controls were accepted during user-attended real-device testing before this report was written.

This evidence is recorded as manual acceptance, not as an automated Codex result bundle.

## Codex UI Regression Evidence

Simulator: iPhone 17 Pro, iOS 26.5, UDID `742A3184-E1C7-44FC-99E0-0C8DFE807698`.

Build:

```sh
xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination generic/platform=iOS\ Simulator -derivedDataPath /tmp/TAPCamDemoCameraControls-DD
```

Result: passed.

Source/design regression:

```sh
xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath /tmp/TAPCamDemoCameraControls-DD -resultBundlePath /tmp/TAPCamDemoCameraControlsPresentationSuite-20260701.xcresult -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests
```

Result: passed, 49 tests.

Simulated-click UI regression:

```sh
xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=742A3184-E1C7-44FC-99E0-0C8DFE807698 -derivedDataPath /tmp/TAPCamDemoCameraControls-DD -resultBundlePath /tmp/TAPCamDemoCameraControlsAcceptance-20260701.xcresult -only-testing:TAPCamDemoUITests/CameraControlsRegressionUITests/testCameraControlToolbarAndAdjustmentStripsRespondToSimulatedClicks
```

Result: passed, 1 test.

Coverage:

- The Debug-only harness reuses production `CameraCaptureControlsView`.
- The UI test taps `EV`, `ISO`, `S`, `AF/MF`, and `VIDEO`.
- The UI test drags the shared `ticked adjustment strip` for EV, ISO, shutter, and MF lens position.
- `VIDEO` remains unavailable and shows the expected `Coming soon` behavior.

The harness does not instantiate AVFoundation, Photos, signing, or capture pipelines; those are covered by the device audit below.

## Physical-Device Output And Score Evidence

Device: `harold_android`, iPhone 15 Pro, UDID `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`.

Command:

```sh
xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7 -derivedDataPath /tmp/TAPCamDemoOutputScoringDevice-DD -resultBundlePath /tmp/TAPCamDemoOutputScoringDeviceAudit-2.xcresult -only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests -skip-testing:TAPCamDemoUITests
```

Result: passed, 2 tests.

Coverage:

- `jpgPhysicalDeviceCaptureExportsAndReadsBackFromPhotos()` passed.
- `exportedPhysicalDeviceCaptureArtifactsReadBackFromPhotos()` passed.
- The live JPG capture selected `release.photo-depth.jpg`, container `jpeg`, codec `jpeg`, dimensions `4032x3024`.
- The live JPG was saved to Photos and read back as original data with `2,274,298` bytes.
- The readback audit validated depth data, proof slot envelope, manifest policy, and capture score summary.
- Two existing exported artifacts were also read back from Photos with original data sizes `3,950,820` bytes and `5,864,305` bytes.

The audit writes JSON reports in the test app temporary directory:

- `TAPDeviceCaptureJPEGAudit.json`
- `TAPDeviceCaptureArtifactAudit.json`

The report schema now includes:

- `captureScoreValue`
- `captureScoreGrade`
- `captureScoreDetail`

The score detail is checked as public-safe: it must not expose capture IDs, Photos asset IDs, or signing key/proof identifiers.

The audit assertion is container-aware: JPEG output must be larger than `100,000` bytes, while non-JPEG output keeps the `1,000,000` byte sanity threshold. This avoids rejecting valid lower-entropy JPEG scenes while still catching empty or truncated output.

## Known Limits

- The Debug-only UI harness proves control composition and interaction, not camera hardware behavior.
- The device audit uses a test assertion proof shape and does not prove production backend App Attest acceptance.
- Capture UI still does not show trusted state, depth state, or score state as persistent chrome.
