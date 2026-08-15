# TAP-0008-r2 / TAP-0081-r3 / TAP-0009-r1 Owner-Approved Slice Design QA

- Source visual truth:
  - `assets/references/tap-share-format-selection.png`
  - `assets/references/tap-share-preparing.png`
  - owner-approved `TAP-0081-r2-candidate` geometry, resource states, local
    integrity states, and anchored app-owned popover
- Implementation: `index.html` served at `http://localhost:4173/`
- Source pixels: `853 x 1844` for each owner-selected reference
- Implementation viewport: `393 x 852` CSS px, `devicePixelRatio = 1`
- Implementation pixels: `393 x 852` per state capture
- Density normalization: each source reference was downsampled to `393 x 852`
  for the combined comparisons listed below. The Web frame is a relationship
  reference and does not claim native pixel identity.
- Inherited browser evidence: `TAP-0081-r2-candidate`, Codex in-app Browser on
  2026-08-13
- Current r3 evidence: static contract test plus Chrome bounding-box comparison
  and exact owner visual approval on 2026-08-14

## Approval boundary

The product owner approved exact first-install revision
`TAP-0008-r2-candidate` on 2026-08-13 with “现在原型已经确认没有问题”. Its
visible hierarchy, copy, exact SF Symbol identities, explicit-action
transitions, and system-owned UI boundary are SwiftUI visual authority. This
prototype-only migration composes that independently approved slice with the
current TAP-0081-r3 and TAP-0009-r1 sources without revising either slice.

The product owner approved exact visual revision `TAP-0081-r2-candidate` on
2026-08-13 with “已确认没有问题 请继续实施 Swift UI”. On 2026-08-14 the owner
directed the r3 lifecycle delta: implemented share types show preparation
as a thin track replacing the selected option's subtitle text inside the exact
same fixed-height slot while every other row remains visible but disabled. The
title, icon, badge, row height, popover dimensions, and sibling positions do not
move; subtitle text and progress are not shown together, and no percentage or
Cancel control is inserted. No independent preparation page, artificial reveal
delay, or minimum-visible hold is inserted; payload readiness ends the app-owned
popover, and no completed/system dismissal page is simulated. The owner approved
exact `TAP-0081-r3-candidate` with “对的 现在原型是我想要的”; the prior approval
continues to govern inherited geometry and states.

## Captures and combined comparisons

- Resource loading:
  - `evidence/TAP-0081-r2-candidate-resource-loading-full.png`
  - `evidence/TAP-0081-r2-candidate-resource-comparison.png`
- Local integrity resolving skeleton:
  - `evidence/TAP-0081-r2-candidate-integrity-checking-full.png`
  - `evidence/TAP-0081-r2-candidate-integrity-comparison.png`
- Failed-integrity degradation:
  - `evidence/TAP-0081-r2-candidate-failed-integrity-full.png`
  - `evidence/TAP-0081-r2-candidate-selection-comparison.png`

These r2 combined comparisons remain evidence for the geometry and states that
r3 deliberately inherits. They are not represented as new r3 lifecycle
captures.

## Full-view comparison

The r3 candidate preserves the approved Viewer hierarchy: full-screen media,
bottom-left Share, centered `RAW / 2D / 3D`, bottom-right Delete, and a compact
material surface anchored above Share. The r1 Share control, toolbar, popover
anchor, popover width, and option-row rhythm are unchanged. The selected row does
not expand; its fixed-height subtitle slot swaps text for an absolutely positioned
thin track and contributes no new layout size.

The incremental states preserve that geometry:

- iCloud loading stays in the Viewer and dims, rather than removes or replaces,
  the stable Share control. The Viewer shows determinate original-resource
  progress and no credential label.
- Opening Share on a ready original first shows a text-free skeleton within the
  existing popover footprint. It exposes no fourth credential state.
- Failed integrity keeps the same four-row selector. TAPNAP is disabled; Share
  Image remains enabled with `无法保证可验证性` in its subtitle.

## Focused state and interaction review

- `Local · Ready` and `iCloud · Ready` enable Share.
- `iCloud · Loading` and `iCloud · Unavailable` disable Share before popover
  presentation and keep the resource state separate from credential failure.
- `Private queue` is the only fixture that enables `待重试`; Photos/iCloud
  fixtures cannot select it.
- The resolving skeleton contains only accessibility text outside the visual
  canvas. `#credential-label` and the selector are hidden until resolution.
- Failed Photo/Live Photo disables `tapnapPackage` while keeping `image`
  enabled. Failed Video keeps `videoPackage` disabled and `video` enabled with
  the same unverifiability warning.
