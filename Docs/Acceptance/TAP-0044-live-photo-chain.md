# TAP-0044 — Live Photo Capture, Signing, Readback, Audio, And Playback

- Status: `Draft — blocked until the owner freezes the matrix and run budget`
- Related Delivery: `TAP-0056`
- Contract: [ProductContract §3.2 and §5.2](../ProductContract.md),
  [shared artifact contract index](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/CONTRACTS.md)
- Build/Commit: `OWNER-LIVE: freeze before execution`
- Device/iOS Matrix: `OWNER-LIVE: approve before execution`
- Human Confirmation: `Pending`

This is an attended physical-device procedure for the current Live Photo
chain. It does not test or imply per-frame MOV depth.

Before execution, the product owner must freeze the supported physical
device/iOS rows, HEIC/JPG and audio-state coverage, repetitions, maximum capture
count, artifact retention, and production-or-development App Attest
environment. An Agent must not choose those values after seeing the result.

## Preconditions

- The candidate build includes the current Live Photo capture, Pending Capture
  Queue signing/export, Photos original-resource loading, TAP Library, and
  native Live Photo playback paths.
- The selected device supports the candidate build's Live Photo path. Camera,
  Photos, and, for audio-captured rows, Microphone authorization are available.
- OS Microphone authorization and TAPCam's Microphone data-use preference can
  be controlled independently. Both must permit audio for an
  `audio = captured` row.
- The run has a visible scene change and a short audible cue that make motion
  and sound observable without identifying a person or recording private
  speech.
- Public-safe logs can correlate capture, paired-MOV delivery, manifest/proof,
  queue state, export, Photos resource loading, and playback without exposing
  raw paths, full identifiers, key IDs, assertions, or proof bodies.
- An approved diagnostic/export path can preserve or hash the exact signed
  primary photo and paired MOV before queue cleanup, then read the original
  Photos `.photo` and `.pairedVideo` resources without using a generic share
  path that may transcode them.
- A usable App Attest capture credential exists for the environment chosen by
  the owner. Production attestation itself is accepted separately under
  `TAP-0046`.
- **OWNER-LIVE:** approve the run budget and fill every selected row below.
  An unselected row must say `Not in approved matrix`, not `Passed`.

## Matrix To Freeze

| Row | Primary format | Microphone OS authorization | TAPCam audio data use | Repetitions | Owner decision |
| --- | --- | --- | --- | --- | --- |
| L1 | HEIC | Granted | On | `OWNER-LIVE` | `OWNER-LIVE` |
| L2 | HEIC | Granted or not granted | Off | `OWNER-LIVE` | `OWNER-LIVE` |
| L3 | JPG | Granted | On | `OWNER-LIVE` | `OWNER-LIVE` |
| L4 | JPG | Granted or not granted | Off | `OWNER-LIVE` | `OWNER-LIVE` |

The owner may reduce or expand this proposal before the run, but the frozen
matrix and reason must be recorded in the result. A row cannot change after its
first capture.

## Reset / Install Procedure

1. **OWNER-LIVE:** approve installation of the frozen signed build and any
   removal of an earlier test build. Do not delete unrelated Photos assets.
2. Record commit, build number, distribution method, signing environment,
   device model, iOS version, free storage, and current Camera/Photos/
   Microphone authorization.
3. Archive prior logs and test artifacts. If named test assets must be removed,
   show the exact list to the owner and use the system Photos confirmation.
4. Install or update using the approved method. Launch once, complete required
   setup, and confirm TAP Library is readable.
5. Set the first frozen matrix row. Start a continuous screen recording and
   public-safe device logs before entering Live Photo capture.

## Procedure And Expected Results

