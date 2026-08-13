# TAP-0081-r2 / TAP-0009-r1 Approved Design QA

- Source visual truth:
  - `assets/references/tap-share-format-selection.png`
  - `assets/references/tap-share-preparing.png`
  - owner-approved `TAP-0081-r1` geometry and anchored-handoff behavior
- Implementation: `index.html` served at `http://localhost:4173/`
- Source pixels: `853 x 1844` for each owner-selected reference
- Implementation viewport: `393 x 852` CSS px, `devicePixelRatio = 1`
- Implementation pixels: `393 x 852` per state capture
- Density normalization: each source reference was downsampled to `393 x 852`
  for the combined comparisons listed below. The Web frame is a relationship
  reference and does not claim native pixel identity.
- Browser evidence: Codex in-app Browser on 2026-08-13
- Browser console: no warnings or errors after the exercised paths

## Approval boundary

The product owner approved exact base revision `TAP-0081-r1` on 2026-08-12 and
approved exact visual revision `TAP-0081-r2-candidate` on 2026-08-13 with
“已确认没有问题 请继续实施 Swift UI”. The approval covers the recorded
local-integrity states and refined toolbar geometry; native and device evidence
remain separate from Web approval.

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

The combined comparisons place the normalized selected source at left and the
candidate state at right. No separate-image or memory-only comparison is used.

## Full-view comparison

The candidate preserves the approved Viewer hierarchy: full-screen media,
bottom-left Share, centered `RAW / 2D / 3D`, bottom-right Delete, and a compact
material surface anchored above Share. The r1 Share control, toolbar, popover
anchor, popover width, row rhythm, and preparation geometry are unchanged.

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
- Fast 35 ms preparation reached the system boundary with
  `progressVisible = false`. The existing 50/400 preparation contract remains
  unchanged by this candidate.
- The script contains no `fetch`, `XMLHttpRequest`, `WebSocket`, backend Verify
  route, or persistent browser storage. iCloud and integrity are deterministic
  visual fixtures only.

## Required fidelity surfaces

- Fonts and typography: the existing Apple/system stack, status hierarchy,
  option-title weights, subtitles, and preparation type scale are unchanged.
  The new Viewer resource card uses the same title/subtitle hierarchy.
- Spacing and layout rhythm: the 393 x 852 Viewer, bottom toolbar, 42 px Share
  control, 288 px popover, 19 px radius, caret, row heights, dividers, and
  preparation spacing remain inherited from r1. New skeleton rows match the
  selector's four-row footprint.
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
- No remaining actionable P0/P1/P2 difference was found. The loading card is a
  new owner-approved behavior state rather than an r1 source-image mismatch.
  Native material optics, PhotoKit/iCloud activity, cryptographic work, and the
  real system activity controller remain native evidence boundaries.

## Implementation checklist

- [x] Preserve r1 Viewer and popover geometry.
- [x] Cover local/iCloud ready, loading, unavailable, and private-queue sources.
- [x] Cover text-free local integrity resolving without a fourth public state.
- [x] Cover Failed package disable plus warned ordinary-media sharing.
- [x] Restrict Needs Retry to the private queue fixture.
- [x] Keep backend Verify, package pre-generation, and persistent caching absent.
- [x] Run static tests, interactive Browser paths, console inspection, and
  normalized combined-image review.
- [x] Obtain exact owner approval for `TAP-0081-r2-candidate`.

final result: passed

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