- Selecting TAPNAP Package, Share Image, or Share Video keeps all four selector
  rows visible and replaces only the selected row's subtitle text with determinate
  progress inside the same slot in the same event turn. The icon, title, badge,
  row box, and popover box remain unchanged. The other rows become disabled
  without disappearing, and progress remains monotonic.
- Progress displays neither percentage text nor a Cancel control.
- There is no independent preparation panel or full-popover preparation state.
- Payload readiness closes the app-owned popover immediately. There is no
  `资料已准备完成` panel, no `模拟系统页关闭` action, and no artificial
  post-completion hold.
- The real iOS activity controller exists only as explanatory boundary copy in
  the review controls; the phone surface does not imitate it.
- The script contains no `fetch`, `XMLHttpRequest`, `WebSocket`, backend Verify
  route, or persistent browser storage. iCloud and integrity are deterministic
  visual fixtures only.

## Preparation geometry measurement

Chrome `getBoundingClientRect()` measurements compared selector state with the
live determinate preparation state on 2026-08-14. The TAPNAP Package and Share
Image paths both returned exact structural equality for the popover, all four
row wrappers/buttons, and every icon/title/subtitle-slot/badge box.

| Surface | Before `[x, y, width, height]` | Preparing | Result |
| --- | --- | --- | --- |
| Popover | `[891.5, 456.8828125, 288, 337]` | identical | exact |
| TAPNAP row | `[908.5, 519.8828125, 254, 65]` | identical | exact |
| Share Image row | `[908.5, 584.8828125, 254, 65]` | identical | exact |
| Sticker row | `[908.5, 649.8828125, 254, 65]` | identical | exact |
| Share Link row | `[908.5, 714.8828125, 254, 64]` | identical | exact |
| TAPNAP subtitle slot | `[952.5, 556.8828125, 175.4921875, 14]` | identical | exact |
| Share Image subtitle slot | `[952.5, 621.8828125, 200, 14]` | identical | exact |

The selected subtitle text was absent while preparing, the 2 px determinate
track occupied that same slot, every option was disabled but remained visible,
and neither percentage text nor a Cancel control existed. A Share Image sample
observed progress value `0.32` without any geometry delta.

## Required fidelity surfaces

- Fonts and typography: the existing Apple/system stack, status hierarchy,
  option-title weights, and subtitles are unchanged. The preparation track adds
  no text.
- Spacing and layout rhythm: the 393 x 852 Viewer, bottom toolbar, 42 px Share
  control, 288 px popover, 19 px radius, caret, and base row heights/dividers
  remain inherited from r1. The selected row and every sibling retain the same
  footprint because the track is an absolute overlay.
- Colors and visual tokens: existing dark material, semantic green/orange/red,
  iOS blue, dividers, and disabled opacity remain unchanged. Resource progress
  reuses the existing blue progress token.
- Image and asset fidelity: the same full-resolution rainy-street fixture is
  reused. Existing vendored icons remain optical Web analogues; no rasterized UI,
  emoji, inline SVG, or CSS-drawn product icon was added.
- Copy and content: visible states use `已验证 / 待重试 / 失败` only. Failed
  ordinary media says `无法保证可验证性`; no proof data, hash, ID, validator
  detail, backend verdict, or external Verify action is exposed.
- Accessibility: Share retains its location and a descriptive disabled/busy
  state during loading; resource progress uses native `progress`/`output`; the
  resolving skeleton has a screen-reader label but no visible fourth status;
  disabled controls remain semantic buttons; reduced motion removes skeleton
  pulsing.

## Viewer toolbar icon geometry

The product owner explicitly selected the prototype toolbar icons, circular
backgrounds, and their relative placement as the native replacement target.
The corresponding machine-readable values now live in
`manifest.json.viewerToolbarVisualSpec`, and the CSS consumes named tokens
rather than restating the numbers at each rule.

- Share and Delete each use a 42 x 42 px circular control, matching the visible
  Back control reference in the prototype.
- Each vector is rendered in a 20 x 20 px icon box whose geometric center is
  exactly the circular background center; there is no CSS translation.
- The toolbar uses 16 px side insets and a 25 px bottom inset. Its middle mode
  capsule stays compact at 140 px and remains centered between equal flexible
  gaps; it does not stretch to consume the remaining width.
- Native parity uses the exact template vector assets `share-network.svg` and
  `trash.svg`. Substituting independently sized SF Symbols would not preserve
  the accepted silhouette or optical balance.
