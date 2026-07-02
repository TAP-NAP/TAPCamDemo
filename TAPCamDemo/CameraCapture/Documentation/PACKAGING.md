# Packaging

`CapturePackage` is the logical result of one shutter press. It records selected
RGB source, depth source, pairing status, zoom, crop metadata, `AVCapturePhoto`,
location, and diagnostics facts.

`PackagedCaptureArtifact` is the physical output. The only runtime strategy is
`EmbeddedPhotoPackager`, and runtime export is intentionally split from capture.

```text
CapturePackage
      |
      v
EmbeddedPhotoPackager only
      |
      v
Unsigned Single Photo Artifact
      |
      v
TAP Library Pending Store
      |
      +--> optional paired-video.mov for Live Photo
      |
      v
Async App Attest Signer
      |
      v
Final Signed-Export Validator
      |
      v
Signed HEIC/JPG or Live Photo Export to TAPCamDepth Photos Album
```

Sidecar JSON, debug bundles, independent depth files, independent metadata
files, metrics files, and intermediate artifacts are absent from runtime code.

## Signed Embedded TAP Depth Photo

Still-photo captures export one photo file. The current reviewed photo
containers are HEIC and JPG. The primary image stores the RGB photo, Apple's
auxiliary depth/disparity attachment stores depth, and TAP's manifest is stored
in XMP at `tapdepth:Manifest`.

At shutter time, `EmbeddedPhotoPackager` creates an unsigned HEIC or JPG with
`proofs: []`. The app writes that file to the app-private TAP Library pending
store first, not directly to Photos. A background worker later reads the pending
photo file, ensures the fixed TAP proof slot exists, recomputes the canonical
content binding over the file bytes excluding that slot, creates the App Attest
assertion, writes the proof envelope into the slot, validates the final signed
bytes, and exports the signed photo file into the TAPCamDepth Photos album.

The final validator is `TAPCaptureProvenanceWriter.validateSignedExportPhoto`.
It opens the exact bytes that will be exported, then checks the HEIC/JPG source
type, manifest schema and `payload.id`, no proof bodies in the manifest, exactly
one fixed proof slot, proof value/digest/signing binding, and Apple auxiliary
depth/disparity presence. Queue status and signed filenames are not trust claims
by themselves.

Live Photo is an extension of this still-photo contract. When
`AVCapturePhotoOutput` delivers a Live Photo movie complement, the app stages
that MOV as `paired-video.mov` next to the unsigned photo in the pending bundle.
Signing then uses `validateSignedExportLivePhoto`: the photo still carries the
fixed TAP proof slot, while the paired MOV is bound as an additional full-file
resource in `content-binding:v3`. If the movie complement is unavailable, the
capture is signed and exported as the still-photo v1/v2 contract rather than as
a partial Live Photo.

If the device is locked, protected data is unavailable, the network is down, or
App Attest fails transiently, the capture remains in the pending store as
`pending`, `waitingNetwork`, or `failedRetryable`. The app does not automatically
export unsigned captures to Photos.
When protected data is unavailable, `TAPPendingCaptureWorkerReadiness` stops the
worker before signing, validation, export, retry mutation, or failure-reason
updates.

The pending store status model is:

- `pending`
- `waitingNetwork`
- `signing`
- `signed`
- `exporting`
- `exported`
- `failedRetryable`

After a signed photo file is exported successfully, Photos becomes the
user-visible source. The worker records the Photos `assetLocalIdentifier` and
removes the large staged photo files in the background.

Camera UI gating is intentionally narrower than the pending-store state model.
The TAP Library button is disabled only while the foreground capture-write
queue is still turning shutter requests into staged pending records. Once a
capture has landed in the pending store, TAP Library can open and show that
record even if the async worker has not signed or exported it yet. In other
words, `waitingNetwork`, `signing`, `signed`, `exporting`, and
`failedRetryable` are Library-visible states, not reasons to block Library
entry.

The App Attest credential name is fixed by the app as `photo_keyid`. The proof's
`keyID` is the actual key id returned by the registered App Attest credential.

## Proof Format

The proof record uses the existing TAP proof JSON shape, but it is stored in the
fixed TAP proof slot rather than inside `manifest.proofs`. The embedded manifest
continues to carry only the TAP payload. This keeps proof bytes, App Attest
assertion bytes, and the signature out of the signed content binding.

The current slots are:

- HEIC/BMFF: one top-level `uuid` box with the TAP proof-slot UUID.
- JPEG: one APP11 segment inserted immediately after SOI.

