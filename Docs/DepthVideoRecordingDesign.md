# Depth Video Recording Design

Status: design accepted; first app-integrated vertical slice implemented.

This document records the agreed first-version design for TAP signed stereo
video recording. It is intentionally narrower than a general video-export
framework: the product goal is one Photos-saveable video file that ordinary
players can play as RGB video with optional audio, while TAP verifies the same
original file and parses whatever original depth coverage the capture produced.

When present, the private depth stream should follow an existing open-source
pattern rather than an invented container shape. The reference model is GoPro's
GPMF approach: store capture-time sensor payloads in an additional time-indexed
MP4/MOV track, encode the payload as compact 32-bit-aligned KLV records, and let
ordinary players ignore the private track while specialized parsers read it.

## Goals

- Record video from the selected depth-capable camera plan and attach real depth
  samples as the session delivers them. Depth is an auxiliary capture signal for
  later judgment, not a reason to split the product or verification path.
- Use the user's selected camera plan. The first version must not silently switch
  to another lens, FOV, or capture device to chase depth availability.
- Save one original video resource to Photos. The saved resource must be playable
  by Photos and by cross-platform players as a normal video.
- Keep RGB and audio standard. RGB is H.264 in MP4; audio is AAC when captured.
- Keep captured depth samples in the same MP4 as a TAP-private stream that
  normal players ignore and TAP parses itself. Missing depth samples are recorded
  as coverage facts in the manifest instead of being invented or treated as a
  different artifact class.
- Sign and verify only the original Photos resource. Edited, transcoded, shared,
  or platform-rendered derivatives are not trusted artifacts.
- Start with lossless depth storage. Do not normalize all depth into Float16 or
  any other lossy canonical representation in the first version.

## Non-Goals

- No zip package or multi-file export as the primary user artifact.
- No realtime depth preview, 3D preview, plane detection, region analysis, or
  scrubber-level depth analysis in the first version.
- No MultiCam or separate-device RGB/depth fusion in the first version.
- No attempt to make the depth stream a standard cross-platform media track.
  Cross-platform playback means RGB/audio playback; TAP depth playback uses our
  parser.
- No trust claim over Photos edits, exported transcodes, social-media uploads, or
  any file that is not byte-identical to the original signed resource except for
  the defined TAP proof slot.

## File Shape

The first target artifact is one MP4 file:

```text
tap-depth-video.mp4
  standard H.264 RGB video track
  optional standard AAC audio track
  optional TAP private GPMF-style timed metadata depth stream
  TAP private manifest/index/calibration data
  one fixed-size TAP proof slot
```

The ordinary media tracks are standard so Photos and common players can play the
file. When depth exists, the depth stream is a TAP-defined private timed metadata
stream inside the same MP4. The parser must not depend on a platform
automatically exposing that depth data as a normal media stream.

MOV is only a fallback if implementation tests show MP4 cannot reliably carry
the private timed data plus proof slot through the Photos original resource path.

## Capture Pipeline

Use a single `AVCaptureSession` with standard video output and best-effort depth
output:

- `AVCaptureVideoDataOutput` for RGB frames.
- `AVCaptureDepthDataOutput` for `AVDepthData` frames.
- `AVCaptureAudioDataOutput` or an equivalent audio input path when microphone
  capture is authorized and the app-level microphone data-use switch permits it.
- `AVCaptureDataOutputSynchronizer` to pair RGB and depth samples by timestamp
  when depth is present.
- `AVAssetWriter` for the standard MP4 video/audio tracks and TAP private timed
  data.

This follows the AVFoundation depth-streaming contract from the Xcode iOS 26.5
SDK headers:

- `AVCaptureDepthDataOutput` streams `AVDepthData` objects, and it delivers them
  in the camera's `activeDepthDataFormat`.
- The selected depth format must come from the active video format's
  `supportedDepthDataFormats`; setting an unrelated depth format is an
  `NSInvalidArgumentException`.
- When streaming depth plus video from a photo format, `AVCaptureVideoDataOutput`
  must deliver preview-sized output buffers. With the photo preset, video is
  captured at preview resolution rather than full sensor resolution.
- `AVCaptureDataOutputSynchronizer` is the AVFoundation path for timestamp
  aligning video and depth outputs and reporting dropped depth data separately
  from missing depth data.

The current still-photo path uses `AVCapturePhotoOutput` and does not yet
implement this streaming video pipeline. The video feature should add new seams
instead of expanding still-photo code until it becomes a general video system.

