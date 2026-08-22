# TAP-0082 — TAP Share system handoff acceptance

- Status: `Completed — four-path transport and integrated r3 lifecycle accepted;
  explicit evidence exceptions retained below`
- Related implementation: `TAP-0081`
- Product Contract: §5.3, §8
- Updated: `2026-08-14`


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
   - Expected: selecting the format keeps the option list mounted and changes
     only that row's existing subtitle slot from text to a thin determinate
     preparation track. The title, icon, badge, row, popover, and sibling frames
     do not move; no percentage or Cancel control appears. Other rows stay
     visible but disabled. Payload readiness closes the app popover with no
     separate preparation/ready page and presents exactly one system activity
     controller.
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
     attempt, that attempt's temporary package/media is cleaned after the exact
     system-sheet binding ends even if UIKit retains its controller, and the
     next Save to Files/AirDrop handoff succeeds.
8. Review the fixed-build logs.
   - Expected: no manual-provider representation error; lifecycle logs identify
     one preparation, one system presentation, and one exact-attempt terminal
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
  attended behavior. A lifecycle-fixed commit and attended device build remain
  `Pending`.
- Automated build: the current uncommitted lifecycle/UI candidate passed both
  generic iOS Simulator and generic iPhoneOS `build-for-testing` without
  launching Simulator. Tests compiled but were not run.
- Sending device/iOS: `iPhone 15 Pro (iPhone16,1), iOS 26.6`; attended actions
  were installed and performed by the owner; Codex did not install, launch, or
  debug the device.
- Receiving device/OS: successful reception confirmed; model and OS `Pending`.
- Save to Files result: ordinary image **Pass**; `.tapnap` **Pass**; both open.
  Filenames, sizes, and hashes: `Pending`.
- AirDrop result: ordinary image **Pass**; `.tapnap` **Pass**; both received and
  open. Receiving-device identity, filenames, sizes, and hashes: `Pending`.
- Historical pre-repair runtime log: ordinary image and `.tapnap` both reached the system
  sheet. The `.tapnap` attempt recorded `activity_sheet_dismissed`, but no
  subsequent `activity_controller_dismantled` or terminal
  `tap_share_temp_cleanup_finished scope=artifactLease` before the next Share
  attempt. Its controller reported `under50ms`, then the app revealed feedback
  attributed to `over50ms phase=controllerConstruction`; that attribution and
  the forced minimum visibility remain lifecycle/performance gaps.
- Human confirmation: **Pass** — owner replied **“验收通过”** to the explicit
  four-path matrix and artifact-openability confirmation.

The attended transport matrix is complete. The later r3 implementation moves
controller construction to the real post-popover system-sheet boundary and
makes exact sheet end schedule off-main attempt cleanup. The current owner-
supplied device log records one complete `.tapnap` attempt through system-sheet
appearance, dismissal, controller release, and final artifact cleanup. The
owner subsequently directed the current Share task to be treated as complete;
the evidence that was not collected is preserved explicitly below rather than
inferred.


## Final lifecycle evidence and accepted exceptions

The owner's final console sample records this exact `.tapnap` sequence:

1. `tap_share_temp_cleanup_finished scope=tapnapResources` removes the
   intermediate packaging resources.
2. `tap_share_payload_ready` is followed by handoff and one direct-file-URL
   activity-controller construction, reported as `under50ms`.
3. LaunchServices, CKShare/SWY, and FileProvider probes occur before
   `tap_share_activity_sheet_appeared`; they do not prevent the system sheet
   from appearing and do not authorize private entitlements or a return to the
   failed manual item-provider transport.
4. `tap_share_activity_sheet_dismissed` is followed by
   `tap_share_activity_controller_released` and
   `tap_share_temp_cleanup_finished scope=artifactLease`, proving the final
   temporary directory is absent at the end of that attempt.

The owner explicitly directed closure with “当前任务我觉得可以视为标记为完成”.
That decision accepts these disclosed evidence exceptions:

- focused XCTest targets compiled successfully but were not executed for the
  final r3 candidate;
- the final console sample independently proves one `.tapnap` lifecycle, not a
  second direct-image lifecycle or a controlled stale-attempt-A/new-attempt-B
  sequence;
- controller release precedes final cleanup in this sample, so the log does
  not independently prove cleanup timing when UIKit retains the controller;
- receiving-device identity, filenames, sizes, and hashes remain unrecorded.

None of those uncollected facts is presented as observed. The earlier explicit
four-path owner verdict remains the transport evidence for ordinary image and
`.tapnap` through Save to Files and AirDrop. The final r3 log and owner verdict
supply the integrated presentation/cleanup acceptance used for closure.

The selected-row 2px determinate track represents only app-owned payload
preparation. Payload readiness closes the popover immediately; TAPCam does not
hold a false 99% state, restore the removed 400ms delay, or claim it can predict
when the system-owned activity sheet is ready. Cold-install/update resource
initialization and the observed 7.795-second first Library catalog load remain
separate open work under TAP-0009/TAP-0083 and are not absorbed by this Share
acceptance.
