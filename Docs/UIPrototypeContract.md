# TAPCam UI Prototype Contract

- Status: canonical UI design-to-implementation workflow
- Last updated: 2026-09-04

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

TAPCamDemo owns the Product Contract, native implementation, workflow, and
acceptance records. TAPCamKanban owns the Project Board. TAPCamPrototype owns the static prototype
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
[TAPCamKanban ProjectBoard.md](../../TAPCamKanban/ProjectBoard.md) across every status. It updates a matching
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
dashboard requirement. The route reducer, events, workloads, timing semantics,
playback behavior, and current-versus-target record meaning are owned once by
[StartupLifecycleContract.md](StartupLifecycleContract.md) §§1–5.2. The
prototype manifest owns the current executable records. This section owns only
their visual projection.

The supported desktop workbench has three simultaneous regions:

1. **One combined UI page directory and operation catalog** on the left. It
   contains Launch Screen, First-Install Setup, Required Permission Check,
   Resource Initialization, Viewfinder, TAP Library, Photo Viewer, and later
   approved surfaces. It must not create parallel approved-slice and lifecycle
   navigation. Selecting a surface reveals only its applicable simulation
   actions; these controls are inputs, not the state-machine visualization.
2. **iPhone visual truth** in the center. The app-owned canvas is exactly
   `393 x 852` CSS px and owns approved visible hierarchy, relative geometry,
   and spacing. A native page without a Web counterpart is first mapped
   one-to-one before redesign or parity claims. The iOS Launch Screen is the
   system-owned static-reference exception.
3. **Current-surface causality** on the right. It projects the selected trace's
   rules, lifecycle intervals, workload ownership, marker effects, machine
   changes, and bounded event log.

An uncovered surface may appear only as a disabled
**Pending — no approved slice** catalog entry. Settings has no approved
`TAP-0087` slice; a system Settings recovery boundary does not authorize an
app-owned preview, operation, copy, or geometry.

The current manifest records have exactly one of these visual treatments:

- **Implemented at target position; validation pending:** one yellow-background,
  red-border card or existing workload effect at the target anchor, with its
  follow-up Task. It has no duplicate actual card, blue target, mismatch label,
  or difference connector.
- **Task-owned behavior not migrated:** one red actual card at its recorded
  source anchor, the existing blue target when present, and exactly one red
  dashed actual-to-target connector. The visible and accessible label names the
  owning Task. No target effect is invented when the trace lacks one.

Every record has exactly one lane owner. Non-workload lifecycle truth uses the
existing **08/09 生命周期** lane; workload-owned truth uses the existing
**Workload** lane and never appears again as lifecycle truth. There is no second
comparison band or duplicate Workload lane. The controller reads records,
ownership, counts, effect selectors, and anchors from the manifest rather than
hardcoding a second catalog.

A red difference connector is a reviewer annotation, not a reducer edge,
machine transition, native timing measurement, or proof that current main emits
a canonical milestone. It is recomputed for scroll, filtering, resize, and
responsive reflow; a hidden or clipped card leaves no floating connector.
Connector SVGs are accessibility-hidden, while their cards state actual phase,
target phase, owner, and verdict without relying on color.

Implemented workload records decorate their exact existing effect selected by
event type, workload ID, status, and occurrence. They keep the canonical
`Eligible`, `Running`, or `Ready` state and focus action. Decorations cannot
promote state, imply regression completion, mutate a snapshot, or synthesize a
missing effect.

State machines render as directed node-edge flow diagrams with the current node,
active transition, and any recorded branch condition visible. The current
candidate is labeled **Executed reducer path** and draws only journaled edges;
a node vocabulary or array order is never presented as a legal transition
graph. The primary event projection is the existing timing-axis view; the
bounded ordered log is its alternate view of the same trace.

The Launch Screen remains a static iOS-owned reference and shows no progress or
measured duration. Deterministic Web delays are interaction fixtures only.
Controls deferred to child Tasks remain inert and identified by their owner;
their presence is not functional coverage.

The Viewfinder candidate preserves the current SwiftUI hierarchy one-to-one:
two-row top chrome, Dynamic Island clearance, rounded inset preview, FOV chips,
flexible middle space, professional-toolbar slot, capture row, and mode strip.
Its controls are visual truth only until `TAP-0088`; no prototype-only badge
redesigns the phone surface.

At the supported desktop reviewer viewport, the catalog/operations, phone
canvas, and inspector remain visible in one browser window without page-level
scrolling; dense regions may scroll internally. **Previous logical event**,
**Next logical event**, and **Reset** form one global row before Launch scenario
controls and are not duplicated inside contextual operations. Their reducer
semantics and action guards are defined in
[StartupLifecycleContract.md](StartupLifecycleContract.md) §5.2.

The approved `TAP-0081` Share slice remains a local presentation inside Photo
Viewer. This section preserves its visual placement only; its no-navigation,
no-startup-event, and system-boundary behavior is owned by
[ProductContract.md](ProductContract.md) §5.3 and
[StartupLifecycleContract.md](StartupLifecycleContract.md) §3.1.

The product owner approved the complete `TAP-0087-r1-candidate` v19 Web
composition on 2026-09-04. That approval establishes its visual intent and
simulated-state coverage only; it does not constitute native parity, regression
completion, measured timing, or device-performance evidence.

## 5. Evidence Levels

| Evidence | It can establish | It cannot establish |
| --- | --- | --- |
| Web prototype | Visual intent, relative layout, icon identity, simulated states and interaction | Native lifecycle, permissions, camera readiness, performance |
| Simulator | SwiftUI layout, navigation, localization, basic state transitions, some automation | Physical Camera/Photos/depth behavior, attended first-install flow, real-device performance |
| Physical device | System prompts, first preview frame, capture/depth lifecycle, haptics, thermal/performance and attended behavior | Behavior outside the executed procedure |

A physical-device gap receives a separate `DeviceAcceptance` Task with explicit
preconditions, numbered procedure, expected results, evidence outputs, and
human confirmation. Following Product Contract §8, each procedure names the
public-safe evidence it requires; its record includes build/device identifiers
and an owner-live textual verdict, with structured logs or JSON/JSONL and
automated assertion reports where applicable. A photo, screenshot, or screen
recording may be retained only when that specific owner-approved procedure
requires visual evidence. The TAP-0040/TAP-0041 startup lifecycle procedures
explicitly prohibit those image/video artifacts.

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

The sibling [TAPCamPrototype README](../../TAPCamPrototype/README.md) owns the
current repository entry and run path. Its
[reviewer guide](../../TAPCamPrototype/Prototype/README.md) and
[manifest](../../TAPCamPrototype/Prototype/manifest.json) own the current and
historical prototype entries, files, revisions, states, and approval mapping.
This workflow contract deliberately does not duplicate that changing file tree.

The prototype does not exist merely to produce screenshots. It is an
interactive, versioned visual contract that the product owner can inspect before
SwiftUI implementation. Pre-extraction milestones remain in TAPCamDemo Git
history; milestones after `TAP-0096` belong to TAPCamPrototype history. Task
revision history remains in the TAPCamKanban Project Board. The Kanban schema does
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
