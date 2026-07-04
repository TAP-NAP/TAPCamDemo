# Live Photo Implementation Trace

## Goal

Implement the first app-side Live Photo path for TAPCamDemo and turn the
agreed browser/server boundary into a versioned artifact specification.

## User Constraints

- Start implementation now; do not edit browser or server repositories.
- Browser and server changes are spec-only in this repo because those codebases
  are maintained separately.
- Still-photo captures must keep the existing manifest and content-binding
  contract.
- Live Photo must be an extension path, routed by explicit schema versions.
- The server remains a signing verifier for `signingBinding`; it does not
  receive or hash photo/MOV bytes.
- Live Photo should still work without microphone access; the current app-side
  path records silent Live Photos.

## Decision Summary

- Still photos keep `depth-manifest:v1` and `content-binding:v2`.
- Live Photos use `depth-manifest:v2` and `content-binding:v3`.
- Live Photo capture is attempted only when the active `AVCapturePhotoOutput`
  supports and enables Live Photo capture.
- If AVFoundation does not deliver the paired movie, the capture is downgraded
  to a signed still photo instead of exporting a partial Live Photo contract.
- The paired MOV is staged as the fixed pending-bundle resource
  `paired-video.mov`.
- Photos export uses `.photo` plus `.pairedVideo` only after the signed Live
  Photo validator recomputes the v3 digest.
- Live Photo depth scope remains still-photo scoped: the signed depth resource
  is `AVCapturePhoto.depthData` embedded in the primary photo, not per-frame
  depth for the MOV.
- `AVCaptureDepthDataOutput` is intentionally out of scope for this slice. A
  streaming video/depth design would need synchronized timestamps, storage,
  manifest fields, and a new content-binding schema rather than reusing the
  current Live Photo v2/v3 contract.
- Local signature verification routes by manifest schema: still photos use the
  existing signed-photo gate, while Live Photos require the signed-photo gate
  plus original `.pairedVideo` MOV validation.
- Local report severity is failure-first: `Failed` wins over `Warnings`, and
  `Warnings` wins over `Verified`.
- Photos presentation resources such as `.fullSizePairedVideo`,
  `.adjustmentBasePairedVideo`, and `.adjustmentData` are warning evidence only.
  They do not become signed inputs and do not change the server request.
- Verification-original export is owned by the saved Photos asset path, not by
  Photos' generic share sheet. Still photos export as one original HEIC/JPG.
  Complete Live Photos export as an uncompressed ZIP containing the original
  primary photo, the original `paired-video.mov`, and an unsigned minimal
  `tapcam-export.json` sidecar. The sidecar is a file map only and is not part
  of the trust chain.
- The primary HEIC/JPG and paired MOV correspond through the Photos `.photo` +
  `.pairedVideo` resource pair and through TAP's v3 `signedResources`. The
  manifest names the Live Photo role and fixed MOV filename; the proof value's
  content digest stores the actual primary-photo, manifest-payload, and MOV
  hash descriptors.
- The Live Photo hash chain is: photo bytes excluding TAP proof slot, canonical
  `manifest.payload` JSON, and complete MOV bytes -> `contentDigest:v3` ->
  canonical content-digest SHA-256 -> `signingBinding.bodySHA256` -> App Attest
  assertion. The backend verifies the assertion over the binding and does not
  re-hash media bytes.
- If a saved Live Photo manifest is present but Photos no longer exposes the
  original `.pairedVideo`, TAPCam may export the primary photo only and warn
  that Live Photo verification remains incomplete. That fallback is not a
  successful Live Photo export.

## Files Updated

- `CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift`: creates
  Live Photo movie capture settings, handles photo/movie delegate completion,
  chooses HEVC then H.264 when available, and returns a still result when the
  movie complement fails.
- `CameraCapture/Runtime/CaptureSessionController.swift`: enables Live Photo
  capture on supported `AVCapturePhotoOutput` configurations.
- `CameraCapture/UI/CameraView.swift` and
  `CameraViewfinderChromeView.swift`: wire the Live Photo button to capability
  and preference state instead of the previous placeholder.
- `DepthAnalysis/DepthAnalyzerSettingsView.swift`: adds the Settings Live Photo
  preference.
- `CameraCapture/Output/TAPDepthManifestSchema.swift` and
  `TAPDepthManifestBuilder.swift`: add manifest v2 and the optional
  `payload.livePhoto` object.
- `CameraCapture/Output/CaptureContentDigest.swift`: adds content-binding v3
  and `signedResources` for primary photo, manifest payload, and paired MOV.
