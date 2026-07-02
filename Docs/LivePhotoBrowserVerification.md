# Live Photo Browser Verification Contract

This document is the handoff for adding Live Photo verification support to the
browser verifier and for confirming the server verification boundary. It is a
contract document, not an implementation patch.

TAPCamDemo owns this specification because it owns the capture artifact format.
Browser verifier code and server code are maintained in separate repositories,
so this repo should not implement those code paths. TAPCamDemo changes should
stop at the app-side capture/sign/export/verification path plus the external
contract documented here.

The important boundary is: Live Photo is an extension of the existing TAP
capture proof model. It must not change the manifest, content binding, or
verification behavior of existing still-photo captures.

## Non-Negotiable Boundaries

- Existing still-photo captures keep the current contract:
  - `urn:tapnap:tapcam:depth-manifest:v1`
  - `urn:tapnap:tapcam:content-binding:v2`
  - one original Photos `.photo` resource, HEIC or JPG
  - fixed TAP proof slot in the photo container
  - SHA-256 over format-native photo bytes excluding exactly one proof slot
  - SHA-256 over canonical `manifest.payload` JSON
- Live Photo captures use a new versioned contract:
  - `urn:tapnap:tapcam:depth-manifest:v2`
  - `urn:tapnap:tapcam:content-binding:v3`
  - one original Photos `.photo` resource plus one `.pairedVideo` MOV resource
  - the same fixed TAP proof slot in the photo resource
  - the paired video is signed as an additional binary resource
- `manifest.payload.livePhoto` is present only for v2 Live Photo manifests:
  - `presence: "paired-video"`
  - `pairedVideoFilename: "paired-video.mov"`
  - `durationSeconds`
  - `photoDisplayTimeSeconds`
  - `width`
  - `height`
  - `videoCodec`
  - `audio`, currently `"not-captured"` for silent Live Photos
- `proof.value.contentDigest.signedResources` is present only for v3 Live Photo
  bindings and uses these roles:
  - `primaryPhoto`
  - `tapDepthManifestPayload`
  - `pairedLivePhotoVideo`
- Do not add Live Photo fields to the v1 manifest payload.
- Do not reinterpret v2 content binding as a Live Photo binding.
- Do not make the backend re-hash photo or video bytes. The backend continues
  to verify only the App Attest assertion over the submitted `signingBinding`.
- Do not use platform-decoded pixels, browser canvas pixels, decoded video
  frames, or metric depth conversion as inputs to the base signature check.
- Do not claim per-frame video depth for Live Photo v2/v3. The depth resource
  is the original still photo's `AVCapturePhoto.depthData` embedded in the
  primary `.photo` resource. The paired MOV is signed as video bytes, not as a
  synchronized stream of video frames plus depth frames.

If Live Photo capture is requested but the movie complement fails, the capture
should be signed and exported as the still-photo contract above, not as a
partial v2/v3 Live Photo.

## Depth Scope and Streaming Depth Non-Goal

Apple exposes two separate depth paths:

- `AVCapturePhotoOutput` can deliver `AVCapturePhoto.depthData`, and that depth
  is associated with one captured photo.
- `AVCaptureDepthDataOutput` can deliver streaming `AVDepthData` frames.

The current TAP Live Photo contract deliberately uses only the first path. It
does not add `AVCaptureDepthDataOutput`, does not synchronize depth frames with
the Live Photo MOV, and does not define a per-frame video-depth sidecar. The
reason is semantic, not only implementation cost: the Apple Live Photo MOV is a
movie complement produced by `AVCapturePhotoOutput`, while a streaming
video/depth product would need an explicit timestamp mapping, storage format,
resource roles, manifest fields, and content-binding schema for every retained
video/depth sample.

Future work may define a separate video-depth capture format using
`AVCaptureVideoDataOutput`, `AVCaptureDepthDataOutput`, and
`AVCaptureDataOutputSynchronizer`. That future format must not reuse the current
v2/v3 Live Photo verifier as if it certified per-frame video depth.

## Version Routing

The browser verifier must route by the embedded TAP manifest schema and the
proof value's content-binding schema.