## Depth Encoding

First-version depth is lossless relative to the captured `AVDepthData` payload.
Each timed depth sample is a TAP KLV payload modeled after GPMF rather than a
JSON blob:

- 32-bit aligned records.
- FourCC keys for stream identity, depth frame payload, dimensions, row stride,
  pixel format, depth/disparity mode, compression, calibration reference, and
  frame counters.
- Big-endian integer fields unless the field explicitly carries opaque native
  sample bytes.
- Unknown keys can be skipped by future parsers.
- Large binary depth bytes are carried as opaque byte payloads, not expanded into
  textual metadata.

- Preserve whether the source is depth or disparity.
- Preserve the pixel format and sample type instead of forcing a project-wide
  Float16 representation.
- Preserve dimensions, row stride, timing, orientation, and camera calibration.
- Use reversible compression such as LZFSE or zlib if needed.
- Include enough per-frame or stream-level metadata for TAP to reconstruct the
  original depth frame bytes and interpret them later.
- Store only real captured depth samples. Do not synthesize, interpolate, or
  duplicate depth frames to match the RGB frame rate in the signed original
  resource.

During the bring-up phase, the app may additionally write an app-private
`depth-preview.mp4` sidecar from the delivered depth callbacks. This sidecar is
a diagnostic grayscale visualization only: it is not saved to Photos, not
included in the signed content binding, and not used as proof of the original
depth bytes. Its purpose is to confirm that `AVCaptureDepthDataOutput` is
delivering frames while the signed MP4's TAP-private KLV metadata track is being
hardened.

Do not adopt GPMF branding or GoPro-specific key meanings as the TAP public
format. The intended reuse is the proven architecture: time-indexed metadata
track plus compact KLV payload. The TAP format owns its own FourCC namespace and
schema version.

Depth absence and gaps are recorded, not treated as an automatic export failure
or product split. The selected camera path is expected to be depth-capable, but
the signed artifact is still one TAP video format even if some or all depth
samples are missing. The manifest records where depth is missing so TAP playback
and analysis can surface the gap instead of pretending the stream is complete.

If recording stops early because of thermal or system pressure, the captured
segment can be kept and signed with a `stopReason`. The manifest records depth
coverage for the segment that was actually captured.

RGB and depth do not need the same frame rate. RGB may be recorded at the normal
video cadence, while the depth stream records the device's actual delivered
cadence. The manifest records each depth sample timestamp and the
nearest/corresponding RGB timestamp or frame index. Any interpolated depth used
by later analysis is a derived product and is not part of the authenticated
original resource.

## Duration, Thermal, and Pending State

The first version supports recordings up to 3 minutes. Recording can stop earlier
for thermal pressure, system pressure, storage errors, app lifecycle events, or
user stop.

Stopping does not require immediate signing or Photos export. The app may first
finalize an unsigned MP4 into the app-private pending store with an empty proof
slot. The async signing/export pipeline then:

1. Reads the finalized unsigned MP4.
2. Computes the content binding over original bytes excluding the proof slot.
3. Requests the App Attest assertion.
4. Writes the proof envelope into the reserved slot.
5. Validates the signed file.
6. Exports the signed MP4 as a Photos video resource.

This should extend `TAPPendingCaptureStore` with an explicit video artifact kind,
for example `.depthVideo`, rather than forcing video into still-photo container
types.

## Hash and Signing Contract

TAP signed video should use a new content-binding schema, tentatively:

```text
urn:tapnap:tapcam:content-binding:v4
```

The root signed artifact is the original MP4 byte stream with exactly one
excluded TAP proof slot. The root hash is not a decoded RGB hash, not a decoded
depth hash, and not a hash built by combining per-track hashes.

```text
assetHash = SHA-256(original MP4 bytes in file order, excluding TAP proof slot)
```

This is still a normal streaming/block hash over a binary file. The only special
handling is the proof slot exclusion, because the file must contain the App
Attest proof, and that proof signs a hash of the file. Including the proof bytes
in the same hash would create a circular dependency:

```text
hash(file) -> signature/proof -> write proof into file -> file bytes changed
```

The signed-content view therefore is:

```text
bytes [0, proofSlot.start)
bytes [proofSlot.end, file.end)
```

The proof slot descriptor records the slot kind, absolute byte range, payload
range, and zero-padding rule. After signing, only proof slot payload bytes may
change. Any rewrite of `moov`, `mdat`, track tables, manifest bytes, RGB frames,
audio samples, depth samples, timing, calibration, or private metadata changes
`assetHash` and invalidates the signature.