Both variants reserve a 60 KiB payload. The payload begins with
`TAPCAM-PROOF-SLOT-V1`, version `1`, a 32-bit envelope length, then canonical
proof JSON bytes. Remaining bytes must be zero-filled. Non-zero padding,
missing slots, duplicate slots, or oversized envelopes fail validation.

The proof envelope JSON is:

```json
{
  "type": "appAttestAssertion",
  "algorithm": "TAPCam.AppAttestCaptureSignature.v1",
  "keyID": "<App Attest key id>",
  "createdAt": "<ISO-8601 capture time>",
  "value": "<base64url canonical JSON>"
}
```

Decoding `value` yields canonical JSON with four fields:

- `contentDigest`: the signed digest package.
- `keyId`: the App Attest credential id used to verify the signature.
- `assertionObject`: the App Attest assertion object, base64url no padding.
- `signingBinding`: the TAPCam capture signing binding submitted to App Attest.

The signing binding is canonical JSON with these fields:

```json
{
  "bodySHA256": "<SHA-256 over canonical contentDigest JSON>",
  "captureID": "<captureID>",
  "operation": "tapcam.capture.sign",
  "schemaID": "urn:tapnap:tapcam:app-attest-capture-signing:v1"
}
```

The app computes `clientDataHash` as `SHA256(canonical signingBinding JSON)` and
passes that hash directly to `DCAppAttestService.generateAssertion`. Capture
signing does not request an assertion challenge and does not use
`challengeId`, `requestBinding`, or `challengeSHA256`.

## Content Digest

The signed `contentDigest` is now a C2PA-aligned content binding. It deliberately
hashes format-native bytes instead of platform-decoded pixels or Apple-converted
depth samples. Still-photo captures use this schema identifier:

```text
urn:tapnap:tapcam:content-binding:v2
```

The binding contains:

- `assetHash`: SHA-256 over the exported HEIC/JPG bytes after excluding exactly
  one fixed TAP proof slot. The excluded range records offset, length, and
  reason `tap-proof-slot`.
- `metadataHash`: SHA-256 over canonical JSON for `manifest.payload`.
- `proofSlot`: the slot kind, byte range, payload range, and zero-padding rule.
- `depthResource`: records that depth is required and covered as format-native
  bytes by `assetHash`, while metric interpretation is not part of the base
  signature.
- `captureID`, `capturedAt`, `schemaID`, and `manifestSchemaID`.

Live Photo captures use:

```text
urn:tapnap:tapcam:content-binding:v3
```

The v3 binding keeps the still-photo fields above and adds `signedResources`:

- `primaryPhoto`: the same HEIC/JPG byte hash excluding the proof slot.
- `tapDepthManifestPayload`: the canonical `manifest.payload` JSON hash.
- `pairedLivePhotoVideo`: SHA-256 over the complete MOV file bytes with media
  type `com.apple.quicktime-movie`.

Live Photo manifests use
`urn:tapnap:tapcam:depth-manifest:v2` and add
`manifest.payload.livePhoto` with the fixed `pairedVideoFilename`, duration,
photo-display time, dimensions, optional video codec, and audio state. Silent
Live Photos record `audio: "not-captured"`; microphone access is not required
for the current implementation.

### Live Photo Depth Scope

Live Photo does not change the depth contract. Depth remains the
`AVCapturePhoto.depthData` associated with the original still photo resource and
embedded in the primary HEIC/JPG container. The paired MOV is signed as one
full-file binary resource; the current manifest and content binding do not
claim depth for every MOV frame.

The app intentionally does not use `AVCaptureDepthDataOutput` for the current
Live Photo path. Streaming depth would be a different product boundary: it
would need video/depth timestamp synchronization, a retained depth-frame storage
format, manifest fields for the depth stream, and a new content-binding schema.
Until that exists, verification must state that Live Photo depth is bound to the
original still photo only.

The final photo bytes are bound directly except for the reserved proof slot. This
matches the C2PA hard-binding principle of hashing asset bytes while excluding
the provenance container whose contents necessarily change when the proof is
written. TAP's current slot is a project-local container, not a complete C2PA
Content Credential or JUMBF manifest store.

The base signature does not call `CGImageSource`, `CGContext`, browser canvas,
libheif image decode, or `AVDepthData.converting(toDepthDataType:)`. It only
needs a byte parser that can locate and exclude the proof slot. The JavaScript
reference parser for this rule lives at
[`Tools/ContentBindingVerifier/tap-content-binding.mjs`](../../../Tools/ContentBindingVerifier/tap-content-binding.mjs).

