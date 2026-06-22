# Multi-Format Photo Implementation Trace

## Goal

Implement the TAP multi-format photo output plan:

- HEIC and JPG are both reviewed TAP depth photo profiles.
- HEIC remains the default.
- JPG is not a HEIC fallback.
- Runtime chooses the largest standard supported still-photo dimensions for the
  selected camera and format.
- Unsupported file type, codec, depth, quality, or dimensions block capture
  instead of silently falling back.

## User Constraints

- Keep code and documents readable for a reviewer with no prior project context.
- Prefer dedicated code for dedicated product behavior.
- Record the AI-assisted work so later reviewers can trace why files moved.
- The score for this round should evaluate this multi-format plan, not the
  whole historical project.
- Avoid unnecessary subagents and close or avoid unused parallel work.

## AI Tool Use

- iOS development skill used: `build-ios-apps:swiftui-ui-patterns`, only for the
  Settings picker shape and SwiftUI placement guidance.
- No subagents were spawned, so there were no subagents to close.
- No security scan subagent was run for this implementation round; the code
  stayed within the already-reviewed provenance, storage, and public-safe
  diagnostics boundaries.

## Implementation Summary

### Output Profile And Capability

- Added `CapturePhotoFileContainer` for `.heic` and `.jpeg`.
- Added `CapturePhotoDimensions` and `.largestStandardSupported`.
- Added `releasePhotoDepthJPEG` next to the existing HEIC profile.
- Extended `CapturePhotoOutputCapabilitySnapshot` to validate:
  - available photo file types
  - per-file-type codec support
  - active-format supported dimensions
  - configured max photo dimensions
  - depth support and depth delivery state
  - max quality prioritization
- Resolution now fails closed when the selected camera cannot satisfy the
  selected profile.

### Runtime

- `CaptureSessionController` now sets `photoOutput.maxPhotoDimensions` during
  session configuration.
- Graph reuse now considers file container and resolved dimensions.
- `SingleCamPhotoSettingsFactory` builds settings with explicit processed file
  type, codec, `AVVideoQualityKey = 1.0`, depth flags, quality prioritization,
  and per-shot `settings.maxPhotoDimensions`.
- Added public-safe `CameraCapture` OSLog entries for:
  - available file types, codecs, supported dimensions, selected dimensions
  - configured `AVCapturePhotoOutput.maxPhotoDimensions`
  - per-shot file type, codec, and `settings.maxPhotoDimensions`
  - resolved photo dimensions after `AVCapturePhoto` returns
  - base and packaged photo byte counts after ImageIO materialization

### Settings

- Added `CameraOutputFormatPreference`, defaulting to HEIC.
- Added `Picker("Photo Format")` in Settings.
- `CameraViewModel` resolves the stored preference through
  `CaptureOutputProfileSelectionIntent` before configuring Runtime.

### Packaging, Pending Store, Photos, And Analysis

- Generalized the HEIC-only writer/reader/provenance path into TAP depth photo
  file handling, while retaining HEIC compatibility wrappers.
- Pending records now store selected file container and container-specific
  unsigned/signed filenames.
- Pending bundle allow-list includes `unsigned.heic`, `signed.heic`,
  `unsigned.jpg`, and `signed.jpg`.
- Photos export uses the validated artifact container to write `UTType.heic` or
  `UTType.jpeg`. The physical-device JPG audit showed that
  `PHAssetCreationRequest.addResource(with:data:)` can strip the JPG XMP
  manifest on Photos round-trip, so the writer now stages the final artifact as
  a `.heic` or `.jpg` temp file and imports it with `addResource(with:fileURL:)`.
- Depth Analysis reads TAP HEIC/JPG photo files and still requires TAP manifest,
  App Attest proof where validation is requested, and Apple auxiliary depth.

## Reading Entry For This Change

1. `TAPCamDemo/CameraCapture/Output/README.md`
2. `TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift`
3. `TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift`
4. `TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift`
5. `TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift`
6. `TAPCamDemo/CameraCapture/UI/CameraOutputFormatPreference.swift`
7. `TAPCamDemo/TAPLibrary/TAPPendingCaptureRecord.swift`
8. `TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift`
9. `TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift`
10. `TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift`
11. `TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift`
12. `TAPCamDemo/DepthAnalysis/DepthAnalysisReader.swift`
13. `TAPCamDemoTests/TAPCaptureOutputProfileTests.swift`
14. `TAPCamDemoTests/TAPLibraryStorageTests.swift`
15. `TAPCamDemoTests/TAPSignedExportValidatorTests.swift`
16. `TAPCamDemoUITests/ShutterCaptureSmokeTests.swift`
17. `TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests.swift`

## Plan Score

Score for this implementation plan after the unlocked physical-device JPG/HEIC
artifact audit and shutter UI smoke test:
**9.3 / 10**.

What is strong:

- HEIC/JPG are explicit profile choices with HEIC default.
- Runtime now configures max still-photo dimensions instead of relying on the
  per-shot smallest-dimension default.
