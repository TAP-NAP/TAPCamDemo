# TAP-0048 — Approved Web Prototype To SwiftUI Parity

- Status: `Evidence in progress — frozen Web/native revisions and device acceptance exist; complete Simulator parity matrix remains pending`
- Related Delivery: `TAP-0081`; prototype foundation `TAP-0006`
- Product Contract: `ProductContract §5.2–5.3, §6, §9`; `UIPrototypeContract §1–5`
- Prototype Task: `TAP-0081`
- Prototype Path/Revision: `Prototype/index.html`; `TAP-0081-r1` and `TAP-0081-r2-candidate`; source commit `70e8b60`
- Prototype Owner Approval: `ownerApproved` on `2026-08-12` and `2026-08-13`
- Build/Commit: `bf20b52452512aefe745624bd9f80c09355abae5`
- Device/iOS: `TAP-0082 accepted on iPhone 15 Pro / iOS 26.6`
- Simulator Matrix: `Pending owner confirmation for the frozen candidate build`
- Date: `2026-08-12`
- Operator: `Codex development session /root; owner audit pending`
- Human Confirmation: `Pending`

This record instantiates the generic Web-to-SwiftUI comparison for the first
approved vertical slice: TAP Share revision `TAP-0081-r1`. It compares that
versioned HTML/Web visual contract with the frozen TAP-0081 SwiftUI delivery.
The owner has accepted the physical-device Share flow under TAP-0082, while the
full TAP-0048 Simulator state/viewport comparison remains deliberately open.
A Web fixture can prove visual intent and simulated
state coverage only. It is never evidence that Camera, Photos, permissions,
depth, capture, signing, export, haptics, accessibility, performance, system
share destinations, or device lifecycle actually works.

The approved interaction is one stable app-owned surface anchored to Share.
Selection, preparation, Cancel, public-safe failure, and Retry replace one
another inside that same surface. After a selected payload becomes ready, the
popover disappears and exactly one system-owned activity controller is
presented. The Web prototype deliberately stops at that native system boundary.

## Preconditions

- **Met:** the Project Board names `TAP-0081` as the implementation Task and
  `TAP-0006` as its prototype-foundation dependency.
- **Met:** `Prototype/manifest.json` at source commit `70e8b60` freezes approved
  revisions `TAP-0081-r1` and `TAP-0081-r2-candidate`, their covered
  Photo/Live Photo/TAP Video fixtures, three credential states, selection,
  hidden-fast, visible-progress, 100%-handoff, Cancel, failure, Retry, native
  symbol intent, responsive review viewport, and explicit non-goals.
- **Met — OWNER-LIVE:** the product owner approved exact revision
  `TAP-0081-r1` on 2026-08-12. An undated screenshot, local working copy, old
  Sketch file, or Agent-selected Web state is not the baseline.
- **Met:** native delivery is frozen at `bf20b52`; focused behavior/build and
  TAP-0082 physical-device acceptance are recorded by their owning Tasks.
- **Pending:** map every approved state to the complete owner-confirmed
  Simulator/viewport matrix and capture its side-by-side parity evidence.
- **Pending — OWNER-LIVE:** approve the Simulator/viewport/state matrix. This
  record intentionally invents no tolerance, pixel threshold, Dynamic Type
  matrix, locale matrix, or visual-diff budget.
- System-owned controls and native icon assets or SF Symbols are identified in
  the comparison sheet. Web rendering is an optical reference; the SwiftUI
  result retains native semantics and is not replaced with a fake Web-like
  control.
- Simulator screen capture and result collection must be ready before executing
  the remaining matrix. Physical-device acceptance is recorded by completed
  `TAP-0082`; this record does not manufacture additional device artifacts.

## Candidate SwiftUI Mapping

This mapping describes the implementation seam to inspect; it is not a parity
verdict.