| Input | Required verifier behavior |
| --- | --- |
| v1 manifest + v2 content binding | Run the current still-photo verifier. Do not require a paired video. |
| v2 manifest + v3 content binding | Run the Live Photo verifier. Require the photo checks and then validate the paired video resource if supplied. |
| v2 manifest + missing paired video file | Report still photo proof status separately, then report Live Photo video resource missing. |
| v2 manifest + paired video hash mismatch | Report still photo proof status separately, then report Live Photo video resource failed. |
| Unknown manifest or content-binding schema | Fail as unsupported schema, not as tampered media. |

The report model should separate:

- still photo container, manifest, proof-slot, depth-resource, and App Attest
  binding status
- Live Photo paired-video resource status
- backend signature verification status

That separation lets a user still inspect a valid TAP depth photo even when the
Live Photo movie resource is absent or mismatched.

## Report Severity and Presentation Warnings

Verifier reports use three final states:

- `Verified`: every required local and backend check passed, with no warning.
- `Warnings`: required checks passed, but the verifier detected presentation
  risk such as Photos adjustment resources.
- `Failed`: at least one required check failed.

Failure has priority over warning. If a report contains both warning and
failure steps, the final state is `Failed`, and the primary jump target should
be the first failed step. If there are warnings and no failures, the jump target
is the first warning step.

The verifier should treat these Photos resource types as warning evidence, not
as signed inputs:

- `.fullSizePairedVideo`
- `.adjustmentBasePairedVideo`
- `.adjustmentData`
- related adjusted presentation resources such as `.adjustmentBasePhoto` and
  `.adjustmentBaseVideo`

These resources can indicate edits or a changed Live Photo key photo. They do
not by themselves invalidate the TAP proof, because the proof covers only the
original `.photo` and, for Live Photo, the original `.pairedVideo`. The UI must
make that boundary visible: a green Live Photo means the original signed
resources match; a yellow Live Photo means the original signed resources match
but the Photos presentation may differ.

## Browser Verification Flow

For still-photo v1/v2 captures, keep the current flow:

1. Read the supplied HEIC or JPG as bytes.
2. Parse XMP `tapdepth:Manifest`.
3. Require `manifest.proofs` to be empty.
4. Locate exactly one fixed TAP proof slot.
5. Read and decode the proof envelope from the slot.
6. Recompute the v2 content binding from photo bytes excluding the proof slot
   plus canonical `manifest.payload` JSON.
7. Compare the recomputed content binding with `proof.value.contentDigest`.
8. Canonically encode `signingBinding` and confirm its `bodySHA256` matches the
   canonical content-digest bytes.
9. Submit only `keyId`, `assertionObject`, and `signingBinding` to
   `/tapcam/capture-signatures/verify`.

For Live Photo v2/v3 captures, extend the local browser step before backend
submission:

1. Read the supplied photo resource as HEIC or JPG bytes.
2. Read the supplied paired video resource as MOV bytes when present.
3. Parse XMP `tapdepth:Manifest` and require schema v2.
4. Locate the same fixed proof slot in the photo resource.
5. Decode the proof value and require content-binding schema v3.
6. Recompute `signedResources` from local bytes:
   - primary photo: SHA-256 over HEIC/JPG bytes excluding the proof slot
   - manifest payload: SHA-256 over canonical `manifest.payload` JSON
   - paired video: SHA-256 over the complete MOV file bytes with media type
     `com.apple.quicktime-movie`
7. Compare every required resource descriptor with `proof.value.contentDigest`.
8. If the video file is missing or mismatched, keep the still-photo checks in
   the report and fail only the Live Photo resource section.
9. Submit the same unchanged backend request shape:

```json
{
  "keyId": "apple-key-id",
  "assertionObject": "base64url-assertion-object",
  "signingBinding": {
    "bodySHA256": "base64url-sha256-content-digest",
    "captureID": "capture-id",
    "operation": "tapcam.capture.sign",
    "schemaID": "urn:tapnap:tapcam:app-attest-capture-signing:v1"
  }
}
```

The server does not need to know whether `bodySHA256` came from v2 still-photo
content binding or v3 Live Photo content binding. That distinction is owned by
the local verifier.