- Unsupported file type, codec, depth, quality, and dimension combinations
  fail closed.
- Pending storage, Photos export, and analysis no longer hard-code HEIC as the
  only TAP artifact.
- Real-device console logs now prove the selected default HEIC profile resolves
  to `4032x3024`, the active device advertises `4032x3024|5712x4284`, and the
  configured output also uses `4032x3024`.
- A dedicated UI smoke-test target now exists for future simulated shutter
  clicks instead of relying on ad hoc coordinate tapping.
- A source-level presentation test now locks the UI smoke-test anchors:
  `TAPCAM_UI_TEST_REAL_APP`, `camera.capture.shutter`, and
  `camera.capture.status`.
- The focused real-device UI smoke test now enables XCTest automation on the
  unlocked device, finds `camera.capture.shutter`, taps it, and verifies the
  `camera.capture.status` element remains available.
- A physical-device artifact audit test now reads exported TAP photo records
  back from Photos and checks original photo bytes, container, manifest policy,
  Apple auxiliary depth, image dimensions, depth dimensions, and proof count.
- The same audit file now also has a focused physical-device JPG path that sets
  the format preference to JPG, configures the real camera through
  `CameraViewModel`, runs the production capture pipeline into an injected
  pending store, signs with an App-Attest-shaped test proof, exports through the
  live Photos writer, reads original bytes back from Photos, and writes
  `TAPDeviceCaptureJPEGAudit.json`.
- On the connected iPhone 15 Pro, the audit read two exported HEIC artifacts:
  - `8,435,378` bytes, image `4032x3024`, depth `640x480`, proof count `1`
  - `6,051,160` bytes, image `4032x3024`, depth `768x576`, proof count `1`
- On the same connected iPhone 15 Pro, the focused JPG audit captured, signed,
  exported, and read back one JPG artifact from Photos:
  - `3,384,792` bytes, image `4032x3024`, depth `768x576`, proof count `1`
- The JPG audit caught a real implementation bug: data-based Photos import
  saved the asset but the round-tripped original missed `tapdepth:Manifest`.
  Switching Photos import to file URL preserved the exact JPG byte count and
  made the audit pass.
- Documentation now gives a readable path for zero-context review.

Why it is not higher:

- Real App Attest/backend acceptance still needs attended device validation.
- The physical-device audit uses an App-Attest-shaped test proof, not the
  production backend.
- The unsupported-camera/unsupported-format block path still needs attended
  device matrix coverage beyond the current iPhone 15 Pro.
- 24 MP deferred photo delivery is intentionally out of scope.

## Validation

- `git diff --check` passed after documentation edits.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator'`
  passed after the multi-format implementation.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TAPCamDemoGenericBuild`
  passed after adding the UI smoke-test target.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TAPCamDemoFinalGenericBuild`
  passed after adding documentation and the source-level smoke-test anchor
  guard.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/TAPCamDemoFinalSimulatorBuild`
  passed after the final trace update.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TAPCamDemoJPEGAuditBuildQuiet2`
  passed after adding the focused physical-device JPG audit test.
- `xcodebuild build -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -configuration Debug -destination 'id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7' -derivedDataPath /private/tmp/TAPCamDemoDeviceBuild`
  passed on the connected iPhone 15 Pro.
- `xcrun devicectl device install app --device 8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7 /private/tmp/TAPCamDemoDeviceBuild/Build/Products/Debug-iphoneos/TAPCamDemo.app`
  installed the app on the connected device.
- `xcrun devicectl device process launch --console --environment-variables '{"OS_ACTIVITY_DT_MODE":"YES"}' ...`
  produced real-device logs showing:
  - `selectedDimensions=4032x3024`
  - `availableFileTypes=org.nema.dicom|public.heic|public.jpeg|public.tiff`
  - `availableCodecs=hvc1|jpeg`
  - `supportedDimensions=4032x3024|5712x4284`
  - `configuredDimensions=4032x3024`
- `xcodebuild test ... -only-testing:TAPCamDemoUITests/ShutterCaptureSmokeTests/testTappingShutterRequestsDepthCapture`
  was attempted twice on the connected device. Both attempts failed before the
  test method ran because XCTest timed out while enabling automation mode.
- `xcodebuild test -quiet ... -only-testing:TAPCamDemoTests/TAPCameraCapturePresentationTests/cameraUISmokeTestAnchorsStayExplicit`
  passed on the connected device, proving the new UI-test anchor source guard
  is runnable without device UI automation mode.
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7' -only-testing:TAPCamDemoTests -derivedDataPath /private/tmp/TAPCamDemoArtifactAuditTargetTest -resultBundlePath /private/tmp/TAPCamDemoArtifactAuditTargetTest.xcresult`
  ran the app-hosted test target on the connected device. The target as a whole
  failed because many source-inspection tests are not designed to read checkout
  files from a physical-device sandbox, but
  `TAPDeviceCaptureArtifactAuditTests/exportedPhysicalDeviceCaptureArtifactsReadBackFromPhotos()`
  passed.
