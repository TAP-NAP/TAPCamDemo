# Packaging

The documentation-only
[TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
repository owns the shared Still/Live manifest fields, HEIC/JPEG container
locations, proof slot, signing and verification procedures, hash participation,
and `.tapnap` routing format. This document owns only TAPCamDemo's capture,
pending-signing, Photos export, and local-integrity orchestration.

## Local Artifact Flow

`CapturePackage` is the logical result of one shutter press. It records the
selected RGB/depth sources, output-profile result, Live Photo pairing state,
zoom/crop metadata, `AVCapturePhoto`, location, and diagnostics needed by the
producer.

`PackagedCaptureArtifact` is the physical handoff. Release has one packager,
`EmbeddedPhotoPackager`:

```text
CapturePackage
  -> EmbeddedPhotoPackager
  -> unsigned HEIC/JPG with embedded manifest and empty fixed proof slot
     + optional paired-video.mov
  -> app-private Pending Capture Queue
  -> asynchronous App Attest signing and local final validation
  -> Photos .photo + optional .pairedVideo
```

Release does not create a manifest sidecar, independent depth file, metrics
file, debug bundle, or other intermediate export. The photo contains the
primary image, Apple auxiliary depth/disparity when delivered, and the embedded
TAP manifest. Shutter-time packaging leaves `manifest.proofs` empty; the proof
envelope belongs only in the separate fixed slot defined by the shared
contract.

When `AVCapturePhotoOutput` delivers a Live Photo movie complement, the package
stages it as `paired-video.mov` beside the unsigned photo. If the complement is
unavailable, the producer takes the Still Photo route rather than publishing a
partial Live Photo family.

## Pending Signing And Export

The foreground capture-write job ends after the artifact is durably staged.
The Pending Capture Queue later:

1. reopens the exact staged files and validates queue/manifest identity plus
   actual container/depth/pairing facts;
2. constructs and signs the shared family-specific binding;
3. writes only the existing proof slot;
4. reopens the final bytes and repeats local binding/relationship validation;
5. gives Photos only a validated photo or validated Live Photo wrapper; and
6. records the Photos asset identity before cleaning up large staged files.

The complete producer order and Still/Live hash inputs are defined once in the
[shared binding/proof contract](https://github.com/TAP-NAP/TAPArtifactContracts/blob/63f96b31de193c3ad456ffa500cc0db03fb97142/bindings/capture-binding-and-proof-v1.md).
`TAPCaptureProvenanceWriter.validateSignedExportPhoto` and
`validateSignedExportLivePhoto` implement TAPCamDemo's final local guard. Queue
status and filenames are scheduling hints, not trust claims.

This local guard checks the received container, manifest/output identity,
proof-slot structure, reconstructed binding relationships, and actual Apple
auxiliary-depth presence. It does not hold the registered App Attest public key
and therefore is not the backend cryptographic signature verdict.

Temporary protected-data, network, or App Attest failures leave the capture in
the app-private queue; they never authorize unsigned Photos export. The worker
stops before private reads or mutations when protected data is unavailable.
Detailed states, retry ordering, storage, recovery, and cleanup live in the
[Pending Capture Queue README](../../TAPLibrary/README.md).

TAP Library entry is blocked only while the foreground write queue is still
turning shutter output into a durable pending record. Once staged, the item can
appear with its pending/signing/export state while asynchronous work continues.

## Live Photo Depth Boundary

Current Live Photo depth is the one `AVCapturePhoto.depthData` resource
associated with the primary still photo. The paired MOV is an additional
full-file signed resource; TAPCam does not claim per-frame MOV depth.

The Live Photo path therefore does not add `AVCaptureDepthDataOutput` or a
video/depth synchronizer. A future streaming-depth product would require its own
timestamp mapping, storage, manifest, and binding decisions and must not be
inferred from the current Live Photo family.

## Verification And Consumer Boundary

TAPCamDemo's pre-export check is a local self-consistency gate. External
verification follows the shared contract:

```text
received original bytes
  -> local family/container/binding reconstruction
  -> compare the binding required for the reported scope
  -> backend App Attest assertion verification
  -> join both gates into the scoped verdict
```

Decoded RGB, browser canvas pixels, converted depth planes, and playback state
are downstream interpretation, never base-signature inputs. A Live Photo
primary may receive a clearly limited primary-photo result when its MOV is
absent, but no consumer may claim that absent video bytes were verified.

The backend HTTP, registered-key trust, counter, and replay boundary remains in
[Docs/AppAttest/BackendContract.md](../../../Docs/AppAttest/BackendContract.md).
The JavaScript reference parser remains an implementation aid at
[`Tools/ContentBindingVerifier/tap-content-binding.mjs`](../../../Tools/ContentBindingVerifier/tap-content-binding.mjs);
it is not a second format authority.

## Diagnostic Boundary

Foreground packaging metrics may time manifest construction, photo
materialization, injection, and readback. Signing and Photos export timing
belongs to the asynchronous queue. Diagnostics are not written into the saved
artifact and must not expose raw paths, identifiers, key IDs, assertion/proof
bodies, photo bytes, location, or localized backend errors.

Future format/profile work is tracked only in
[Docs/ProjectBoard.md](../../../Docs/ProjectBoard.md). This file does not keep a
parallel backlog or define speculative resource shapes.
