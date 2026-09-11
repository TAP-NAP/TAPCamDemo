# TAPCamDemo

English | [简体中文](README.zh-CN.md)

## Purpose

TAPCamDemo is an iPhone app for capturing, signing and sharing TAP photos, Live
Photos and video, with depth where supported. It includes a media library,
playback, depth maps, plane analysis and point-cloud views.

## Usage

Open [TAPCamDemo.xcodeproj](TAPCamDemo.xcodeproj) in Xcode and select the
`TAPCamDemo` scheme. The app targets iPhone on iOS 18.6 or later. For device
capture and signing, configure your signing team and `APP_ATTEST_BACKEND_URL`
in the build settings; the server interface is defined in the
[backend contract](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/BackendContract.md).

From the repository root, compile the app and test targets without a device:

```sh
xcodebuild build-for-testing \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

To run unit and app-hosted tests, choose a booted iPhone Simulator and replace
`<UDID>` with its identifier:

```sh
xcrun simctl list devices booted
xcodebuild test \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<UDID>' \
  -only-testing:TAPCamDemoTests
```

Use `-only-testing:TAPCamDemoUITests` for UI tests, or
`-only-testing:TAPCamDemoTests/<SuiteName>` for a specific suite. Check the
executed test count. With SwiftLint installed, run
`Scripts/lint-tap-video-refactor.sh` for the scoped TAP Video structure check.
Simulator tests cover deterministic logic and UI; physical capture, depth,
Photos and App Attest require the relevant [device acceptance
checks](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/Acceptance.md).

## How it works

```text
Camera capture → media + manifest → pending queue → hashes + App Attest proof
               → Photos export and readback → library, playback and analysis
```

Camera planning resolves a supported capture configuration. The runtime captures
media, and the output layer embeds its manifest. The pending queue signs and
exports completed files while the camera remains available. Integrity checks
use the covered file bytes; media decoding serves playback and analysis.

## Directory structure

| Directory | Responsibility |
| --- | --- |
| [TAPCamDemo/App](TAPCamDemo/App) | App entry, startup, settings, App Attest and App Intents. |
| [TAPCamDemo/CameraCapture](TAPCamDemo/CameraCapture) | Capture planning, session runtime, file output, camera UI and Playground. |
| [TAPCamDemo/PendingCaptureQueue](TAPCamDemo/PendingCaptureQueue) | Capture ingest, storage, signing, export and retries. |
| [TAPCamDemo/TAPLibrary](TAPCamDemo/TAPLibrary) | Media access, catalog, gallery, viewer and sharing. |
| [TAPCamDemo/DepthAnalysis](TAPCamDemo/DepthAnalysis) | Depth decoding, heatmaps, planes and photo/video point clouds. |
| [TAPCamDemo/Diagnostics](TAPCamDemo/Diagnostics) | Logging, capture metrics and performance traces. |
| [Assets.xcassets](TAPCamDemo/Assets.xcassets), [Resources](TAPCamDemo/Resources), [en.lproj](TAPCamDemo/en.lproj), [zh-Hans.lproj](TAPCamDemo/zh-Hans.lproj) | Visual assets, bundled notices and localized permission text. |
| [TAPCamDemoTests](TAPCamDemoTests), [TAPCamDemoUITests](TAPCamDemoUITests) | Unit/app-hosted tests, fixtures and UI automation. |
| [Scripts](Scripts), [Tools/ContentBindingVerifier](Tools/ContentBindingVerifier) | Scoped lint command and JavaScript byte-binding utilities/tests. |
| [TAPCamDemo.xcodeproj](TAPCamDemo.xcodeproj) | Targets, shared scheme, build settings and resolved Swift packages. |

## Dependencies

[TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/README.md)
is the normative source for product, UI, artifact and shared API requirements.
This app implements the artifact contracts pinned at
[`16242f01674d5c8b771b93e2cb46bc42a039d174`](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/CONTRACTS.md).

The [server](https://github.com/TAP-NAP/server) provides the configured App Attest
HTTP service; it is not a source or build dependency. Its API requirements remain
in the backend contract. No other TAP repository is needed to build the app.

Xcode resolves the packages recorded in
[Package.resolved](TAPCamDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved):

| Package | Version | Use |
| --- | --- | --- |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 0.9.20 | `.tapnap` sharing archives. |
| [zstd](https://github.com/facebook/zstd) | 1.5.7 | TAP depth-frame compression through `libzstd`. |

Capture, rendering and Photos access use Apple frameworks. App Attest uses
DeviceCheck, with credential metadata stored in Keychain. When updating the
contract pin, compare the [mirrored extension
vector](TAPCamDemoTests/Fixtures/tap-video-extensions-v1.json) byte-for-byte with
the [pinned contract vector](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/examples/vectors/tap-video-extensions-v1.json).
