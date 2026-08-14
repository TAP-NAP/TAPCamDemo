# TAP-0082 — TAP Share system handoff acceptance

- Status: `In progress — four-path transport Pass; lifecycle repair pending`
- Related implementation: `TAP-0081`
- Product Contract: §5.3, §8
- Updated: `2026-08-14`

## Regression record

On the original reopened physical-device build, choosing **Save to Files** made
the system destination picker flash and dismiss with an invalid-argument error.
Choosing **AirDrop** remained at **Waiting** and produced no received artifact.
The captured log repeatedly included:

```text
Could not load representation public.zip-archive from the item provider for opening in place
```

Candidate `35745be` replaced that option with a copy-backed manual provider and
passed its provider-load tests, but the owner's later physical-device run still
failed: AirDrop displayed **未找到用户**, and ordinary-image Share exhibited the
same system failure and repeated LaunchServices `Code=-54` diagnostics as
`.tapnap`. That cross-format result rejects a package/custom-UTI-only diagnosis
and rejects `35745be` as an accepted repair. The `Code=-54` diagnostics may
accompany system plugin discovery, but they are not by themselves a reason to
add a private entitlement or a substitute for behavioral evidence.

The current recovery restores the previously working system-native file-URL
activity item for ordinary media and `.tapnap`. It removes the shared manual
`NSItemProvider`/`UIActivityItemsConfiguration` transport while preserving the
materialized package, exported `.tapnap` UTI, one system activity controller,
and app-owned Share UI. The system controller is the final source owner:
system/user dismissal, representable dismantling, or never-appeared recovery may
end app state but must not explicitly delete its file; controller release
performs the attempt-scoped idempotent cleanup. TAPCam does not install a
destination-completion callback to proactively close the system presentation.
After the ineffective destination-completion callback was removed, the owner
explicitly replied **“验收通过”** to the immediately preceding confirmation of
the complete ordinary-image/`.tapnap` × Save to Files/AirDrop matrix, including
that every saved or received artifact opens. That is a Pass for the four-path
attended transport matrix below. The containing checkpoint commit freezes that
working transport under the subject **“Checkpoint working Share transport
before lifecycle repair”**. It deliberately does not accept teardown or
temporary-file lifecycle: the detailed follow-up log shows system URL probing
begins after controller construction but before the coordinator records
handoff, and the first dismissed attempt has no observed controller-dismantle
or terminal `scope=artifactLease` cleanup milestone before the next attempt.

## Fixed-build prerequisites

- [x] Freeze the accepted transport baseline in the containing commit under the
      subject **“Checkpoint working Share transport before lifecycle repair”**
      on `codex/tap-share-system-handoff-recovery`; `35745be` remains failed
      history. This self-reference does not claim a later lifecycle-fixed build.
- [x] The owner installed and attended-tested the current recovery working tree
      on the sending device rather than reusing the old `bf20b52` result. Its
      exact commit/build identity remains Pending.
- [x] Record sending device model and iOS version.
- [ ] Record the reachable receiving Apple device model and OS. Successful
      AirDrop reception is confirmed, but those identifiers were not supplied.
- [x] Files and AirDrop were available for the accepted four-path matrix.
- [x] Prepare one ordinary image-share case and one signed still or Live Photo
      whose TAPNAP Package row is available.
- [ ] Keep device logs available and choose a destination where the received
      artifact can be inspected and hashed.

## Attended procedure

1. Launch the fixed build after a clean installation or cleared container, open
   TAP Library, enter the selected Viewer, open TAP Share, and first choose the
   ordinary **Share Image** path.
   - Expected: app-owned preparation reaches ready and presents exactly one
     system activity controller.
2. Choose **Save to Files**.
   - Expected: the Files destination picker remains presented; it must not flash
     and dismiss or report an invalid argument.
3. Choose a directory and save.
   - Expected: the ordinary image is present, non-empty, and opens correctly.
     TAPCam does not proactively dismiss the system-owned presentation merely
     because the destination reports completion.
4. Start a new ordinary-image share attempt and choose **AirDrop** to the
   prepared receiving device.
   - Expected: transfer advances beyond Waiting, the receiver can accept it,
     and a received image artifact is available and opens correctly.
