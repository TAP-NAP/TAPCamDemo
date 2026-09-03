# TAPCam Product Contract

- Status: canonical product constraint document
- Owner: product owner
- Last updated: 2026-09-04

This document is the single current product contract for TAPCamDemo. It defines
what the product currently does, what it deliberately does not do, which work is
future or experimental, and which claims require more evidence.

Implementation code, tests, prototypes, task status, acceptance reports, and
historical notes must conform to this document. None of them can silently
redefine the product contract.

## 1. Document Authority And Classification

Every product statement must be classified as exactly one of these:

- **Current capability**: behavior the product contract currently requires.
- **Explicit non-goal**: behavior outside the product scope. It must not remain
  in Todo.
- **Future**: approved future product work that belongs in the project board.
- **Experimental**: work being explored without a production-capability claim.
- **Deprecated design**: an old interaction, implementation direction, or claim
  replaced by the current contract. It must not be restored without a new
  product decision.
- **Evidence gap**: a current capability whose Simulator, device, performance,
  accessibility, or operational acceptance is incomplete. An evidence gap does
  not turn the capability back into an unimplemented feature.
- **Historical record**: an accurate record of an earlier state that no longer
  defines the product.

The document roles are:

1. This document defines current product behavior and scope.
2. The sibling [TAPCamKanban ProjectBoard.md](../../TAPCamKanban/ProjectBoard.md)
   tracks work states and compact history.
3. The independent `TAPCamPrototype` repository owns approved visual intent,
   static implementation, manifest, fixtures, QA, tests, and prototype evidence;
   §9 and root `AGENTS.md` own the prototype-to-SwiftUI workflow.
4. `Docs/Acceptance/` stores evidence and executable acceptance procedures.
5. Root [README.md](../README.md) is the sole implementation map and validation
   entry. Implementation and tests enforce, but cannot redefine, this contract.
6. [PlanesTechnicalDesign.md](../TAPCamDemo/DepthAnalysis/Documentation/PlanesTechnicalDesign.md)
   owns only the reusable photo-local geometry explanation.
7. [App Attest BackendContract.md](AppAttest/BackendContract.md) owns the
   cross-project HTTP, server-trust, counter, and replay boundary.
8. AITrace, dated acceptance reports, branch audits, old implementation plans,
   POCs, and experiment logs are historical records. Once their still-relevant
   facts, acceptance procedures, and cross-project obligations have been
   migrated, they do not need to remain in the current documentation tree. Git
   history is the recoverable archive. Until removal, they cannot override this
   contract.

`Done` on the project board means a task met its recorded completion condition.
It does not independently declare a current product capability. Conversely, a
missing device test is tracked through an evidence task and does not make an
implemented feature a Todo again.

### 1.1 Current runtime platform

The current TAPCamDemo product target supports iPhone only. `iphoneos` is the
shipping runtime platform and `iphonesimulator` is retained only for iPhone
Simulator compilation, automated tests, and UI validation. Simulator support
does not expand the product platform and does not replace attended iPhone
device acceptance.

iPad and iPad multitasking, Mac Catalyst or native macOS, running the iOS app
as Designed for iPhone/iPad on Mac, and Apple Vision Pro compatibility are
explicit non-goals for the current product. Current implementation, prototype,
build, and acceptance work must not introduce conditional branches, layout
adaptation, or validation obligations solely for those unsupported platforms.
Any future platform expansion requires a separate owner-approved Task, updated
contract and prototype coverage, and its own build and device evidence.

Xcode target settings express the repository build boundary; availability of
an iOS app on Mac or Apple Vision Pro is also controlled by App Store Connect
and is not proven by repository settings alone.

### 1.2 Pre-release version and compatibility policy

The current App marketing/build version remains `0.2 (2)`. Before the first
public release, every distinct current public-format and security-schema family
starts at its own unambiguous `v1`; a shared numeric version does not make
structurally different still-photo, Live Photo, TAP Video, content-binding,
registration, proof, or attestation objects interchangeable. The named shared
contracts own the exact identifiers and fail-closed routing rules.

The documentation-only
[TAPArtifactContracts contract index](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/CONTRACTS.md)
owns the shared wire-level conventions consumed by TAPCam and external
verifiers. This Product Contract continues to own which format families are
current product capabilities, their claim boundaries, and their non-goals.
The local operational rules below implement that authority and must not silently
redefine the shared artifact contract.

Superseded development-format identifiers are unsupported and must not remain
as compatibility readers in TAPCam or TAPCamVerifier. Pre-release local app
data is also disposable: a developer moving between incompatible builds clears
the app container or deletes and reinstalls instead of relying on preference,
database, queue-record, cache, or setup-marker migration. This policy does not
weaken validation of current data and does not define the eventual compatibility
policy for data or artifacts created by a public release.

TAPCamVerifier accepts a capture package only through the `.tapnap` extension or
the registered TAPNAP MIME and requires its current v1 root sidecar. Legacy
`.zip`, `application/zip`, generic ZIP-magic discovery, and missing/invalid-
sidecar filename fallback are unsupported. `.tapnap` remains ZIP-compatible
internally; this input boundary does not remove bounded archive parsing.

