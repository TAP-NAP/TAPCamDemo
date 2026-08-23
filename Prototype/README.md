# TAPCam Interactive Visual Contract

This directory is the lightweight, statically served prototype foundation for
`TAP-0006`. Its current vertical slices are the TAP Share flow owned by
`TAP-0081`, the first-install setup flow owned by `TAP-0008`, and the separate
resource-initialization flow owned by `TAP-0009`.
It is intentionally plain HTML, CSS, and JavaScript: no backend, package manager,
framework runtime, production hosting configuration, or persistent cache is
required.

## Run

From the repository root:

```sh
python3 -m http.server 4173 --directory Prototype
```

Then open:

- `http://127.0.0.1:4173/startup-lifecycle.html` for the active
  `TAP-0087-r1-candidate` workbench.

The independent historical composition remains available at
`http://127.0.0.1:4173/` for its own TAP-0008/TAP-0009/TAP-0081 records, but it
is not a second top-level entry, switch, or navigation target inside the
TAP-0087 workbench. The workbench uses one combined UI page directory.

## Review TAP-0087-r1-candidate

This is the P0 prototype/analysis prerequisite for TAP-0008, TAP-0009, and
TAP-0083. It does not revise native SwiftUI, restore Locked Camera, add AirDrop
or system-Share simulation, or apply an old stash. Photo Viewer presents the
owner-approved TAP-0081 Share slice locally in the same page; it performs no
URL/resume/session round trip and does not import Share behavior, events,
workloads, timing, or markers into TAP-0087/TAP-0008/TAP-0009. Existing
TAP-0008-r2, TAP-0009-r1, and
TAP-0081-r3 approvals remain independent; the new composition, semantics,
screens, reviewer playback, and inspector need their own exact owner review.

The current owner correction turns this page into one review workbench rather
than a scenario-button panel beside a phone:

- **Left:** choose a UI surface from one combined page directory, then use only
  that surface's contextual operations. There is no parallel **approved visual
  slices / TAP-0087 lifecycle** switch. Launch Screen owns scenario simulation
  controls; permissions expose only actions that can legally reduce from the
  current snapshot; Photo Viewer exposes the approved TAP-0081 local Share
  presentation.
- **Center:** inspect the exact `393 x 852` app-owned UI canvas. Once approved,
  its elements and relative positions are a strict SwiftUI constraint. A page
  already implemented natively but missing here must first be reproduced one-
  to-one; it is not silently redesigned. Viewfinder therefore follows the
  current SwiftUI hierarchy and relative geometry—two top-chrome rows, Dynamic
  Island clearance, inset preview, FOV chips, flexible space, professional slot,
  capture row, and mode strip. Its camera controls remain functionally deferred
  to TAP-0088 without adding a prototype-only mock badge.
- **Right:** inspect the selected surface's business rules, lifecycle,
  workloads, marker effects, and state changes. State machines use directed
  node-edge flow diagrams. Events default to a `t0…tn` / `Δ` timing sequence
  with UI, Reducer, Workload, and Marker swimlanes; **Ordered log** remains an
  alternate view of the same trace. The graph draws only transitions that
  actually occurred in the reducer journal and is labeled **Executed reducer
  path**; it never treats the order of `machineRegistry.nodes` as legal edges.
  Missing branch conditions stay visibly unrecorded. A complete state graph
  requires a future explicit transition registry, and swimlane causality
  likewise comes only from recorded trace effects.

The workload inspector compares complete
`observed { trigger, owner, earliest, blocks, network, evidence }` and
`target { trigger, owner, earliest, blocks, network, evidence }` records plus an
alignment verdict. Clicking a workload restores the real reducer snapshot for
its registered `{ event, status, page }` inspection moment,
including the left UI surface/operations, center phone, and complete right
inspector—not only its owning machine and sequence. The match must also contain
the workload in the tail effects; a recent arbitrary effect, cancellation, or
stale result is not a match. If playback history has no qualifying snapshot,
the same card click immediately switches to its registered canonical inspection
fixture and legally replays to that moment; no second confirmation is needed.
No synthetic event, direct state mutation, skipped predecessor, or fabricated
Ready state is allowed. A real `eligible`, `running`, or `skipped` inspection
moment remains in that state. The
displayed `t0…t5` sequence belongs to the target reducer. Current-main interval
labels are source-order inferences only, not native timestamps or device
measurements.

