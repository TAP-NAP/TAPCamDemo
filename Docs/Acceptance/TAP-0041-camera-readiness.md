# TAP-0041 — First Camera-Interactive Readiness

- Status: `Draft — bounded fix0809 device path accepted; full matrix open`
- Related Delivery: `TAP-0009`, `TAP-0010`, `TAP-0015`, `TAP-0090`
- Contract: `ProductContract §2.4–2.6`; `StartupLifecycleContract`
- Build/Commit: `fix0809 candidate; this commit`
- Device/iOS: `Owner-attended physical device; exact identifiers not recorded in this evidence`
- Human Confirmation: `Accepted 2026-08-15 for the bounded fix0809 non-Network executed path; full procedure pending`

This attended procedure proves the ordering that prevents early camera entry
and an unresponsive startup. The Agent must first agree with the owner on a
safe method for delaying or failing readiness; an unreviewed fault injection is
not allowed.

The 2026-08-15 `fix0809` native candidate contains the independent marker,
camera-plus-catalog gate, stable Resource Initialization surface, and local
poster/recent-cover release needed for this procedure. The owner exercised and
accepted that bounded lifecycle path on a physical device. Post-Setup App
Attest and credential/network-dependent Pending scheduling were not migrated
and remain owned by `TAP-0015`, so the complete deferred-release target is not
implemented by this candidate.

For this branch, only the non-Network candidate subset is executable: validate
Camera/Photos → Initialization routing with an existing compatible Setup fact;
exercise the two readiness groups, marker interruption/invalidation, committed
Viewfinder-frame barrier, local poster/recent-cover release, and permission
recovery. Canonical credential-bound Setup receipt creation and the App Attest/
Pending children of deferred release remain blocked on `TAP-0010` and
`TAP-0015`. The bounded device acceptance recorded below does not assign this
full procedure a `Pass` verdict or substitute for its unexecuted scenario
matrix. `TAP-0090` owns the non-Network structured ordering assertions reused by
this attended procedure.

## 2026-08-15 Bounded Device Observation

The owner ran the current `fix0809` working tree on a physical device, supplied
the resulting lifecycle log, and accepted the experienced non-Network startup
flow. The log records the usable TAP Library catalog publication before the
camera readiness group, followed by initialization-marker commit and then the
local recent-cover refresh release. The owner also exercised the resulting
Viewfinder/Library experience without reporting an early marker, black or
stalled preview, or unsafe first interaction.

This observation covers only the executed path. It does not cover the second
interruption round, readiness fault injection, Camera/Photos revocation and
recovery, In-place App Update, restore/migration, exact marker-file inspection,
or instrumented physical timing. Canonical credential-bound `S`, Network, and
the App Attest/Pending children of `W11/W12` remain outside the accepted
candidate scope under `TAP-0010`/`TAP-0015`.

## Preconditions

- `TAP-0040` has passed for the same setup behavior, or the same boundary has
  been reconfirmed for this build.
- The build logs required rows complete, Continue, separate Setup-receipt write,
  capture graph/path ready, real first preview frame presented,
  controls/shutter safe, haptics prepared, first usable Library catalog
  metadata snapshot, initialization-marker write, Viewfinder entry, deferred
  App Attest health/recovery, and Pending Capture Queue retry.
- A reviewed readiness delay/failure method and marker inspection are available.
- The `TAP-0090` public-safe versioned JSON/JSONL trace schema and assertion
  report are available for the non-Network ordering consumed here.
- **Owner live:** the owner can observe the real frame, controls, shutter, and
  haptic response.

## Reset And Install

1. Perform Delete-and-Reinstall with the pinned build; confirm setup is
   incomplete.
2. Complete the Network row's first-install App Attest bootstrap; then authorize
   Camera and Photos; optionally skip Location/Microphone.
3. Start the structured device log before pressing Continue. Do not start or
   retain a photo, screenshot, or screen recording as proof.
4. Reserve a second Delete-and-Reinstall round for interruption/failure
   recovery.

## Procedure And Expected Results