- The SVG artwork is not mathematically centered within each 256-unit viewBox:
  Share's artwork center is 0.625 CSS px left at the approved 20 px size, and
  Delete's is 0.625 CSS px above. These are intrinsic, owner-approved optical
  balances, not extra layout offsets. SwiftUI should center the vector viewport
  and must not add a second compensating translation.

## Findings and comparison history

- Initial candidate capture showed the document scrollbar over the 393 x 852
  mobile review surface. Fixed by hiding only the document scrollbar at the
  phone breakpoint, then recapturing all three states at the same viewport.
- Initial test design allowed the queue-only credential option to be visible as
  a general fixture. Fixed by disabling `待重试` unless `Private queue` is the
  selected resource source and by recording the invariant in the state fixture
  and static test.
- The prior r2 comparison found no remaining actionable P0/P1/P2 geometry
  difference. R3 intentionally removes the post-ready boundary panel and the
  timing fixtures; exact r3 visual approval is recorded. Native material
  optics, PhotoKit/iCloud activity, cryptographic work, and the real system
  activity controller remain native evidence boundaries.

## Implementation checklist

- [x] Preserve r1 Viewer and popover geometry.
- [x] Cover local/iCloud ready, loading, unavailable, and private-queue sources.
- [x] Cover text-free local integrity resolving without a fourth public state.
- [x] Cover Failed package disable plus warned ordinary-media sharing.
- [x] Restrict Needs Retry to the private queue fixture.
- [x] Keep backend Verify, package pre-generation, and persistent caching absent.
- [x] Make preparation progress immediate for every implemented share type.
- [x] Keep the selector and all non-selected rows visible during preparation;
  disable non-selected rows and replace only the selected subtitle text with
  progress inside that same slot.
- [x] Preserve all row/popover bounding boxes, selected title/icon/badge, and
  sibling positions; show subtitle text or progress, never both, and show neither
  percentage nor Cancel UI.
- [x] Remove the independent preparation panel.
- [x] Remove reveal-delay, minimum-hold, completed-page, and simulated-dismissal
  behavior from the prototype.
- [x] End the app-owned popover when the fixture payload becomes ready while
  keeping the system activity controller as explanatory copy only.
- [x] Run the static prototype contract test.
- [x] Obtain exact owner visual approval for `TAP-0081-r3-candidate`.

current result: static contract and browser geometry checks passed; owner visual approval recorded

## TAP-0008 first-install setup QA

- Revision: exact `TAP-0008-r2-candidate`; approval status `ownerApproved`.
- Brand correction: the temporary `TAPCAM` text mark was removed. The header
  uses an exact copy of
  `TAPCamDemo/Assets.xcassets/LaunchLogo.imageset/launch_logo@3x.png` with SHA-256
  `ec4a28fb75b3c3fb87b036c3f0885e169857fab950c163efeca1e53958e0c236`.
- Owner-comment revision on 2026-08-13:
  - Subtitle changed to `在使用之前请先容许我们使用必要的权限`.
  - Location and Microphone titles changed to `位置访问(可选)` and
    `麦克风访问(可选)`.
  - All five placeholder glyphs were removed.
- Icon fidelity: Web assets are 2x exports of the exact code-owned SF Symbol
  identities and configuration (`19 pt`, semibold, `34 pt` container): `wifi`,
  `camera`, `photo.on.rectangle`, `location`, and `mic`. Their paths and
  SHA-256 values are machine-readable in `manifest.json`; Unicode
  approximations are an explicit contract violation.
- Visible states: untouched, camera request initiated by its own Allow action,
  network failure with row-scoped Retry, and required checks ready with the
  optional checks represented as skipped.
- Entry behavior: the untouched fixture contains no automatic request,
  preflight, observer activation, camera start, or background work.
- Action isolation: each row owns one explicit operation. An individual Allow
  action changes only that row; Location and Microphone additionally own Skip.
- Continue boundary: only Network, Camera, and Photos are required. Location
  and Microphone do not block Continue and may remain idle, be granted, or be
  skipped.
- System boundary: the prototype describes the transition after a user action
  but never imitates an iOS permission sheet.
- Flow boundary: Continue routes to the separate TAP-0009 Resource
  Initialization slice rather than directly to the camera.
- Browser evidence: Codex in-app Browser at desktop review size and exact
  `393 x 852` mobile viewport; no console warnings or errors.
- Captures:
  - `evidence/TAP-0008-r2-candidate-untouched-full.png`
  - `evidence/TAP-0008-r2-candidate-untouched-phone.png`
  - `evidence/TAP-0008-r2-candidate-camera-request-full.png`
