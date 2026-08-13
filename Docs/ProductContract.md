# TAPCam Product Contract

- Status: canonical product constraint document
- Owner: product owner
- Last updated: 2026-08-13

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
2. [ProjectBoard.md](ProjectBoard.md) tracks work states and history.
3. [UIPrototypeContract.md](UIPrototypeContract.md) defines the visual-prototype
   to SwiftUI workflow and the authority of an approved Web prototype.
4. `Docs/Acceptance/` stores evidence and executable acceptance procedures.
5. Module READMEs explain implementation ownership.
6. AITrace, dated acceptance reports, branch audits, old implementation plans,
   POCs, and experiment logs are historical records. Once their still-relevant
   facts, acceptance procedures, and cross-project obligations have been
   migrated, they do not need to remain in the current documentation tree. Git
   history is the recoverable archive. Until removal, they cannot override this
   contract.

`Done` on the project board means a task met its recorded completion condition.
It does not independently declare a current product capability. Conversely, a
missing device test is tracked through an evidence task and does not make an
implemented feature a Todo again.

## 2. First-Install Setup

### 2.1 Explicit action owns every setup operation

Every action row on the first-install setup page follows the same rule:

- Camera, Photos, Location, and Microphone system prompts may be requested only
  by tapping that row's explicit **Allow** action.
- Network preflight may start only from its explicit setup-page action.
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

- Required before `Continue`: Network preflight, Camera authorization, and
  Photos authorization.
- Optional and skippable: Location and Microphone authorization.
- Skipping Location means captures may continue without location metadata.
- Skipping Microphone means Live Photos and TAP Video may continue without
  captured audio.
- OS authorization and TAPCam's in-app data-use preference remain separate
  decisions. An OS grant does not force the corresponding data-use switch on
  after the user has explicitly opted out.

### 2.3 Network retry

One explicit Network action may run a bounded sequence of automatic attempts:

1. Attempt the preflight.
2. On a retryable failure, wait for the policy-defined interval and retry.
3. Stop automatic attempts when the total wall-clock timeout is reached.
4. After timeout, remain on setup and require the user to press **Retry** to
   start a new bounded attempt sequence.

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
subtitle **Please Wait**. It exists to prevent the app from entering the camera
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

App Attest credential warmup and Pending Capture Queue retry begin after camera
entry as background work. They do not block the first interactive frame and are
not the same operation as the required Network preflight.

### 2.5 Completion markers

Permission/setup completion and Resource Initialization completion are separate
facts. Resource Initialization owns an independent marker identifying both the
current installed app update and the current initialization-schema generation.
Write it atomically only after the camera-interactive and TAP Library catalog
readiness groups have both succeeded.

- It is not proof that any permission remains authorized forever.
- It is not a recurring permission gate for later launches.
- An absent marker, a marker for another installed update, or an initialization-
  schema mismatch requires the gate. A fresh installation or reinstallation has
  no matching marker.
- An interrupted or abnormally incomplete run leaves the marker absent or stale
  so the next launch remains in Resource Initialization.
- Ordinary later launches whose marker exactly matches the current update and
  schema generation silently skip Resource Initialization.
- If a permission changes later, the affected feature handles the missing
  permission in context. The app does not send the user through first-install
  setup again.
- A legacy persisted key name may remain as an implementation compatibility
  detail, but it cannot merge setup permission state with this versioned
  readiness marker or redefine the marker's product meaning.

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

### 3.2 Still Photo and Live Photo

- Still Photo supports the reviewed HEIC and JPG TAP depth-photo contracts.
- A still photo that receives no depth is still saved, signed, and exported.
  The user receives a non-blocking `Depth unavailable` indication.
- Live Photo capture, paired MOV handling, signing, export, playback, and the
  existing versioned verification contract are current capabilities.
- Live Photo depth belongs to the primary still photo. The paired MOV is a
  signed resource; TAPCam does not claim per-frame MOV depth.
- A per-frame Live Photo video-depth product is an explicit non-goal for the
  current Live Photo contract and would require a separately designed format.

### 3.3 TAP Video

TAP Video's current product contract includes:

- one MP4 containing RGB, optional audio, private KLV depth metadata, manifest,
  and proof contract;
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

### 5.3 Share

The canonical Share flow is:

1. While the current item is being viewed, resolve its complete original
   resource set for normal Viewer use. The Share control remains unavailable
   while that original is absent, cloud-only, downloading from iCloud, or
   incomplete. A preview, thumbnail, displayed Live Photo, video poster, or
   first decoded video frame is not sufficient Share readiness.
