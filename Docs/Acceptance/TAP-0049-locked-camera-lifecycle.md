# TAP-0049 — Lifecycle-Correct Locked Camera Experiment

- Status: `Draft — Blocked until TAP-0013 is ready`
- Related Delivery: `TAP-0013`
- Product Contract: `ProductContract §4`; `§8`
- Experiment Branch: `Dedicated branch required; to be recorded`
- Build/Commit: `To be frozen after TAP-0013 handoff`
- Device/iOS: `To be confirmed with the product owner`
- Soak Duration/Repetitions: `Owner decision required before execution`
- Import Observation Window: `Owner decision required before execution`
- Date: `Unscheduled`
- Operator: `Unassigned`
- Human Confirmation: `Pending`

This is the promotion evidence draft for a new lifecycle-correct experiment,
not an acceptance run for the existing POC. The old E1–E7 branches, routes,
timings, log results, and smoke counts are historical diagnostic input only.
They do not define the candidate, its baseline, its soak duration, or a passing
result.

Execution remains Blocked until `TAP-0013` delivers a candidate on a dedicated
experiment branch. Passing this procedure still does not make Locked Camera a
production capability; production promotion requires a separate owner decision.

## Preconditions

- The Board Steward has recorded a `TAP-0013` handoff with the dedicated
  experiment branch, frozen commit/build, bounded scope, tests, and remaining
  gaps. A main-tree historical E-series build is not eligible.
- The candidate uses only APIs exposed in the installed SDK's public Swift
  interfaces and public documentation. It does not dynamically call, link, or
  emulate private or `.tbd`-only transition symbols, including historical
  examples such as `openApplicationAfterTransitionCompletion(for:)`,
  `applicationDidCompleteTransition()`, `urlsToOpen`, or `hasActiveSession`.
- No private/programmatic dismiss mechanism is used. Exit and suspension follow
  the system-supported user or lifecycle path approved for this run.
- The extension owns only locked launch UI, the live camera/depth capture path,
  and writing the declared unsigned capture resource to its session-content
  boundary. It does not request permissions or run App Attest, network, Photos
  export, Live Photo, or Pending Capture Queue work.
- The containing app uses the public Locked Camera manager/update boundary to
  import exposed session content into the existing Pending Capture Queue. The
  exact candidate artifact layout is documented by `TAP-0013`; no old flat-HEIC
  or staging layout is assumed by this procedure.
- Structured, public-safe correlated logs cover control intent, extension scene
  and root, session setup/running/interruption, real first frame, shutter/write,
  suspend/exit, containing-app exposure/import, resource release, and relaunch.
- The owner has approved the physical device/iOS matrix, launch source, exit
  path, soak duration, capture schedule, repetition count, import observation
  window, and any recovery/interruption scenario. This draft inherits none of
  the historical five-minute/three-capture/three-relaunch suggestions.
- **OWNER-LIVE:** approve the branch/build, matrix, destructive install/reset,
  duration/repetitions, and exact system-supported lifecycle actions.

## Reset / Install Procedure

1. Archive old E-series logs separately and label them Historical; do not merge
   them into this candidate's result bundle.
2. Record the candidate branch, commit, build configuration, entitlements,
   public-API inventory, extension dependency audit, device/iOS, available
   storage, initial thermal state, and approved test schedule.
3. Install the frozen signed build using the owner-approved method. Complete any
   required containing-app preparation before locking the device; do not grant
   a new permission from inside the locked extension.
4. Confirm the real system Locked Camera control is available. Directly opening
   a debug view, SwiftUI preview, or Simulator scene is supporting evidence only
   and cannot replace the lock-screen launch.
5. Empty or inventory only the approved candidate test records. Do not delete
   unrelated Photos or Pending Capture Queue data.