- Owner approval recorded on 2026-08-13: “现在原型已经确认没有问题”.

final result: passed visual prototype gate

## TAP-0009 resource-initialization candidate QA

- Visual source: the repository's current `CameraInitialReadinessOverlayView`
  and the historical post-Continue full-screen preparation state.
- Visible states exercised: Preparing, Camera ready / catalog pending, catalog
  ready / camera pending, and both ready followed by camera handoff.
- Interaction result: returning to TAP Share restores the Viewer with its
  popover closed; startup state never exposes Viewer controls underneath it.
- Console result: no warnings or errors across the complete state path.
- Boundary result: the fixture waits only for camera interactive readiness and
  one usable Library metadata snapshot. It contains no network, PhotoKit media
  download, thumbnail decode, hash, ZIP, App Attest, or persistent cache code.
- Product policy: no Failed, Retry, timeout, or degraded-entry surface.
  Abnormal noncompletion remains on the stable initialization UI and emits
  developer diagnostics. Exact visual approval was recorded on 2026-08-13.
- Approval: exact `TAP-0009-r1-candidate` approved by the product owner on
  2026-08-13 with “原型我检查了 没有问题”. Native implementation and device
  acceptance remain separate evidence.

final result: passed

## TAP-0087-r1 startup-lifecycle candidate QA

- Task: `TAP-0087`; P0 prerequisite for `TAP-0008`, `TAP-0009`, and
  `TAP-0083`.
- Candidate entry: `startup-lifecycle.html`.
- Shared-tree revision: `v16`.
- Verification pass: `v16b`.
- Status: `candidate`; `ownerReviewRequired`. Exact owner approval of the v16
  TAP-0087 composition and synchronized lifecycle contract is pending. The
  existing TAP-0008-r2, TAP-0009-r1, and TAP-0081-r3 approvals remain
  independent and do not approve this workbench revision.

### v16 contract represented

- The workbench uses one UI surface catalog with contextual legal operations,
  one `393 x 852` app-owned preview, and one lifecycle/workload/state inspector.
  Previous, Next, and Reset share one playback row before Launch scenario
  controls and are not repeated as contextual actions.
- The target state authority remains `startup-model.mjs`. Phone state, legal
  operations, timing swimlane, executed node-edge path, marker effects,
  workload focus, ordered log, Previous, and Next are projections of the same
  reducer trace and complete reviewer snapshots.
- A machine graph contains only node-edge transitions observed in the reducer
  journal. `machineRegistry.nodes` is a node vocabulary, not a transition
  registry; array order is never treated as a legal edge. Timing causality is
  likewise derived only from real trace effects.
- Workload records compare
  `observed { trigger, owner, earliest, blocks, network, evidence }` with
  `target { trigger, owner, earliest, blocks, network, evidence }`, plus an
  alignment result. `t0…t5` are target reducer milestones. Any current-main
  `t*` association is source-order inference, not device timing evidence.
- The JSON source catalog contains 14 truths: 12 mismatches and 2 aligned facts.
  The default **08 / 09 真值** panel now lists only the six lifecycle-owned
  mismatches plus the two aligned facts; the six workload-owned mismatch truths
  render only in the Workload lane. Red comes from the explicit `mismatch`
  field, never a parsed phase string or generic workload `gap` label.
- Each mismatch also carries a JSON `fix0809Disposition`. Eleven lifecycle
  truths are `approvedToFix`; `networkBootstrap` is the one
  `deferredFrozen` lifecycle truth. Workload children may narrow their parent:
  nine are approved and the first-install credential, Network completion,
  post-setup App Attest, and credential/network-dependent Pending records are
  frozen. Both dispositions remain red mismatches; neither rewrites current
  `/healthz` behavior as the target or approves the complete v16 composition.
- Every visible red record has one red dashed SVG path to its explicit
  current-main `actual.anchor` circular `t0…tn` node. The card separately shows
  the target anchor/phase. Connectors are decorative review annotations, not
  reducer transitions, and are recomputed after scroll, filter, resize, and
  responsive reflow.
- Timing gives each mismatch one owner. The reviewer-only **08/09 生命周期**
  lane contains only the six non-workload mismatch truths; workload-owned truth
  is excluded there. A lifecycle red card appears only after its actual
  milestone and keeps one dashed path to that circular Timing anchor.
