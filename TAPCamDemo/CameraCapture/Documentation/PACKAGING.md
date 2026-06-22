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
      v
Async App Attest Signer
      |
      v
Final Signed-Export Validator
      |
      v
Signed HEIC/JPG Export to TAPCamDepth Photos Album
```

Sidecar JSON, debug bundles, independent depth files, independent metadata
files, metrics files, and intermediate artifacts are absent from runtime code.

## Signed Embedded TAP Depth Photo

Each exported capture is still one photo file. The current reviewed containers
are HEIC and JPG. The primary image stores the RGB photo, Apple's auxiliary
depth/disparity attachment stores depth, and TAP's manifest is stored in XMP at
`tapdepth:Manifest`.

At shutter time, `EmbeddedPhotoPackager` creates an unsigned HEIC or JPG with
`proofs: []`. The app writes that file to the app-private TAP Library pending
store first, not directly to Photos. A background worker later reads the pending
photo file, recomputes the canonical content digest, creates the App Attest
assertion, inserts the proof into `manifest.proofs[0]`, validates the final
signed bytes, and exports the signed photo file into the TAPCamDepth Photos
album.

The final validator is `TAPCaptureProvenanceWriter.validateSignedExportPhoto`.
It opens the exact bytes that will be exported, then checks the HEIC/JPG source
type, manifest schema and `payload.id`, exactly one App Attest proof, proof
value/digest/signing binding, and Apple auxiliary depth/disparity. Queue status
and signed filenames are not trust claims by themselves.

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

The proof record uses the existing manifest proof shape:

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

The signed `contentDigest` contains:

- `rgb`: SHA-256 over the primary HEIC or JPG image decoded to RGBA8 bytes.
- `depth`: SHA-256 over `AVDepthData` converted to `DepthFloat32`, serialized
  row-by-row as little-endian Float32 bit patterns without row padding.
- `metadata`: SHA-256 over canonical JSON for `manifest.payload`, excluding
  `proofs`.
- `captureID`, `capturedAt`, `schemaID`, and `manifestSchemaID`.

The final photo bytes themselves are not signed directly because writing the
proof changes the photo file. Signing the content digest avoids that circular
dependency while still binding the RGB image, depth data, and TAP metadata.

Implementation note: the app feeds canonical RGB and depth bytes into
CryptoKit's SHA-256 incrementally instead of first materializing additional
full-size `Data` buffers. This preserves the digest contract above while
reducing memory copies during packaging.

Foreground capture metrics break embedded packaging into manifest build,
base photo materialization, XMP injection, and XMP readback verification. The
RGB/depth/metadata digest and App Attest assertion now belong to the async
pending processor, not the shutter-time capture-write job. These timings are
diagnostics only; they are not written into the saved photo file.

Future optimization candidate: evaluate whether `AVCapturePhoto`'
`cgImageRepresentation()` can produce the same canonical RGBA8 digest as
decoding the flattened base photo. This is intentionally not a production path
yet because the signed digest must remain reproducible from the saved photo, and
changing the digest source could alter that verification contract or affect the
camera pipeline.

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

## Important Future TODO

P1, intentionally not implemented in this slice: design the file format and
manifest abstraction before adding RAW, video, Live Photo, deferred 24 MP, or
multi-camera capture formats.

Future work should introduce a focused design for `CaptureFormatProfile`,
format-agnostic semantic manifests, container adapters, and resource roles with
UTType bundles. The current implementation stays within reviewed HEIC/JPG TAP
depth photo profiles so the asynchronous signing pipeline does not become a
speculative multi-resource abstraction.

## Verification

To verify a signed TAP depth photo:

1. Read the original photo resource and require the selected HEIC or JPG
   container type.
2. Parse XMP `tapdepth:Manifest` and verify the expected `payload.id`.
3. Read exactly one `manifest.proofs[0]` and require
   `type == "appAttestAssertion"`.
4. Base64url-decode `proof.value` and parse the canonical proof JSON.
5. Recompute the RGB, depth, and metadata digests using the rules above.
6. Compare the recomputed digest package with `proof.value.contentDigest`.
7. Encode that digest package canonically and verify that its SHA-256 matches
   `signingBinding.bodySHA256`.
8. Submit `keyId`, `assertionObject`, and `signingBinding` to
   `/tapcam/capture-signatures/verify`, or perform the equivalent App Attest
   assertion verification locally with the registered public key.
9. Treat the capture proof as valid only if the image/depth digest check and
   App Attest signature check both pass.