Prototype revision identifiers remain unchanged until a separate owner decision.
Historical or redundant Prototype prose and assertions may be removed when no
current fixture, approved visual truth, behavior, or acceptance obligation is
lost. `TAP-0096` relocates the complete static artifact tree without creating a
new revision or changing any approval/evidence state. Pre-extraction commits and
paths remain recoverable in TAPCamDemo history.

## 2. First-Install Setup

### 2.1 Explicit action owns every setup operation

Every action row on the first-install setup page follows the same rule:

- Camera, Photos, Location, and Microphone system prompts may be requested only
  by tapping that row's explicit **Allow** action.
- The Network row is the explicit user action that may start the initial App
  Attest registration and verification operation. A generic backend
  reachability check alone does not complete that row.
- Page appearance, status refresh, `Continue`, app foregrounding, returning from
  Settings, retrying unrelated work, media reads, observers, capture warmup,
  and background preparation must not implicitly start one of these operations.
- Before the corresponding explicit action, the app may read a passive
  authorization status but must not activate protected work that can cause a
  system prompt.
- A denied or restricted permission is handled by that row and, after first
  setup, by the affected feature. The app must not repeatedly request it in the
  background.

### 2.2 Required and optional setup rows

- Required before `Continue`: successful first-install App Attest registration
  and verification through the Network row, Camera authorization, and Photos
  authorization.
- Optional and skippable: Location and Microphone authorization.
- Skipping Location means captures may continue without location metadata.
- Skipping Microphone means Live Photos and TAP Video may continue without
  captured audio.
- OS authorization and TAPCam's in-app data-use preference remain separate
  decisions. An OS grant does not force the corresponding data-use switch on
  after the user has explicitly opted out.

### 2.3 First-install App Attest and Network retry

One explicit Network action may run a bounded App Attest bootstrap sequence:

1. Reach the App Attest backend and attempt the required challenge,
   registration, and verification work.
2. On a retryable failure, wait for the policy-defined interval and retry.
3. Stop automatic attempts when the total wall-clock timeout is reached.
4. After timeout, remain on setup and require the user to press **Retry** to
   start a new bounded attempt sequence.

A `/healthz` or equivalent reachability result may be used as diagnostics, but
it is not the success condition. The row is complete only when the initial App
Attest credential operation has completed successfully.

Returning from the background or Settings may refresh displayed state, but it
must not silently start a new sequence after the previous sequence timed out.

### 2.4 Continue and first camera readiness

Completing the required rows does not complete first-install setup. The order is:

```text
required setup rows complete
        -> user presses Continue
        -> resource-initialization readiness gate
        -> persist the resource-initialization completion marker
        -> enter the interactive camera
```

After an app update, already-completed permission/setup rows are not replayed,
but the resource-initialization gate still runs before the interactive camera
when its independent marker does not match the current update and
initialization-schema generation.

The full-screen app-owned state is titled **Resource Initialization** with the
subtitle **Please wait…**. It exists to prevent the app from entering the camera
surface too early and presenting a frozen or non-responsive page. It completes
only after both readiness groups below are ready.

**Camera interactive** requires all of the following:

- the underlying capture graph and required capture path are ready;
- a real first preview frame has been presented;
- the shutter and primary camera controls can safely accept input;
- required first-interaction haptics are prepared.

Session configuration alone is insufficient. A loading or readiness surface
must remain until all of the conditions above hold.

**TAP Library catalog ready** requires the first usable identity/order metadata
snapshot. A successful empty snapshot is usable. The gate does not wait for or
decode the media represented by that snapshot.

Initialization is a startup invariant, not a user-recoverable failure flow.
There is no Failed, Retry, timeout, or degraded-entry surface. If readiness does
not complete, the stable Resource Initialization state remains visible and the
app emits low-cardinality developer diagnostics that identify the incomplete
readiness group. Such noncompletion is treated as an engineering defect.

The gate must never wait for iCloud originals, complete original-resource
downloads, all thumbnail decoding, local proof or media hashing, ZIP/package
generation, system activity-controller prewarming, App Attest/network warmup,
or Pending Capture Queue retry/batch completion.

The initial App Attest credential operation has already completed through the
required first-install Network row before `Continue`. Later credential health
validation, recovery/re-attestation, and Pending Capture Queue retry begin only
after camera entry as background work. They do not block the first interactive
frame, ordinary Viewfinder entry, or local capture.

### 2.5 Completion markers

Permission/setup completion and Resource Initialization completion are separate
facts. Resource Initialization owns an independent marker identifying both the
current installed app update and the current initialization-schema generation.
Write it atomically only after the camera-interactive and TAP Library catalog
readiness groups have both succeeded.

- It is not proof that any permission remains authorized forever.
- It is not a recurring permission gate for later launches.
- An absent marker, a marker for another installed update, or an initialization-
  schema mismatch requires the gate. Fresh Installation and
  Delete-and-Reinstall have no matching marker. Offload-and-Reinstall may retain
  a current marker and must be routed from the actual retained `S/P/I` facts.