Use the default **08 / 09 真值** filter to review the audited current-main source
truth, current candidate placement, and TAP-0008/TAP-0009 prototype target. The
`main@4cc02e5f12f2` `actual` and `target` fields remain historical audit
evidence. The active candidate uses two review presentations instead of
treating every retained record as an active mismatch:

- **Implemented at target; regression pending:** the right lifecycle card and
  its **08/09 生命周期** Timing projection appear once at the target anchor with a
  yellow background/red border and a linked follow-up Task. They do not show an
  actual-phase card, blue target duplicate, **不一致** verdict, or dashed line.
- **Task-owned behavior not migrated:** the current actual remains red, the
  existing prototype target remains blue, and one red dashed line connects the
  pair. Initial Network/App Attest names `TAP-0010`; post-Setup App Attest and
  credential/network-dependent Pending name `TAP-0015`.

Workload-owned records are omitted from the lifecycle lane and appear only in
the existing **Workload** lane. For an implemented record, the exact existing
target workload effect receives the yellow/red pending-regression decoration
and linked Task directly; there is no separate **实际 · 不一致** card, blue
duplicate, or dashed line. For behavior that is not migrated, one red actual
annotation may appear in its JSON-selected reviewer visibility/upstream column,
and a dashed line terminates at the matching existing blue target effect. If the
target effect has not been recorded yet, the red actual says
**既有 trace effect 尚未出现** and no substitute or future event column is
created. Target lifecycle `tN` reachability remains separate from the workload
effect's canonical status. There is no lower comparison band or duplicate
Workload lane.

The lifecycle truth records and workload difference records are read from
[`manifest.json`](manifest.json) under
`independentCandidates.startupLifecycle.workbench.right.tap0008Tap0009CodeTruth`.
The page does not maintain a second hardcoded list, lane-ownership list, or
count. Each record scopes one current-main path/trigger, names the lifecycle
truth that it represents, carries the scenario/event/workload/status binding
used to find the existing prototype trace effect, and supplies its current
`reviewState`, `activeDifference`, and `followUpTaskIDs`. Historical disposition,
outcome, actual, and target fields do not override that current review state.

Implemented non-Network lifecycle order and workload-period regression is
tracked by `TAP-0090`; attended evidence remains in `TAP-0040`/`TAP-0041`,
route-shell/first-frame and 2 × 2 timing in `TAP-0083`, and exact
prototype/native visual parity in `TAP-0048`. Workload children keep their own
review state instead of inheriting a parent, so the implemented local part of
`deferredWorkGuard` can decorate its target effects while its `TAP-0015` App
Attest/Pending children remain red differences. The candidate makes no direct
change to those executors or retry policy and does not reinterpret `/healthz`
as the target.

The complete prior outcome view—including originally aligned and device-log-
accepted records—is historical at `fix0809@d4b19d9`; those records are not
loaded into active JSON merely to form a second archive. Target placement does
not close a linked validation Task or approve the complete TAP-0087 composition,
which remains `ownerReviewRequired`.

Settings is catalogued only as **Pending — no approved slice**. It has no
invented phone preview or operations. The system Settings handoff used for
permission recovery remains a system-owned boundary.

1. Confirm **上一个事件 / 下一个事件 / 重置** share one row before the Launch
   scenario controls and do not reappear in contextual actions. Then choose
   **Launch Screen** in the UI catalog and a canonical
   installation/activation operation. The projected route is derived only from
   the structured Setup receipt, Camera/Photos snapshot, and versioned
   initialization marker. Installation labels and Debug/Release measurement
   settings do not select a route.