Run the numbered steps for every frozen matrix row and repetition.

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Record the row ID, output-format setting, both Microphone states, capture mode, and pre-capture queue count. | The recorded settings exactly match the frozen row. Changing OS authorization alone does not override a saved TAPCam data-use opt-out. | Pending | Pending |
| 2 | **OWNER-LIVE:** frame the approved moving scene, produce the approved audible cue for audio-on rows, and press the shutter once. | The shutter responds once, the live camera remains interactive, and exactly one candidate capture enters the pipeline. | Pending | Pending |
| 3 | Observe photo completion and the Apple movie-complement callback. | A successful Live Photo row produces one primary HEIC/JPG and one `paired-video.mov`. If the complement fails, the app may produce a valid still-photo v1 artifact, but it must not label or export a partial Live Photo v1 artifact; that row has not passed Live Photo acceptance. | Pending | Pending |
| 4 | Before cleanup, inspect the pending resource inventory and hash the exact resources through the approved diagnostic path. | The bundle has the selected primary container and exactly one paired MOV. No decoded frame, preview image, or adjusted Photos resource replaces either source. | Pending | Pending |
| 5 | Decode the embedded manifest from the primary photo. | The manifest passes the current shared Live Photo contract, reports the observed audio and primary-photo depth facts truthfully, and makes no per-frame MOV-depth claim. | Pending | Pending |
| 6 | Allow the Pending Capture Queue to sign the capture and inspect the resulting proof through the approved audit tool. | The exact photo/MOV pair passes the complete shared producer-binding checks and one App Attest capture assertion is written without changing the bound resources. | Pending | Pending |
| 7 | Observe the final local gate and Photos commit. | `validateSignedExportLivePhoto` accepts the exact signed photo/MOV pair before `saveDepthLivePhoto` can commit it; any shared-contract mismatch is rejected before export. | Pending | Pending |
| 8 | Load the saved asset's original Photos resources using the approved original-resource path. | Photos exposes the original `.photo` and `.pairedVideo`, and the complete shared local binding reproduces from those resources. Adjustment or presentation resources, if any, are recorded separately and never substituted. | Pending | Pending |
| 9 | Open the saved item in TAP Library, page away and back, then press and hold the Live Photo. | The correct item remains selected, native Live Photo motion plays without a blank replacement or crash, and release returns to the still presentation. Record the Viewer mute policy separately; this step does not silently convert captured-audio acceptance into a requirement for surprise sound in TAP Library. | Pending | Pending |
| 10 | Inspect the original paired MOV's audio tracks, then **OWNER-LIVE** plays it on the approved sound-enabled diagnostic or system surface. | Audio-on rows contain the captured audio track, report `audio = captured`, and reproduce the approved cue when sound is explicitly enabled. Audio-off rows contain no captured audio, report `audio = not-captured`, and remain silent. Ambient privacy-sensitive audio is not retained as acceptance evidence. | Pending | Pending |
| 11 | Export verification originals through the approved TAP verification-resource path and compare them with the Photos readback. | The primary file and paired MOV remain byte-identical to the Photos readback; transport routing metadata remains unsigned and supplies no trust facts. | Pending | Pending |
| 12 | Repeat steps 1–11 for the frozen matrix without changing counts or pass thresholds. | Every selected row produces a complete result record. A failed repetition remains in the report; it is not overwritten by a later success. | Pending | Pending |

## Required Evidence

- Frozen build/commit, distribution/signing environment, device/iOS matrix,
  row selections, repetitions, run budget, and operator.
- Continuous owner-attended recordings for capture and native playback, with
  privacy-sensitive audio excluded from the retained package.
- Per-capture public-safe event timeline: shutter, primary photo, movie
  complement, queue states, signing, final gate, Photos commit/readback, and
  playback.
- Primary format, Photos resource-type inventory, shared-contract conformance
  report, and redacted App Attest proof summary.
- SHA-256 audit table for the exact pre-export resources and Photos original
  readback. Raw media and proof material must remain in the owner-approved
  access-controlled evidence location; the Markdown result stores only
  redacted identifiers and hashes.
- Audio track/manifest result and owner-heard playback on the approved
  sound-enabled surface for every selected audio state; record TAP Library's
  mute policy separately.
- **OWNER-LIVE:** written confirmation of the visible motion, audio behavior,
  TAP Library paging/playback, and final matrix result.

## Verdict Conditions

- **Pass:** every frozen row and repetition completes the primary-photo plus
  paired-MOV chain; shared Live Photo contract facts are truthful; signing,
  final gate, Photos original readback, and native motion playback all succeed;
  the original MOV's audio behavior matches both permission layers on the
  approved sound-enabled surface; and the owner accepts the result.
- **Fail:** a selected row loses or substitutes an original resource; exports a
  partial Live Photo; binds the wrong bytes or schema; misreports audio or depth
  scope; bypasses the final gate; cannot reproduce the signed hashes from
  Photos originals; produces a missing/wrong audio track or cannot reproduce
  the cue on the approved sound-enabled surface in an audio-on row; captures
  audio in an audio-off row; or fails owner-observed native motion playback.
- **Blocked:** the build, matrix, repetitions, run budget, device, permission
  state, credential environment, safe diagnostics, exact-resource readback, or
  owner attendance is unavailable. Simulator, generated fixtures, or generic
  Photos sharing alone cannot close this Task.

## Human Confirmation

`Pending — OWNER-LIVE must accept the frozen matrix and observed device run.`