6. Start synchronized screen recording plus control-extension, capture-
   extension, and containing-app logs before the first lock-screen action.

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Review the frozen binary/source dependency and API inventory before device execution. | Every Locked Camera call is public for the approved SDK/deployment target; no private, hidden, selector-based, or `.tbd`-only API is present; forbidden extension-side App Attest/network/Photos/queue dependencies are absent. | `Pending` | `Pending` |
| 2 | **OWNER-LIVE:** Lock the device and launch the candidate through the real system Locked Camera control. | Correlated logs show the real control intent, secure-capture scene, persistent root/controller, camera preparation, and a visible non-empty UI. No containing-app UI or debug direct-launch path substitutes for it. | `Pending` | `Pending` |
| 3 | Wait for the candidate's readiness gate without tapping the shutter. | A real preview frame is visibly presented and recorded by the first-frame signal before shutter/primary controls become safe. Session configuration or a placeholder image alone is insufficient; no unexplained black/frozen surface appears. | `Pending` | `Pending` |
| 4 | Capture according to the owner-approved schedule while observing the live surface. | Each shutter action creates one declared unsigned locked capture under the public session-content boundary, reports truthful depth/container facts, gives visible completion/error state, and returns to a responsive live surface. It starts no permission, App Attest, network, Photos, or queue work inside the extension. | `Pending` | `Pending` |
| 5 | Keep the extension live for the owner-approved soak duration and perform the approved capture/idle/interruption schedule. | Preview and controls remain responsive. Any real interruption or missing-frame event becomes an attributable visible recovering/unavailable state rather than a silent black/frozen UI, and follows the candidate's documented public recovery boundary. | `Pending` | `Pending` |
| 6 | Use the pre-approved system/user exit or suspension path. | The extension follows public lifecycle callbacks, releases or relinquishes camera/preview resources as designed, preserves successfully written session content for system migration, and does not use private dismissal or treat app opening as proof migration completed. | `Pending` | `Pending` |
| 7 | Open or resume the containing app only through the path approved for this candidate, without a handoff-time Library poll invented by the acceptance script. | Main camera/navigation remains interactive. The app does not block its first interactive surface while waiting for locked content, and import begins only when the public manager/update boundary exposes content. | `Pending` | `Pending` |
| 8 | Observe the public session-content exposure for the owner-approved window and inspect Pending Capture Queue/TAP Library. | Every valid locked capture is imported idempotently exactly once into the existing Pending Capture Queue and becomes visible as its pending/local TAP Library item. Import failure preserves diagnosable source content; normal later signing/Photos export remains outside the extension and outside this lifecycle pass condition. | `Pending` | `Pending` |
| 9 | Lock the device and relaunch the real Locked Camera control for every owner-approved repetition, including immediately after the prior suspend/import cycle. | Every repetition reaches root UI, a real first frame, and safe controls without first-tap freeze, black screen, stale prior session, duplicate controller/session ownership, or requiring an extra lifecycle round trip. | `Pending` | `Pending` |
| 10 | Capture again after relaunch, exit/suspend, and reopen the containing app. | The second and later cycles retain the same capture, migration, exactly-once import, and responsiveness properties as the first cycle. Previously imported records remain stable and are not duplicated or lost. | `Pending` | `Pending` |
| 11 | Terminate and relaunch the containing app through the approved normal path, then inspect the test records and launch Locked Camera once more. | Imported pending/local items persist once, normal app startup remains responsive, and the next locked launch again presents a real first frame without lifecycle regression. | `Pending` | `Pending` |
| 12 | **OWNER-LIVE:** review the synchronized lifecycle timeline and every recovery/import result. | The owner can correlate each physical action to one control, extension, content, import, and relaunch sequence and explicitly accepts or rejects the candidate. | `Pending` | `Pending` |

## Required Evidence

- Logs: one synchronized public-safe timeline for control intent, scene/root,
  session start/interruption/stop, first real frame, shutter/write, lifecycle
  transition, manager content update, import/duplicate decision, Pending Capture
  Queue visibility, resource release, and every relaunch.
- Screenshots/recording: continuous attended device recording covering lock-
  screen launch, first real frame, capture, complete soak, recovery if invoked,
  system-supported exit/suspend, main-app import visibility, and relaunches.
- Output artifacts: candidate public-API/dependency audit; declared unsigned
  session-content inventory; corresponding imported pending records; container,
  manifest/depth/proof-slot facts required by the candidate contract; and an
  exactly-once capture-to-record reconciliation table.
- Result bundles: branch/build/commit, entitlements, device/iOS, approved
  schedule and observation window, crash/spindump or symbolicated diagnostics
  for any stall, and focused automated tests used only as supporting evidence.
- **OWNER-LIVE:** written confirmation of first-frame visibility, control
  responsiveness, soak, capture, lifecycle exit, import, every relaunch, and
  the separation of historical E-series evidence from this result.

## Verdict Conditions

- **Pass:** the new `TAP-0013` candidate completes the owner-approved matrix,
  repetitions, soak, and observation window using public API only; every launch
  reaches a real first frame and safe controls; captures remain truthful;
  suspend/exit/relaunch never freezes or blacks out; content imports exactly
  once through the containing app; forbidden extension work is absent; and the
  owner accepts the result.
- **Fail:** any eligible run has an unexplained black/frozen/empty root, no real
  first frame, unsafe shutter, capture loss/corruption, private API, extension-
  side permission/App Attest/network/Photos/queue work, unresponsive system
  exit, next-launch freeze, dependency on an extra lifecycle round trip,
  duplicate/lost import, or no import within the approved observation window.
- **Blocked:** `TAP-0013` has no ready dedicated-branch candidate; only an old
  E-series build is available; the public API/dependency audit is incomplete;
  device/iOS, duration, repetition, exit path, or observation window is
  unapproved; the real lock-screen control/log chain is unavailable; the owner
  cannot attend; or diagnostics cannot distinguish candidate failure from an
  invalid test environment.

## Human Confirmation

`Pending — OWNER-LIVE attended execution and a separate promotion decision are required`