When a depth stream exists inside the MP4, the depth bytes are covered by
`assetHash`. Optional per-track hashes may be added for diagnostics and faster
error reporting, but they must not replace the whole-file byte hash as the trust
root.

The signing chain remains aligned with the current still-photo and Live Photo
model:

```text
assetHash over MP4 excluding proof slot
metadataHash over canonical video manifest payload JSON
proofSlot descriptor
  -> canonical contentDigest JSON
  -> SHA-256 canonical contentDigest JSON
  -> signingBinding.bodySHA256
  -> canonical signingBinding JSON
  -> clientDataHash
  -> App Attest assertion
  -> proof envelope written into TAP proof slot
```

## Manifest

TAP signed video needs a video-specific manifest payload, tentatively:

```text
urn:tapnap:tapcam:video-manifest:v1
```

It should reuse the existing manifest style where possible, but the payload must
describe a timed multi-track video artifact instead of one still image. Depth
coverage is represented inside that manifest as capture coverage facts, not as a
separate product or verification family. Expected fields:

- `captureID`, `capturedAt`, device identity, selected camera/FOV plan, and app
  build facts.
- MP4 container facts and track identifiers.
- RGB track facts: codec, dimensions, transform/orientation, frame rate or time
  base, duration, and frame count.
- Audio facts: `captured`, `notCaptured`, or `unavailable`, with codec and timing
  when captured.
- Depth coverage facts: whether a TAP depth track exists, sample count,
  dimensions, data type, depth-vs-disparity, pixel format, row stride,
  compression, timing, calibration, invalid-sample policy, and dropped-frame/gap
  summary when samples exist.
- Synchronization facts: relationship between RGB frame timestamps and depth
  sample timestamps, nearest/corresponding RGB frame references, observed timing
  deltas, and gap records.
- Stop reason: user stop, 3-minute limit, thermal pressure, system pressure,
  lifecycle interruption, storage failure, or capture failure.
- `assetHash` input policy reference and proof-slot descriptor reference.

The manifest describes what the file contains. The proof contains the
trust-bearing hashes. Per-track hashes, if added, are signed diagnostics; they
are not the primary resource boundary.

Depth coverage is represented as coverage summary plus gap ranges, not as a
per-RGB-frame bitmap. When there are depth samples, the samples themselves live
in the TAP private timed metadata track; the manifest records where depth is
absent so readers can explain gaps without inflating the manifest. If no depth
samples arrive, the same structure records `sampleCount: 0`.

```json
{
  "depthCoverage": {
    "track": "tap-depth-klv",
    "sampleCount": 1234,
    "gapCount": 2,
    "gaps": [
      {
        "startTime": "PT12.340S",
        "endTime": "PT12.520S",
        "nearestStartRGBFrame": 370,
        "nearestEndRGBFrame": 376
      }
    ]
  }
}
```

If no depth samples arrive, the same unified artifact records that fact:

```json
{
  "depthCoverage": {
    "track": null,
    "sampleCount": 0,
    "gapCount": 0,
    "gaps": []
  }
}
```

## Open-Source References

Use open-source tooling as a compatibility guardrail:

- GoPro `gpmf-parser`: reference for parsing capture-time telemetry payloads
  stored in an MP4/MOV time-indexed metadata track.
- GoPro `gpmf-write`: reference for writing compact GPMF-style KLV payloads.
- Bento4 tools such as `mp4dump`/`mp4info`: reference inspection tools for
  checking that the MP4 contains standard playable RGB/audio tracks plus the TAP
  private timed metadata track and appended proof slot.

The implementation should start as an app-integrated vertical slice, not as an
offline throwaway spike. The existing `VIDEO` mode should enter a constrained
signed-video path that records a short MP4, attaches a TAP KLV depth metadata
track when depth is available, saves it through the pending/sign/export pipeline,
reads the Photos original resource back, and confirms ordinary playback plus
byte-level TAP parsing. The first UI can be minimal, but the path must be wired
into the real app surfaces so early validation covers the same storage, signing,
Photos, and library seams that production will use.

## Proof Slot

For MP4, append TAP private top-level `uuid` boxes after `AVAssetWriter`
finalizes the unsigned file. The current implementation writes one manifest box
followed by one fixed-size proof-slot box. Both are appended at the end to avoid
rewriting existing MP4 offsets or media tables.