- An interrupted or abnormally incomplete run leaves the marker absent or stale
  so the next launch remains in Resource Initialization.
- Ordinary later launches whose marker exactly matches the current update and
  schema generation silently skip Resource Initialization.
- If Camera or Photos changes later to an unusable state, the app enters the
  app-owned **Required Permission Check** page. That page does not replay
  first-install setup and automatically re-evaluates the startup route after a
  targeted status refresh. Location and Microphone remain feature-context
  optional permissions.
- Pre-release builds read and write only the current setup and initialization
  records. Earlier development keys and record shapes are not migrated; clearing
  the app container or deleting and reinstalling is the supported recovery.

### 2.6 Startup route, installation, and timing vocabulary

Installation labels describe evidence context, never the route itself:

- **Fresh Installation** has no restored app container. **Delete-and-Reinstall**
  deliberately creates that condition; **Development Replacement Install** is
  only an install method and may retain state.
- **In-place App Update** and **Offload-and-Reinstall** normally retain app data;
  the latter preserves documents while replacing the binary.
- **Same-Device Backup Restore** may retain valid setup, while **Cross-Device
  Migration Restore** invalidates device-bound initialization and may require
  App Attest credential recovery. **Local State Inconsistency** treats only the
  invalid fact as absent.
- **Foreground Process Launch** creates a process; **Foreground Resume**
  reactivates an existing scene. A **Cold Resource Path** has no usable relevant
  cache, while a **Warm Resource Path** does. Warmth never changes route truth.

Bare `reinstall`, `cold start`, or `first launch` is insufficient in a Task,
test, log, or acceptance conclusion; name the installation, activation, and
resource conditions separately.

The deterministic route reads four facts:

- `S` is the structured Setup receipt for the current installation generation,
  locally bound to the App Attest credential created by the explicit Network
  row. It is not a bare Boolean or proof of current network health.
- `P` is the passive required-permission snapshot: Camera must be authorized;
  Photos may be authorized or limited. Location, Microphone, and network do not
  affect `P`.
- `I` is the atomic initialization completion for the current bundle/build,
  schema, and installation/device generation. It is not permission evidence or
  a purgeable cache.
- `R` is a safe app-owned resume target used only across permission recovery;
  the current startup target is Viewfinder.

Route priority is fixed:

```text
missing or invalid S -> First-Install Setup
valid S + unusable P -> Required Permission Check
valid S/P + missing or stale I -> Resource Initialization
valid current S/P/I -> Viewfinder
```

A restored `S` without its bound credential is invalid and returns to Setup
credential recovery without replaying already-granted Camera/Photos prompts.
After setup, network unavailability never enters Required Permission Check and
does not block ordinary camera entry or local capture.

### 2.7 Startup milestones and cold-path execution

One ordered milestone vocabulary is used for implementation and evidence:

- `t0` activation requested;
- `t1` first app-owned frame committed;
- `t2` initial route surface stably committed;
- `t3` first real camera preview presented;
- `t4` shutter, primary controls, required haptics, and any required first
  Library metadata snapshot are ready; `I` is committed in this transition;
- `t5` startup-critical interaction is protected and deferred work may release;
- `tn` the selected test journey reaches its terminal state.

Before `t1`, only fixed-cost bootstrap, bounded local `S/I` reads, passive
Camera/Photos status reads, and construction of the lightweight first surface
are allowed. Camera enumeration/session construction, PhotoKit observer or
catalog activation, pending scans, media decode/hash/ZIP, network/App Attest,
and analysis are prohibited. Between `t1` and `t2`, pure route reduction and
bounded state publication remain the only work; route-owned camera/catalog work
starts only after its surface is committed. Post-setup App Attest, Pending
Capture recovery, posters, off-screen thumbnails, Share preparation, and eager
analysis wait until `t5` or an explicit later user action.

Cold-path work obeys these execution rules:

- `async` does not prove work is off the MainActor. Work scaling with item count,
  bytes, devices, formats, network, or analysis complexity needs an explicit
  non-MainActor isolation boundary. A normal synchronous MainActor slice should
  stay below 8 ms; scalable work may not rely on that allowance.
- An accepted action publishes its loading/preparing state, yields so the frame
  can commit, then starts scalable work. Progress is monotonic, latest-value
  coalesced to at most 20 UI updates per second, and checked against cancellation
  plus exact request identity immediately before publication.
- Equivalent collection snapshots do not advance public revisions. SwiftUI
  `body` never decodes media bytes; decoded images come from bounded caches.
- Popovers, sheets, and system controllers handle success, cancellation, both
  SwiftUI and UIKit dismissal, presenter loss, construction/presentation failure,
  and stale callbacks. Temporary files stay alive only for the exact attempt and
  are cleaned idempotently after its system consumer releases them.
- Diagnostics are low-cardinality milestones. Public logs and UI never expose
  capture/Photos IDs, file URLs or paths, proof/assertion bodies, credential/key
  IDs, backend response text, or per-chunk events.