2. Select **启动本场景** in that surface's operation panel. A Foreground Process Launch shows the exact static
   `LaunchBackground`/`LaunchLogo` reference, then automatically commits the
   lightweight **First App Frame** bridge at `t1`. The next separate logical
   event commits the selected Setup / Permission / Initialization / Viewfinder
   route at `t2`; with **自动过渡** enabled, both events advance automatically,
   and disabling it leaves each interval independently inspectable. Fixture
   delays demonstrate order only and are not native timing claims. Foreground
   Resume has no Launch Screen.
3. In First-Install Setup, the Network row explicitly starts initial App Attest
   registration/verification; `/healthz` alone is insufficient. Continue needs
   App Attest, Camera, and Photos. Location/Microphone remain optional. After a
   Camera action enters `waitingSystem`, the contextual operation list is empty;
   only the system-return event can restore the next legal actions.
4. In Required Permission Check, only Camera and Photos appear. Network failure
   cannot enter that route. Returning from the system boundary passively
   rechecks the affected status and automatically re-runs the reducer.
5. In Resource Initialization, review Camera-first and catalog-first scenarios.
   The marker writes only after a real-preview/interaction fixture and the first
   usable Library identity/order snapshot are both ready.
6. Continue through Viewfinder -> Library -> Photo Viewer. The Library entry and
   back paths work. The Viewer Share control opens the independently approved
   TAP-0081 slice in place. Verify
   `integrityChecking -> selector -> preparing -> closed / system boundary`
   while the browser URL, TAP-0087 sequence, focus,
   workload, and Viewer snapshot remain unchanged. The first Viewer Back while
   Share is open closes only Share; the next Back returns to Library. Payload
   readiness closes only the app-owned popover; no activity sheet or AirDrop UI
   is simulated. Viewfinder camera controls remain functionally deferred to
   TAP-0088; Viewer 2D/3D remain deferred to TAP-0089.
7. At every TAP-0087 action, confirm the same trace sequence and focus highlight the
   phone, `t0…tn`/`Δ` timing swimlane, namespaced `S/P/C/L/V` span, directed
   machine node/edge, workload owner, marker effect, and ordered log. Switch
   between **Timing** and **Ordered log** without changing state. **Previous
   logical event** restores the preceding complete reviewer snapshot without
   adding a product/reducer event; Next then reduces forward again from that
   snapshot. Confirm **Previous logical event**, **Next logical event**, and
   **Reset** share one row and do not reappear in the selected surface's
   contextual operations. Click a workload with a playback-history match and
   confirm its registered event/status/page plus tail workload effect select one
   real snapshot; the left selected surface/operations, center phone, and entire
   right inspector must restore together. If no qualifying history exists, the
   same click must switch directly to the registered canonical inspection
   fixture and legally replay to that moment, without a second confirmation.
   It must not create a synthetic event, select a later cancel/stale effect,
   skip a predecessor, fabricate Ready, or promote a real
   `eligible`/`running`/`skipped` state.
8. Compare Debug attached/detached and Release attached/detached using identical
   scenario facts. The Web prototype proves route invariance only; TAP-0083 must
   measure `t0/t1` and lag on the same physical iPhone.

At the supported desktop reviewer viewport, the left UI/operation catalog,
center phone, and right lifecycle/workload/state/event inspector stay visible
in one window without page-level scrolling. Dense panels may scroll internally.

The generated Viewfinder preview fixture is
`assets/media/viewfinder-camera-fixture.png`. It was created with OpenAI's
built-in image generator from a prompt for a photorealistic portrait camera
view containing a matte dark ceramic cup, plant, concrete objects, soft window
light, and no baked UI, text, logo, or watermark. It is prototype media, not
device or camera-output evidence. The surrounding chrome and geometry map the
current SwiftUI hierarchy; only the fixture pixels are generated.

## Review TAP-0081-r3-candidate