- The audit report was copied from the device with
  `xcrun devicectl device copy from ... --source 'tmp/TAPDeviceCaptureArtifactAudit.json' --destination /private/tmp/TAPDeviceCaptureArtifactAudit.json`.
  It contains no raw capture IDs or Photos asset identifiers.
- `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7' -only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests -derivedDataPath /private/tmp/TAPCamDemoJPEGAuditDeviceTest -resultBundlePath /private/tmp/TAPCamDemoJPEGAuditDeviceTest.xcresult`
  was attempted for the focused HEIC/JPG artifact audit suite. Xcode stopped at
  destination preflight with `Unlock harold_android to Continue`; the device
  display was lit but inactive, and the run was interrupted to avoid waiting
  indefinitely.
- The focused audit was attempted again with
  `/private/tmp/TAPCamDemoJPEGAuditDeviceTest2`; it reached the same Xcode
  destination preflight state: `Unlock harold_android to Continue`.
- The test README now records the cleaner rerun command with
  `-only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests` and
  `-skip-testing:TAPCamDemoUITests`, so the next attended run avoids unrelated
  UI test target noise.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoFocusedAuditCommandCheck`
  passed, confirming the documented focused audit arguments are accepted by
  `xcodebuild` without needing an unlocked device.
- After the device was unlocked,
  `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7' -only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoJPEGAuditDeviceTestUnlocked -resultBundlePath /private/tmp/TAPCamDemoJPEGAuditDeviceTestUnlocked.xcresult`
  reached the real device and showed why the audit needed tightening:
  Swift Testing ran the two physical-device audit tests concurrently, and the
  JPG path wrote a pending record but the test still failed with
  `.recordNotFound("jpeg")`.
- `TAPDeviceCaptureArtifactAuditTests` was changed to `@Suite(.serialized)`,
  and the JPG path now waits for the container-specific record in its injected
  temp store instead of using a fragile captured-time cutoff.
- The next unlocked run,
  `/private/tmp/TAPCamDemoJPEGAuditDeviceTestUnlocked2.xcresult`, reached the
  full JPG capture/sign/export/readback flow and failed with
  `.xmpManifestMissing` after Photos round-trip. Logs showed the signed JPG was
  saved, but the read-back original no longer contained the TAP XMP manifest.
- `PhotoLibraryWriter` was changed from data-based resource creation to
  file-URL resource creation for the final validated `.heic` or `.jpg`
  artifact.
- The final unlocked run,
  `/private/tmp/TAPCamDemoJPEGAuditDeviceTestUnlocked4.xcresult`, passed:
  `jpgPhysicalDeviceCaptureExportsAndReadsBackFromPhotos()` passed in 4.380s
  and `exportedPhysicalDeviceCaptureArtifactsReadBackFromPhotos()` passed in
  0.075s.
- The JPG audit report was copied from the device to
  `/private/tmp/TAPDeviceCaptureJPEGAudit.json`. It records one sanitized JPG
  artifact: `3,384,792` bytes, image `4032x3024`, manifest `4032x3024`, depth
  `768x576`, proof count `1`.
- The HEIC/exported audit report was copied from the device to
  `/private/tmp/TAPDeviceCaptureArtifactAudit-unlocked.json`. It records two
  sanitized HEIC artifacts: `8,435,378` bytes with `640x480` depth and
  `6,051,160` bytes with `768x576` depth; both are `4032x3024` with proof
  count `1`.
- Final `git diff --check` passed after the file-URL Photos writer fix,
  physical-device audit test serialization, source guard, and documentation
  updates.
- `xcodebuild build-for-testing -quiet -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -only-testing:TAPCamDemoTests/TAPCaptureOutputProfileTests/currentPhotosExportSurfaceUsesSingleValidatedPhotoResource -skip-testing:TAPCamDemoUITests -derivedDataPath /private/tmp/TAPCamDemoPhotoLibraryFileURLGuardBuild`
  passed, confirming the updated product code and source-level Photos writer
  guard compile for iOS. No booted Simulator was available for running that
  source-level test method directly.
- After the phone was unlocked, the focused UI smoke test also passed:
  `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7' -only-testing:TAPCamDemoUITests/ShutterCaptureSmokeTests/testTappingShutterRequestsDepthCapture -derivedDataPath /private/tmp/TAPCamDemoShutterUITestUnlocked -resultBundlePath /private/tmp/TAPCamDemoShutterUITestUnlocked.xcresult`.
  XCTest enabled automation, tapped `camera.capture.shutter`, and completed 1
  UI test with 0 failures in 11.840s.

## Manual Acceptance Still Required

- Visually confirm TAP Library displays both HEIC and JPG captures in the app.
- Visually confirm Depth Analysis opens both formats from the normal user flow.
- Run attended production App Attest/backend verification for both formats.
- Confirm a camera/format that cannot satisfy the selected profile blocks the
  shutter instead of falling back.
