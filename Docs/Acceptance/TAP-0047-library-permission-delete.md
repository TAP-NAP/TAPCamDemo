# TAP-0047 — TAP Library Permission, Delete, And Return Semantics

- Status: `Draft — not executed`
- Related Delivery: `TAP-0058`, `TAP-0059`, `TAP-0061`
- Product Contract: `ProductContract §5.1–5.4`; `§8`
- Build/Commit: `To be frozen before execution`
- Device/iOS: `To be confirmed with the product owner`
- Date: `Unscheduled`
- Operator: `Unassigned`
- Human Confirmation: `Pending`

This is an attended physical-device procedure. It covers Limited Photos access,
source-owned deletion, post-delete Viewer selection, empty-Library close, and
in-session return in a large Library. It does not redefine the TAP Library as
the private Pending Capture Queue, and it does not promise durable pixel-exact
scroll restoration across a fresh Library entry.

The owner must approve the disposable media set, visible item order, large-
Library fixture, device/iOS matrix, and any method used to hold a capture in a
genuine pending/local-only state. No personal asset is a test deletion target.

## Preconditions

- The frozen candidate build implements the mixed-media TAP Library, horizontal
  Viewer, current bottom toolbar, source-owned deletion, and route bookmarks.
- The owner has approved a disposable Photos set containing:
  - app-owned exported assets that may be deleted;
  - an allowed subset and an excluded subset for Limited access; and
  - enough ordered items to exercise middle, terminal, and single-item deletion.
- A genuine pending or local-only capture can be prepared through the normal
  product path or an owner-reviewed test path. The method must not relabel an
  exported Photos asset as pending and must not mutate the artifact under test.
- The owner has approved the large-Library fixture and has recorded its item
  count and canonical sort order. This draft intentionally defines no minimum
  count or scroll distance.
- Screen recording, public-safe app logs, and before/after Photos screenshots
  are ready. Private Photos identifiers remain in the evidence bundle and are
  not copied into public logs or this report.
- **OWNER-LIVE:** approve the disposable asset list, Photos authorization
  changes, every destructive confirmation, and the pending-item preparation
  method before the run starts.

## Reset / Install Procedure

1. Archive previous evidence and record the current Photos authorization state.
2. Install the frozen signed build using the owner-approved install method.
3. Using the system-owned Photos access UI, grant TAPCam Limited access to only
   the approved subset. Record the selected and intentionally excluded fixture
   assets without exposing unrelated personal media.
4. Prepare the approved pending/local-only item and confirm it has not exported
   to Photos before its deletion steps.
5. Load the approved large-Library fixture. Record the visible canonical order
   and the identities of the disposable middle, terminal, and single-item test
   targets.
6. Begin continuous screen recording and app/device logs before opening TAP
   Library.

If Limited authorization, a genuine pending item, or a disposable ordered
fixture cannot be established, stop as Blocked instead of substituting a Web or
Simulator fixture.

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | **OWNER-LIVE:** Open TAP Library while Photos access is Limited. Compare the grid with the owner-approved allowed and excluded subsets. | TAP Library loads without an app-owned replacement permission prompt. It may show accessible app-owned/pending content, but it must not reveal an excluded Photos asset or claim full-library access. | `Pending` | `Pending` |
| 2 | Leave and re-enter TAP Library once without changing the system selection. | The authorization remains Limited, the same permitted set is used, and re-entry does not silently broaden access or request permission again. | `Pending` | `Pending` |
| 3 | Change the Limited selection through the system-owned access UI using the owner-approved add/remove fixture, then return to TAPCam. | TAP Library refreshes to the newly authorized set without duplicating items, exposing removed assets, or reopening first-install setup. | `Pending` | `Pending` |
| 4 | Open an exported Photos asset, tap Delete, and cancel at the system confirmation. | TAPCam presents no app-owned confirmation before the Photos prompt. Cancel leaves the Photos asset, grid item, Viewer item, and current position intact. | `Pending` | `Pending` |
| 5 | **OWNER-LIVE:** Delete an approved exported Photos asset that is in the middle of a recorded three-or-more-item order, and confirm only the system prompt. | Exactly one system-owned confirmation is used. The deleted asset leaves Photos/TAP Library, and the Viewer selects the item that occupied the next index in the pre-delete order. | `Pending` | `Pending` |
| 6 | Delete the terminal exported Photos asset in the controlled order and confirm the system prompt. | With no next item, the Viewer selects the previous remaining item. It does not close while any TAP Library item remains. | `Pending` | `Pending` |
| 7 | Open the genuine pending/local-only item, tap Delete, and cancel the app-owned confirmation. | One TAPCam-owned confirmation appears, no Photos system deletion prompt appears, and cancel preserves the local record and artifact. | `Pending` | `Pending` |
| 8 | **OWNER-LIVE:** Delete the same pending/local-only item and confirm the app-owned prompt. | The Pending Capture Queue removes the intended local record through its normal storage boundary. No Photos system deletion prompt appears, and adjacent selection follows the same next-then-previous rule. | `Pending` | `Pending` |
| 9 | Establish the approved one-visible-item fixture, open its Viewer, and delete it using the confirmation owned by its actual source. | After the last visible item is removed, the Viewer closes to the empty TAP Library. It does not remain on stale content or an invalid next/previous route. | `Pending` | `Pending` |
| 10 | In the approved large Library, scroll well beyond the initial viewport, record a distinctive allowed item and its viewport position, open it, page left/right once if valid, return to the originally selected item, then return to the grid. | The in-session return lands at or near the clicked item using its item bookmark; the item remains recognizable without a top-of-grid jump or unrelated selection. Exact pixel offset is not promised. | `Pending` | `Pending` |
| 11 | Leave TAP Library completely, then open it as a fresh entry. | Fresh entry follows the current top-start contract. The prior view-local offset is not treated as a durable cross-entry coordinate. | `Pending` | `Pending` |

## Required Evidence

- Logs: authorization-state changes, Library snapshot/merge counts, selected
  source type, deletion request/result, pending-store removal, post-delete
  selected index, Viewer close, and route-bookmark resolution.
- Screenshots/recording: continuous attended recording of Limited selection,
  both confirmation owners, cancel/confirm outcomes, adjacency, empty close,
  and large-Library return.
- Output artifacts: before/after inventory of only the disposable Photos and
  pending/local targets, kept in the private evidence bundle.
- Result bundles: frozen build/commit, device/iOS, fixture manifest, approved
  sort order, and any focused automated result used as supporting evidence.
- **OWNER-LIVE:** written confirmation that no personal asset was targeted,
  each prompt had the correct owner, and the observed return position was
  acceptable for the approved large-Library fixture.

## Verdict Conditions

- **Pass:** every approved fixture completes; Limited access never exposes an
  excluded asset; exported and pending/local deletion use exactly their owning
  confirmation; cancel is non-destructive; next/previous/empty behavior is
  correct; in-session return preserves the clicked-item context; and the owner
  accepts the run.
- **Fail:** TAPCam adds a second confirmation for Photos deletion, omits its
  confirmation for local deletion, deletes on cancel, deletes the wrong item,
  exposes an excluded asset, duplicates/stales the Limited set, selects the
  wrong adjacent item, leaves an empty Viewer open, or loses the approved
  in-session clicked-item return.
- **Blocked:** the owner has not approved the device, disposable fixtures, or
  destructive steps; Limited access cannot be established; a genuine
  pending/local item cannot be held; canonical order cannot be recorded; logs
  cannot distinguish Photos from local deletion; or only Web/Simulator
  fixtures are available.

## Human Confirmation

`Pending — OWNER-LIVE attended execution and explicit acceptance required`
