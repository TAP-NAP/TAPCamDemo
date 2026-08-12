# TAP Video Format Contract

Status: current interface and provenance contract
Owner: TAP Video format and cross-implementation compatibility
Last updated: 2026-08-12

This document defines the current TAP Video artifact, timed-depth payload,
manifest, proof, pending/export, readback, and playback boundaries. Product
scope comes from [ProductContract.md](ProductContract.md), especially §3.3 and
§7. Task and evidence status comes from [ProjectBoard.md](ProjectBoard.md).

This is not an implementation plan. Old vertical-slice phases, branch-specific
failures, refactor scorecards, and experiments do not define this contract.
Changing a versioned field or byte layout requires a new Task, schema version,
reader compatibility decision, and golden vector; it must not silently mutate
version 2.

## 1. Canonical Artifact

One capture produces one original MP4 resource:

| Part | Current contract |
| --- | --- |
| Container | One `video/mp4` file. |
| RGB | Exactly one standard video track. The finalized file's actual codec, dimensions, timing, transform, and track ID are bound in the manifest. The Runtime fallback is H.264; readers must use the recorded facts rather than assume a codec. |
| Audio | Zero or one standard audio track. When written, Runtime uses AAC. The manifest distinguishes `captured`, `notCaptured`, and `unavailable`; it must not invent a silent track. |
| Depth | Zero or one TAP-private timed metadata track. It exists only when real depth samples were stored. |
| Manifest | Exactly one TAP manifest top-level BMFF `uuid` box with user type `TAPCAMVIDEOMANF1`. Its payload is bounded to 1 MiB. |
| Proof | Exactly one fixed TAP proof-slot top-level BMFF `uuid` box with user type `TAPCAMPROOFSLOT1`. |

The Release artifact has no durable depth-preview movie, JSON sidecar, ZIP
wrapper, or debug derivative. A poster is a local TAP Library derivative and is
not part of the signed MP4.

The current capture UI stops at 180 seconds by default. That duration is a
Runtime policy, not a decoder rule or a versioned MP4-format limit. A shorter
valid segment may record a truthful stop reason such as user stop, duration
limit, thermal pressure, system pressure, lifecycle interruption, storage
failure, or capture failure.

## 2. Finalization And Track Truth

`AVAssetWriter` first finalizes the standard tracks. The app then reads the
finished asset's actual track facts, constructs the manifest, appends the
manifest box, appends one empty proof slot, and publishes the file into the
Pending Capture Queue workspace. Appending the private boxes must not rewrite
the existing media tables or offsets.

The manifest records postflight facts rather than requested assumptions:

- container duration, timescale, and track count;
- RGB track ID, codec, dimensions, timing, frame rate/count, and transform;
- audio status and actual track facts when captured;
- depth track facts, format, delivered/stored/drop counters, calibration,
  synchronization, and bounded gap ranges;
- selected camera plan, capture/package identities, stop reason, and software
  facts.

For an artifact with stored depth, semantic validation requires exactly one
RGB track, exactly one TAP metadata track, and zero or one audio track. For a
zero-depth artifact, the canonical composition is one RGB track plus optional
audio and no TAP metadata track. The manifest and file must agree in both
cases.

Runtime ownership is documented in
[CameraCapture/Runtime](../TAPCamDemo/CameraCapture/Runtime/README.md); schema,
proof, and validator ownership is documented in
[CameraCapture/Output](../TAPCamDemo/CameraCapture/Output/README.md).

## 3. TAP Timed Depth Track

When depth samples exist, the metadata item identifier is:

```text
mdta/com.tapnap.depth.klv
```

Each timed item contains one independently decodable TAP KLV frame. TAP reuses
the compact, time-indexed KLV pattern associated with GPMF, but this is a
TAP-private namespace and schema; it does not adopt GoPro field meanings or
claim that the track is a standard depth-video track.

### 3.1 KLV frame version 2

Every record is:

```text
fourCC[4] | payloadLengthUInt32BE[4] | payload | zero padding to 4 bytes
```

Current frame version 2 emits these records:

| Key | Meaning |
| --- | --- |
| `TVER` | KLV frame schema version, currently `2`. |
| `FRAM` | Stored depth-frame index. |
| `PTS ` | Capture-relative presentation value and timescale. |
| `COMP` | `raw`, `lzfse`, or `zstd1`. |
| `ULEN` | Uncompressed packed-frame byte count. |
| `CALI` | Optional index into the manifest calibration table. |
| `DPTH` | Opaque compressed or raw packed depth bytes. |

Readers may skip unknown keys, but must reject duplicate keys, truncated
records, unsupported `TVER`, non-zero alignment padding, oversized payloads,
and a decoded byte count that differs from `ULEN`. Integer control fields are
big-endian. The packed depth samples use the byte order declared by the
manifest, currently little-endian.

### 3.2 Packed depth and compression

- Pack only `width * bytesPerSample` logical bytes per row; capture-buffer
  alignment and extended padding are not signed as pixel content.
- Current accepted stored formats are Float16 or Float32 depth/disparity:
  `hdep`, `fdep`, `hdis`, and `fdis`.
