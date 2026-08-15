# TAPCam UI Prototype Contract

- Status: canonical UI design-to-implementation workflow
- Last updated: 2026-08-15

## 1. Two Complementary Sources Of Truth

TAPCam UI work has two current constraints:

1. [ProductContract.md](ProductContract.md) defines functionality, state
   machines, triggers, errors, recovery, capability degradation, future scope,
   and explicit non-goals.
2. A repository-owned HTML/Web prototype defines visible component hierarchy,
   component appearance, stable icon identity, relative position, spacing,
   sizing, responsive layout, and approved simulated interaction.

Neither replaces the other. The prototype cannot invent a product state, and a
functional requirement cannot silently override an approved layout. A conflict
returns to the associated Task for a product decision.

## 2. Default Workflow

```text
product contract and state machine
        -> find or create one Task ID
        -> create or revise the HTML/Web prototype
        -> product-owner visual approval
        -> implement or revise SwiftUI
        -> Simulator acceptance
        -> physical-device acceptance when required
```

HTML/Web is the default interactive visual specification because it lets the
product owner inspect and directly adjust component relationships in a browser.
Sketch is optional. If Sketch is used, its accepted decision must be synchronized
to the Web prototype so the project does not gain a second active visual truth.

The prototype grows by approved vertical slices; it is not a requirement to
redraw the entire application before the first native change. The foundation
first provides one lightweight, statically served interaction entry and one
complete Task-scoped flow. Later Tasks read their relevant Product Contract
states and extend the same prototype with additional flows such as first-install
setup or the Viewfinder. Each added slice keeps its own Task, revision, covered
states, approval, and acceptance mapping.

## 3. What The Web Prototype Owns

For every covered state, the prototype may define:

- component hierarchy and grouping;
- relative position, alignment, spacing, size, and safe-area intent;
- color and typography tokens;
- stable icon identity, including the intended SF Symbol name where relevant;
- navigation and simulated state transitions;
- visible enabled, disabled, loading, failure, empty, and selected states;
- responsive behavior for explicitly supported viewports.

The prototype should let the product owner see relationships among components
and switch between the states needed by its Task. It may use deterministic
fixtures to demonstrate those states.

The current runtime product is iPhone-only, so repository prototype and native
parity requirements cover only the iPhone viewports explicitly approved by
their Task. iPad, Mac, and Apple Vision Pro layouts are not implicit responsive
requirements. Adding one of those platform families requires a separate
owner-approved product and prototype scope.

This makes the prototype an executable visual constraint rather than a second
product implementation. Text remains authoritative for runtime facts, state
meaning, failure policy, and non-goals; the prototype makes the approved
visible hierarchy and interaction sequence concrete enough to review before
SwiftUI. A state not covered by the current slice remains an explicit gap, not
an invitation for implementation to invent it.

The prototype does not prove or own:

- AVFoundation or PhotoKit capability;
- a real system permission lifecycle;
- camera session or first-frame readiness;
- real depth, capture, signing, export, or verification;
- native haptics, accessibility behavior, performance, or device lifecycle;
- App Store submission evidence.

HTML icon rendering is an optical preview. SwiftUI should use the intended
native control or SF Symbol where appropriate, and the final iOS result owns
native optical behavior.

## 4. Task Requirements

Before changing a UI, an Agent must search
[ProjectBoard.md](ProjectBoard.md) across every status. It updates a matching
Task rather than creating a duplicate. Each UI Task records:

- related Product Contract section;
- affected state-machine states;
- prototype path and approved prototype revision;
- components and icon identities in scope;
- out-of-scope states;
- SwiftUI implementation owner;
- Simulator and device acceptance requirements.

Prototype approval proves visual intent and simulated state coverage only. It
does not mark the delivery or device-acceptance Task complete.

If implementation reveals a conflict between platform behavior and the
prototype, the Agent must return the Task for decision. It may not silently
change the state machine or imitate an iOS system control with a visually
similar Web control.

Later visual changes normally follow prototype-first revision and approval.
An urgent runtime or safety defect may precede prototype work only when the fix
does not intentionally change the UI, or when the product owner explicitly
authorizes that exception. Any visible divergence must be synchronized back to
the prototype, reviewed, and recorded before the Task closes.

### 4.1 TAP-0087 review workbench and lifecycle inspector

