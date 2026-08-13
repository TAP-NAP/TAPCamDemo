# TAPCam UI Prototype Contract

- Status: canonical UI design-to-implementation workflow
- Last updated: 2026-08-12

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
the 6.9-inch and, while the target remains Universal, iPad capture matrix,
device-frame decision, asset rights, locale order, export validation, and
submit-ready files.

Real Preview pixels, TAP Library thumbnails, 3D output, and credential-state
marketing evidence must come from a fixed runtime build and documented asset
chain. HTML, Sketch, placeholders, redrawn projection, or a deterministic Ready
fixture cannot substitute for those runtime sources.

Prototype or marketing localization does not silently change the app's runtime
locale contract. The current camera surface remains English until a separate
product/code Task changes and validates it; localized marketing wrappers may be
considered independently.