- Preserve the captured depth/disparity kind and bit patterns. Do not quantize,
  synthesize, interpolate, or duplicate samples to match the RGB cadence.
- Each frame is compressed independently. The writer prefers Zstandard level 1
  and stores the raw frame whenever compression fails or is not smaller.
- Version-2 readers accept `raw`, `lzfse`, and `zstd1`. The current writer's
  declared policy is `per-frame:zstd1|raw`; LZFSE remains a readable codec, not
  a claim that every current file uses it.
- One uncompressed frame is bounded to 32 MiB. A KLV frame has a bounded record
  count and encoded-size limit.

The invariant stored layout lives once in `depthCoverage.format`. Per-sample
KLV records carry timing, codec, byte count, optional calibration index, and
payload. Real missing intervals are represented as signed gap ranges with a
reason; they are not filled with fabricated depth.

## 4. Manifest Version 2

The current identifiers are:

```text
schema.id    = urn:tapnap:tapcam:video-manifest:v2
schema.version = 2
mediaType    = application/vnd.tapnap.video-manifest+json;version=2
```

The writer encodes canonical JSON with sorted keys and without escaped slashes.
The top-level `proofs` array remains empty: the App Attest proof body belongs
only in the separate proof slot. The canonical metadata hash covers the
manifest `payload` without `proofs`; the raw manifest box is independently
covered by the MP4 asset hash.

The payload owns these groups:

- capture and package identity plus capture time;
- selected camera plan;
- container, RGB, and audio facts;
- depth coverage, format, counters, and gaps;
- spatial registration and calibration coverage;
- RGB/depth timestamp relationship;
- stop reason and recorded duration; and
- schema-writer software facts.

Depth gaps are bounded to 1,024 records. The calibration table is bounded to 16
entries, and its indexed/missing/overflow counters must account for every
stored depth sample.

### 4.1 Registration

The current reproducible registration descriptor is:

```text
urn:tapnap:tapcam:video-depth-registration:avdepthdata-yuv-warp:v1
```

Only `registered` plus a complete, validated descriptor enables registered 2D
playback. It binds RGB/depth reference dimensions, RGB clean aperture,
connection transform and mirroring, stabilization mode, calibration, and the
depth-pixel-center to aligned-RGB affine mapping. `unavailable` carries no
descriptor. `approximate` is not an accepted substitute and must never enable
the 2D overlay.

## 5. Zero-Depth Is A Canonical TAP Video

A successfully finalized RGB/audio MP4 remains a TAP Video when no valid depth
sample arrived. Its canonical depth facts are:

```text
depthCoverage.trackID = null
depthCoverage.trackCodec = null
depthCoverage.sampleCount = 0
depthCoverage.format = null
synchronization.rgbToDepthMapping = no-depth-samples
```

The manifest may record the full affected interval as a truthful
`silentCadence` gap. The content binding records `depthResource.presence` as
`no-samples` and binds that fact through the manifest. The app must retain,
sign, export, read back, and play the RGB/audio artifact, while showing a
non-blocking depth-unavailable indication. It must not create a fake metadata
track or claim 2D/3D readiness.