`TAP-0087` adds reviewer-only chrome outside the iPhone canvas for startup and
heavy-work analysis. It is not product UI and creates no iPad, Mac, or runtime
dashboard requirement.

The supported desktop workbench has three simultaneous regions:

1. **One combined UI page directory and operation catalog** on the left. Its
   top-level navigation is a single catalog containing Launch Screen,
   First-Install Setup, Required Permission Check, Resource Initialization,
   Viewfinder, TAP Library, Photo Viewer, and later approved surfaces. It must
   not retain parallel **approved visual slices** and **TAP-0087 lifecycle**
   entries, tabs, or switches. Selecting a surface reveals only that surface's
   applicable simulation actions, such as choosing a Launch scenario, acting
   on one permission row, opening Library, or opening the approved TAP-0081
   local Share presentation inside Photo Viewer. These controls are inputs to
   the simulation; they are not the state-machine visualization.
2. **iPhone visual truth** in the center. The app-owned canvas remains exactly
   `393 x 852` CSS px and owns the hierarchy, visible elements, and relative
   geometry that an approved revision constrains in SwiftUI. When a native page
   already exists but has no Web counterpart, its first prototype slice must
   map the current native page one-to-one before proposing a redesign or
   claiming parity. The iOS Launch Screen is the explicit system-owned static
   reference exception.
3. **Current-surface causality** on the right. It shows the business rules,
   lifecycle intervals, workloads and owners, marker effects, and machine
   changes associated with the selected surface and focused trace event.

The surface catalog may name an uncovered future or existing page only as a
disabled **Pending — no approved slice** entry. In particular, Settings has no
approved TAP-0087 slice, so this candidate may not invent its preview,
operations, copy, or geometry. A system Settings boundary used for permission
recovery is not an app-owned Settings-page design.

The right-side inspector may show:

- installation and activation scenario facts;
- `t0…tn` milestones and the active interval;
- logical workloads plus observed and intended actor/queue ownership;
- state-machine nodes and transition edges;
- lifecycle-marker effects; and
- a bounded deterministic event log.

Every workload entry presents two explicit records plus an alignment verdict:

```text
observed { trigger, owner, earliest, blocks, network, evidence }
target   { trigger, owner, earliest, blocks, network, evidence }
alignment = aligned | partial | gap | deferred
```

`observed` describes current-main source placement and cites source evidence;
`target` describes the contract-required placement and cites its contract or
Task evidence. Every workload also registers one inspection moment as
`{ event, status, page }`: the lifecycle point the owner intends “click to
inspect,” normally the moment that workload becomes prepared for its role. A
workload card is reviewer navigation into the complete reducer snapshot at that
moment, not merely a machine-focus shortcut.

The inspector also owns a separate, source-grounded **TAP-0008 / TAP-0009 code
truth** projection. Route, persistence, recovery, readiness, and presentation
differences are not forced into the workload state machine when they are not
executable workloads. Each truth record has a stable ID, related Task IDs,
`actual { anchor, phase, summary, evidence }`,
`target { anchor, phase, summary, evidence }`, and an explicit alignment verdict.
Anchors are data, never parsed from prose. Records whose audited current-main
behavior differs from the prototype target keep the visible word **不一致**;
aligned facts remain green and say **一致**. Card color may additionally
project a later branch's owner-reviewed delivery and evidence status, but it
never rewrites the audited baseline, `alignment`, `mismatch`, actual phase, or
target phase.

Each mismatch also reads its `fix0809Disposition` from the prototype manifest.
That field preserves the original owner-approved implementation boundary. A
separate per-record `fix0809Outcome`, also loaded from the manifest rather than
inferred from IDs or prose, projects the candidate result in all three actual-
truth surfaces:

- `implementedLogAccepted`: yellow background and yellow border. The fix0809 code
  changed and the bounded physical-device log accepted the executed path.
- `implementedNotLogVerified`: yellow background and red border. The code
  changed, but the supplied log does not prove that record is aligned.
- `deferredFrozen`: red background and red border. Network, App Attest, and
  credential/network-dependent Pending behavior remain frozen and untreated.
- an originally aligned record has no fix0809 outcome and keeps its existing
  green presentation.