| Approved responsibility | SwiftUI candidate | Evidence state |
| --- | --- | --- |
| Stable Share toolbar leaf shared by Photo, Live Photo, and TAP Video | `DepthViewerShareControl` mounted from the shared Viewer chrome | `Implemented in bf20b52; complete parity cell pending` |
| App-owned anchored selection/preparation/failure surface | `DepthAnalysisSharePopover` using native popover adaptation and stable in-place state layers | `Implemented in bf20b52; complete parity cell pending` |
| Frozen media subject, credential state, preparation timing, cancellation, Retry, stale-callback rejection, and payload lease | `DepthAnalysisShareCoordinator` | `Focused tests passed; complete parity cell pending` |
| Exact Share/Delete template vectors, Back-matched circular backgrounds, compact centered mode capsule, and additive Share progress ring | `ViewerToolbarIconButton` plus `DepthViewerModeCapsule` in the shared Viewer chrome | `Owner device result accepted under TAP-0082; Simulator parity cell pending` |
| One subsequent native system destination chooser | sibling `VerificationExportActivityView` presentation after popover disappearance | `Owner device result accepted under TAP-0082; Simulator parity cell pending` |

The candidate must preserve the contract rather than merely resemble the Web
pixels: resources are prepared only after selection; Share never contacts the
TAP backend or repeats App Attest verification, while the frozen downloaded
    original must pass local proof/content binding before it is labeled Verified
    in this owned-capture Share flow; this state does not independently verify
    App Attest assertion authenticity without the backend-held public key;
progress is hidden for the first 50 ms and, once
visible, held for at least 400 ms with monotonic advancement; and no package is
pre-generated, background-prewarmed, or retained as a persistent cache.

## Reset / Install Procedure

1. Confirm `Prototype/manifest.json` names the owner-reviewed revision. The
   previously approved `TAP-0081-r1` remains the geometry baseline; exact
   `TAP-0081-r2-candidate`, including local-integrity states and the refined
   toolbar geometry, was owner-approved on 2026-08-13.
2. Produce read-only Web reference captures directly from that revision. Do not
   manually redraw or edit them after approval.
3. Freeze the SwiftUI candidate commit and record scheme, configuration,
   Simulator model, iOS runtime, and locale.
4. Reset/install that build on every owner-approved Simulator in the comparison
   matrix. The separate physical-device run has already completed under
   `TAP-0082`.
5. Prepare each deterministic SwiftUI credential/media/preparation state through
   a documented fixture or real runtime path. Label fixture-backed and runtime
   states separately.
