# TAP-0048 — Approved Web Prototype To SwiftUI Parity

- Status: `Draft — blocked until an approved prototype Task/revision exists`
- Related Delivery: `TAP-0006`; the implementation Task named by the approved prototype
- Product Contract: `ProductContract §8–9`; `UIPrototypeContract §1–5`
- Prototype Task: `Required before execution`
- Prototype Path/Revision: `Required before execution`
- Prototype Owner Approval: `Required before execution`
- Build/Commit: `To be frozen after prototype approval`
- Device/iOS: `To be confirmed with the product owner`
- Simulator Matrix: `To be confirmed with the product owner`
- Date: `Unscheduled`
- Operator: `Unassigned`
- Human Confirmation: `Pending`

This procedure compares one approved, versioned HTML/Web visual contract with
its SwiftUI implementation. A Web fixture can prove visual intent and simulated
state coverage only. It is never evidence that Camera, Photos, permissions,
depth, capture, signing, export, haptics, accessibility, performance, or device
lifecycle actually works.

## Preconditions

- The Project Board contains an approved prototype Task and the implementation
  Task being accepted. Both IDs are recorded above.
- The repository-owned prototype manifest records its path, immutable revision,
  covered Product Contract states, approved viewports, component hierarchy,
  icon identities, relative geometry, spacing, responsive rules, and explicitly
  out-of-scope states.
- **OWNER-LIVE:** the product owner has approved that exact prototype revision.
  An undated screenshot, local working copy, old Sketch file, or Agent-selected
  Web state is not a baseline.
- The candidate SwiftUI build identifies the code revision that implements the
  approved prototype and provides a mapping from each approved state to a
  deterministic Simulator setup or a documented real runtime path.
- The owner has approved the Simulator/device/viewport/state matrix. This draft
  intentionally invents no screen sizes, tolerance, pixel threshold, Dynamic
  Type matrix, locale matrix, or visual-diff budget.
- System-owned controls and native SF Symbols are identified in the comparison
  sheet. Web rendering is an optical reference; the SwiftUI result retains
  native semantics and is not replaced with a fake Web-like control.
- Screen capture, Simulator result collection, and device recording are ready.

## Reset / Install Procedure

1. Record the approved prototype Task, repository path, commit/revision,
   manifest, approval date, covered states, and approved viewports.
2. Produce read-only reference captures directly from that frozen revision.
   Do not manually redraw or edit the captures after approval.
3. Build the frozen SwiftUI candidate and record its commit and configuration.
4. Reset/install the candidate on every owner-approved Simulator. Install the
   same signed build on every approved physical device needed by the matrix.
5. Prepare each deterministic SwiftUI state through the documented fixture or
   navigation path. Label fixture-backed and real-runtime states separately.
6. Start paired capture and create one empty parity row for every approved
   prototype state × viewport cell before visual review begins.

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Verify the frozen prototype manifest against its Project Board Task and Product Contract state list. | Every reviewed screen/state has one stable Task, revision, state name, viewport, and contract mapping; no deprecated or unapproved state is silently included. | `Pending` | `Pending` |
| 2 | Open each approved Web state from the frozen revision and capture its hierarchy, visible controls, icon names, relative positions, spacing, sizes, selected/loading/error/empty presentation, and simulated transition endpoints. | The captured reference matches the owner-approved revision and contains no post-approval manual edits. | `Pending` | `Pending` |
| 3 | Render the corresponding SwiftUI state on each approved Simulator viewport and compare it side by side with the reference. | Component grouping, hierarchy, native icon identity, relative geometry, spacing, safe-area intent, visibility, emphasis, and responsive relationship conform to the approved prototype or carry an owner-approved documented exception. | `Pending` | `Pending` |
| 4 | Exercise every approved simulated navigation and state transition in Web, then perform the corresponding SwiftUI interaction. | Start state, user action, destination/state, enabled/disabled behavior, and persistent chrome agree with the prototype and Product Contract. No deprecated interaction is restored. | `Pending` | `Pending` |
| 5 | Exercise every approved loading, failure, empty, selected, and disabled state in SwiftUI using its documented setup. | SwiftUI presents each approved state without fixture leakage, placeholder-only production content, layout collapse, or a state invented outside the approved revision. | `Pending` | `Pending` |
| 6 | Inspect every system-owned control and SF Symbol mapping on SwiftUI. | The intended native control or symbol is used where applicable. Optical platform differences are documented; SwiftUI is not changed into a non-native imitation merely to match browser pixels. | `Pending` | `Pending` |
| 7 | Run the same visual/navigation matrix on each owner-approved physical device. | Native layout, safe-area behavior, control reachability, transitions, and state presentation remain consistent with the approved relationship contract and the accepted Simulator result. | `Pending` | `Pending` |
| 8 | For any state that claims a physical runtime fact, reach it through the documented real device path rather than the Web/SwiftUI fixture. | Real system permission, camera first frame, Photos content, depth, capture, haptic, or lifecycle claims are supported only by their linked DeviceAcceptance evidence. A visually correct fixture is labeled visual-only. | `Pending` | `Pending` |
| 9 | Record every mismatch and classify it as implementation defect, approved native-platform variance, prototype revision request, or Product Contract conflict. | No Agent silently changes the prototype or Product Contract. Conflicts return to the associated Task; accepted variance has explicit owner disposition. | `Pending` | `Pending` |
| 10 | **OWNER-LIVE:** review the final side-by-side matrix and all exceptions. | The owner either accepts the specific prototype/build pair or keeps acceptance Pending with named mismatches. | `Pending` | `Pending` |

## Required Evidence

- Logs: navigation/state identifiers and fixture-versus-runtime provenance for
  every compared SwiftUI state.
- Screenshots/recording: frozen Web references, matching Simulator captures,
  physical-device captures, and attended interaction recordings organized by
  Task/revision/state/viewport.
- Output artifacts: prototype manifest and approval record, SwiftUI mapping
  sheet, completed parity matrix, and documented exception dispositions.
- Result bundles: frozen prototype and code commits, Simulator UI test bundles
  where used, device/build/iOS identifiers, and links to separate runtime
  acceptance evidence.
- **OWNER-LIVE:** explicit acceptance of the prototype revision, every native
  variance, and the final SwiftUI implementation pair.

## Verdict Conditions

- **Pass:** all cells in the owner-approved matrix match the approved visual and
  interaction relationships or have explicit accepted native variances; no
  Product Contract conflict remains; runtime claims link to real runtime
  evidence; and the owner accepts the exact prototype/build revisions.
- **Fail:** SwiftUI drifts from hierarchy, icon identity, relative geometry,
  navigation, or approved state presentation; deprecated UI returns; a mismatch
  is hidden by changing the baseline; a fake control replaces native behavior;
  or a Web/SwiftUI fixture is presented as runtime evidence.
- **Blocked:** no approved prototype Task/revision exists; the implementation
  Task or frozen build is missing; the owner has not approved the comparison
  matrix or variance policy; a platform conflict requires a product decision;
  required device/runtime evidence is unavailable; or the owner cannot attend.

## Human Confirmation

`Pending — OWNER-LIVE must accept the exact prototype revision and SwiftUI build`