Every yellow card still says **不一致** because it describes the immutable
`main@4cc02e5f12f2` source audit beside a later fix0809 result. Its outcome badge
and accessible name state whether the executed path was log-accepted or merely
implemented without log coverage. A deferred record shows the manifest label
**本轮冻结 · Network/App Attest/Pending**. For `networkBootstrap`, this means
Network/App Attest behavior is excluded from fix0809; it never means that
`/healthz` has become the target state or that the mismatch is resolved.

A workload record may narrow its broader lifecycle parent: Network/App Attest
and credential/network-dependent children remain `deferredFrozen` even when a
non-network portion of the parent truth is `approvedToFix`. The child record's
JSON disposition and outcome control the visible badge, color treatment, and
accessible name. Outcome is always stored per child; it is never inherited from
the parent lifecycle truth.

The default truth-card list renders the six non-workload mismatch records plus
the two aligned records. The six workload-owned mismatch sources remain in the
same JSON catalog but render only as their scoped Workload-lane comparisons;
they must not also produce a truth card or lifecycle-circle connector.

Every visible mismatch truth card has exactly one decorative red dashed connector to
the circular `t0…tn` anchor that locates its **current-main actual phase**. The
card separately names the target phase, so the connector cannot be read as a
target transition. Scrolling, filtering, resize, and responsive reflow must
recompute this one-to-one mapping; a hidden or clipped card does not leave a
floating connector. The SVG is accessibility-hidden, while each card's text and
accessible name state actual phase, target phase, and verdict without relying on
color. These dashed paths are difference annotations, not reducer-journal edges,
machine transitions, native timing evidence, or proof that current main emits a
canonical `t*` milestone. They connect only to the always-present timeline
circles, never to an executed-path machine node that may be absent from the
current journal.

The **Timing 时序** projection gives every mismatch exactly one lane owner.
Non-workload lifecycle differences appear in the reviewer-only **08/09 生命周期**
lane after their explicit `actual.anchor` is present. Each outcome-colored
lifecycle card keeps one dashed path to that column's circular milestone.
Workload-related
truth is omitted from this lane so it cannot appear once as lifecycle and again
as workload.

Workload differences live inside the existing **Workload** lane; there is no
standalone comparison band or second Workload lane. Their canonical records are
loaded from the repository JSON manifest, and the controller must not duplicate
records, ownership IDs, or derived counts. A record has an explicit
`differenceType` of `timing` or `semantic`, one scoped current-main path and
checkpoint, evidence-backed actual/target anchors, and the lifecycle-truth IDs
whose Workload-lane representation it owns.

Every canonical reducer workload effect remains present. A manifest-owned
current-main difference appears as an outcome-colored **实际 · 不一致** annotation in the
`actualVisibleAfter` reviewer visibility/upstream projection column only after its JSON
`scenarioGroupID` matches; the annotation separately names the coarse
`actual.anchor` lifecycle period. Its corresponding prototype workload is
the already-rendered trace effect uniquely selected by event type, workload ID,
resulting status, and occurrence; that existing effect is blue and retains its
normal focus/status behavior. Exactly one dashed SVG connector joins the two
when the target exists.

The actual annotation states mismatch kind, checkpoint, real source scope/trigger,
actual and target phases, target reachability, and the reviewer projection
event. It focuses that projection column, which controls only when the source-
grounded difference becomes visible; it does not claim that current main ran the
actual workload during that prototype reducer event.
If the target effect is absent, it says **既有 trace effect 尚未出现** and
renders no synthetic blue target, future trace column, milestone node, reducer
event, workload transition, marker effect, or phone-state mutation. The card
shows target lifecycle-anchor reachability separately from the exact existing
workload effect's canonical `Eligible` / `Running` / `Ready` status. Current-main
placement remains source-order or predicate inference, not an instrumented
timestamp, elapsed duration, or device-performance claim.

On click, the workbench first searches the current playback history for a real
snapshot matching all three registered moment fields whose tail event effects
also contain that workload. It restores that exact moment—not the most recent
arbitrary effect and not a later cancellation, stale publication, or unrelated
terminal state. The left selected UI surface and legal contextual operations,
center phone, and right machine, timing, workload, marker, ordered-log,
sequence, and focus projections all restore together. The workbench must not
combine a historical inspector state with the current phone or catalog.