6. Create one empty parity row for every approved state × Simulator viewport,
   then capture Web and SwiftUI results side by side.

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Verify the frozen prototype manifest against TAP-0081 and Product Contract §5.3/§6. | Every reviewed state has one revision, media kind, credential state, viewport, and contract mapping; no deprecated modal Share sheet or direct-share path is included. | `Pending` | `Pending` |
| 2 | Capture the approved geometry from `TAP-0081-r1` and the approved original-readiness/local-integrity states from `TAP-0081-r2-candidate`. | The references preserve the stable Viewer hierarchy while adding Share-disabled iCloud loading, the text-free local-check skeleton, and Failed direct-media warning. Both exact revisions are recorded as owner-approved. | `Pending` | `Pending` |
| 3 | Open Share from Photo, Live Photo, and TAP Video in the SwiftUI candidate. | The same native Share control and anchored popover appear for all three media kinds without remounting the pager, media surface, video player, toolbar, or chrome. | `Pending` | `Pending` |
| 4 | Exercise Viewer original loading plus Verified, Needs Retry, and Failed fixtures. | Share stays disabled until the complete local/iCloud original is ready. Opening Share freezes that resource and runs only local proof/content-binding validation; it never calls backend/App Attest Verify. Photos without a queue record can become Verified from embedded identity; Needs Retry remains queue-only. | `Pending` | `Pending` |
| 5 | Compare format rows, native icons, copy, enabled states, and Coming Soon boundaries for all media kinds. | Locally valid Still/Live expose TAPNAP Package and Share Image; a local mismatch disables Package but retains Image/Video with an explicit unverifiability warning. Video Package remains Coming Soon; Sticker and Link remain disabled. Native icon assets and SF Symbols match their respective manifest intent, including the exact Share/Delete vector geometry. | `Pending` | `Pending` |
| 6 | Run a preparation that completes within 50 ms. | Selection hands off without inserting progress UI. No row flash, blank frame, toolbar rebuild, or full-screen loading state appears. | `Pending` | `Pending` |
| 7 | Run threshold and slow preparations while recording timing and progress updates. | Progress appears only after 50 ms in the same anchored surface, never regresses, reaches 100%, and remains visible for at least 400 ms once revealed. The Share glyph remains fixed and its ring is additive. | `Pending` | `Pending` |
| 8 | Cancel visible preparation, exercise a controlled failure, and Retry the same option. | Cancel stops the attempt and returns to selection; failure remains in the anchored surface with public-safe copy; Retry restarts only the failed option. No stale callback or prior artifact affects the new attempt. | `Pending` | `Pending` |
| 9 | Complete a ready payload and dismiss the system presentation. | The app-owned popover disappears before exactly one native system activity controller appears. Dismissal returns to the unchanged Viewer; per-attempt temporary resources are cleaned. No persistent share cache is created. | `Pending` | `Pending` |
| 10 | Inspect localized copy, accessibility identifiers/values, Reduce Motion behavior, material, geometry, spacing, and native-platform variances on each approved Simulator viewport. | The native result preserves the approved component relationships and semantics; documented optical platform differences do not become Web imitation controls. | `Pending` | `Pending` |
| 11 | Record every mismatch and classify it as implementation defect, approved native-platform variance, prototype revision request, or Product Contract conflict. | No Agent silently changes the prototype or Product Contract; every accepted variance has explicit owner disposition. | `Pending` | `Pending` |
| 12 | **OWNER-LIVE:** review the final side-by-side Simulator matrix and exceptions. | The owner either accepts the exact r1-geometry/r2-behavior prototype plus build pair for TAP-0048 or keeps this parity Task Pending with named mismatches. The already accepted TAP-0082 device verdict remains separate evidence. | `Pending` | `Pending` |

## Required Evidence

- Logs: Share presentation/preparation/handoff state identifiers, timing,
  monotonic progress, cancellation/cleanup, and fixture-versus-runtime
  provenance for every compared SwiftUI state.
- Screenshots/recording: frozen Web references and matching Simulator captures
  organized by Task/revision/state/viewport. Physical-device captures and
  attended interaction recordings are evidence for `TAP-0082`, not this run.
- Output artifacts: prototype manifest and approval record, SwiftUI mapping
  sheet, completed parity matrix, and documented exception dispositions.
- Result bundles: frozen prototype and code commits, Simulator UI test bundles
  where used, build/Simulator/iOS identifiers, and a link to the completed
  `TAP-0082` device-acceptance record.
- **OWNER-LIVE:** explicit acceptance of the prototype revision, every native
  variance, and the final SwiftUI implementation pair.

## Verdict Conditions

- **Pass:** all cells in the owner-approved matrix match the approved visual and
  interaction relationships or have explicit accepted native variances; no
  Product Contract conflict remains; Simulator/runtime claims are bounded to
  the evidence actually gathered; the owner accepts the exact prototype/build
  revisions; and physical-device claims remain bounded to the accepted
  `TAP-0082` record rather than inferred from Simulator evidence.
- **Fail:** SwiftUI drifts from hierarchy, icon identity, relative geometry,
  navigation, or approved state presentation; deprecated UI returns; a mismatch
  is hidden by changing the baseline; a fake control replaces native behavior;
  or a Web/SwiftUI fixture is presented as runtime evidence.
- **Blocked:** the frozen implementation build is missing; the owner has not
  approved the comparison matrix or variance policy; a deterministic state
  cannot be reached; a platform conflict requires a product decision; required
  Simulator evidence is unavailable; or the owner cannot attend the audit.

## Human Confirmation

`Pending for the complete TAP-0048 Simulator parity matrix. Exact r1/r2 Web
revisions and native bf20b52 are frozen, and physical-device Share acceptance
is complete under TAP-0082; those facts do not silently complete this separate
matrix audit.`
