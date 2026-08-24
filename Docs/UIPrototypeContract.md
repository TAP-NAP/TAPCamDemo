# TAPCam UI Prototype Contract

- Status: canonical UI design-to-implementation workflow
- Last updated: 2026-08-24

## 1. Two Complementary Sources Of Truth

TAPCam UI work has two current constraints:

1. [ProductContract.md](ProductContract.md) defines functionality, state
   machines, triggers, errors, recovery, capability degradation, future scope,
   and explicit non-goals.
2. The independently repository-owned HTML/Web prototype in `TAPCamPrototype`
   defines visible component hierarchy, component appearance, stable icon
   identity, relative position, spacing, sizing, responsive layout, and
   approved simulated interaction.

Neither replaces the other. The prototype cannot invent a product state, and a
functional requirement cannot silently override an approved layout. A conflict
returns to the associated Task for a product decision.

TAPCamDemo owns the Product Contract, Project Board, native implementation,
workflow, and acceptance records. TAPCamPrototype owns the static prototype
implementation, manifest, fixtures, assets, QA, tests, and prototype evidence.
The standard local layout places the repositories side by side. From the
TAPCamDemo repository root, the prototype is at
`../TAPCamPrototype/Prototype/`; no duplicate implementation lives inside
TAPCamDemo.

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
- prototype repository/path and approved prototype revision;
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

Every workload registry entry preserves two explicit records plus an alignment
verdict:

```text
observed { trigger, owner, earliest, blocks, network, evidence }
target   { trigger, owner, earliest, blocks, network, evidence }
alignment = aligned | partial | gap | deferred
```

`observed` describes current-main source placement and cites source evidence;
`target` describes the contract-required placement and cites its contract or
Task evidence. The active reviewer presentation below determines whether those
records remain a visible actual/target pair or the implemented candidate is
shown once at its target effect. Every workload also registers one inspection
moment as `{ event, status, page }`: the lifecycle point the owner intends
“click to inspect,” normally the moment that workload becomes prepared for its
role. A workload card is reviewer navigation into the complete reducer snapshot
at that moment, not merely a machine-focus shortcut.

The inspector also owns a separate, source-grounded **TAP-0008 / TAP-0009 code
truth** projection. Route, persistence, recovery, readiness, and presentation
facts are not forced into the workload state machine when they are not
executable workloads. Each truth record has a stable ID, related Task IDs, and
historical baseline fields
`actual { anchor, phase, summary, evidence }` and
`target { anchor, phase, summary, evidence }`. Anchors are data, never parsed
from prose. Those baseline fields continue to describe the
`main@4cc02e5f12f2` audit; they do not force the current candidate to render as
if its implemented work still occupied the old actual position.

The active candidate derives one of two review presentations from the manifest:

- **Implemented at target position; validation pending.** The right-side card
  uses a yellow background with a red border, names the candidate/target phase,
  and links the derived follow-up Tasks. It is a pending-regression record,
  not an active mismatch and does not display **不一致**, a current-main actual
  phase, a blue comparison target, or an actual-to-target difference line.
- **Task-owned behavior not migrated.** Network, App Attest, and
  credential/network-dependent Pending behavior that remains outside the
  candidate keeps a red actual card, an existing blue target, and one red
  dashed actual-to-target difference line. Its visible label and accessible
  name identify the owning implementation Task directly; active copy does not
  use session-relative disposition language. For `networkBootstrap`, `/healthz`
  remains current behavior and never becomes the target state.

For this candidate, `TAP-0090` owns non-Network lifecycle-order and workload-
period regression assertions; `TAP-0040`/`TAP-0041` own attended startup
evidence; `TAP-0083` owns route-shell/first-frame placement and 2 × 2 timing;
and `TAP-0048` owns exact prototype/native visual parity. Initial Network/App
Attest that is not migrated is owned by `TAP-0010`; post-Setup App Attest and
credential/network-dependent Pending are owned by `TAP-0015`.

No device-log-accepted or originally aligned historical record is reintroduced
into active JSON solely to provide an archive; the complete prior outcome
catalog remains recoverable at `fix0809@d4b19d9`. Each active record still reads
its implementation/verification disposition and linked Task IDs from the
manifest rather than inferring them from its ID or prose.

A Workload child may narrow a broader lifecycle parent. The child record's JSON
state controls its badge, color, geometry, accessible name, and Task link; it is
never inherited from the parent lifecycle truth. This lets an implemented local
portion of `deferredWorkGuard` appear at its target workload effect while the
unmigrated App Attest and Pending children remain explicit red actual-to-blue-
target differences.