If playback history has no qualifying snapshot, that deliberate card click is
itself authorization to switch immediately to the workload's **registered
canonical inspection fixture**; no second confirmation control is required.
The fixture declares canonical initial facts and ordered inputs, then dispatches
only events accepted by the same reducer until the registered moment is reached.
It may not insert a synthetic event, mutate a snapshot directly, skip a
predecessor, or force a workload or phone surface to `Ready`/`succeeded`. A
registered moment whose real state is `eligible`, `running`, or `skipped`
remains exactly that state in every synchronized region.

State machines must be rendered as actual node-edge flow diagrams with
direction, any recorded branch condition, current node, and active transition
visible. An absent branch condition is labeled unrecorded rather than invented.
Rows of state buttons, pills, or cards alone do not satisfy this requirement.
The current candidate may draw only node-edge paths that actually occurred in
the reducer journal and labels this projection **Executed reducer path**. A
`machineRegistry.nodes` vocabulary is not a transition graph, and its array
order must never be interpreted as a legal edge or next state. A future complete
normative graph requires an explicit transition registry before it can be
rendered or claimed.

Events default to a timing-axis sequence/swimlane view organized by `t0…tn`
points and their `Δ` intervals. At minimum it separates **UI**, **Reducer**,
**Workload**, and **Marker** lanes and draws their order and causal connection.
Every lane item and connector comes from the focused trace event's recorded
effects; the visualization must not infer unrecorded work, markers, or causes.
The existing bounded ordered log remains available through an explicit view
switch; it is a secondary textual projection of the same trace, not another
event source.

The workbench's `t0…t5` points and `Δ` intervals belong to the TAP-0087 target
reducer. A current-main workload may be mapped beside one of those intervals
only as an explicitly labeled source-order inference. Such a mapping is not an
instrumented timestamp, device measurement, duration, or proof that current
native execution satisfies the target milestone.

One reducer/event trace must drive the phone surface and every inspector
highlight, including both diagram modes and the selected UI's contextual
operations. The inspector cannot maintain a second state machine that
disagrees with the simulated product flow. Current-source placement and
intended target placement remain visibly distinct until native evidence proves
alignment. Workload-card navigation therefore changes the review cursor or
explicitly replaces the review trace with a registered canonical fixture; it
never patches only the right-side inspector.

The Launch Screen fixture is labeled as a static iOS-owned reference and cannot
show progress or claim measured duration. Deterministic delays in the Web page
are interaction fixtures only; they are never native performance evidence.
Controls deliberately deferred to a child Task remain disabled/inert and are
identified by that Task. Their visual presence is not simulated functional
coverage.

The TAP-0087 Viewfinder candidate maps the current SwiftUI hierarchy and
relative geometry one-to-one: the two-row top chrome, Dynamic Island clearance,
rounded inset preview, FOV chips, flexible middle space, professional-toolbar
slot, capture row, and mode strip remain structurally distinct. The current
controls are present as visual truth but their functional simulation is deferred
to TAP-0088. The phone surface does not add a prototype-only mock badge or use
that deferral to redesign the current hierarchy.

At the supported desktop reviewer viewport, the left catalog/operations, center
phone preview, and right lifecycle/workload/state/event inspector are visible
in the same browser window without page-level scrolling. Dense inspector
regions may scroll internally. This composition is reviewer tooling only and
does not scale or adapt the iPhone product UI.

The reviewer may advance or rewind one logical event. **Previous logical
event** restores the preceding complete review snapshot; it does not dispatch a
product event, append a reducer token, run a workload, or mutate a lifecycle
marker. Phone, timing swimlane, flow graph, workload, marker, and ordered-log
projections all move to that same restored snapshot and focus. A subsequent
Next action reduces forward again from the restored state.

**Previous logical event**, **Next logical event**, and **Reset** are one global
review-playback group, remain on the same row, and appear before the Launch
scenario controls in the left rail. They are not repeated inside the selected
surface's contextual operation list. Contextual actions contain only controls
whose corresponding event can legally reduce from the current snapshot, or an
explicitly labeled independent local-presentation boundary; they do not
duplicate review transport. In particular, First-Install Setup exposes no
context action while a permission row is in `waitingSystem`; legal row actions
reappear only after the recorded system return changes the reducer state.