- The 14 lifecycle-truth records and 13 workload-difference records have one
  JSON authority in `manifest.json`; `startup-model.mjs` loads them through a
  shallow top-level shape gate instead of embedding a second list or count. The
  test suite validates record fields, IDs, ownership, bindings, uniqueness, and
  replay resolution. A failed reviewer-data load or top-level shape gate yields
  empty comparison registries without preventing reducer/model import.
- The existing **Workload** lane owns 10 timing and 3 semantic workload
  differences. Each JSON record declares its applicable scenario group, real
  source trigger, reviewer visibility/upstream checkpoint, and exact prototype
  event/workload/status binding. The focusable red **实际 · 不一致** annotation
  stays in that JSON-selected projection column and labels the real trigger;
  the column is not claimed as the current-main execution event. When the exact prototype workload effect has been recorded, that
  existing trace element becomes blue and one dashed path connects the two;
  the target decoration never creates a second causal event.
- There is no standalone workload-comparison band, fixed duplicate axis, or
  second Workload lane. If the exact target effect is absent, the red actual
  card says **既有 trace effect 尚未出现**; no synthetic blue target, connector,
  event column, milestone, workload transition, marker effect, or phone-state
  mutation is created. Target lifecycle `tN` reachability is shown separately
  from the existing workload effect's own `Eligible` / `Running` / `Ready`
  status.
- Viewfinder mirrors the current SwiftUI hierarchy and relative geometry. Its
  controls remain functionally deferred to TAP-0088; there is no
  prototype-only mock badge.
- Photo Viewer mounts the independently approved TAP-0081 Share presentation
  locally on the same page. Share does not enter the TAP-0087/TAP-0008/TAP-0009
  reducer, event, workload, timing, or marker model. Payload readiness closes
  only the app-owned presentation and records a system boundary; neither an
  activity sheet nor AirDrop is simulated.
- Settings remains only a pending catalog entry because there is no approved
  slice. No Settings phone preview, copy, geometry, or action is inferred.

### Stale evidence boundary

All earlier TAP-0087 captures through v16a and v10/v11/v12 measurements are
historical for the v16b disposition pass. The v16a capture still supports its
trace-binding observations, but it predates the disposition badges and cannot
prove their layout, accessible copy, or connector reflow. This also includes
the old `1600 x 941` screenshot and SHA,
page/inspector/timing scroll
measurements, playback-button coordinates, single-catalog DOM measurements,
mobile viewport captures, console result, and historical automated-test count.
They remain historical comparison inputs only and do not establish current v16b
parity or acceptance.

No mobile/responsive run, native Simulator/device
parity result, physical-device timing, or owner approval is claimed here.

### Historical v11f browser-verified interaction facts

- Codex in-app Browser viewport: `1703 x 1204`. The body reported
  `scrollHeight = 1204` and `clientHeight = 1204`, so this desktop pass had no
  page-level vertical scrolling. No screenshot file was produced.
- Viewfinder showed two top-chrome rows, three FOV chips, `PHOTO` and `VIDEO`,
  and the interactive `viewfinder` page at reducer sequence `8`.
- After the Setup Camera action, both `phone.stage` and the permission machine
  were `waitingSystem`, and contextual operations were empty. After
  `SYSTEM_PERMISSION_RETURNED`, the stage was `awaitingExplicitActions` and the
  legally reducible actions returned.
- Share stayed inside Photo Viewer. Opening it reached `selector` while the URL
  and TAP-0087 sequence remained unchanged at `15`. The first Back closed only
  Share and stayed in Viewer at sequence `15`; the second Back returned to TAP
  Library at sequence `16`.
- The earlier machine-and-sequence-only workload focus check was superseded by
  the owner-corrected complete-snapshot verification recorded below.
- Incremental `dev.logs` inspection before and after the exercised actions
  contained no new `error` entry.

### Current automated and static checks

- `node --test Prototype/*.test.mjs`: `58/58` passed.
- `node --check` passed for all six Prototype MJS files.
- `Prototype/manifest.json` parsed successfully.
- `git diff --check` passed for the checked change set.

### Historical v12a browser-verified lifecycle-difference map

- Codex in-app Browser loaded the candidate at `1703 x 1204`; the default
  filter was `truth` and rendered 14 records, including 12 red mismatch cards
  and 2 aligned green cards.
- All seven lifecycle anchors computed `border-radius: 50%`. The six anchors
  referenced by current differences (`t0` through `t5`) showed the red
  difference treatment; `tn` remained neutral.
- At the top of the scrollable truth list, exactly 2 red cards were visible and
  exactly 2 SVG paths existed, each carrying the matching truth ID and actual
  anchor ID.