No numeric launch SLO is claimed until an optimized, debugger-detached physical
iPhone baseline records the same route and reset conditions. Debug or Simulator
measurements are diagnostic only, and a warm rerun cannot close a cold-path gap.

## 3. Camera And Capture

### 3.1 Standard and Photographer Mode

**Standard** is the ordinary camera path. Its visible field-of-view choices
must each resolve to a corresponding RGB/depth capture plan. A field-of-view
selection is not allowed to be a preview-only magnification that then claims a
different captured view or depth relationship.

**Photographer Mode (PRO)** is a fixed eligible rear depth/manual-control path:

- It supports both Photo and TAP Video.
- It uses the eligible rear LiDAR 24 mm / 1x path.
- It does not expose cropping, a multi-focal selector, or an unproven LiDAR
  hardware-zoom range.
- It exposes EV, ISO, shutter duration, AF/MF, and focus-only tap assist on the
  same active control path. Aperture (`ƒ`) is read-only.
- Standard Basic EV remains a Standard capability.
- Front-camera MF, PRO multi-focal operation, automatic LiDAR/RGB fusion,
  adjustable physical aperture, and a promise of 2x/3x depth-safe LiDAR zoom
  are explicit non-goals.

White-balance UI, true source switching, and broader physical-device coverage
are future work. Source switching, if approved, must recompute depth and manual
control capabilities from the active Apple camera path; it must not be described
as ordinary preview zoom.

The executable capture path has these fail-closed boundaries:

- Planning is pure decision logic. A Standard choice resolves one Apple-paired
  RGB/depth device or virtual-device constituent, compatible active formats, and
  a depth-safe raw `videoZoomFactor`; unsupported pairings never become capture.
- `CaptureSessionController` is the sole `AVCaptureSession` mutator. Runtime
  executes the supplied plan on its serial session queue, validates stale device
  and capability signatures before control writes, and never reinterprets a
  semantic FOV label as raw zoom.
- Output selection resolves one reviewed profile against the live photo output
  before graph configuration. Settings, packager, manifest, and validation use
  that same resolved container, codec, dimensions, quality, and depth state;
  unavailable combinations fail instead of silently falling back.
- The UI requests plans and presents public-safe values; it does not construct
  capture plans, mutate AVFoundation, receive proof/key material, or expose raw
  device, capture, Photos, path, URL, or error values.
- Preview crop is provenance metadata only. Release never destructively crops
  the final image or depth map, and Debug overrides use the same SingleCam path
  rather than an independent depth pipeline.

### 3.2 Still Photo and Live Photo

- Still Photo supports the reviewed HEIC and JPG TAP depth-photo contracts.
- A still photo that receives no depth is still saved, signed, and exported.
  The user receives a non-blocking `Depth unavailable` indication.
- Live Photo capture, paired MOV handling, signing, export, playback, and the
  existing versioned verification contract are current capabilities.
- Live Photo depth comes from the primary still photo; TAPCam does not claim
  per-frame MOV depth.
- A per-frame Live Photo video-depth product is an explicit non-goal for the
  current Live Photo contract and would require a separately designed format.
- The shutter path uses the most recent cached optional location and never waits
  for a new Core Location prompt. It stages one unsigned artifact in the Pending
  Capture Queue and returns; App Attest signing and Photos export are serialized
  later and never extend foreground capture completion.

### 3.3 TAP Video

TAP Video's current product contract includes:

- capture and finalization of the current shared-contract TAP Video family;
- pending ingest, signing, export, and original-resource readback;
- TAP Library poster and local foreground RAW playback;
- registered 2D playback when registration is available;
- both Standard and eligible PRO Video capture paths.

No-depth TAP Video follows the same non-blocking principle as still photos:

- retain the valid RGB/audio artifact;
- record zero or missing depth coverage truthfully;
- sign and export the artifact;
- show a non-blocking depth-unavailable warning;
- do not turn missing depth alone into a terminal capture failure.

TAP Video finalization is one ordered local transaction: finish media, inspect
the finalized tracks, construct the shared-contract metadata/container, validate
the artifact against those observed facts, then atomically publish it into the
Pending Capture Queue. One capture publishes one original MP4 with no durable
preview movie, JSON sidecar, ZIP, or Debug derivative. Requested settings never
substitute for finalized track facts; container finalization must not rewrite
existing media tables or offsets. Parsing, hashing, consistency, calibration,
depth, timeline, and gap checks remain bounded and streaming rather than loading
the complete MP4 into `Data`. The current 180-second UI stop is recording policy,
not a format or decoder limit.

Pending signing uses the exact finalized bytes. Before signing, local binding
reconstruction must pass; after proof insertion and again after Photos original
readback, identity and local binding are revalidated. Photos playback success or
a filename is only an index hint. Missing depth is not an integrity failure, and
depth health remains an optional semantic gate after local binding succeeds.

TAP Video 3D is future work. AirPlay, Picture in Picture, and background playback
are outside the product scope and must not remain on the Todo list.

### 3.4 Output and provenance scope