1. **Owner live:** verify that required rows completing does not leave setup.
2. Tap Continue. Confirm the Setup receipt is written, then a Resource
   Initialization surface remains while both readiness groups progress:
   camera graph/path, real first preview frame, safe shutter/primary controls,
   and haptics; plus the first usable Library identity/order metadata snapshot.
3. Try shutter and primary controls during readiness. Inputs must be safely
   blocked and must not start capture or an unsafe state transition.
4. Record the exact event order. The versioned initialization marker and
   Viewfinder transition must occur only after every camera condition and the
   Library snapshot, not after session configuration or either group alone.
   Inspect the marker as one Application Support JSON value and verify its
   bundle, version, build, initialization schema, installation generation, and
   local device-generation fields.
5. **Owner live:** immediately after dismissal, capture once and operate a FOV
   plus a primary mode/control. Confirm a real frame, normal haptic, no UI stall,
   black screen, or unresponsive control.
6. On the second Delete-and-Reinstall round, use the approved method to terminate after
   Continue but before both readiness groups complete. Relaunch: the Setup
   receipt remains valid, the initialization marker remains absent/stale, and
   Resource Initialization returns without replaying Setup.
7. Delay each readiness group separately. Confirm the stable Resource
   Initialization page exposes no product Failed, Retry, timeout, skip, or
   degraded-entry action; bounded diagnostics identify the incomplete group.
8. Complete readiness, perform another Foreground Process Launch with a Cold
   Resource Path, and confirm both Setup and Resource Initialization are
   silently skipped when their independent facts are valid.
9. Revoke Photos, perform a Foreground Process Launch, restore it through
   Required Permission Check,
   then repeat for Camera. Neither change may replay Setup. The permission page
   must automatically re-evaluate to Resource Initialization when its marker is
   stale or Viewfinder when it is current.
10. Perform an owner-approved In-place App Update with the Setup receipt
    retained and the initialization marker stale. Start offline. **Owner live:**
    confirm Resource Initialization and first interactive camera entry do not
    wait for later App Attest health/recovery or Pending Capture Queue work. A
    Development Replacement Install is separate diagnostic evidence and does
    not substitute for this update scenario unless it is recorded explicitly.

## Required Evidence

- A structured Continue-to-first-interaction event timeline with monotonic
  ordering and automated assertions.
- Setup-receipt and initialization-marker timestamps relative to Continue,
  graph readiness, first real preview, safe controls/haptics, and Library
  catalog publication.
- Structured interruption/relaunch events plus a public-safe textual marker
  inspection containing only schema/runtime/install/device-generation status,
  never credential material.
- A capture-success event and control/haptic interaction events after readiness;
  no captured image is retained as proof.
- Foreground Process Launch logs after Photos and Camera revocation, including
  Required Permission Check and automatic post-recovery routing.
- Offline App Attest/queue scheduling logs showing camera readiness remains
  independent. A deliberately rejected Debug attestation is not a lifecycle
  failure verdict; only its scheduling position is relevant here.
- Automated assertions for the required ordering and prohibited-early-work
  conditions.
- The machine-readable `TAP-0090` assertion report, with each result mapped to
  its stable TAP-0087 lifecycle/workload record ID.
- **Owner live:** a retained textual verdict confirming the real preview,
  haptic, safe controls, and absence of a UI stall.

Do not save a photo, screenshot, or screen recording as acceptance proof. The
structured logs, automated assertions, and owner-live textual verdict are the
durable evidence for this procedure.

This procedure begins before Continue and proves readiness ordering, but it does
not measure `Δt0–t1` or close a Launch Screen timing threshold. `TAP-0083`
owns the same-device 2 × 2 Debug/Release-by-debugger launch comparison.

## Verdict

- **Pass:** both readiness groups precede marker/entry; interruption cannot
  leave a false marker; later Camera/Photos changes use Required Permission
  Check without replaying Setup; the owner accepts the first interaction.
- **Fail:** the marker is early; a fake, black, or stalled preview appears; shutter or
  controls are unsafe; background credential work blocks entry; or permission
  changes reopen setup.
- **Blocked:** first-frame/marker ordering is not observable; no approved
  readiness failure method exists; the device lacks camera/haptic capability;
  or the owner cannot attend.
