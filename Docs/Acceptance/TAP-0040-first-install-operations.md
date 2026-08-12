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

## Preconditions

- The candidate build contains the explicit-action and bounded Network retry
  fixes and can log, with public-safe timestamps: setup appearance, button tap,
  each permission request, each Network attempt/interval/timeout, PhotoKit
  observer/fetch/backfill/write, and camera warmup.
- The device can return Camera, Photos, Location, and Microphone to
  `.notDetermined` and can be taken offline.
- Screen recording and device-log capture are ready before process launch.
- **Owner live:** approve deleting the test app. If reinstall does not restore
  `.notDetermined`, separately approve any system-level privacy reset.

## Reset And Install

1. Archive earlier logs; do not delete existing Photos media.
2. Delete the test app and install the frozen signed build.
3. Confirm all four OS permission states are `.notDetermined`; otherwise stop
   as Blocked.
4. Begin screen recording and logs before first launch.
5. Run one offline round and one new clean-install optional-skip round.

## Procedure And Expected Results

1. **Owner live:** launch and leave the page untouched for at least 10 seconds.
   No system prompt, Network attempt, observer, protected fetch/write, or camera
   warmup may occur.
2. Background and foreground the app without tapping. Only passive status
   refresh is allowed.
3. With the device offline, tap the Network action once. One bounded sequence
   may perform policy-timed automatic attempts and must end at its total timeout.
4. After timeout, background/foreground, wait at least one retry interval, then
   restore the network without tapping Retry. Displayed state may refresh, but
   no new Network sequence may start.
5. **Owner live:** tap Network Retry. Exactly one new bounded sequence starts and
   succeeds.
6. **Owner live:** tap Camera, Photos, Location, and Microphone Allow one at a
   time, resolving each system prompt before the next tap. Each tap must map to
   exactly its own request and must not start another row.
7. Delete/reinstall again. After the untouched and background/foreground checks,
   complete Network, Camera, and Photos; use Skip for Location and Microphone.
   Neither Skip may show a system prompt.
8. **Owner live:** confirm Continue is enabled after the three required rows and
   that the two optional rows remain skippable. Do not press Continue in this
   procedure; readiness belongs to `TAP-0041`.

## Required Evidence

- Continuous recordings of both clean-install rounds, including system prompt
  titles and actions.
- Timestamped action/request/Network timeline plus negative evidence for early
  PhotoKit work and camera warmup.
- OS authorization screenshots before both rounds.
- Network attempt table covering start, automatic retries, timeout,
  background/foreground, connectivity recovery, and manual Retry.
- Frozen build/commit, device, and iOS identifiers.
- **Owner live:** recorded confirmation that there were no surprise prompts and
  every operation followed its corresponding action.

## Verdict

- **Pass:** every step completes, all trigger boundaries hold, and the owner
  accepts both first-install flows.
- **Fail:** any appearance/refresh/lifecycle/background path starts an operation;
  a row starts another row; post-timeout Network restarts without Retry; an
  optional Skip requests permission; or evidence cannot prove hidden work stayed
  inactive.
- **Blocked:** permissions cannot be reset; network conditions cannot be
  controlled; logging is insufficient; or required deletion/privacy-reset
  approval is absent.
