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

## Active TAP-0087-r1 target-placement candidate QA

- Candidate entry: `startup-lifecycle.html`.
- Status: `candidate`; `ownerReviewRequired`.
- The `main@4cc02e5f12f2` actual/target fields remain historical audit data.
  Current rendering is derived from manifest `reviewState`,
  `activeDifference`, and `followUpTaskIDs`.
- An implemented lifecycle record renders once at `target.anchor` in the right
  panel and **08/09 生命周期** Timing lane with a yellow background/red border.
  It has no actual card, blue target duplicate, **不一致** verdict, or dashed
  connector.
- An implemented Workload record decorates its exact existing target effect
  yellow/red. It has no separate Actual card, blue duplicate, or connector.
- Initial Network/App Attest remains a `TAP-0010` red actual-to-blue-target
  difference. Post-Setup App Attest and credential/network-dependent Pending
  remain `TAP-0015` red actual-to-blue-target differences. Their active labels
  name those owning Tasks directly.
- Non-Network lifecycle ordering and workload-period regression is tracked by
  `TAP-0090`; attended evidence remains in `TAP-0040`/`TAP-0041`, numeric
  route-shell/first-frame and 2 × 2 timing in `TAP-0083`, and exact
  prototype/native visual parity in `TAP-0048`.
- Browser DOM/computed-style verification at
  `startup-lifecycle.html?revision=v19` confirmed the new presentation without
  saving an image. Ordinary Process Launch sequence `17` rendered five right
  lifecycle target follow-ups and five Timing lifecycle target follow-ups with
  zero lifecycle Actual cards/connectors; Workload rendered four yellow/red
  target follow-ups plus two red Actual/two blue Target/two connector pairs.
  Fresh Installation sequence `27` rendered two yellow/red target follow-ups
  plus four task-owned Actual/Target/connector pairs. Yellow targets carried no
  `actualAnnotationId`; every retained path was non-empty and contained no
  `NaN` or `undefined`; Timing to Ordered log to Timing preserved the counts;
  browser console inspection returned no warning or error.
- Do not create or retain photo, screenshot, or screen-recording proof. Durable
  evidence is the structured DOM/reducer assertion report, console result, and
  owner-live textual verdict.

final result: passed for v19 reviewer projection and no-image browser DOM/style
verification; complete TAP-0087 composition approval remains separately open


### Remaining gate

Mobile/responsive coverage, exact prototype-to-native visual parity, and
physical-device timing remain unclaimed. Separately, the owner accepted the
bounded `fix0809` non-Network lifecycle path after exercising it on a physical
device; that verdict is not approval of the current workbench or its complete
scenario matrix. `TAP-0048`, `TAP-0083`, `TAP-0090`, and the applicable
attended `TAP-0040`/`TAP-0041` procedures retain those gates. Exact product-
owner review of the synchronized workbench and contract remains required.

### 2026-08-15 `fix0809` native candidate

- The complete earlier implementation/acceptance record remains at `d4b19d9`.
  The active manifest presents implemented non-Network records at their target
  positions with linked validation Tasks; it does not preserve them as active
  actual-versus-target position mismatches.
- Setup/marker separation, retained-container routing, camera construction, and
  local deferred release are implemented candidate records. Camera mounting
  follows route selection and uses lazy `StateObject` construction, but
  `Task.yield()` is not a real shell-frame acknowledgement; `TAP-0083` owns
  that placement/timing evidence and `TAP-0090` owns structured lifecycle
  ordering regression.
- The owner-approved TAP-0009 Resource Initialization hierarchy and two
  readiness rows are present in SwiftUI. Required Permission Check remains a
  visual/copy candidate; exact parity is owned by `TAP-0048`.
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
  update/restore, measured timing, and canonical `S` remain outside that
  verdict. Initial Network/App Attest stays with `TAP-0010`; post-Setup App
  Attest and credential/network-dependent Pending stay with `TAP-0015`.

final result: native bounded path owner-accepted; linked regression, visual,
timing, Network/App Attest/Pending, and full-scenario Tasks remain open