Foreground capture metrics break embedded packaging into manifest build,
base photo materialization, XMP injection, and XMP readback verification. The
content binding and App Attest assertion now belong to the async pending
processor, not the shutter-time capture-write job. These timings are diagnostics
only; they are not written into the saved photo file.

## TAP Library Pending Store

The pending store is app-private storage for current TAP depth photo captures
that have not yet completed signing and Photos export. TAP Library merges these
internal records with the current TAPCamDepth Photos album at display time.
Pending, signing, and exporting records show status badges. Once export
succeeds, the item is shown from Photos; if the user deletes the Photos asset,
the next library refresh naturally removes it from the visible list.

If a pending record's staged photo file is temporarily unavailable during
analysis,
the analysis screen shows a calm "temporarily not available" message and asks
the Library to refresh. It does not surface low-level file-system messages such
as "No such file" to the user.

Startup and foreground recovery reconcile partially completed work:

- `signing` records are eligible for signing again because the app may have
  been killed while a worker was in flight.
- Signing validates that the queue record `captureID` still matches the staged
  photo file's embedded TAP manifest `payload.id` before App Attest is called.
- `exporting` records are matched by final signed-export validation before
  another Photos export is attempted.
- `exported` records have staged large files cleaned up again if a previous
  cleanup was interrupted.
- Live Photo records may also carry `pairedVideoFilename: paired-video.mov`.
  That file is signed as part of v3 and is removed with the staged
  unsigned/signed photo files after export.

## Important Future TODO

P1, intentionally not implemented in this slice: design the file format and
manifest abstraction before adding RAW, general video, deferred 24 MP, or
multi-camera capture formats.

Future work should introduce a focused design for `CaptureFormatProfile`,
format-agnostic semantic manifests, container adapters, and resource roles with
UTType bundles. The current Live Photo support is deliberately narrower: one
reviewed photo-depth file plus one Apple paired MOV resource.

P2, intentionally not implemented in this slice: design a video-depth capture
format if TAPCam needs synchronized video frames and depth frames. That design
may use `AVCaptureDepthDataOutput`, `AVCaptureVideoDataOutput`, and
`AVCaptureDataOutputSynchronizer`, but it needs its own resource model and must
not be treated as the current Live Photo v2/v3 contract.

## Verification

To verify a signed TAP depth photo:

1. Read the original photo resource and require the selected HEIC or JPG
   container type.
2. Parse XMP `tapdepth:Manifest` and verify the expected `payload.id`.
3. Require `manifest.proofs` to be empty.
4. Locate exactly one fixed TAP proof slot and read its proof envelope.
5. Base64url-decode `proof.value` and parse the canonical proof JSON.
6. Recompute the content binding: SHA-256 over file bytes excluding the proof
   slot, plus SHA-256 over canonical `manifest.payload` JSON.
7. Compare the recomputed digest package with `proof.value.contentDigest`.
8. Encode that digest package canonically and verify that its SHA-256 matches
   `signingBinding.bodySHA256`.
9. Submit `keyId`, `assertionObject`, and `signingBinding` to
   `/tapcam/capture-signatures/verify`, or perform the equivalent App Attest
   assertion verification locally with the registered public key.
10. Treat the capture proof as valid only if the content binding check and App
   Attest signature check both pass.

To verify a TAP Live Photo, route by `depth-manifest:v2` and
`content-binding:v3`, then perform the still-photo checks above plus the
`signedResources.pairedLivePhotoVideo` MOV hash check before backend App Attest
verification. The browser/server split and required browser tools are specified
in [Docs/LivePhotoBrowserVerification.md](../../../Docs/LivePhotoBrowserVerification.md).
Verification should report that Live Photo depth is bound to the original still
photo only. A valid paired MOV hash proves the MOV bytes match the signed
resource; it does not prove per-frame video depth.

Local verification reports use failure-first severity:

- `Verified`: required local and backend checks passed.
- `Warnings`: required checks passed, but Photos has presentation resources
  such as `.fullSizePairedVideo`, `.adjustmentBasePairedVideo`, or
  `.adjustmentData`.
- `Failed`: any required local or backend check failed.

Warnings do not downgrade a valid original-resource signature into failure.
They mean the app verified the original `.photo` and optional `.pairedVideo`,
while the visible Photos presentation or selected Live Photo key photo may have
extra adjustment state.

Depth analysis after verification may still parse Apple auxiliary depth and
convert it to metric Float32 for geometry tools. That interpretation path is a
consumer of an already-bound artifact, not an input to the base signature. A
future strict verifier can add a deterministic, format-native depth graph parser
or a separate metric conversion specification without changing the hard rule
that platform conversion output is not the primary signature input.
