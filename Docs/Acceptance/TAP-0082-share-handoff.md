# TAP-0082 — TAP Share system handoff acceptance

- Status: `Pending fixed-build device retest`
- Related implementation: `TAP-0081`
- Product Contract: §5.3, §8
- Updated: `2026-08-14`

## Regression record

On a current physical-device build, choosing **Save to Files** made the system
destination picker flash and dismiss with an invalid-argument error. Choosing
**AirDrop** remained at **Waiting** and produced no received artifact. The
captured log repeatedly included:

```text
Could not load representation public.zip-archive from the item provider for opening in place
```

The typed provider had registered an app-private, per-attempt temporary file
with the `openInPlace` option. Files and AirDrop are out-of-process consumers;
they must receive a transport-owned copy. LaunchServices `Code=-54` database
mapping messages may accompany the system share flow, but they are not by
themselves the product failure or a reason to add a private entitlement.

The approved repair preserves the explicit `.tapnap` type and ZIP fallback,
uses the default copy-backed `NSItemProvider` file representation, and retains
the source artifact until the provider copy and activity lifecycle finish. A
bare-URL-only handoff is not an accepted fallback.

## Fixed-build prerequisites

- [x] Record the exact implementation commit and device build configuration:
      `35745be` (`Fix TAPNAP system share transport`), Debug iphoneos build.
- [ ] Install the fixed build on the sending device without reusing the old
      `bf20b52` acceptance result.
- [x] Record sending device model and iOS version.
- [ ] Prepare a reachable receiving Apple device and record its model and OS.
- [ ] Confirm Files is available on the sender and AirDrop is enabled on both
      devices.
- [ ] Use a signed still or Live Photo whose TAPNAP Package row is available.
- [ ] Keep device logs available and choose a destination where the received
      artifact can be inspected and hashed.

## Attended procedure

1. Launch the fixed build, open TAP Library, enter the selected Viewer, open TAP
   Share, and choose **TAPNAP Package**.
   - Expected: app-owned preparation reaches ready and presents exactly one
     system activity controller.
2. Choose **Save to Files**.
   - Expected: the Files destination picker remains presented; it must not flash
     and dismiss or report an invalid argument.
3. Choose a directory and save.
   - Expected: `TAPNAP-Capture.tapnap` is present, non-empty, and can be opened
     as the expected ZIP-backed package.
4. Start a new share attempt for the same media and choose **AirDrop** to the
   prepared receiving device.
   - Expected: transfer advances beyond Waiting, the receiver can accept it,
     and a received `TAPNAP-Capture.tapnap` artifact is available.
5. Compare the saved and received artifacts.
   - Expected: each artifact has the intended filename/type, is non-empty,
     opens as a TAPNAP package, and passes the same package-structure checks as
     the generated artifact. Record both hashes; do not assume two independently
     generated attempts must have the same archive hash. Automated provider-load
     tests separately prove that each typed representation copies the source
     bytes without mutation.
6. Repeat once, cancelling the system activity controller before choosing a
   destination, then share again.
   - Expected: cancellation dismisses cleanly, no stale activity blocks the next
     attempt, and the next Save to Files/AirDrop handoff succeeds.
7. Review the fixed-build logs.
   - Expected: no `Could not load representation ... for opening in place`
     error for the `.tapnap` provider; lifecycle logs identify one preparation,
     one system presentation, and one
     `tap_share_temp_cleanup_finished` terminal cleanup for each attempt, with
     no terminal `tap_share_temp_cleanup_failed` result.

## Verdict rules

- **Pass:** every expected result above is observed; Save to Files produces an
  inspectable artifact; AirDrop produces an inspectable received artifact; and
  the owner explicitly accepts the fixed build.
- **Fail:** the Files picker dismisses unexpectedly, AirDrop remains waiting,
  either destination produces no artifact or unreadable bytes, a later share is
  blocked by stale lifecycle state, or the open-in-place provider error recurs.
- **Blocked:** a device/OS/AirDrop availability problem prevents an action and
  is documented separately from an app failure. Build/install/launch alone is
  not a pass.

## Evidence

- Fixed commit/build: `35745be`; signed Debug iphoneos build succeeded. The
  owner will install this candidate directly from Xcode; no successful
  tool-driven install or launch is claimed.
- Sending device/iOS: `iPhone 15 Pro (iPhone16,1), iOS 26.6`; attended actions
  remain Pending after the owner requested that Codex stop device installation,
  launch, and debugging operations.
- Receiving device/OS: `Pending`
- Save to Files result and artifact hash: `Pending`
- AirDrop result, received artifact, and hash: `Pending`
- Relevant logs/screenshots: `Pending`
- Human confirmation: `Pending`

The interrupted Codex installation attempt and the transient AirDrop
“未找到用户” state observed while Xcode/LLDB still held the replaced process are
excluded from the verdict. The next valid evidence starts after the owner has
installed `35745be` independently and supplies the resulting Console log.