The manifest box is covered by the file hash. The unsigned file contains an
empty, zero-padded TAP proof slot. The app hashes the file excluding only that
slot, obtains the App Attest proof, and overwrites only the proof slot payload.
Normal MP4 players should ignore the unknown top-level `uuid` boxes.

Verification must reject missing slots, duplicate TAP proof slots, wrong slot
size, non-zero padding, proof overflow, or any file whose recomputed binding does
not match the proof value.

## Photos Boundary

Photos receives the final signed MP4 as a `.video` resource. The app must verify
the original resource after export by reading it back from Photos when possible
and comparing the byte-level binding. Playback success alone is not proof of
authenticity.

The user-visible rule is:

- Photos and normal players can play RGB/audio.
- TAP verifies the original signed MP4 resource the same way regardless of depth
  coverage, then parses depth samples according to the manifest coverage facts.
- Any derivative is allowed to play, but it is not an authenticated TAP depth
  video unless it passes the original-resource byte binding.

## UI Boundary

Use the existing `VIDEO` mode entry. The selected camera/FOV plan remains the
source of truth. In video mode:

- Shutter toggles start/stop recording.
- The UI shows elapsed time, depth availability, and pending/signing/export
  status.
- The shutter is not gated by instantaneous depth coverage. The UI must show
  depth coverage clearly before and during recording.
- The app does not auto-switch to a different lens or FOV. A future explicit
  "switch to a depth-capable lens" affordance can be added after the
  first version.
- Overheating or system pressure stops recording, saves the complete segment when
  valid, and surfaces the stop reason to the user.

## First Playback and Verification Scope

First-version viewing should be minimal:

- TAP Library can show pending and exported TAP video records with depth coverage
  status.
- Opening a record plays the standard RGB/audio video.
- The app shows signature status.
- The app parses the TAP manifest.
- The app can display one depth frame or basic depth stats when samples exist,
  such as frame count, dimensions, min/max, and invalid count. If
  `sampleCount == 0`, the app shows that coverage fact instead of a depth viewer.

Full depth-video scrubbing, per-frame 3D point cloud playback, region selection,
plane detection, and video-depth analysis are deferred.

## Implementation Phases

1. Enable the existing `VIDEO` mode as a constrained signed-video entry point.
2. Add depth coverage reporting for selected depth-capable capture plans.
3. Add TAP signed-video pending artifact modeling to `TAPPendingCaptureStore`.
4. Implement streaming RGB/depth/audio capture and unsigned MP4 finalization.
5. Add TAP private depth stream writer and parser.
6. Add video manifest schema with optional depth coverage and canonical encoder.
7. Add MP4 proof slot append/read/write support.
8. Add `content-binding:v4`, App Attest signing, and validation.
9. Export signed MP4 to Photos and validate original-resource readback.
10. Add video-mode pending/signing/export status.
11. Add minimal playback and manifest/depth-frame verification in TAP Library.
12. Add cross-platform parser tests for proof slot, content binding, manifest,
    and depth stream parsing.

## Verification Matrix

| Case | Expected Result |
| --- | --- |
| Standard player opens signed MP4 | RGB video plays; AAC audio plays when captured |
| TAP verifier opens original signed MP4 | App Attest proof, `assetHash`, `metadataHash`, proof slot, and manifest parse successfully |
| TAP verifier opens original signed MP4 with depth samples | Verification is the same; TAP parser also reads the depth stream named by `depthCoverage.track` |
| TAP verifier opens original signed MP4 with zero depth samples | Verification is the same; manifest reports `depthCoverage.sampleCount = 0` |
| One depth byte changes | `assetHash` mismatch; verification fails |
| One RGB frame byte changes | `assetHash` mismatch; verification fails |
| One audio sample changes | `assetHash` mismatch; verification fails |
| Manifest changes | `assetHash` and/or `metadataHash` mismatch; verification fails |
| Proof slot payload changes but proof remains structurally valid | App Attest or digest comparison fails |
| Proof slot padding is non-zero | Verification fails |
| MP4 is transcoded by Photos/share sheet | Playback may succeed; TAP verification fails unless the original byte binding is preserved |
| Depth stream has missing samples | Export can remain signed; manifest records depth gaps and TAP playback reports them |
| Thermal stop | Save shorter segment with `stopReason` and recorded depth coverage |
| Microphone unavailable or disabled | Export TAP video with `audio.status = notCaptured`; no fake silent track |