- After browser-native scrolling to the final record, the four visible red
  cards were `libraryReadinessPredicate`, `initializationCommit`,
  `resourceInitializationSurface`, and `deferredWorkGuard`; exactly four paths
  with those IDs existed. No connector from a clipped card remained floating.
- The rendered screenshot was visually inspected: red backgrounds, visible
  **不一致** verdicts, actual-to-target phase rows, circular anchors, and dashed
  links remained legible without covering the phone canvas or event console.

### Historical v13a browser-verified Timing differences

- The Viewfinder canonical fixture reached sequence `8` with actual milestone
  anchors `t0`, `t1`, `t2`, `t3`, and `t4` present. `t5` was not reached and no
  future `t5` Timing anchor/card was fabricated.
- The Timing grid exposed lanes in this order: Timing, **08/09 差异**, UI,
  Reducer, Workload, Marker. The additional lane remained a reviewer annotation;
  the Reducer lane still contained the same 8 journal events.
- Eleven reached mismatch cards and exactly eleven dashed SVG paths existed.
  Every path's truth ID and actual-anchor ID matched one card one-to-one.
- Switching **Timing → 顺序日志 → Timing** restored all 11 cards and all 11
  connectors. Switching the right-hand card filter to **当前** removed the
  separate truth-card list but left the Timing lane's 11 cards/connectors
  unchanged, matching the annotated owner state.
- Visual evidence:
  `evidence/TAP-0087-r1-v13-timing-lifecycle-differences.png`.

### Historical v14a browser-verified standalone Workload comparison

- Codex in-app Browser loaded Viewfinder at reducer sequence `8` in the default
  `1703 x 1204` desktop viewport. The body remained `1204 / 1204` with no page-
  level vertical scrolling; the Timing panel owns its internal scroll.
- The comparison phase axis contained `t0`, `t1`, `t2`, `t3`, `t4`, and `t5`.
  Ten red actual cards, ten blue prototype cards, and exactly ten dashed paths
  rendered. The actual-card, target-card, and connector ID sets matched one-to-
  one; the SVG-derived connector count was also `10`.
- The red actual card computed a red gradient/border and the prototype card a
  blue gradient/border. Each visible pair exposed separate **实际 Workload** and
  **原型 Workload** rows plus its explicit mismatch label and phase movement.
- Timing -> Ordered log -> Timing preserved Viewfinder `seq 8`, all `8` reducer
  journal events, and all `10 + 10 + 10` comparison elements. Switching the
  independent truth-card filter to **当前** removed that card list but preserved
  every workload pair and path.
- Internal Timing scroll exposed paired cards without detaching their lines.
  A temporary `1500 x 1000` viewport produced the same 10 paths; the viewport
  override was reset to the default afterward. Browser console inspection
  returned no warning or error.
- Visual evidence:
  `evidence/TAP-0087-r1-v14-workload-timing-comparison.png`.
- Claim boundary: source-order comparison and prototype-review evidence only;
  not native instrumentation, elapsed duration, Simulator/device parity,
  physical-device performance, or owner approval.

### Historical v15a browser-verified integrated Workload differences

- Codex in-app Browser loaded the ordinary process-launch Viewfinder fixture at
  sequence `8` in the default `1703 x 1204` viewport. Body height remained
  `1204 / 1204`; Timing retained its own internal scroll.
- The Timing lane order is **Timing**, **08/09 生命周期**, **UI**, **Reducer**,
  **Workload**, **Marker**. The lifecycle lane contains six non-workload red
  cards and six dashed paths. The previous standalone workload comparison has
  zero DOM nodes.
- The one existing Workload lane contains 12 JSON-backed pairs: 10 timing and 2
  semantic. Every pair has exactly one red actual region, one inline dashed
  connector, and one blue prototype region. All four ID sets were unique and
  equal. Actual-anchor distribution was `t0: 3`, `t2: 8`, `t3: 1`.
- Four target phases at `t5` visibly say **原型目标 · 未到达投影** inside their
  pairs. No `t5` event column, reducer event, or milestone was created.
- Clicking the W01 actual region focused sequence `2` while the reducer state
  stayed at sequence `8`; **Follow latest** restored the latest focus. Switching
  **Timing → 顺序日志 → Timing** preserved eight reducer events, all 12 pairs,
  and the six lifecycle links.
- Browser console inspection returned no warning or error. The v14 and v15
  screenshots were inspected together: the lower duplicate comparison is gone,
  and actual/target workload differences are now visibly grouped inside the
  Workload row.