2. Open one lightweight app-owned format-selection surface anchored to the
   Viewer's Share action. The same stable surface owns selection, preparation,
   cancellation, public-safe failure, and Retry; it is not a separate modal
   page. On opening, check the actual ready original resource locally against
   its embedded TAP proof and content binding before resolving the public
   credential state. This local integrity gate must not contact the TAP
   verification backend.
3. Copy, package, or otherwise generate a Share-specific payload only after the
   user selects a format. Normal Viewer original-resource loading is not Share
   prewarming and must not pre-generate a package or persistent Share payload.
4. Present the system activity controller only after that payload is ready.
   The app-owned surface hands off directly to this one system-owned
   presentation; TAPCam does not imitate or embed controls inside it.
5. Remove per-attempt temporary resources on completion, cancellation, or
   dismissal.

Preparation presentation follows one anti-flash policy across still photos,
Live Photos, and TAP Video:

- work completed within 50 ms never inserts progress UI;
- work still running after 50 ms reveals progress in the same anchored surface;
- once revealed, progress remains visible for at least 400 ms, advances
  monotonically, and reaches 100% before handoff when preparation completes
  early; and
- selection, preparation, and system handoff must not create an intermediate
  blank frame, rebuild the Viewer/pager/chrome, or flash a full-screen loading
  state.

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

For a capture made by TAPCam whose attestation/signing process has completed,
TAPCam has already performed the App Attest signing operation. The app
therefore:

- keeps unsigned, retry, and terminal signing state in the app-private Pending
  Capture Queue rather than maintaining a second durable signed/unsigned index
  for every exported Photos asset;
- may expose the queue state for private pending captures in Share presentation;
- locally recomputes the embedded proof/content binding over a complete
  original resource before sharing it, including the paired MOV for a Live
  Photo and the original MP4/MOV bytes for TAP Video;
- does not submit a new App Attest Verify request to the TAP verification
  backend every time the user views or shares an owned capture;
- does not require a separate Verify button for its own attested captures.

The local content-binding gate confirms that the actual resource bytes match
the digest and signing binding embedded alongside the App Attest assertion. It
does not re-sign the capture, verify the assertion object's cryptographic
signature with a registered App Attest public key, or independently establish a
new backend credential verdict. The current App keeps only the App Attest key
handle; complete assertion authenticity remains the responsibility of the TAP
backend (or a future verifier with an explicitly provisioned public key).
iCloud may be used only to retrieve the original Photos resources needed by
this byte-integrity gate.

A true in-app Verify workflow becomes relevant only if a future product accepts
external media whose origin and credential state are not already owned by the
current capture pipeline. External import and Verify are future work and need a
separate product contract.

The browser Live Photo verification specification is an important
cross-repository delivery contract. It does not claim that the external browser
verifier is implemented inside TAPCamDemo.

Fine-grained credential cooldown, retry windows, stage-specific pause, and
migration are future technical optimization. Current product documentation must
describe the current coarse Pending Capture Queue behavior separately.

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
- required logs, screenshots, recordings, and output artifacts;
- explicit pass, fail, and blocked conditions;
- final human confirmation.

Simulator tests, automated UI tests, logs, and screenshots may contribute
evidence, but they cannot impersonate an attended physical-device acceptance.
Only an explicitly recorded owner acceptance can close a `DeviceAcceptance`
task.

Cold-path behavior is a separate required evidence condition whenever a
capability performs first-install, empty-cache, first-open, large-catalog,
iCloud, or first system-presentation work. The attended procedure must include
a newly installed app or an explicitly cleared container/cache. A successful
warm re-entry is useful comparison evidence, but it cannot substitute for the
cold run or close a cold-path acceptance condition. Scalable work must publish
visible acknowledgement before it begins and follow the repository standard
in [ColdPathResponsiveness.md](ColdPathResponsiveness.md).

## 9. UI Design Source Of Truth

TAPCam uses two complementary current constraints:

1. This document owns functionality and state machines.
2. The approved HTML/Web prototype owns visible component hierarchy, icon
   identity, relative position, spacing, sizing, and simulated interaction.

The Web prototype cannot redefine permissions, AVFoundation capability, camera
readiness, or other runtime facts. SwiftUI implementation must satisfy both
sources, followed by Simulator and physical-device acceptance. The complete
workflow is defined in [UIPrototypeContract.md](UIPrototypeContract.md).

Prototype coverage grows by Task-scoped vertical slices rather than requiring a
complete Web copy of TAPCam before native work. Each slice reads the applicable
product states from this contract, records uncovered states explicitly, and
becomes implementation authority only for its approved visible hierarchy and
simulated interaction.