- `CameraCapture/Output/TAPCaptureProvenanceWriter.swift`: separates still-photo
  validation from Live Photo validation.
- `TAPLibrary/*`: persists optional paired MOV resources through pending
  signing/export and cleans them up after export.
- `PhotoLibraryWriter.swift`: adds `saveDepthLivePhoto` with `.pairedVideo`
  while keeping `saveDepthPhoto` as photo-only. It also loads original `.photo`
  plus optional `.pairedVideo` resources for local verification and flags Photos
  presentation resources for warning reports.
- `DepthAnalysis/AppAttestSignatureVerification.swift`: routes local
  verification between still-photo and Live Photo gates, requires paired MOV for
  Live Photo v2/v3, and returns `Verified`, `Warnings`, or `Failed`.
- `DepthAnalysis/AppAttestSignatureVerificationPanel.swift`: shows warning
  state, keeps failure priority, and jumps to the first failed or warning step.
- `DepthAnalysis/TAPVerificationExportBuilder.swift`: builds verification
  originals from Photos resource bytes, runs local still/Live export gates,
  writes Live Photo ZIP packages with ZIPFoundation, and keeps ZIP sidecars
  unsigned and minimal.
- `TAPCaptureProvenanceWriter.swift`: adds a primary-photo-only Live Photo
  validation gate for the missing-MOV fallback. It validates the signed primary
  resource and the proof's Live Photo resource descriptors without treating the
  absent MOV as verified.
- `Docs/LivePhotoBrowserVerification.md`: specifies the browser/server handoff,
  verifier tools, version routing, resource roles, and verification ZIP
  package shape. It now also includes the Mermaid HEIC/MOV hash-chain diagram,
  the resource-descriptor table, and cross-platform verifier requirements for
  browser, desktop, Android, server-side worker, and CLI implementations.
- `CameraCapture/Documentation/PACKAGING.md`,
  `CameraCapture/Output/README.md`, and `TAPLibrary/README.md`: record the
  app-side Live Photo contract and reading path.

## Whitepaper Documentation Addendum

The verifier-facing documentation now treats the Live Photo pair as a
byte-level protocol rather than an Apple Photos playback feature:

- `primary-photo.heic` or `primary-photo.jpg` is the trust-bearing photo
  container. It carries XMP `tapdepth:Manifest` and the fixed TAP proof slot.
- `paired-video.mov` is the trust-bearing movie resource. It is hashed as a
  complete file and never decoded for base signature validation.
- `manifest.payload.livePhoto` declares that a paired MOV is required and names
  the fixed filename, but it does not carry the MOV hash.
- `proof.value.contentDigest.signedResources` is the authoritative list of
  bound resources.
- `tapcam-export.json` is unsigned transport metadata only.

This is the text basis for future public technical whitepapers and for the
separate TAPCamVerifier implementation. Other platforms are supported when they
consume TAPCam's byte-preserving ZIP or equivalent fixture inputs and reproduce
the specified hash chain. Generic AirDrop, Photos compatible export, social app
export, Android Motion Photo conversion, and native Live Photo playback state
are explicitly outside the trust chain.

## Validation

- `xcodebuild build-for-testing -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17'`
- `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPLibraryStorageTests -only-testing:TAPCamDemoTests/TAPCaptureOutputProfileTests`
- `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPCaptureManifestEncodingTests -only-testing:TAPCamDemoTests/TAPCaptureProvenanceWriterSigningTests -only-testing:TAPCamDemoTests/TAPLibraryProcessingTests`
- `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPCaptureContentDigestTests`
- `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPAppAttestSignatureVerificationTests`
- `xcodebuild test -quiet -scheme TAPCamDemo -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:TAPCamDemoTests/TAPVerificationExportBuilderTests`
- `git diff --check`

## Open Follow-Ups

- Run a real-device capture with Live Photo enabled on the current 24/48/77 mm
  depth path and inspect the saved Photos asset resources.
- Add physical-device fixtures for v2/v3 browser verification.
- Run real-device verification-original export after editing a Live Photo key
  photo in Photos, then confirm the ZIP verifies while warning about
  presentation resources.
- Implement browser local verifier support in the TAPCamVerifier repository.
- Research a future video-depth format using streaming `AVCaptureDepthDataOutput`
  only after defining resource storage, synchronization, manifest, and signing
  semantics.
- Keep the server endpoint unchanged unless the App Attest signing-binding
  schema changes in a future protocol.