- Release exposes HEIC/JPG **Output Format** only.
- `Speed / Balanced / Quality` capture prioritization is Debug tuning, not a
  Release Photo Quality picker and not a resolution or compression promise.
- RAW/ProRAW, 24 MP deferred delivery, arbitrary non-TAP video, and complete
  external C2PA support are future work.
- TAPCam currently has no C2PA certification or authority to claim completed
  C2PA compliance. New resource, manifest, and signing designs must avoid
  blocking future C2PA compatibility.

Shared manifest, canonical JSON, container, proof-slot, content-binding, KLV,
and signing bytes come only from the pinned TAPArtifactContracts revision. The
producer encodes that contract but never creates a local variant. Photo and Live
Photo packaging preserves the primary pixels and Apple auxiliary depth without
a decode/re-encode pass. The shutter-time artifact contains a proof-free manifest
and the fixed empty proof slot; later signing binds the exact canonical payload
and media resources, fills only that slot, and never hashes a re-encoded manifest.

Every signed Still, Live Photo, or TAP Video path has a final-byte gate before
Photos save. It reopens the exact outgoing bytes and fails closed on container,
schema/canonical form, manifest identity, source/profile facts, resource set,
proof-slot cardinality, digest/content binding, or declared-versus-actual depth
mismatch. A Live Photo validates its paired MOV as part of the same resource set.
No queue status, filename, earlier validation, or successful signing call may
bypass this gate, and Photos writers accept no unsigned artifact.

## 4. Locked Camera

Locked Camera is **experimental**, not a current production capability.

- Existing POC, E-series experiments, API notes, smoke results, and their code
  are historical experimental evidence only.
- They may guide a later experiment but must not be presented as the current
  product implementation.
- The active goal is a new lifecycle-correct version that can launch, present a
  real first frame, capture, suspend, exit, and relaunch without lifecycle
  freezes or black-screen regressions.
- This work belongs on the project board and remains isolated on its dedicated
  experiment branch until explicitly promoted.
- Production promotion requires a separate decision and attended device
  acceptance.
- The main shipping project embeds no Locked Camera capture or control
  extension and owns no Locked Camera shared intent, URL or user-activity
  entry, app-context publication, or session-content import runtime.
  Experimental implementations belong only on dedicated experiment branches;
  Git history remains the archive for removed main-tree code.

The extension does not own App Attest, Photos export, network work, Live Photo,
or unsolicited permission requests. Those remain explicit non-goals for the
experimental extension boundary.

## 5. TAP Library, Pending Capture Queue, And Viewer

### 5.1 Required terminology

Use these terms consistently:

- **TAP Library**: the user-facing mixed-media grid and Viewer containing still
  photos, Live Photos, and TAP Video.
- **Pending Capture Queue**: the app-private queue for pending artifacts,
  signing, Photos export, retry, and cleanup. The implementation module may
  still be named `TAPLibrary`, but product and architecture prose must call this
  queue the Pending Capture Queue.

Never use `TAP Library` to mean the private queue. Never expose `Pending Capture
Queue` as the name of the user-facing gallery.

#### 5.1.1 Pending Capture Queue lifecycle

The queue serializes signing, Photos export/readback, retry, and cleanup. Its
durable states are `pending`, `waitingNetwork`, `signing`, `signed`, `exporting`,
`exported`, `failedRetryable`, and `failedTerminal`. One worker runs at a time;
within one run it visits a capture ID at most once and prioritizes
`signed/exporting`, then `pending/signing`, then retryable/network-waiting work.
There is no hidden fine-grained stage scheduler, `nextAttemptAt`, cooldown, or
manual Release signing Retry until the separately approved optimization exists.

Protected-data unavailability stops the worker before any private queue read or
mutation and preserves the current record rather than inventing a failure.
Records, bundle paths, and fixed artifact names are validated fail closed before
filesystem access. TAP Video proof filling uses an independent same-bundle
working generation and atomically publishes the completed inode; failure or
cancellation discards that generation without mutating a file Viewer or Share
may hold. Export pre-commit and commit-ambiguous state survives interruption so
retry cannot create a duplicate Photos asset. Final bytes are revalidated before
save and original-resource readback before marking the record exported.

Exported large files and precise pending location are removed when no longer
needed; the minimal record, thumbnail, and Photos identifier may remain for
Library identity. Durable route context stores protected fixed-length tokens,
not raw capture or Photos identifiers, and can resolve only against the current
visible item set. It never triggers media reads, signing, export, retry, Photos
fetch, or automatic analysis navigation.

#### 5.1.2 PhotoKit request and catalog boundary

PhotoKit request-ID installation and continuation installation each occur at
most once; cancellation, success, and failure compete for one terminal result.
Cancellation before installation cancels a later request immediately, and stale
or degraded callbacks cannot complete a newer request. Resource-to-memory,
resource-to-file, display-image, and Live Photo adapters keep their distinct
callback semantics while sharing the same exact lifecycle rules.