This owner-directed candidate preserves the geometry, resource/integrity states,
and capability matrix approved in `TAP-0081-r2-candidate`. It changes only the
app-owned preparation lifecycle: choosing TAPNAP Package or another implemented
share type keeps the selector visible and immediately adds determinate progress
as a 2 px track that replaces the selected option's subtitle text inside the
exact same fixed-height subtitle slot. The title, icon, badge, row height, popover
dimensions, and every sibling position remain unchanged; the subtitle text and
track are never shown together, and no percentage or Cancel control is inserted.
Every other option remains visible but is temporarily disabled. There is no
independent preparation page, artificial reveal delay, or minimum-visible hold.
When the payload becomes ready, the app-owned popover ends immediately. The
subsequently presented iOS activity controller remains a text-only boundary and
is never imitated by this Web prototype.

1. Choose Photo, Live Photo, or Video.
2. Choose **iCloud · Loading**. Confirm the Viewer shows original-resource
   progress and the bottom-left Share control remains present but disabled.
3. Choose **Local · Ready** or **iCloud · Ready**. Confirm the loading state is
   removed and Share becomes enabled. Use **Private queue** to make the
   queue-only 待重试 fixture available.
4. Choose **Hold for review**, tap Share, and inspect the text-free local
   integrity skeleton. It deliberately exposes no fourth credential label.
   Use **Resolve local check** to reveal 已验证, 待重试, or 失败.
5. Inspect the capability matrix. TAPNAP Package is available only for a
   verified Photo/Live Photo; Video Package, Sticker, and Link remain disabled.
   In Failed, TAPNAP stays disabled while Share Image/Video remains enabled with
   the explicit warning “无法保证可验证性”.
6. Keep **Success · observable** selected and choose any implemented format.
   Confirm the original subtitle text is replaced immediately by a thin progress
   track inside the same slot, without moving the title, icon, badge, row, popover,
   or sibling rows, and that progress never moves backwards. The subtitle and
   track must not appear together; no percentage or Cancel control appears. The
   other three rows stay visible and disabled. When the payload becomes ready,
   confirm the app-owned popover closes without inserting a preparation or
   completion screen.
7. Use Cancel, Failure, and Retry. Confirm the Viewer, media, pager region, and
   toolbar never disappear or rebuild.
8. Read the System boundary note in the control panel. It documents the native
   handoff only; the real iOS activity controller and its dismissal are not
   simulated.

The prototype performs no PhotoKit, iCloud, proof parsing, hashing, App Attest,
or backend request. The observable success/failure fixtures describe visible
state relationships only; the native implementation owns actual resource,
integrity, payload-progress, and system-presentation work.

The exact state coverage, source-image hashes, native symbol intent, system
boundaries, and approval status are recorded in [manifest.json](manifest.json).

## Review owner-approved TAP-0008 first-install setup

The product owner approved exact revision `TAP-0008-r2-candidate` on
2026-08-13 with “现在原型已经确认没有问题”. It remains deliberately separate
from the already-approved TAP-0009 initialization slice.

1. Select **首次安装设置** under Flow and choose **Untouched**. Confirm that all
   five rows are idle. Merely entering or foregrounding this page performs only
   passive status refresh: no permission UI, Network-row operation, PhotoKit change
   observation, camera start, or background warm-up begins. The header uses the
   exact current `LaunchLogo` asset from the app catalog; it does not substitute
   a text wordmark or redraw the brand. Every setup-row icon is exported from
   the exact SF Symbol identity used by `WelcomeStartupSetupView.swift`;
   Unicode or hand-drawn approximations are forbidden.
2. Tap an individual row's **允许** button. Confirm only that row changes to
   requesting and the app-owned system-boundary note appears. The real iOS
   permission sheet is deliberately not imitated.
3. Choose **Camera tapped** to review the exact camera handoff boundary. Other
   permission rows remain idle, proving that one explicit action cannot fan out
   into unrelated requests.
4. Choose **Network failed**. Confirm Retry belongs to the network row and does
   not request any system permission.
5. Choose **Required ready**. Network, Camera, and Photos are complete;
   optional Location and Microphone are shown as skipped for this fixture, but
   they do not block **继续** and may remain untouched in the product flow.
6. Select **继续** and confirm the prototype advances to the independent
   TAP-0009 **资源初始化** screen rather than directly entering the Viewfinder.

