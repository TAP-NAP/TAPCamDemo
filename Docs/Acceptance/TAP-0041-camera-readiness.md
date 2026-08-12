# TAP-0041 — First Camera-Interactive Readiness

- Status: `Draft — not executed`
- Related Delivery: `TAP-0009`
- Contract: `ProductContract §2.4–2.5`
- Build/Commit: `To be frozen before execution`
- Device/iOS: `To be confirmed with the product owner`
- Human Confirmation: `Pending`

This attended procedure proves the ordering that prevents early camera entry
and freezes. The Agent must first agree with the owner on a safe method for
delaying or failing readiness; an unreviewed fault injection is not allowed.

## Preconditions

- `TAP-0040` has passed for the same setup behavior, or the same boundary has
  been reconfirmed for this build.
- The build logs required rows complete, Continue, capture graph/path ready,
  real first preview frame presented, controls/shutter safe, haptics prepared,
  completion-marker write, App Attest warmup, and Pending Capture Queue retry.
- A reviewed readiness delay/failure method and marker inspection are available.
- **Owner live:** the owner can observe the real frame, controls, shutter, and
  haptic response.

## Reset And Install

1. Delete and reinstall the frozen build; confirm setup is incomplete.
2. Complete Network, Camera, and Photos; optionally skip Location/Microphone.
3. Start continuous recording and logs before pressing Continue.
4. Reserve a second clean install for interruption/failure recovery.

## Procedure And Expected Results

1. **Owner live:** verify that required rows completing does not leave setup.
2. Tap Continue. A readiness surface remains while the graph/path, real first
   preview frame, safe shutter/primary controls, and haptics become ready.
3. Try shutter and primary controls during readiness. Inputs must be safely
   blocked and must not start capture or an unsafe state transition.
4. Record the exact event order. The completion marker and readiness dismissal
   must occur only after every readiness condition, not after session
   configuration alone.
5. **Owner live:** immediately after dismissal, capture once and operate a FOV
   plus a primary mode/control. Confirm a real frame, normal haptic, no freeze,
   black screen, or unresponsive control.
6. On the second clean install, use the approved method to terminate before the
   first frame or produce a readiness failure. Relaunch: the marker must be
   absent and setup/readiness recovery must remain visible.
7. Exercise Retry and, when the failure is permission-related, Open Settings.
8. Complete readiness, cold-launch again, and confirm setup is silently skipped.
9. Revoke Photos, cold-launch, then separately revoke Camera and cold-launch.
   Neither change may reopen onboarding; the affected feature handles it.
10. After Network preflight succeeds but before Continue, disconnect the
    network. **Owner live:** confirm App Attest warmup/queue retry can fail or
    wait without delaying first-frame camera entry.

## Required Evidence

- Continuous Continue-to-first-capture recording and event timeline.
- Marker-write timestamp relative to graph, first frame, controls, and haptics.
- Interruption/failure relaunch evidence and marker inspection.
- Successful first capture/control artifact and logs after readiness.
- Cold-launch recordings after Photos and Camera revocation.
- Offline App Attest/queue logs showing camera readiness remains independent.
- **Owner live:** confirmation of real preview, haptic, safe controls, and no
  freeze.

## Verdict

- **Pass:** all readiness events precede marker/entry; interruption cannot leave
  a false marker; later permission changes remain contextual; the owner accepts
  the first interaction.
- **Fail:** the marker is early; a fake/black/frozen preview appears; shutter or
  controls are unsafe; background credential work blocks entry; or permission
  changes reopen setup.
- **Blocked:** first-frame/marker ordering is not observable; no approved
  readiness failure method exists; the device lacks camera/haptic capability;
  or the owner cannot attend.