The Library store is observer-inert when constructed. It activates PhotoKit
observation only after usable Photos access is established and deactivation
cancels queued/in-flight refreshes. Resource Initialization consumes only the
first usable identity/order snapshot; an empty catalog succeeds and never waits
for iCloud originals, thumbnails, posters, hashes, ZIP, or media decode.

### 5.2 Current Viewer

The current design is the Photos-style mixed-media Viewer:

- horizontal previous/current/next asset paging;
- stable viewer chrome;
- a bottom capsule for `RAW / 2D / 3D` modes;
- Share and Delete actions in the bottom toolbar;
- native Live Photo press-and-hold playback;
- local foreground TAP Video RAW/2D playback.

The former tool drawer, up-swipe Verify/drawer action, down-swipe dismissal,
detents, and top-level Heatmap/Overlay/Mask buttons are **deprecated designs**.
They are not Todo items and must not be restored as the starting point for a
future redesign. Any new Viewer proposal requires a new task and an approved
prototype.

Static-photo 3D means a native point projection for an eligible photo with
usable depth and calibration. It does not mean mesh, scan, reconstruction,
digital twin, or a world-space model. A possible SceneKit-to-Metal replacement
is a technical option activated by evidence, not a promised product feature.

TAP Video opens a pending file or a leased temporary copy of the Photos original
without loading the whole MP4. RAW RGB/audio playback is independent of depth;
2D requires a complete registered spatial descriptor and matching depth track.
Decode is bounded around the playhead, and seek, discontinuity, item change,
cancellation, backgrounding, or memory reset clears retained depth so stale
frames cannot cross contexts. Playback is local and foreground-only with
external playback disabled. Viewer Share validates and leases the exact same
original bytes; it does not re-fetch them, call backend Verify, pre-generate a
package, or persist a Share cache.

### 5.3 Share

The canonical Share flow is:

1. While the current item is being viewed, resolve its complete original
   resource set for normal Viewer use. The Share control remains unavailable
   while that original is absent, cloud-only, downloading from iCloud, or
   incomplete. A preview, thumbnail, displayed Live Photo, video poster, or
   first decoded video frame is not sufficient Share readiness.
2. Open one lightweight app-owned format-selection surface anchored to the
   Viewer's Share action. The same stable surface owns selection, preparation,
   public-safe failure, and Retry; it is not a separate modal
   page. On opening, check the actual ready original resource locally against
   its embedded TAP proof and content binding before resolving the public
   credential state. This local integrity gate must not contact the TAP
   verification backend.
3. Copy, package, or otherwise generate a Share-specific payload only after the
   user selects a format. Normal Viewer original-resource loading is not Share
   prewarming and must not pre-generate a package or persistent Share payload.
4. Selecting an implemented format keeps the selector hierarchy mounted and
   immediately replaces only that row's existing subtitle text with a thin,
   determinate preparation track inside the exact same fixed-height subtitle
   slot. The title, icon, badge, row, popover, and sibling positions do not
   change; no percentage or Cancel control is inserted. Other options remain
   visible but disabled. As soon as the payload is ready, dismiss that app-owned
   surface and present exactly one system activity controller. There is no
   whole-popover preparation page or app-owned ready/boundary page between
   selection and the system sheet, and TAPCam does not imitate or embed controls
   inside the system-owned presentation.
5. Remove a per-attempt temporary resource immediately when preparation is
   cancelled or becomes stale before system handoff. After handoff, pass the
   materialized file URL directly to the one system activity controller. Do
   not construct that controller while the app-owned popover is still visible:
   UIKit and LaunchServices begin inspecting the URL during initialization, so
   construction belongs to the actual system-sheet presentation boundary. The
   exact attempt's SwiftUI item binding and `onDismiss` fallback feed one
   exact-ID, idempotent app-owned end transition; there is no timed
   appearance/dismantle watchdog or destination-completion callback. When that
   sheet ends, schedule attempt-scoped source cleanup away from the main thread.
   UIKit may retain a dismissed controller internally, but that implementation
   detail must not retain the temporary file or block a later Share attempt.
   Closing the system-owned presentation remains an iOS/user action.

Preparation follows one direct policy across still photos, Live Photos, and TAP
Video: the option tap immediately replaces the clicked row's subtitle with a
thin, determinate, monotonic track in that same layout slot while the selector
remains mounted. No percentage, Cancel control, delayed-reveal threshold, or
artificial minimum-visible duration may postpone handoff or change geometry.
Payload readiness closes the popover immediately; the sibling system sheet then
constructs its controller and takes over. This sequence must not create a
separate app-owned preparation/ready page or blank frame, rebuild the
Viewer/pager/chrome, or flash a full-screen loading state.

The app must not pre-generate packages, background-prewarm them, or keep a
persistent share cache. The old direct-preparation/direct-system-share design
and the separate app-owned modal format sheet are deprecated.

The three public Share credential labels remain `Verified`, `Needs Retry`, and
`Failed`:

- `Verified` means the complete original resource set passed the local TAP
  proof/content-binding integrity gate for the bytes that may be shared.
- `Needs Retry` is emitted only by the app-private Pending Capture Queue for an
  unsigned capture whose signing operation is pending or retryable.
