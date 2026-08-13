# TAPCam Cold-Path Responsiveness Standard

- Status: repository engineering standard
- Owner: TAPCam engineering
- Applies to: first install, first launch after update, empty or evicted caches,
  first TAP Library entry, first Viewer entry, first Share attempt, iCloud
  resource retrieval, and first system-owned presentation
- Related tasks: `TAP-0009`, `TAP-0041`, `TAP-0045`, `TAP-0047`, `TAP-0081`,
  `TAP-0082`, `TAP-0083`

Warm behavior is not evidence that a cold path is responsive. Every feature
that owns scalable startup work must remain correct and visibly responsive
when no in-memory image, catalog, media, LaunchServices, or presentation cache
has been warmed.

## 1. Main-Actor Budget

The MainActor owns observable UI state and UIKit/SwiftUI presentation calls.
It must not own scalable work such as:

- file copying or whole-resource reads;
- media hashing or proof/content-binding computation;
- ZIP generation;
- PhotoKit catalog enumeration or large catalog reconciliation;
- image decode/downsampling;
- video metadata scans; or
- per-chunk progress fan-out.

An `async` function is not automatically off the MainActor. Scalable work must
have an explicit isolation boundary. A synchronous MainActor slice should stay
below one 120 Hz frame budget (8 ms) in normal operation; work that can grow
with item count or file size is not allowed to depend on that budget.

## 2. Visible Acknowledgement Before Scalable Work

An accepted user action follows this order:

```text
tap
  -> publish one stable visible acknowledgement
  -> allow that state to commit
  -> start scalable work away from the MainActor
  -> deliver bounded progress
  -> complete, fail, cancel, or hand off
```

The acknowledgement may be the existing stable surface changing state; it
does not require a new full-screen loader. TAP Share must mount its app-owned
surface before local integrity work and must keep visible handoff feedback if
the first system activity controller is slow. It must not expose a bare Viewer
gap between app-owned and system-owned presentations.

## 3. Backpressure And Semantic Publication

- High-frequency progress is latest-value coalesced to at most 20 UI updates
  per second. Explicit start and terminal values are preserved.
- Progress delivery is monotonic where the UI represents completed work.
- Cancellation and request identity are checked immediately before UI
  publication; stale samples cannot mutate a newer request.
- Large collections publish only when their value-semantic contents or public
  error state change. Equivalent refreshes do not advance a public revision.
- Per-cell geometry tracking must not invalidate an entire grid while the user
  scrolls.
- SwiftUI `body` must not decode image bytes. Decode/downsample once outside
  render work and reuse an image object from a bounded cache.

## 4. Presentation And Resource Ownership

Every popover, sheet, and system-owned presentation must cover:

- successful completion;
- user cancellation;
- SwiftUI binding dismissal;
- UIKit dismissal;
- presenter disappearance;
- controller initialization or presentation failure; and
- delayed callbacks from an older attempt.

Temporary resources remain alive while the system controller can request
them, then clean up idempotently using the exact attempt/artifact identity.
Custom exported files declare the public conformances required by their system
destinations and use explicit type metadata instead of filename inference.

## 5. Observability

Cold-path diagnostics use low-cardinality milestones. They may record:

- phase name;
- duration bucket or integer milliseconds;
- item count;
- media kind;
- semantic-change Boolean; and
- public outcome.

They must not record capture IDs, Photos local identifiers, file URLs, paths,
proof material, or one log event per file chunk. The TAP Share sequence is:

```text
tap
  -> app surface appeared
  -> local integrity started / finished
  -> payload ready
  -> activity handoff started
  -> activity controller created / appeared
  -> activity completed / dismissed
```

The final emitted milestone identifies the stalled phase without relying on
private LaunchServices diagnostics.

For first-install Resource Initialization, noncompletion is an engineering
defect rather than a public Failed/Retry state. The stable initialization UI
remains mounted. Bounded checkpoint logs identify whether camera-interactive or
Library-catalog readiness is incomplete; they do not upload identifiers or
media and do not create an unbounded retry loop.

## 6. Required Automated Checks

Focused tests for an affected cold path must prove, as applicable:

- equivalent large snapshots cause no observable publication;
- progress callback count is bounded independently of chunk count;
- the newest progress value and terminal value survive coalescing;
- cancellation and stale-request guards reject delayed work;
- images are reused from decoded cache rather than decoded in `body`;
- completion and every dismissal route clean temporary resources exactly once;
- delayed completion/dismissal from attempt A cannot alter attempt B; and
- an exported custom type contains its required filename, MIME, and public UTI
  conformances in the built app.

Source-string checks may protect a narrow architectural boundary, but they do
not replace behavior tests.

## 7. Physical-Device Acceptance

At least one attended run for a cold-path delivery starts from a newly
installed app or an explicitly cleared app container/cache. Its procedure
records:

1. build/commit, device, OS, and reset method;
2. TAP Library size and representative media kinds;
3. first entry into TAP Library and Viewer;
4. first Share selection and first system activity presentation;
5. cancellation/dismissal and a second Share attempt;
6. required milestone logs and visual evidence; and
7. owner pass/fail/blocked confirmation.

A warm re-entry comparison is useful, but it cannot replace the cold run or
close a cold-path acceptance condition.
