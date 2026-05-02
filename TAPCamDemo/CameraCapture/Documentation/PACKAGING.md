# Packaging

`CapturePackage` is the logical result of one shutter press. It records selected
RGB source, depth source, pairing status, zoom, crop metadata, `AVCapturePhoto`,
location, and diagnostics facts.

`PackagedCaptureArtifact` is the physical output. The only runtime strategy is
`EmbeddedPhotoPackager`.

```text
CapturePackage
      |
      v
EmbeddedPhotoPackager only
      |
      v
Signed or Unsigned Single Photo Artifact
      |
      v
Local Photos Writer
```

Sidecar JSON, debug bundles, independent depth files, independent metadata
files, metrics files, and intermediate artifacts are absent from runtime code.

## Signed Embedded HEIC

Each saved capture is still one HEIC file. The primary HEIC image stores the RGB
photo, Apple's auxiliary depth/disparity attachment stores depth, and TAP's
manifest is stored in XMP at `tapdepth:Manifest`.

Before the HEIC is saved to Photos, `EmbeddedPhotoPackager` tries to create an
App Attest assertion over a canonical content digest. If assertion generation
succeeds, the proof is inserted into `manifest.proofs[0]` and the manifest is
injected into the HEIC. If assertion generation fails, the photo is still saved
with `proofs: []`; the app does not retry or backfill signatures for that photo.

The App Attest credential name is fixed by the app as `photo_keyid`. The proof's
`keyID` is the actual key id returned by AppAttestKit in the assertion envelope.

## Proof Format

The proof record uses the existing manifest proof shape:

```json
{
  "type": "appAttestAssertion",
  "algorithm": "AppAttestKit.AppAttestAssertionEnvelope.v1",
  "keyID": "<App Attest key id>",
  "createdAt": "<ISO-8601 capture time>",
  "value": "<base64url canonical JSON>"
}
```

Decoding `value` yields canonical JSON with two fields:

- `contentDigest`: the signed digest package.
- `assertionEnvelope`: the AppAttestKit assertion envelope, including
  `credentialName`, `keyId`, `challengeId`, `assertionObject`, and
  `requestBinding`.

The protected request bound into the assertion uses:

```text
method = POST
path = /tapcam/captures/{captureID}/assertion
body = canonical contentDigest JSON
nonce = {captureID}
```

## Content Digest

The signed `contentDigest` contains:

- `rgb`: SHA-256 over the primary HEIC image decoded to RGBA8 bytes.
- `depth`: SHA-256 over `AVDepthData` converted to `DepthFloat32`, serialized
  row-by-row as little-endian Float32 bit patterns without row padding.
- `metadata`: SHA-256 over canonical JSON for `manifest.payload`, excluding
  `proofs`.
- `captureID`, `capturedAt`, `schemaID`, and `manifestSchemaID`.

The final HEIC bytes themselves are not signed directly because writing the
proof changes the HEIC. Signing the content digest avoids that circular
dependency while still binding the RGB image, depth data, and TAP metadata.

## Verification

To verify a signed TAP depth HEIC:

1. Read the original HEIC resource and parse XMP `tapdepth:Manifest`.
2. Read `manifest.proofs[0]` and require `type == "appAttestAssertion"`.
3. Base64url-decode `proof.value` and parse the canonical proof JSON.
4. Recompute the RGB, depth, and metadata digests using the rules above.
5. Compare the recomputed digest package with `proof.value.contentDigest`.
6. Encode that digest package canonically and verify that its SHA-256 matches
   `assertionEnvelope.requestBinding.bodySHA256`.
7. Verify the App Attest assertion object using the registered attestation for
   `assertionEnvelope.keyId`, the challenge identified by `challengeId`, and
   the `requestBinding` client data hash.