- `Failed` means a terminal queue failure or a complete resource whose embedded
  proof/content binding is missing, malformed, incomplete, or does not match
  the actual bytes. A Photos/iCloud asset must not become `Failed` merely
  because its old Pending Capture Queue record no longer exists.

`Verified` is the approved public label, not the name of a backend-verification
result. Internal state and diagnostics for that branch must use
`localIntegrityPassed` / “本地完整性检查通过” semantics so source and telemetry
cannot imply that the App Attest assertion was independently verified.

Local integrity failure disables `.tapnap`, because TAPCam cannot describe that
payload as verifiable. Direct image or video sharing remains available with an
explicit warning that verifiability is not guaranteed. Live Photo `.tapnap`
requires both the original photo and its signed paired MOV.

Still and Live Photo `.tapnap` sharing and supported original-media sharing are
current. TAP Video `.tapnap`, Sticker, and Link remain future items until their
contracts are implemented.

### 5.4 Delete

- Exported Photos assets use the system Photos deletion semantics and system
  confirmation only. TAPCam must not add a second app-owned confirmation.
- Pending or local-only captures require an app-owned confirmation before local
  data is removed.
- After deleting the current item, move to the item that occupied the next
  index when possible; otherwise move to the previous item. Close the Viewer
  only when the Library is empty.

## 6. Credential And Verification UX

TAPCam uses the fixed private credential lookup name `photo_keyid`. The name is
not an Apple claim, user identity, or trust decision and must remain stable;
future account/install/tenant naming requires opaque or hashed identifiers, never
raw PII. Apple retains the private key; Keychain stores only the key handle and
credential metadata.

`prepare` creates and attests a new key and persists its mapping only after
backend acceptance; `prepareIfNeeded` may reuse a ready mapping; `reset` removes
only that name's local metadata and health token, not the Apple private key or
backend record. An unsupported device or failed preparation never authorizes a
silent trust fallback. The runtime accepts only the configured HTTPS base URL
without an endpoint path; localhost, bare IP, cleartext HTTP, and `/healthz`-style
endpoint URLs fail configuration. Debug uses App Attest development metadata and
Release/TestFlight uses production; runtime metadata, entitlement, and build
configuration must agree. `AppAttestKit` remains pinned until its revision is
deliberately reviewed and advanced.

The explicit first-install Network row owns initial App Attest challenge,
registration, and backend verification. Post-setup credential preparation is a
different, guarded task released only after `t5`; it cannot gate Setup, Required
Permission Check, Resource Initialization, first frame, preview, interaction, or
ordinary local capture. Its local health token is bound to bundle ID,
version/build, backend URL, App Attest environment, and credential name; changing
one invalidates the token and requires preparation again.

Capture signing is offline file proofing: the app constructs the shared canonical
capture `signingBinding` and asks `DCAppAttestService` to sign that hash directly.
It does not use the protected-request `generateAssertion` route and has no server
assertion challenge. The final local export check proves byte self-consistency,
not Apple attestation trust, registered-key authenticity, freshness, or replay
protection. The cross-project server trust and HTTP requirements remain in
[App Attest BackendContract.md](AppAttest/BackendContract.md).

Release Settings presents `Photo Integrity` as one `Protection Readiness` row
with `Not Ready`, `Preparing`, `Ready`, or `Preparation Failed`, plus Prepare or
Retry where applicable. It exposes no App Attest terminology, backend URL,
credential/key ID, raw error, or proof. Public diagnostics use fixed error
domain/code and scalar outcomes; URLs, paths, identifiers, proof/assertion bodies,
backend responses, and localized error text stay private. Debug-only controls do
not expand Release behavior.

For a capture made by TAPCam whose attestation/signing process has completed,
TAPCam has already performed the App Attest signing operation. The app
therefore:

- keeps unsigned, retry, and terminal signing state in the app-private Pending
  Capture Queue rather than maintaining a second durable signed/unsigned index
  for every exported Photos asset;
