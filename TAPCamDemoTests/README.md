# TAPCamDemo Tests

This directory contains the default deterministic automation target for the
shared `TAPCamDemo` scheme. Start here to choose the smallest test surface that
can answer a question; do not treat the number of passing tests as product or
device acceptance.

## Test entry points

- `TAPCamDemoTests` contains Swift Testing and app-hosted checks that run on an
  iPhone Simulator without a depth-capable camera, live App Attest backend,
  Photos UI automation, or attended device interaction.
- `TAPCamDemoUITests` is the separate app UI automation target. Its camera and
  playback cases are attended evidence paths, not part of the default unit
  gate.
- The shared
  [`TAPCamDemo` scheme](../TAPCamDemo.xcodeproj/xcshareddata/xcschemes/TAPCamDemo.xcscheme)
  contains both targets and sets `TAPCAM_XCTEST_HOST=1`. The app-hosted unit
  path uses the minimal XCTest host instead of entering first-install setup,
  camera startup, credential warmup, or Pending Capture Queue processing.

Choose a Booted iPhone Simulator by UDID so Xcode does not create a temporary
clone or spend the test timeout starting a shutdown destination:

```sh
xcrun simctl list devices booted
```

Compile the shared test products:

```sh
xcodebuild build-for-testing \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>'
```

Run the deterministic unit/app-hosted target:

```sh
xcodebuild test-without-building \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>' \
  -only-testing:TAPCamDemoTests
```

To build and run in one command, replace `test-without-building` with `test`.
Use additional `-only-testing:TAPCamDemoTests/<SuiteName>` arguments for a
focused suite; verify the executed count because an invalid Swift Testing
filter can succeed while executing zero tests.

Run UI automation explicitly and report it separately from the unit target:

```sh
xcodebuild test \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<BOOTED_IPHONE_SIMULATOR_UDID>' \
  -only-testing:TAPCamDemoUITests
```

The TAP Video production-structure gate is also separate:

```sh
Scripts/lint-tap-video-refactor.sh
```

It checks only the production allowlist configured by
`.swiftlint-tap-video.yml`; it is not a repository-wide style pass and does not
cover tests, UI tests, Debug fixtures, benchmarks, or resolved packages.

## Fixture and golden-vector ownership

- [`TAPCamDemoTestFixtures.swift`](TAPCamDemoTestFixtures.swift) owns reusable,
  deterministic test payloads, manifests, pending records and artifacts,
  manual-control capability snapshots, temporary directories, thumbnails, and
  `bundle.json` helpers. Keep a fixture beside one suite when no other suite
  uses it.
- [`TAPCaptureProvenanceTestFixtures.swift`](TAPCaptureProvenanceTestFixtures.swift)
  owns capture-signing and export-validation fixtures; it deliberately does not
  turn synthetic data into positive real-device depth evidence.
- [`TAPCaptureAssertionTestDoubles.swift`](TAPCaptureAssertionTestDoubles.swift)
  owns test doubles for the capture assertion boundary. These doubles do not
  prove App Attest hardware or backend acceptance.