The prototype records the app-owned state before the action and after iOS
returns. It never draws or claims control over a system permission sheet.

## Review TAP-0009 resource initialization

The product owner approved exact revision `TAP-0009-r1-candidate` on
2026-08-13. It remains a separate Task and visual contract from TAP Share.

1. Select **冷启动资源初始化** under Flow. This historical slice represents an
   absent/stale initialization marker after Fresh Installation,
   Delete-and-Reinstall, or a changed In-place App Update; an
   Offload-and-Reinstall with a current marker and ordinary later process
   launches skip it.
2. Inspect **Preparing**: neither the camera nor the first TAP Library catalog
   is ready, and the full-screen state remains stable.
3. Select **Camera ready**: the first preview frame and controls are ready while
   the Library catalog remains pending.
4. Select **Library ready** to inspect the reverse completion order: the
   catalog may complete while the real first camera frame is still pending.
5. Select **Ready → Camera**: both readiness groups turn ready, the spinner is
   removed, and the fixture advances to the explicit camera-entry boundary.

There is deliberately no Failed, Retry, timeout, or degraded-entry surface.
Initialization is a startup invariant: abnormal noncompletion keeps this stable
UI visible and emits developer diagnostics. It is treated as a defect, not a
user-recoverable product state.

This slice is independent from TAP Share. It does not prebuild or prewarm Share,
proof parsing, hashing, ZIP creation, or the system activity controller.

### `fix0809` native-candidate synchronization

[manifest.json](manifest.json) records implementation progress separately from the audited
current-main truth cards. The 2026-08-15 `fix0809` candidate changed the bounded
non-Network lifecycle slice. Implemented records therefore appear at their
target lifecycle anchors or target workload effects with the yellow/red
pending-regression treatment; they are not retained as position differences.
Camera construction follows route-shell selection and keeps model creation lazy
across later parent updates, while `TAP-0083` still owns the missing rendered-
frame and 2 × 2 timing evidence. `TAP-0090` owns the remaining non-Network
structured trace and assertion regression. The complete earlier reviewer
overlay and its accepted/aligned records remain available in Git at `d4b19d9`
rather than in an active manifest archive.

The owner-approved TAP-0009 Resource Initialization copy and its Camera/TAP
Library readiness rows are implemented natively. Required Permission Check is
a native candidate whose exact visual/copy parity remains under `TAP-0048`.
The native marker write is off-MainActor and Application-Support-only;
local poster/recent-cover work and pending App Intent navigation wait until a
two-display-tick committed-Viewfinder barrier. The owner accepted the bounded
non-Network lifecycle path after exercising it on a physical device. Exact
prototype-to-native visual parity (`TAP-0048`), structured lifecycle regression
(`TAP-0090`), physical timing (`TAP-0083`), and the unexecuted attended
installation/restore/recovery matrix (`TAP-0040`/`TAP-0041`) are not claimed by
that verdict. Initial Network/App Attest (`TAP-0010`) and post-Setup App
Attest/Pending (`TAP-0015`) remain red actual-to-blue-target differences. The
complete workbench remains `ownerReviewRequired`.

## Evidence Boundary

This prototype can establish visible hierarchy, relative geometry, copy,
enabled/disabled presentation, and simulated interaction order. It cannot prove
PhotoKit or AVFoundation behavior, real iCloud transfer, local content-binding
integrity, package preparation timing, signing, backend verification,
temporary-file cleanup, haptics, native accessibility, AirDrop, third-party
destinations, or physical-device performance.

Do not save photos, screenshots, or screen recordings as prototype or native
acceptance proof. Durable evidence consists of public-safe structured logs or
JSON/JSONL, automated DOM/reducer/native assertion reports, build/device
identifiers where relevant, and an owner-live textual verdict. Historical
captures remain historical facts; this policy does not recreate or retain new
image proof.

Later Tasks may add functional Viewfinder controls or other vertical slices only
after reading and mapping their relevant Product Contract states. A missing
slice remains explicit; it is not invented here.