- Visual evidence:
  `evidence/TAP-0087-r1-v15-integrated-workload-differences.png`.
- Claim boundary: source-order/predicate comparison and prototype-review
  evidence only; not native instrumentation, elapsed duration, Simulator/device
  parity, physical-device performance, or owner approval.

### v16a browser-verified trace-bound Workload differences

- Codex in-app Browser used the same `1703 x 1204` desktop viewport. Body height
  remained `1204 / 1204`; Timing retained one internal scroll surface and one
  Workload lane. The previous standalone comparison had zero DOM nodes.
- At ordinary Viewfinder sequence `8`, eight applicable red actual annotations
  appeared. Three exact prototype effects already existed and therefore became
  blue with three one-to-one dashed paths. The catalog and four deferred targets
  remained visibly **既有 trace effect 尚未出现** with no synthetic target
  element, connector, or future `t5` column.
- At ordinary sequence `9`, the existing `t5` workload effects became available:
  seven exact prototype effects were blue and all seven red-to-blue path IDs
  matched. Opening Library additionally bound the existing catalog effect, for
  eight targets and eight paths.
- The complete fresh-install journey at sequence `20` rendered eleven applicable
  actual records and the same eleven exact target/path IDs. The first-install
  credential difference stayed in its Continue visibility/upstream projection
  column (`seq 13`), while its card named the real post-camera fixed-delay trigger,
  while its prototype App Attest effect remained in `seq 5`; the dashed path
  correctly ran backward across columns instead of moving the actual card to a
  coarse `t2` column.
- `ordinaryForegroundResume` sequence `2` rendered zero actual, target, and
  connector records, confirming that JSON scenario bindings do not leak
  first-install or ordinary-launch differences into unrelated paths.
- The persistent model test replays all 154 concrete record/scenario bindings;
  every applicable visibility checkpoint and exact target effect resolves, with
  no duplicate target or cross-scenario match.
- In the Resource Initialization ordering where Library catalog publication
  preceded camera completion, the catalog semantic actual appeared at its
  JSON visibility checkpoint while `t4` was still absent
  (`actualAnchorReached = false`).
  Its exact existing catalog target was blue and connected; the coarse `t4`
  anchor remained a label rather than an incorrect visibility gate.
- Every recorded reducer workload effect remains in the Workload lane. At the
  complete fresh-install checkpoint there were 23 trace effects, 11 red actual
  annotations, 11 existing blue targets, and 11 paths; no path contained
  `NaN` or `undefined`.
- Clicking the first-install credential actual focused `seq 13` without changing
  reducer state; **跟随最新** restored `seq 20`. Switching **Timing → 顺序日志 →
  Timing** restored all 11 actuals, targets, paths, and 23 trace effects.
- Computed styles confirmed red and blue gradients/borders, `4px 4px` dashed
  paths, and `pointer-events: none`. Browser console inspection returned no
  warning or error.
- The red card's visible copy and accessible name include mismatch kind,
  checkpoint, source scope/trigger, actual phase, target phase, and target
  reachability. Connector lookup uses a reviewer-only target-element data ID;
  the source-focus button does not falsely claim ARIA control of the blue target.
- The v15 and v16 screenshots were inspected together at the same viewport. v16
  preserves the canonical Workload trace and connects red current-main source
  annotations directly to corresponding existing blue prototype workload
  elements.
- Visual evidence:
  `evidence/TAP-0087-r1-v16-trace-bound-workload-differences.png`.
- Claim boundary: code-grounded source-order/predicate comparison and
  prototype-review evidence only; not native instrumentation, elapsed duration,
  Simulator/device parity, physical-device performance, or owner approval.

### v16b browser-verified fix0809 dispositions

- Codex in-app Browser loaded the current working tree at `1604 x 1204`.
  `body.scrollHeight` and `body.clientHeight` were both `1204`; Timing retained
  one internal `1019 / 336` scroll surface.
- In fresh-install sequence `5`, `initialAttestationCompletionMeaning` remained
  a red mismatch, visibly said **本轮暂缓 · Network frozen**, decorated the
  existing blue target, and owned one `4px 4px` dashed path. At sequence `12`,
  `firstInstallCredentialStartsAfterContinue` appeared with the same frozen
  treatment and its own backward connector to the existing Setup App Attest
  effect.
- In ordinary-process sequence `9`, eight actual annotations rendered with
  seven existing blue targets and seven paths. The non-network poster and
  recent-cover guard records said **fix0809 · 已批准修复**. Post-setup App Attest
  and credential/network-dependent Pending recovery remained red and said
  **本轮暂缓 · Network frozen**.