Lifecycle-truth ownership and Workload ownership remain disjoint. A
workload-owned truth renders only through its scoped Workload records and must
not also produce a lifecycle card or lifecycle-circle decoration. The manifest
owns the active counts and partitions; the renderer must not hardcode them.

This candidate composition remains `ownerReviewRequired`. Moving implemented
records to target placement and attaching verification Tasks does not claim
that their regression procedures have passed, approve the complete workbench,
or approve any Task-owned behavior that is still visibly unmigrated.

Only a red not-migrated truth card owns a decorative red dashed connector to
the circular `t0…tn` anchor for its current-main actual phase. Its blue target
and target phase remain separate. Scrolling, filtering, resize, and responsive
reflow recompute this one-to-one mapping; a hidden or clipped red actual card
does not leave a floating connector. The SVG is accessibility-hidden, while
the card and target state actual phase, target phase, owning Task, and verdict
without relying on color. These paths are difference annotations, not reducer-
journal edges, machine transitions, native timing evidence, or proof that
current main emits a canonical `t*` milestone. An implemented-at-target yellow
card owns no such path.

The **Timing 时序** projection gives every active record exactly one lane owner.
An implemented non-workload lifecycle record appears in the reviewer-only
**08/09 生命周期** lane at its explicit `target.anchor`, uses the yellow/red
pending-validation treatment, and has no difference line. A not-migrated
non-workload lifecycle record appears at its `actual.anchor` as a red actual
card with one dashed path to its blue target. Workload-related truth is omitted
from this lane so it cannot appear once as lifecycle and again as workload.

Workload follow-up and active-difference records live inside the existing
**Workload** lane; there is no standalone comparison band or second Workload
lane. Their canonical records are
loaded from the repository JSON manifest, and the controller must not duplicate
records, ownership IDs, or derived counts. A record has an explicit
`differenceType` of `timing` or `semantic`, one scoped current-main path and
checkpoint, evidence-backed actual/target anchors, and the lifecycle-truth IDs
whose Workload-lane representation it owns.

Every canonical reducer workload effect remains present. For an implemented
record, the exact existing target effect selected by event type, workload ID,
status, and occurrence receives the yellow background/red-border candidate
decoration and linked verification Task directly. There is no separate
**实际 · 不一致** annotation, blue duplicate, or dashed line. The effect keeps its
canonical focus action and `Eligible` / `Running` / `Ready` state; the yellow
decoration does not promote it to completion or imply that validation passed.

For behavior that is still not migrated, the JSON-selected
`actualVisibleAfter` projection may show one red actual annotation containing
the source scope/trigger, actual phase, target phase, and owning Task. Its
corresponding existing prototype effect remains blue, and exactly one dashed
line joins the pair when that effect exists. The projection event controls only
when the source-grounded actual becomes reviewable; it does not claim that
current main executed the work during that prototype reducer event. If the
target effect is absent, the red actual card says **既有 trace effect 尚未出现**
and creates no synthetic target, connector, future column, milestone, reducer
event, workload transition, marker effect, or phone-state mutation.

Historical current-main placement remains source-order or predicate inference,
not an instrumented timestamp, elapsed duration, or device-performance claim.

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
disagrees with the simulated product flow. A Task-owned behavior that has not
been migrated keeps its current-source and target placement visibly distinct.
An implemented behavior instead occupies the target placement once, carries a
yellow/red pending-regression treatment and its follow-up Tasks, and does not
retain a synthetic actual-to-target difference solely because regression
evidence remains open. Workload-card navigation therefore changes the review
cursor or explicitly replaces the review trace with a registered canonical
fixture; it never patches only the right-side inspector.

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
human confirmation. Durable acceptance evidence is limited to public-safe
structured logs or JSON/JSONL, automated assertion reports, build/device
identifiers, and an owner-live textual verdict. Do not retain a photo,
screenshot, or screen recording as prototype or device-acceptance proof.

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
TAPCamPrototype/
  AGENTS.md                 # cross-repository Agent boundary
  README.md                 # repository entry point and ownership map
  Prototype/
    README.md               # run instructions and evidence boundary
    index.html              # statically served interaction entry
    prototype.css           # shared visual tokens and layout
    prototype.js            # deterministic state transitions
    states/                 # deterministic state fixtures
    assets/                 # reviewed prototype-only assets
    manifest.*              # prototype revision and Task/contract mapping
```

The prototype does not exist merely to produce screenshots. It is an
interactive, versioned visual contract that the product owner can inspect before
SwiftUI implementation. Pre-extraction milestones remain in TAPCamDemo Git
history; milestones after `TAP-0096` belong to TAPCamPrototype history. Task
revision history remains in the TAPCamDemo Project Board. The Kanban schema does
not need a separate `Partial` status to acknowledge a completed slice while the
broader foundation Task continues.

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