## Browser Tool Requirements

The browser verifier needs these implementation tools:

| Need | Browser-side tool |
| --- | --- |
| Read user-selected photo and MOV bytes | File input / drag-drop plus `Blob.arrayBuffer()` |
| Parse binary containers | TAP-owned HEIC/BMFF and JPEG byte parsers, preferably in the existing Rust/WASM verifier path |
| Locate and validate the TAP proof slot | Extend `Tools/ContentBindingVerifier/tap-content-binding.mjs` rules or port the same rules into WASM |
| Parse TAP XMP manifest | TAP-owned XMP extraction for JPEG APP1 and HEIC/BMFF metadata, then JSON parse the `tapdepth:Manifest` value |
| Canonical JSON | A deterministic sorted-key encoder matching Swift `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes` |
| SHA-256 | Web Crypto `crypto.subtle.digest("SHA-256", data)` for in-memory buffers; add a WASM/JS streaming hasher if MOV size makes whole-file hashing too expensive |
| Base64url | TAP-owned base64url no-padding encode/decode helpers |
| Backend verification call | `fetch()` POST with JSON to `/tapcam/capture-signatures/verify` after local byte checks pass |
| Test vectors | Still-photo v1/v2 fixtures plus Live Photo v2/v3 fixtures with matching, missing, and mismatched paired MOV resources |

The optional browser-side streaming hasher above is only a memory optimization
for hashing one MOV file. It is not camera streaming depth capture.

Do not require these for base signature verification:

- `canvas`
- `CGImageSource` equivalents
- `libheif` image decode
- `ffmpeg.wasm`
- video frame decode
- depth Float32 conversion

Those can be useful for preview, geometry inspection, or diagnostics, but they
must not define whether the capture proof is valid.

Relevant browser API references:

- [`Blob.arrayBuffer()`](https://developer.mozilla.org/en-US/docs/Web/API/Blob/arrayBuffer)
- [`SubtleCrypto.digest()`](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest)
- [`TextEncoder`](https://developer.mozilla.org/en-US/docs/Web/API/TextEncoder)
- [`Fetch API`](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API)

## Server Contract

The existing server endpoint remains the same:

```text
POST /tapcam/capture-signatures/verify
```

The request shape remains `keyId`, `assertionObject`, and `signingBinding`.
The server verifies that a registered App Attest key signed the canonical
`signingBinding`. It does not receive the photo, paired MOV, manifest payload,
or recomputed resource hashes.

For Live Photo, the browser/app local verifier must compute the v3 content
binding first. The resulting canonical content binding hash is still represented
only through `signingBinding.bodySHA256`, so the server does not need a Live
Photo-specific branch unless a future protocol changes the App Attest signing
binding schema itself.

## TAPCamVerifier Handoff Checklist

Implementation belongs in the TAPCamVerifier repository. TAPCamDemo only
publishes the artifact contract and fixtures/spec expectations.

- Accept either a single still-photo file or a Live Photo pair: photo plus MOV.
- Keep the visible verifier simple: file selection or drag-drop should start
  verification directly.
- Preserve the current server split:
  - browser proves the media bytes match the embedded content binding
  - server proves the registered App Attest key signed the binding
- Add v3 fixtures before changing UI:
  - still HEIC/JPG v1/v2 remains green
  - Live Photo v2/v3 with matching MOV is fully green
  - Live Photo v2/v3 without MOV shows still proof status plus video missing
  - Live Photo v2/v3 with wrong MOV shows still proof status plus video mismatch
  - unknown schema is unsupported
- Keep CORS expectations unchanged for the backend JSON POST. Browser transport
  failures are separate from local hash verification failures.

## Related Local Contracts

- [App Attest backend contract](AppAttest/BackendContract.md)
- [Camera capture packaging](../TAPCamDemo/CameraCapture/Documentation/PACKAGING.md)
- [Camera capture output README](../TAPCamDemo/CameraCapture/Output/README.md)
- [JS proof-slot reference parser](../Tools/ContentBindingVerifier/tap-content-binding.mjs)