`TAP-0087` preserves the owner-approved Viewer Share control and presents the
independently approved `TAP-0081` slice locally inside the same Photo Viewer.
It is an independently owned local presentation, not a page navigation or a
startup route: opening, selecting, preparing, completing, or closing it does
not change the browser URL and uses no resume key, session storage, or reducer
replay. Its local state may be shown in a separately labeled TAP-0081 inspector,
but it is never imported into the TAP-0087, TAP-0008, or TAP-0009 reducer,
event log, workload registry, timing spans, markers, or acceptance claims.
Payload readiness closes only the app-owned popover and records the local
system boundary; the Web prototype does not imitate an activity sheet, AirDrop,
or destinations. While Share is open, the first Viewer Back closes only that
local presentation; a subsequent Back follows the normal Viewer-to-Library
reducer path.

## 5. Evidence Levels

| Evidence | It can establish | It cannot establish |
| --- | --- | --- |
| Web prototype | Visual intent, relative layout, icon identity, simulated states and interaction | Native lifecycle, permissions, camera readiness, performance |
| Simulator | SwiftUI layout, navigation, localization, basic state transitions, some automation | Physical Camera/Photos/depth behavior, attended first-install flow, real-device performance |
| Physical device | System prompts, first preview frame, capture/depth lifecycle, haptics, thermal/performance and attended behavior | Behavior outside the executed procedure |

A physical-device gap receives a separate `DeviceAcceptance` Task with explicit
preconditions, numbered procedure, expected results, evidence outputs, and
human confirmation.

## 6. Current Viewer Visual Contract

The current Viewer uses horizontal mixed-media paging and a stable bottom
toolbar containing Share, the `RAW / 2D / 3D` capsule, and Delete.

These former designs are deprecated and are not prototype Todo items:

- tool drawer;
- up-swipe Verify or drawer presentation;
- down-swipe dismissal and detents;
- top-level Heatmap, Overlay, or Mask mode buttons.

New Viewer ideas may be proposed later through a new Task and prototype
revision. They do not reopen a deprecated design automatically.

## 7. Sketch Pilot Status

The completed Sketch pilot proved a limited Viewfinder/Settings visual workflow,
but it is no longer an active design source. Its reusable rules were migrated
into this contract and its unresolved work into the Project Board. The pilot
plans, bilingual traceability contracts, state manifest, conflict register, and
design-review images have therefore been removed from the current tree; Git
history remains the recoverable archive.

Unfinished Sketch P3 work was not inherited automatically. Any future App Store
or Sketch work requires its own Project Board Task after the HTML-first workflow
is considered.

## 8. Repository Shape And Incremental Coverage

The prototype starts with the smallest stack that can express its approved
interaction states. A lightweight HTML/CSS/JavaScript implementation is valid;
a framework, backend, package manager, hosting runtime, or full-app shell is not
required merely to satisfy the workflow. Add infrastructure only when a later
Task demonstrates that the current foundation cannot express its states.

The intended durable shape is:

```text
Prototype/
  README.md                # run instructions and evidence boundary
  index.html               # statically served interaction entry
  prototype.css            # shared visual tokens and layout
  prototype.js             # deterministic state transitions
  states/                  # deterministic state fixtures
  assets/                  # reviewed prototype-only assets
  manifest.*               # prototype revision and Task/contract mapping
```

The prototype does not exist merely to produce screenshots. It is an
interactive, versioned visual contract that the product owner can inspect before
SwiftUI implementation. Repository history and Task revision history record
incremental milestones; the Kanban schema does not need a separate `Partial`
status to acknowledge a completed slice while the broader foundation Task
continues.

## 9. App Store And Localization Boundary

App Store media work is not active merely because a prototype exists. It remains
an Inbox decision on the Project Board. A future Store Task must separately own
the supported iPhone display-size capture matrix, device-frame decision, asset
rights, locale order, export validation, and submit-ready files. App Store
media work must not silently expand the current iPhone-only runtime target;
iPad or Mac product support requires its own product decision and Task.

Real Preview pixels, TAP Library thumbnails, 3D output, and credential-state
marketing evidence must come from a fixed runtime build and documented asset
chain. HTML, Sketch, placeholders, redrawn projection, or a deterministic Ready
fixture cannot substitute for those runtime sources.

Prototype or marketing localization does not silently change the app's runtime
locale contract. The current camera surface remains English until a separate
product/code Task changes and validates it; localized marketing wrappers may be
considered independently.
