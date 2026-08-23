# TAP Video Operational Contract

Status: current TAPCamDemo operational contract
Owner: finalization, Pending Capture Queue, Photos export/readback, playback,
and evidence
Last updated: 2026-08-23

## Authority Boundary

The documentation-only
[TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
repository is the sole shared authority for TAP Video v1 manifest fields,
canonical JSON, MP4 UUID boxes, proof-slot layout, KLV records/codecs/bounds,
content binding, signing, verification, and hash participation. Start with its
[TAP Video manifest](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/manifests/tap-video-v1.md),
[container/KLV contract](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/containers/tap-video-container-v1.md), and
[binding/proof contract](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/bindings/capture-binding-and-proof-v1.md).

This document owns only how TAPCamDemo implements that artifact through its
local lifecycle. Product scope comes from [ProductContract.md](ProductContract.md),
especially §3.3 and §7. Task and evidence status comes from
[ProjectBoard.md](ProjectBoard.md). A shared identifier, field, byte layout,
hash rule, or reader rule repeated in Git history is not a second authority.

## Finalization And Publication

```text
AVAssetWriter workspace
  -> finish capture media
  -> read finalized track facts
  -> assemble shared-contract metadata
  -> complete shared-contract container finalization
  -> validate the finalized artifact against the inspected facts
  -> atomically publish into the Pending Capture Queue
```

TAPCamDemo keeps these operational obligations:

- one capture publishes one original MP4; it has no durable preview movie,
  JSON sidecar, ZIP wrapper, or debug derivative;
- postflight values come from the finalized asset rather than requested
  settings;
- container finalization does not rewrite existing media tables or offsets;
- shared-contract consistency, calibration accounting, depth samples, and
  timeline/gap checks are bounded and stream payloads rather than loading the
  complete MP4 into `Data`; and
- the current 180-second UI stop is Runtime policy, not a decoder or format
  limit.

Runtime ownership is documented in
[CameraCapture/Runtime](../TAPCamDemo/CameraCapture/Runtime/README.md). Swift
schema, writer, and validator ownership is documented in
[CameraCapture/Output](../TAPCamDemo/CameraCapture/Output/README.md).

## Zero-Depth Operation

A successfully finalized RGB/audio MP4 remains a TAP Video when no valid depth
sample arrived. TAPCamDemo must retain, sign, export, read back, and play it,
while presenting depth as unavailable. It must not create a fake metadata track,
duplicate samples, or turn missing depth alone into an integrity failure.

The shared manifest contract owns the exact zero-depth fields. Remaining paths
that still persist zero depth as terminal are the P0 conformance gap
[TAP-0011](ProjectBoard.md#tap-0011--make-zero-depth-tap-video-non-blocking),
not an alternate artifact definition.

## Signing And Local Integrity Gates

A finalized, ingested pending MP4 is the app-owned source artifact. The queue:

1. validates queue and manifest capture/package identity;
2. freezes the unsigned artifact into an independent same-bundle working
   generation;
3. reconstructs and persists the pre-sign shared content binding;
4. asks the capture signer to generate the App Attest proof and fills only the
   fixed slot in the working generation;
5. reopens that generation and repeats the shared local reconstruction and
   relationship checks; and
6. atomically publishes the complete inode over the durable path only after the
   check passes.

The temporary generation is discarded on failure or cancellation. It is not a
Share package or persistent cache, and it must never be a hard-linked mutable
view of the durable file.

This local gate proves byte, manifest, content-digest, signing-binding, and
proof-envelope consistency. It does not possess the registered App Attest
public key and therefore does not perform the backend cryptographic assertion
verification. The browser/backend split and exact signature verification order
are defined in the shared binding/proof contract.

Depth-track health is a separate optional semantic gate. For an already signed
untrusted file, local binding reconstruction precedes any requested bounded
AVFoundation scan. Normal signing, Photos export, and original-resource
readback use the local binding gate without making depth presence or health a
condition of authenticity.

## Pending Queue, Photos Export, And Readback

The app-private workflow is:

```text
Pending/<captureID>/
  bundle.json
  artifact.mp4
  thumbnail.jpg   # optional local derivative
```

- Recording uses a hidden workspace and commits the finalized file plus record
  atomically.
- Video APIs pass file URLs and use clone/copy plus streaming inspection; they
  do not materialize the whole MP4 as `Data`.
- The pre-sign binding detects mutation outside the proof slot before signing.
- Photos export persists pre-commit and commit-ambiguous state so retry does not
  create a duplicate asset after an interrupted save.
- The app exports one video resource named from the package identity, streams
  the Photos original into a temporary file, and repeats identity plus local
  binding validation before marking the queue record exported.
- A filename or Photos playback success is only an index hint, never integrity
  evidence.

Queue state, retry, storage, and cleanup ownership lives in
[TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md).

## Playback And Derivatives

TAP Library opens a pending file or a managed temporary copy of the Photos
original without loading the whole MP4 into memory.

- `RAW` plays standard RGB/audio independently of depth.
- `2D` requires a complete, validated registered descriptor and matching depth
  track/format; placement uses `AVPlayerLayer.videoRect`.
- Decode stays bounded around the playhead. Seek, discontinuity, item change,
  cancellation, and memory reset clear retained depth so unrelated frames are
  not reused.
- Playback is foreground/local only; external playback, Picture in Picture, and
  background playback remain explicit non-goals.
- TAP Video 3D remains future work.

Playback is downstream consumption, not a new cryptographic Verify action.
Photos edits, transcodes, and social uploads may remain playable but are not the
original authenticated byte view. Share Video may make an on-demand
byte-for-byte temporary copy; TAP Video `.tapnap` transport remains Coming Soon.

The playback implementation boundary is documented in
[PLAYBACK.md](../TAPCamDemo/DepthAnalysis/Playback/PLAYBACK.md).

## Fixtures And Evidence

Executable vector mirrors and runtime-generated fixture ownership are recorded
once in the test
[fixture and golden-vector ledger](../TAPCamDemoTests/README.md#fixture-and-golden-vector-ownership).

Current evidence gaps remain tracked by their canonical Tasks:

- `TAP-0011`: complete zero-depth non-blocking conformance.
- `TAP-0045`: attended device codec, memory, thermal, registration, zero-depth,
  iCloud, and device/format coverage.
- `TAP-0046`: production App Attest entitlement/backend/assertion and final
  signed-export evidence.

Physical-device execution requires the written procedure and owner confirmation
defined by [Acceptance/README.md](Acceptance/README.md). No field, identifier,
box, KLV rule, or signing rule may change through this operational document; a
format change needs a separately approved Task and shared-contract versioning
decision first.
