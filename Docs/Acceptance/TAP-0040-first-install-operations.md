# TAP-0040 — First-Install Explicit Operations

- Status: `Draft — not executed`
- Related Delivery: `TAP-0008`, `TAP-0010`
- Contract: `ProductContract §2.1–2.3`
- Build/Commit: `To be frozen before execution`
- Device/iOS: `To be confirmed with the product owner`
- Human Confirmation: `Pending`

This is an attended physical-device procedure. Before execution, the Agent must
present the filled build, device, reset method, logging surface, and full scope
to the product owner. Simulator permission fixtures are not a substitute.

The 2026-08-15 `fix0809` native candidate implements the non-Network
permission/recovery and observer boundaries in this procedure. It deliberately
keeps `/healthz` and App Attest behavior frozen, so this record remains Draft
and cannot receive a Pass verdict from that candidate alone.

The branch-executable subset is limited to Camera/Photos row ownership,
denied/restricted recovery, Required Permission Check targeted refresh, and the
PhotoKit observer/catalog activation boundary. Steps that require initial App
Attest registration, `/healthz` replacement, or retry delivery remain blocked;
their current behavior must not be counted as target acceptance.

## Preconditions

- The candidate build contains the explicit-action and bounded Network retry
  fixes and can log, with public-safe timestamps: setup appearance, button tap,
  each permission request, each first-install App Attest
  challenge/registration/verification attempt and timeout, PhotoKit
  observer/fetch/backfill/write, and camera warmup. Logs do not expose
  credential material or key identifiers.
- The device can return Camera, Photos, Location, and Microphone to
  `.notDetermined` and can be taken offline.
- Screen recording and device-log capture are ready before process launch.
- **Owner live:** approve a Delete-and-Reinstall of the test app. If that reset
  does not restore `.notDetermined`, separately approve any system-level
  privacy reset.

## Reset And Install

1. Archive earlier logs; do not delete existing Photos media.
2. Perform Delete-and-Reinstall with the frozen signed build.
3. Confirm all four OS permission states are `.notDetermined`; otherwise stop
   as Blocked.
4. Begin screen recording and logs before the first Foreground Process Launch.
5. Run one offline Delete-and-Reinstall round and one separately reset
   Delete-and-Reinstall optional-skip round.

## Procedure And Expected Results

1. **Owner live:** launch and leave the page untouched for at least 10 seconds.
   No system prompt, Network attempt, observer, protected fetch/write, or camera
   warmup may occur.
2. Background and foreground the app without tapping. Only passive status
   refresh is allowed.
3. With the device offline, tap the Network action once. One bounded sequence
   may attempt initial App Attest work with policy-timed automatic retries and
   must end at its total timeout. A generic `/healthz` success is not the row's
   completion condition.
4. After timeout, background/foreground, wait at least one retry interval, then
   restore the network without tapping Retry. Displayed state may refresh, but
   no new Network sequence may start.
5. **Owner live:** tap Network Retry. Exactly one new bounded sequence starts;
   the row succeeds only after initial App Attest registration/verification is
   complete.
6. **Owner live:** tap Camera, Photos, Location, and Microphone Allow one at a
   time, resolving each system prompt before the next tap. Each tap must map to
   exactly its own request and must not start another row.
7. Perform Delete-and-Reinstall again. After the untouched and
   background/foreground checks,
   complete Network, Camera, and Photos; use Skip for Location and Microphone.
   Neither Skip may show a system prompt.
8. **Owner live:** confirm Continue is enabled only after App Attest, Camera,
   and Photos are complete and that the two optional rows remain skippable. Do
   not press Continue in this procedure; readiness belongs to `TAP-0041`.
9. In separate reset rounds, deny Camera, Photos, Location, and Microphone one
   row at a time. Confirm each denied row owns its **Open Settings** recovery;
   a restricted fixture shows stable restricted guidance and does not promise
   a Settings recovery that the system policy cannot provide.
10. After Setup has completed, revoke Camera and then Photos. On each launch or
    foreground return, confirm the root enters Required Permission Check with
    only Camera and Photos represented and with no Continue button.
11. Recover the affected required permission from its row/system boundary.
    Confirm the targeted return refresh does not start Network, Location, or
    Microphone work and automatically re-evaluates the route.
12. For Photos, correlate observer registration and catalog logs: no observer
    or catalog scan before the explicit eligible boundary; exactly one
    idempotent observer activation afterward; revocation/deactivation cancels
    queued catalog refresh work.

## Required Evidence

- Continuous recordings of both Delete-and-Reinstall rounds, including system prompt
  titles and actions.
- Timestamped action/request/Network timeline plus negative evidence for early
  PhotoKit work and camera warmup.
- OS authorization screenshots before both rounds.
- App Attest attempt table covering explicit start, bounded automatic retries,
  timeout, background/foreground, connectivity recovery, manual Retry, and
  final registration/verification success without private credential values.
- Frozen build/commit, device, and iOS identifiers.
- **Owner live:** recorded confirmation that there were no surprise prompts and
  every operation followed its corresponding action.

This procedure proves explicit trigger boundaries. It does not close Launch
Screen-to-first-frame timing; that requires the `TAP-0083` 2 × 2
Debug/Release-by-debugger device matrix with `t0/t1` instrumentation.

## Verdict

- **Pass:** every step completes, all trigger boundaries hold, and the owner
  accepts both first-install flows.
- **Fail:** any appearance/refresh/lifecycle/background path starts an operation;
  a row starts another row; post-timeout Network restarts without Retry; an
  optional Skip requests permission; Network is marked complete by reachability
  without App Attest completion; or evidence cannot prove hidden work stayed
  inactive.
- **Blocked:** permissions cannot be reset; network conditions cannot be
  controlled; logging is insufficient; or required deletion/privacy-reset
  approval is absent.