- Every actual whose exact target existed had one target and one connector; no
  connector was orphaned, empty, `NaN`, or `undefined`. Red/blue gradients and
  borders remained intact. Switching **Timing → 顺序日志 → Timing** preserved
  ordinary sequence `9` and restored all `8 / 7 / 7` elements plus both frozen
  children.
- Visible and accessible disposition labels came from the manifest registry.
  Deferred items remained mismatches rather than becoming aligned, and the
  accessible copy continued to state that `/healthz` is not the target.
- Browser console inspection returned no warning or error. Both evidence files
  are real PNG images:
  `evidence/TAP-0087-r1-v16b-fix0809-dispositions.png` and
  `evidence/TAP-0087-r1-v16b-fix0809-timing-workload.png`.
- Claim boundary: current prototype disposition and connector evidence only;
  not native implementation, a Network/App Attest behavior change,
  Simulator/device parity, physical-device timing, or approval of the complete
  TAP-0087 v16 composition.

### Owner-corrected workload navigation — browser verified

The final Codex in-app Browser pass used the same `1703 x 1204` viewport. The
body remained `scrollHeight = 1204` / `clientHeight = 1204`, with no page-level
vertical scrolling. The screenshot was inspected inline in the in-app Browser;
no screenshot file was saved.

- `cameraSession` found its registered moment in current playback history and
  restored `ordinaryProcessLaunch`, Viewfinder, sequence `6`, **Capture graph
  configured**, `Ready`, and the `cameraReadiness` machine together.
- `initialAttestation` had no qualifying snapshot in the current history. One
  card click directly switched to the registered `freshInstall` canonical
  fixture and legally replayed to First-Install Setup, sequence `6`, **Initial
  App Attest ready**, `Ready`, and `appAttestCredential`; the left catalog
  selected `firstInstallSetup`. No second confirmation was required.
- `videoPosterBackfill` restored the registered ordinary Viewfinder inspection
  moment at sequence `9` and remained `Eligible`; it was not promoted to Ready.
- `viewfinderControls` restored the registered In-place App Update Viewfinder
  inspection moment at sequence `10` and remained `Deferred child task`; it was
  not promoted to Ready.
- Every exercised workload card exposed the accessibility label
  `跳转到对应 UI 与生命周期审阅时刻`.
- Across these actions, incremental `dev.logs` contained `0` new error entries.

### Remaining gate

Mobile/responsive coverage, exact prototype-to-native visual parity, and
physical-device timing remain unclaimed. Separately, the owner accepted the
bounded `fix0809` non-Network lifecycle path after exercising it on a physical
device; that verdict is not approval of the exact v16 workbench or its complete
scenario matrix. Exact product-owner review of the v16 workbench and
synchronized contract remains required.

### 2026-08-15 `fix0809` native candidate

- The manifest now keeps native implementation progress beside, but separate
  from, the immutable `main@4cc02e5f12f2` truth records.
- Seven mismatch IDs are recorded as fully implemented candidates. Setup/
  marker separation, retained-container routing, camera construction, and
  deferred release are recorded as partial. Camera mounting now follows route
  selection and uses lazy `StateObject` construction, but `Task.yield()` is not
  a real shell-frame acknowledgement; canonical `S` and Network-owned deferred
  work also remain outside the approved frozen boundary.
- The owner-approved TAP-0009 Resource Initialization hierarchy and two
  readiness rows are present in SwiftUI. Required Permission Check remains a
  visual/copy candidate rather than a claimed v16 approval.
- Marker I/O is off-MainActor and fails closed without Application Support;
  local poster/recent-cover work and pending App Intent navigation wait for a
  two-display-tick committed-Viewfinder barrier.
- Build-for-testing passed on the iPhone 17 Pro / iOS 26.5 Simulator target;
  the four focused suites passed 146/146 with zero failures or skips. These
  automated facts do not replace browser evidence or a native visual
  comparison, so Simulator parity remains pending.
- On 2026-08-15, the owner exercised and accepted the bounded non-Network
  lifecycle path on a physical device. The supplied log showed Library catalog
  publication and camera readiness before initialization-marker commit, then
  local recent-cover release. Interruption/fault injection, permission recovery,
  update/restore, measured timing, canonical `S`, and complete `W11/W12` remain
  outside that verdict.

final result: native bounded path owner-accepted; exact v16 composition and full
scenario matrix remain candidate work