- [`TAPVideoManifestV1GoldenVectors.json`](../Docs/Fixtures/TAPVideoManifestV1GoldenVectors.json)
  is a repository-local composite fixture because
  `TAPVideoManifestTests` loads that exact path. Its `depthFrame` member mirrors
  the exact KLV/zstd v1 vector owned by
  [`TAPArtifactContracts`](https://github.com/TAP-NAP/TAPArtifactContracts/blob/50d83e9b5916f0fa4621b24b5c5c5702c59ee7de/examples/vectors/tap-video-klv-zstd1-v1-golden-vector.json).
  Its separate manifest object is local decoder input, not current manifest
  authority; the shared manifest contract and example are authoritative. Do not
  regenerate the shared byte vector to fit an incompatible reader.
- TAP Video playback fixtures are generated at runtime by
  [`TAPVideoPlaybackFixtureHarnessTests.swift`](TAPVideoPlaybackFixtureHarnessTests.swift).
  They must not create a second checked-in binary-fixture authority.
- The JavaScript content-binding reference checks live in
  [`Tools/ContentBindingVerifier`](../Tools/ContentBindingVerifier/). They are
  cross-language parser evidence, not a replacement for Swift tests or real
  exported-resource verification.

Debug fixtures and oversized-suite organization belong to `TAP-0029`. Moving
helpers, splitting files, or changing target boundaries is outside this
README's responsibility.

## Stable responsibility map

Use the source directory and suite names to find the exact current tests. This
map records durable responsibilities rather than a file-by-file or
function-by-function inventory.

| Responsibility | Required property |
| --- | --- |
| Startup and Resource Initialization | Structured Setup/permission/initialization facts route deterministically; only explicit actions own prompts and initial Network/App Attest work; Camera and Photos recovery does not replay Setup; readiness markers commit atomically only after camera-interactive and usable-catalog readiness. |
| Capture output policy | Release HEIC/JPG profiles, depth requirements, quality policy, pre-capture configuration, and the resolved Runtime output request fail closed instead of silently falling back. |
| Capture provenance and export | Manifest payload bytes, content binding, proof-slot exclusions, assertion input, resource plans, and final Photos preflight remain deterministic and fail closed. Synthetic signer data does not claim backend verification. |
| TAP Video format | BMFF/KLV bounds, manifest schema, depth codec, streaming behavior, parser rejection, playback policy, and the contract-owned golden vector remain compatible and bounded. |
| Pending Capture Queue | Bundle paths and filenames are constrained; records, migration, retry classification, protected-data readiness, signing/export order, cleanup, and public-safe failure reasons remain durable and deterministic. |
| TAP Library and PhotoKit | Catalog identity/order publication, observer lifecycle, cancellation, stale-result rejection, thumbnail/resource loading, pending-to-owned handoff, and route restoration remain race-safe. |
| Camera and manual controls | Camera presentation state, preferences, exposure/focus intent, capability resolution, Runtime command ordering, stale-camera guards, and public-safe status copy remain deterministic. |
| Depth analysis | Input budgets, depth-map shape, geometry, selection, async freshness, scoring, presentation state, and public-safe error/statistics boundaries fail safely without treating synthetic inputs as real capture evidence. |
| Share, Viewer, and localization | Share preparation state, Viewer paging/identity, cancellation, localization catalog coverage, hostile dynamic values, and public-safe visible copy follow the current product/prototype contracts. |
| Security, privacy, and architecture static gates | Forbidden dependencies, whole-file reads, decoded-pixel binding, local backend Verify calls, unsafe paths, sensitive logging, and Release-only boundary drift remain prohibited when runtime observation is not the right enforcement seam. |
| Persistence and compatibility | Explicit legacy migrations, public formats, cross-project contracts, and fail-closed readers remain covered even when the current Runtime no longer writes the legacy shape. |

Source-inspection tests are architecture, security, privacy, or format gates;
they are not UI-behavior evidence. Prefer observable state, event, output, or
parser behavior for ordinary product logic, and keep a static gate only when it
protects an explicit boundary that cannot be observed reliably at runtime.

## Evidence boundaries

- A Simulator unit pass proves only the exercised deterministic model,
  integration, parser, or app-hosted boundary. It does not prove rendered
  SwiftUI geometry, touch/gesture delivery, haptics, shutter sound, physical
  camera behavior, depth quality, Photos UI behavior, App Attest hardware or
  backend acceptance, iCloud timing, thermal behavior, or device performance.
- UI automation contributes Simulator or attended-device interaction evidence
  only for the executed path. It does not replace an approved Web-prototype
  comparison or owner-attended physical-device acceptance.
- Static source gates prove the named prohibition or dependency boundary. They
  do not prove that a user flow works.
- Runtime-generated and synthetic fixtures prove deterministic handling of
  known shapes. Positive HEIC/JPG auxiliary-depth, physical camera, Photos
  readback, and production credential claims require their separate device or
  backend procedures.
- A warm rerun is comparison evidence, not cold-path proof. First-install,
  empty-cache, large-catalog, iCloud, and first-presentation work follows
  [`ColdPathResponsiveness.md`](../Docs/ColdPathResponsiveness.md).
- Report declared, executed, passed, failed, and skipped counts. A command that
  executes zero tests, a skipped physical-device case, or a passing unrelated
  suite is not evidence for the requested conclusion.
- Physical-device acceptance remains governed by
  [`Docs/Acceptance/README.md`](../Docs/Acceptance/README.md) and its Task-linked
  procedure. Simulator automation never supplies the required human verdict.

## Physical-device artifact audit

Run the focused exported-artifact audit only under its approved, attended
procedure with an unlocked, trusted iPhone. Skip the unrelated UI target:

```sh
xcodebuild test \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:TAPCamDemoTests/TAPDeviceCaptureArtifactAuditTests \
  -skip-testing:TAPCamDemoUITests \
  -derivedDataPath /private/tmp/TAPCamDemoDeviceArtifactAudit \
  -resultBundlePath /private/tmp/TAPCamDemoDeviceArtifactAudit.xcresult
```

The suite may validate real exported resources and write sanitized audit JSON
inside the app container. A passing XCTest result still needs the evidence and
human confirmation required by the owning DeviceAcceptance Task.