- may expose the queue state for private pending captures in Share presentation;
- runs the shared
  [local artifact-binding gate](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/bindings/capture-binding-and-proof-v1.md#local-artifact-binding-gate)
  over the complete original resource set before sharing, including the paired
  MOV for a Live Photo and the original video bytes for TAP Video;
- does not submit a new App Attest Verify request to the TAP verification
  backend every time the user views or shares an owned capture;
- does not require a separate Verify button for its own attested captures.

Passing that local gate does not re-sign the capture or establish registered-key
App Attest assertion authenticity. The current App keeps only its key handle;
complete assertion authenticity remains a backend or explicitly provisioned
verifier responsibility. iCloud may be used only to retrieve the original
Photos resources needed by the local gate.

A true in-app Verify workflow becomes relevant only if a future product accepts
external media whose origin and credential state are not already owned by the
current capture pipeline. External import and Verify are future work and need a
separate product contract.

The browser Live Photo verification flow remains an important cross-repository
delivery boundary. Its artifact conventions are defined by the shared
[contract index](https://github.com/TAP-NAP/TAPArtifactContracts/blob/ca3b223e0717242ce1016b34dc34f04ef2417936/CONTRACTS.md);
TAPCamDemo retains its app-side behavior and handoff responsibility. Neither
document claims that the external browser verifier is implemented inside
TAPCamDemo.

Fine-grained credential cooldown, retry windows, and stage-specific pause are
future technical optimization. A public-release persistence policy must be an
explicit later decision; pre-release development records are not migrated.
The current coarse Pending Capture Queue behavior remains the distinct §5.1.1
lifecycle and must not be mistaken for that future design.

## 7. Claim Boundaries

TAPCam may claim a capture credential and integrity over the explicitly bound
resource set. It must not turn that claim into proof that:

- a person, event, location, or time is real;
- media is non-AI or not a recapture;
- physical depth is correct;
- the capture is fresh or protected against every replay.

`Photo Integrity = Ready` means the protection capability is prepared; it is
not a new cryptographic verification result. The Simplified Chinese translation
`照片保真` is deprecated because it can imply visual quality or real-world
authenticity. A replacement term requires an explicit copy decision before it
is synchronized to localization, prototypes, marketing claims, and acceptance
assets.

## 8. Evidence And Acceptance

Every current capability with missing device evidence receives a separate
`DeviceAcceptance` task. Before execution, the product owner confirms the test
scope. Its acceptance record must include:

- related delivery and product-contract section;
- build/commit, device, and OS;
- prerequisites and reset/install procedure;
- numbered user actions;
- an expected result for every action;
- required evidence types, such as structured logs, automated assertions,
  textual owner verdicts, and output artifacts where the procedure actually
  needs them;
- explicit pass, fail, and blocked conditions;
- final human confirmation.

Simulator tests, automated UI tests, structured logs, and procedure-approved
artifacts may contribute evidence, but they cannot impersonate an attended
physical-device acceptance. Image or video proof is retained only when the
specific owner-approved procedure requires it. The TAP-0040/TAP-0041 startup
lifecycle procedures retain no photo, screenshot, or screen recording; they
use public-safe structured logs, automated assertions, and an owner-live
textual verdict. Only an explicitly recorded owner acceptance can close a
`DeviceAcceptance` task.

Cold-path behavior is a separate required evidence condition whenever a
capability performs first-install, empty-cache, first-open, large-catalog,
iCloud, or first system-presentation work. The attended procedure must include
a newly installed app or an explicitly cleared container/cache. A successful
warm re-entry is useful comparison evidence, but it cannot substitute for the
cold run or close a cold-path acceptance condition. Scalable work must follow
§2.7, including visible acknowledgement before it begins, bounded publication,
exact request ownership, cleanup, and public-safe evidence.

## 9. UI Design Source Of Truth

TAPCam uses two complementary current constraints:

1. This document owns functionality and state machines.
2. The approved HTML/Web prototype owns visible component hierarchy, icon
   identity, relative position, spacing, sizing, and simulated interaction.

The current static artifacts live in the independent `TAPCamPrototype`
repository at `Prototype/`. From the TAPCamDemo repository root, the standard
sibling checkout manifest is `../TAPCamPrototype/Prototype/manifest.json`.
TAPCamDemo does not retain a duplicate prototype implementation.

The Web prototype cannot redefine permissions, AVFoundation capability, camera
readiness, or other runtime facts. SwiftUI implementation must satisfy both
sources, followed by Simulator and physical-device acceptance. Prototype proof
is limited to visible hierarchy, relative geometry, icon identity, responsive
layout for approved iPhone viewports, and simulated interaction. It cannot prove
native lifecycle, real permissions/camera/depth/signing/Photos behavior,
accessibility, performance, or physical-device acceptance.

Every visible change first records one approved Task, affected Product Contract
states, prototype path/revision, in-scope components/icons, uncovered states,
and Simulator/device acceptance. The workflow is fixed:

```text
Product Contract + approved Task
    -> sibling HTML/Web prototype revision
    -> explicit product-owner visual approval
    -> SwiftUI implementation
    -> Simulator comparison
    -> attended device acceptance when required
```

HTML/Web is the default visual specification; if the owner chooses another tool,
its accepted result is synchronized into the Web prototype so there is still one
active visual truth. Do not fake system permission dialogs or system-owned
controllers: prototype only the app-owned before/after states and label the
boundary. An urgent runtime or safety fix may precede prototype work only when it
does not intentionally change UI or the owner explicitly approves the exception;
any visible divergence must be synchronized before closure.

If native platform behavior conflicts with the prototype, return to the Task for
a decision rather than silently changing the product state machine or imitating
a system control. Prototype approval never closes implementation, parity, or
device evidence. The Viewfinder remains English; other app surfaces inherit the
selected app locale unless a separately approved product/copy Task changes that
boundary.

Prototype coverage grows by Task-scoped vertical slices rather than requiring a
complete Web copy of TAPCam before native work. Each slice reads the applicable
product states from this contract, records uncovered states explicitly, and
becomes implementation authority only for its approved visible hierarchy and
simulated interaction.
