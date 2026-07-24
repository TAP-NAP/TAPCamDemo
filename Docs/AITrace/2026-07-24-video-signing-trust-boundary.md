# TAP Video Signing Trust Boundary

## Goal

Correct the TAP Video signing pipeline after a freshly recorded video could be
classified `invalidVideoArtifact` / `failedTerminal` before App Attest signing.
The accepted product rule is that the finalized, ingested app-owned MP4 is the
source artifact. Signing proves which exact bytes were captured; it does not
prove that a later semantic reader agrees with every depth-track health rule.

## Root Cause

`TAPCaptureProvenanceWriter.signedVideoFile` ran
`TAPVideoDepthTrackValidator.validate` before computing the signing binding.
The signed-export validator also ran the full manifest semantic schema checks
even when `validatesDepthTrack` was false, while export and Photos readback
defaulted the flag to true.

That combined two independent questions:

1. Does this proof correspond to these exact MP4 and manifest bytes?
2. Does an AVFoundation/KLV semantic scan consider every track, counter,
   calibration record, and timeline gap healthy?

A negative answer to question 2 could therefore prevent question 1 from ever
being signed and could move an unsigned capture to `failedTerminal`.

## Implemented Contract

The normal pipeline now:

1. locates the fixed proof slot;
2. decodes the manifest and matches capture/package identity;
3. hashes exact MP4 bytes outside the proof slot plus canonical manifest
   payload;
4. creates and writes the App Attest proof;
5. re-reads the proof and recomputes the binding;
6. requires proof `contentDigest` and `signingBinding` to match those exact
   bytes;
7. repeats the byte-binding check before Photos save and after original-resource
   readback.

Full `TAPVideoDepthTrackValidator` work is still available through the explicit
`validatesDepthTrack: true` health path. For a signed candidate, byte
authentication runs before AVFoundation parses its timed metadata.

Queue classification now reads the latest persisted record. Manifest/proof
errors on `.unsigned` video remain retryable. The same errors on a persisted
`.signed` artifact may be terminal, as may an externally changed persisted
pre-sign binding. Existing capture-time missing-depth policy is unchanged.

Existing records require a disk migration because changing the classifier does
not change a previously persisted `.failedTerminal` status. Worker reconcile
now reopens only records that:

- are TAP Video and still `.unsigned`;
- failed with the historical `.invalidVideoArtifact` or
  `.proofValidationFailed` code;
- retain their local video artifact;
- have no Photos asset or export-recovery phase.

They become `.failedRetryable` and enter the normal signing route during the
same worker run. Signed failures, missing-depth failures, external mutation,
Photos readback failures, and records without the source artifact remain
terminal.

## Scope

- No server URL, App Attest environment, or Release signing behavior changed.
- Video recording/finalization and Photos save mechanics are unchanged.
- No persistent probe or high-frequency logging was added.

## Validation

Automated coverage includes:

- signing a synthetic finalized pending MP4 that intentionally cannot pass a
  real media-track scan;
- successful default byte-binding validation of that signed file;
- failure of the explicit semantic health path for the same synthetic file;
- rejection after mutating one byte outside the proof slot;
- retryable classification for unsigned manifest failure;
- terminal classification after signed state has been persisted.
- scoped migration and same-run retry of an existing unsigned
  `invalidVideoArtifact` terminal record.

Completed locally:

- Debug `build-for-testing` passed for iPhone 17 Pro, iOS 26.5.
- `TAPVideoStreamingTests`, `TAPLibraryProcessingTests`,
  `TAPLibraryStorageTests`, and `TAPDiagnosticsOSLogPrivacyTests` passed in one
  serialized focused run.
- `TAPVideoReleaseSourceGuardTests` and `TAPSignedExportValidatorTests` passed.
- Generic iOS Simulator Release build passed.
- `git diff --check` passed.

Physical-device acceptance remains required for one real PRO Video capture:
record, finish, sign, export, and Photos original-resource readback. Simulator
tests cannot exercise LiDAR delivery or the physical recording graph.