5. Repeat Steps 1–4 using **TAPNAP Package**.
   - Expected: Save to Files produces a non-empty
     `TAPNAP-Capture.tapnap`; AirDrop discovers the same known-reachable peer,
     advances beyond Waiting, and produces a received `.tapnap` artifact that
     opens as the expected ZIP-backed package.
6. Record the saved and received ordinary-media and `.tapnap` filenames, types,
   sizes, openability, and hashes. Do not assume independently generated TAPNAP
   attempts must have identical archive hashes.
7. Repeat once, cancelling the system activity controller before choosing a
   destination, then share again.
   - Expected: cancellation dismisses cleanly, no stale activity blocks the next
     attempt, that attempt's temporary package/media is cleaned after the
     controller is released, and the next Save to Files/AirDrop handoff
     succeeds.
8. Review the fixed-build logs.
   - Expected: no manual-provider representation error; lifecycle logs identify
     one preparation, one system presentation, and one controller-owned terminal
     cleanup for each attempt, with no terminal
     `tap_share_temp_cleanup_failed` result. LaunchServices `Code=-54` alone is
     diagnostic context, not a pass or fail verdict.

## Verdict rules

- **Pass:** every expected result above is observed for both ordinary media and
  `.tapnap`; Save to Files and AirDrop produce inspectable artifacts; and the
  owner explicitly accepts the fixed build.
- **Fail:** the Files picker dismisses unexpectedly, AirDrop remains waiting,
  either destination produces no artifact or unreadable bytes, a later share is
  blocked by stale lifecycle state, or the open-in-place provider error recurs.
- **Blocked:** a device/OS/AirDrop availability problem prevents an action and
  is documented separately from an app failure. Build/install/launch alone is
  not a pass.

## Attended result matrix

The owner answered **“验收通过”** to a confirmation question that enumerated
these four paths and required every saved or received artifact to open. No
filename, size, hash, receiving-device identity, or additional log evidence was
supplied, so none is inferred here.

| Share artifact | Destination | Result | Openability |
| --- | --- | --- | --- |
| Ordinary image | Save to Files | **Pass** | **Pass** |
| Ordinary image | AirDrop | **Pass** | **Pass** |
| `.tapnap` package | Save to Files | **Pass** | **Pass** |
| `.tapnap` package | AirDrop | **Pass** | **Pass** |

## Evidence

- Transport checkpoint: the containing commit, subject **“Checkpoint working
  Share transport before lifecycle repair”**, on
  `codex/tap-share-system-handoff-recovery`. Candidate `35745be` failed
  attended behavior. A lifecycle-fixed commit/build remains `Pending`.
- Automated build: generic iPhoneOS `build-for-testing` passed. Tests compiled
  but were not run.
- Sending device/iOS: `iPhone 15 Pro (iPhone16,1), iOS 26.6`; attended actions
  were installed and performed by the owner; Codex did not install, launch, or
  debug the device.
- Receiving device/OS: successful reception confirmed; model and OS `Pending`.
- Save to Files result: ordinary image **Pass**; `.tapnap` **Pass**; both open.
  Filenames, sizes, and hashes: `Pending`.
- AirDrop result: ordinary image **Pass**; `.tapnap` **Pass**; both received and
  open. Receiving-device identity, filenames, sizes, and hashes: `Pending`.
- Relevant runtime log: ordinary image and `.tapnap` both reached the system
  sheet. The `.tapnap` attempt recorded `activity_sheet_dismissed`, but no
  subsequent `activity_controller_dismantled` or terminal
  `tap_share_temp_cleanup_finished scope=artifactLease` before the next Share
  attempt. Its controller reported `under50ms`, then the app revealed feedback
  attributed to `over50ms phase=controllerConstruction`; that attribution and
  the forced minimum visibility remain lifecycle/performance gaps.
- Human confirmation: **Pass** — owner replied **“验收通过”** to the explicit
  four-path matrix and artifact-openability confirmation.

The attended transport matrix is complete and frozen by the containing
checkpoint commit. Source ownership between controller construction and the
coordinator's later handoff, prompt controller teardown, terminal temporary-file
cleanup, corrected progress attribution, focused tests, and a lifecycle-fixed
device build remain before this record can leave `In progress`.