Missing depth alone is not a writer, integrity, or terminal queue failure. The
remaining source paths that still persist zero depth as terminal are the P0
conformance gap [TAP-0011](ProjectBoard.md#tap-0011--make-zero-depth-tap-video-non-blocking),
not an alternate format rule.

## 6. Proof Slot And Content Binding

The proof-slot box payload is exactly 60 KiB. Version 1 uses a 32-byte header:

```text
0...19   ASCII TAPCAM-PROOF-SLOT-V1
20...23  reserved zero bytes
24...27  UInt32BE version = 1
28...31  UInt32BE proof-envelope length
32...    proof-envelope JSON followed by zero padding
```

Readers require exactly one correctly sized slot, a valid header and version,
a non-empty bounded envelope, and all remaining padding bytes equal to zero.
Duplicate, missing, malformed, overflowing, or non-zero-padded slots fail
closed.

The video content binding is
`urn:tapnap:tapcam:content-binding:v4`:

```text
assetHash = SHA-256(MP4 bytes in file order, excluding exactly the complete
                    fixed proof-slot uuid-box byte range)
metadataHash = SHA-256(canonical manifest payload JSON)
```

The manifest box, media tables, RGB, audio, KLV samples, timing, calibration,
and every other MP4 byte remain inside `assetHash`. The binding also records
capture/manifest identity, capture time, the excluded proof-slot descriptor,
and the depth-resource presence rule.

Signing then uses
`urn:tapnap:tapcam:app-attest-capture-signing:v1`: SHA-256 of the canonical v4
binding becomes `bodySHA256`; SHA-256 of the canonical signing binding becomes
the App Attest `clientDataHash`. The resulting
`appAttestAssertion` / `TAPCam.AppAttestCaptureSignature.v1` proof envelope is
written in place. Only proof-slot bytes may change after the pre-sign binding
is persisted.

Proof authentication and depth-track health are deliberately separate:

1. Recompute and authenticate the proof and v4 byte binding first.
2. Run the AVFoundation track/KLV/timeline semantic scan only when a caller
   explicitly requests it.

Normal signing, Photos export, and original-resource readback use the first
gate without making depth presence or health a condition of authenticity. A
semantic scan of untrusted input must never run before proof authentication.
Neither gate proves the physical scene, event, person, time, non-AI origin, or
the correctness of depth as a statement about reality.

## 7. Pending, Photos Export, And Readback

The app-private Pending Capture Queue owns the durable workflow:

```text
Pending/<captureID>/
  bundle.json
  artifact.mp4
  thumbnail.jpg   # optional poster derivative
```

Recording starts in a hidden workspace, then commits the finalized MP4 and
record atomically. The same `artifact.mp4` transitions from empty proof slot to
proof-filled signed file in place. Video APIs use file URLs, streaming box
inspection, bounded hashing, and bounded depth work; production must not
materialize the complete MP4 as `Data` or create a second full-size signing
copy.

Before signing, `captureID` and `packageID` must match the manifest. The queue
persists the pre-sign binding so a later byte change outside the proof slot is
an external-mutation failure. After local proof authentication it records the
artifact as signed.

Photos export follows a crash-recoverable boundary:

1. Persist pre-commit intent.
2. Authenticate the exact local file and pass its URL to Photos as one video
   resource named `tap-<lowercase-package-uuid>.mp4`.
3. Persist commit-ambiguous/committed state before assuming another create is
   safe.
4. Stream the Photos original resource into a temporary file and run the same
   proof and v4 byte-binding gate.
5. Only after successful readback mark the record exported and remove the
   app-private large MP4. Keep the small record/poster needed by TAP Library.

Recovery uses the package-specific filename only as an index hint. A candidate
is accepted only after identity and byte-binding validation; retry must not
create a duplicate Photos asset after an ambiguous commit.

Queue ownership and its coarse retry state are documented in
[TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md). Photos playback or
successful decoding alone is never authenticity evidence.

## 8. Playback And Derivatives

TAP Library opens a pending file locally or obtains the current Photos original
as a managed temporary file. It does not load the complete MP4 into memory.

- `RAW` plays the standard RGB/audio tracks and is available independently of
  depth.
- `2D` is available only when the manifest provides a complete registered
  descriptor and a matching depth track/format. The overlay is placed against
  `AVPlayerLayer.videoRect`, not the whole viewport.
- A transient gap during continuous playback may hold the last depth frame to
  avoid flashing. First-frame absence, seek/discontinuity, item change,
  cancellation, or memory reset clears it so unrelated depth is not reused.
- Depth decode is bounded around the playhead: currently 24 MiB retained and at
  most two concurrent decodes.
- Playback is local and foreground-only. External playback/AirPlay is disabled;
  Picture in Picture and background playback are explicit non-goals.
- TAP Video 3D remains future work. Playback must not reinterpret current KLV
  frames as an implemented 3D product.

The playback module boundary is documented in
[PLAYBACK.md](../TAPCamDemo/DepthAnalysis/Playback/PLAYBACK.md). Playback is not
a new Verify action for a TAPCam-owned capture; it consumes the capture's
persisted credential state.

The signed object is the original MP4 byte view defined above. A Photos edit,
transcode, social upload, or other derivative may remain playable but is not an
authenticated TAP Video unless it independently preserves and passes the same
binding. Share Video may make an on-demand byte-for-byte temporary copy of the
original. A TAP Video `.tapnap` transport is not part of this format and remains
Coming Soon.

## 9. Compatibility And Evidence

Ordinary MP4 players are expected to play the standard RGB/audio tracks and
ignore the private metadata and top-level `uuid` boxes. TAP readers use the
versioned private contract. Unknown KLV keys are skippable; unsupported schema
versions and malformed bounded structures fail closed.

The repository interoperability fixture is
[TAPVideoManifestV2GoldenVectors.json](Fixtures/TAPVideoManifestV2GoldenVectors.json).
It fixes a manifest-v2 JSON example, KLV-v2 frame, Float16 bit-pattern payload,
and Zstandard 1.5.7 level-1 vector. Readers must reproduce the decoded bytes and
semantic values. Changing the vector requires a version/compatibility review,
not regeneration to fit an incompatible writer.

Current proof and resource design must preserve a migration path toward C2PA
compatibility, but TAPCam does not claim C2PA certification or complete C2PA
interoperability.

The following are evidence or conformance gaps, not alternate contracts:

- `TAP-0011`: remove remaining terminal zero-depth behavior across Runtime,
  queue, semantic validation, and presentation.
- `TAP-0045`: attended device evidence for codec throughput and drops,
  duration-to-RSS behavior, thermal limits, registration landmarks, zero-depth,
  iCloud-only originals, and broader device/format coverage.
- `TAP-0046`: production App Attest entitlement/backend/assertion and final
  signed-export evidence.
- Cross-platform non-Swift parsing and proof verification must be demonstrated
  against the golden vector and real original resources; the Swift fixture
  alone is not that evidence.

Physical-device execution requires the written procedure and owner confirmation
defined by [Acceptance/README.md](Acceptance/README.md).
