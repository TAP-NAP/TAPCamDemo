# TAPCam Startup Lifecycle And Workload Contract

- Status: `TAP-0087-r1-candidate`; exact owner approval pending
- Owner: product owner
- Task: `TAP-0087`
- Last updated: 2026-08-15
- Applies to: iPhone process launch, scene activation, startup routing, TAP
  Library entry, Photo Viewer entry, and startup-adjacent heavy work

This document gives TAPCam one vocabulary for installation events, process and
scene activation, visible startup surfaces, timing milestones, and heavy work.
It is the detailed contract referenced by
[ProductContract.md](ProductContract.md). The Product Contract remains the
highest product authority; this document owns the cross-module lifecycle and
workload detail needed by `TAP-0008`, `TAP-0009`, and `TAP-0083`.

The current Swift implementation does not yet satisfy every rule below. The
workload registry therefore distinguishes **observed current behavior** from
the **required target window**. A Web prototype can make the route and state
relationships reviewable, but it cannot prove native first-frame timing,
AVFoundation readiness, PhotoKit behavior, or device performance.

The product owner assigned a per-mismatch `fix0809Disposition` and
`fix0809Outcome` in the prototype manifest. The complete v17 catalog, including
originally aligned and log-accepted records, remains historical at
`fix0809@d4b19d9`. The active v18 panel is unresolved-only: it loads nine
lifecycle truths, partitioned into five lifecycle projections and four
workload-owned truths, plus eight Workload difference records comprising seven
timing differences and one semantic difference. Accepted and originally aligned
v17 records are not active JSON records or DOM nodes.

Only two unresolved outcome treatments remain active. An
`implementedNotLogVerified` record uses a yellow background with a red border:
the code changed, but the supplied device log did not cover enough of that
record to claim alignment. A `deferredFrozen` record remains red with a red
border. These colors are reviewer evidence for unresolved records, not a rewrite
of the audited source/target facts or a claim about an unexecuted scenario.

The frozen outcome excludes Network/App Attest and credential/network-dependent
Pending behavior from the current fix0809 implementation scope. It does not
turn the existing `/healthz` preflight into the target state, approve a Network
behavior change, or change this contract's pending whole-revision approval
status. Workload-level outcome may narrow a broader parent truth:
`deferredWorkGuard` remains yellow with a red border while its post-setup App
Attest and Pending recovery children remain frozen red records. The manifest
remains the single source for every active per-record disposition and outcome;
renderers must not derive child outcome from the parent truth ID. The complete
v18 composition remains `ownerReviewRequired`.

## 1. Canonical Vocabulary

Installation, activation, resource temperature, and visible surface are
orthogonal facts. Do not use `reinstall`, `cold start`, or `first launch` alone
in a Task, log, acceptance procedure, or performance conclusion.

### 1.1 Installation and restore context

| Canonical term | Exact meaning | Data expectation |
| --- | --- | --- |
| **Fresh Installation** | The app is installed without restoring a previous TAPCam app container. | Setup and initialization facts are absent. The device Photos Library may still contain TAP media. |
| **In-place App Update** | The bundle for the same app identity is replaced without deleting its container. Upgrade and downgrade are both included. | Setup normally survives. Initialization becomes stale when build identity or schema differs. |
| **Development Replacement Install** | Xcode, `devicectl`, or another development tool installs the same Bundle ID over an existing app. | It is a test method, not a route. The route uses the container, marker, and permission facts that actually remain. |
| **Delete-and-Reinstall** | The user or test procedure deletes the app, then installs it again. | The app container is new. Keychain residue must never be used to infer setup completion. |
| **Offload-and-Reinstall** | iOS removes the app binary while preserving app documents and data, then restores the binary. | Preserved setup and a current initialization marker remain valid; caches are never assumed to survive. |
| **Same-Device Backup Restore** | A backup is restored onto the same physical iPhone. | Restored setup may remain valid. The initialization marker must be revalidated against the restored installation generation. |
| **Cross-Device Migration Restore** | Backup restore, Quick Start, or another migration brings TAPCam data to a different iPhone. | A missing device-bound App Attest credential can enter First-Install Setup in credential-recovery mode. Existing Camera/Photos grants are read passively and are not replayed merely because the device changed. Initialization is stale for the new camera/device environment. |
| **Local State Inconsistency** | A setup or initialization marker is absent, corrupt, partially cleared, or mutually inconsistent. | Treat the invalid fact as absent. Do not relabel this as a Fresh Installation. |

Bare `reinstall` is prohibited in current specifications. State whether the
procedure means Delete-and-Reinstall or Offload-and-Reinstall.

### 1.2 Activation and resource context

| Canonical term | Exact meaning |
| --- | --- |
| **Foreground Process Launch** | iOS creates a new TAPCam process and activates a scene in the foreground. The system Launch Screen may be visible. |
| **Foreground Resume** | The existing process returns from inactive/background to active. There is no Launch Screen. |
| **Settings Return** | The existing scene becomes active after the user visited system Settings. It is a Foreground Resume with a mandatory fresh permission snapshot. |
| **Interrupted Relaunch** | A new process starts after setup or initialization ended before its completion marker was committed. |
| **Cold Resource Path** | Required code pages, caches, catalogs, media, or framework resources are not warm. This is a performance fact, not a product route. |
| **Warm Resource Path** | Some relevant resources are cached. It is comparison evidence only. |
| **First Process Launch After X** | The first new process after a named installation event, for example the first process launch after an In-place App Update. |

### 1.3 Visible surfaces

| Name | Owner | Meaning |
| --- | --- | --- |
| **iOS Launch Screen** | iOS | Static `UILaunchScreen` transition using `LaunchBackground` and `LaunchLogo`. It cannot own progress or initialization. |
| **First-Install Setup** | TAPCam | One-time surface whose required rows are the Network-triggered initial App Attest registration/verification, Camera, and Photos; Location/Microphone remain optional. The same surface may later appear in credential-recovery mode without replaying already-granted permission prompts. |
| **Required Permission Check** | TAPCam | Recovery surface entered when Camera or Photos is currently unusable after setup. |
| **Resource Initialization** | TAPCam | Stable invariant gate used only when the current initialization marker is absent or stale. |
| **Viewfinder** | TAPCam | Camera shell, real preview, and eventually safe primary camera interaction. |
| **TAP Library** | TAPCam | User-facing mixed-media catalog. It is not the private Pending Capture Queue. |
| **Photo Viewer** | TAPCam | Saved/pending still-photo viewing surface with stable chrome. |

`video poster` means a derived TAP Video thumbnail. It is unrelated to the iOS
Launch Screen and must never be called a launch poster.

The TAP-0087 reviewer keeps these surfaces in one combined UI page directory
and shows only the operations applicable to the selected surface. It does not
split the directory into parallel approved-slice and lifecycle entries.
**Settings** may appear only as a disabled `Pending — no approved slice`
catalog entry until a separately approved app-owned Settings visual exists.
Permission recovery's system Settings boundary does not authorize a fabricated
Settings preview or action model.

The Viewfinder prototype maps the current SwiftUI hierarchy and relative
geometry rather than inventing a simplified camera mock: two-row top chrome,
Dynamic Island clearance, rounded inset preview, FOV chips, flexible middle
space, professional-toolbar slot, capture row, and mode strip remain separate
layout owners. Only TAP Library entry is functional in this candidate. The
remaining visible controls are deferred to `TAP-0088`; that deferral is not
represented by a prototype-only badge inside the phone surface.

## 2. Route Facts And Priority

Startup route selection reads facts; installation labels are diagnostic
metadata only.

### 2.1 Persisted and runtime facts

- `S — SetupReceipt`
  - A structured receipt for the current local installation generation, not a
    bare Boolean.
  - Valid only after the user explicitly completes first-install App Attest,
    Camera, and Photos setup and presses Continue.
  - The Network row is the explicit trigger and visible owner of the initial
    App Attest registration/verification operation. A generic reachability
    check does not satisfy this row.
  - The receipt includes a local binding to the successfully created App Attest
    credential for this installation generation. Route selection may check the
    presence and local binding without performing a network health request.
  - Location and Microphone may be granted or explicitly skipped.
  - Once written, `S` records that the initial setup completed; it is not proof
    that the network or credential remains healthy forever.
- `P — RequiredPermissionSnapshot`
  - Camera is usable only when `.authorized`.
  - Photos is usable when `.authorized` or `.limited`.
  - `.notDetermined`, `.denied`, and `.restricted` are not usable.
  - Location, Microphone, and network availability do not affect `P`.
- `I — InitializationCompletion`
  - Identifies the current Bundle ID, short version, build, initialization
    schema generation, and installation/device generation required to reject a
    restored or migrated stale marker.
  - It is written atomically only after Camera interactive and the first usable
    TAP Library catalog metadata snapshot are both ready.
  - It is not permission evidence and is never stored in a purgeable cache.
- `R — ResumeTarget`
  - Records the safe app-owned destination requested before permission
    recovery. The current startup recovery target is Viewfinder. TAP Library or
    Viewer restoration requires its own explicitly approved route behavior.

The exact native storage schema and migration are owned by `TAP-0008` and
`TAP-0009`; these semantics may not be collapsed into one Boolean. A restored
Setup receipt without its locally bound App Attest credential is invalid and
enters Setup recovery. Existing Camera/Photos grants are shown passively and
are not requested again merely because the receipt needs credential recovery.

### 2.2 Deterministic route reducer

The route priority is fixed:

```text
if S is absent or invalid
    -> First-Install Setup
else if P is unusable
    -> Required Permission Check
else if I is absent, corrupt, or stale
    -> Resource Initialization
else
    -> Viewfinder
```

Consequences:

- A setup page never appears merely because an app version changed.
- Required Permission Check has priority over Resource Initialization, so an
  updated app with revoked Camera or Photos permission first explains and
  repairs the permission.
- Permission recovery has no Continue button. A fresh passive snapshot
  automatically re-runs the reducer.
- `.notDetermined` uses an explicit **Allow** action and then a system-owned
  permission boundary. `.denied` uses **Open Settings**. `.restricted` uses
  distinct policy-restriction copy and does not promise that Settings can fix
  it.
- The same status-specific actions apply to a permission row that was denied
  during First-Install Setup: a separate explicit **Open Settings** action may
  enter the Settings boundary, while a restricted row remains stable and
  disabled. Neither status may replay the original Allow event.
- During First-Install Setup, the explicit Network row runs the initial App
  Attest registration/verification and remains incomplete when that operation
  cannot reach its required service. This is a Setup-row state, not a
  permission-check route.
- After `S` is written, network failure never routes to Setup or Required
  Permission Check. Ordinary Viewfinder entry and capture remain
  network-independent.
- Later App Attest health/recovery and future membership networking are
  feature-owned, deferred work. They do not rewrite `S`, `P`, or `I`.

### 2.3 Scenario matrix

| Scenario | Facts read at activation | Required route |
| --- | --- | --- |
| Fresh Installation | `S absent`, `I absent`, current `P` read passively | Launch Screen -> Setup (App Attest + Camera + Photos required) -> Resource Initialization -> Viewfinder |
| Delete-and-Reinstall | New container; old Keychain residue ignored for `S/I` | Same as Fresh Installation |
| In-place App Update | `S valid`; `I` stale on any version/build/schema mismatch | Launch Screen -> Permission Check if needed -> Resource Initialization -> Viewfinder |
| Development Replacement Install | Whatever container and markers actually remain | Same reducer; same-build replacement does not force a special route |
| Offload-and-Reinstall, current build | Preserved `S/I`; caches may be empty | Launch Screen -> Permission Check if needed, otherwise Viewfinder |
| Offload-and-Reinstall, changed build | Preserved `S`; stale `I` | Launch Screen -> Permission Check if needed -> Resource Initialization -> Viewfinder |
| Same-Device Backup Restore | Restored receipt may outlive its non-restorable App Attest system key; `I` must validate current build/schema/install generation | Invalid local credential binding -> Setup recovery; then Permission Check if needed -> Resource Initialization -> Viewfinder |
| Cross-Device Migration Restore | Restored receipt cannot prove an App Attest key on the new iPhone; migrated `I` is stale for the new device generation | Setup recovery for App Attest -> Permission Check if needed -> Resource Initialization -> Viewfinder |
| Setup interrupted before Continue | `S absent` | Next process launch returns to Setup |
| Initialization interrupted | `S valid`; `I absent/stale` | Next process launch returns to Resource Initialization |
| Ordinary later Process Launch | `S/P/I` valid | Launch Screen -> Viewfinder |
| Foreground Resume | Existing process; no Launch Screen | Refresh `P`; invalid -> Permission Check; otherwise remain/return to the safe route |
| Settings Return | Existing process; no Launch Screen | Refresh only the affected permission snapshot, then automatically re-run the reducer |
| Camera or Photos revoked | `S/I` retained; `P` invalid | Required Permission Check; do not replay Setup |
| Location or Microphone revoked | `P` remains valid | Stay on the current route; the affected capture metadata/audio feature degrades in context |
| iOS update only | `S/I` unchanged unless another fact changed | No special route; the runtime still resolves current capabilities when Camera starts |

## 3. Timing Milestones

Milestones are events for one activation-to-interactive-camera journey. Durations
are written as intervals such as `Δt0–t1`. `t3/t4` are camera-entry milestones,
not reusable names for every later page. TAP Library and Photo Viewer use the
namespaced spans below. User time inside a permission sheet, Settings, or an
explicit first-install Network operation is recorded separately and is never
misreported as uninterrupted app CPU time.

`t0…t5` and their `Δ` intervals are canonical milestones of the TAP-0087 target
reducer. They are not claims that current main already emits those events. Any
current-main `t*` or `Δt*` label in the workload inspector is a source-order
inference used to compare placement with the target; it is not an instrumented
timestamp, physical-device measurement, duration, or performance result.

For Foreground Resume, `t1` means the first app-owned frame committed after that
activation request. It does not imply process creation and there is no Launch
Screen. The frame remains the safe return surface; the launch-brand bridge is
used only between a new process's Launch Screen and its initial route.

| Point | Canonical event | Completion evidence |
| --- | --- | --- |
| `t0` | **Activation Requested** | Foreground Process Launch or Foreground Resume request is recorded. |
| `t1` | **App First Frame** | The first app-owned frame for this activation is committed; on a process launch, the system Launch Screen can end. |
| `t2` | **Initial Route Committed** | First-Install Setup, Required Permission Check, Resource Initialization, or direct Viewfinder shell is stably mounted. A static gate's visible readiness is acknowledged here. |
| `t3` | **First Camera Preview Ready** | After any required Setup/permission/initialization gate, a current real preview frame is presented. |
| `t4` | **Interactive Viewfinder Ready** | Shutter and primary controls are safe, required first-interaction haptics are prepared, and—when Resource Initialization was required—the first usable Library catalog is ready and `I` is committed. |
| `t5` | **Deferred Work Released** | Startup-critical interaction is protected; post-setup App Attest, Pending Capture recovery, poster maintenance, and other non-blocking work may be scheduled according to their guards. |
| `tn` | **Selected Journey Terminal** | The deterministic fixture reached its selected end, which may include Library/Viewer navigation after `t5`; a stable empty TAP Library may terminate without inventing a Viewer transition. Deferred work may still run. |

### 3.1 Namespaced gate and page spans

The inspector keeps these spans beside `t0…tn`; they do not create extra route
facts or a second state machine.

| Namespace | Events |
| --- | --- |
| `S0…S4 — Setup` | `S0` surface committed -> `S1` explicit row action -> `S2` App Attest/system wait -> `S3` App Attest + Camera + Photos ready -> `S4` Continue and `S` receipt commit |
| `P0…P3 — Permission` | `P0` check committed -> `P1` explicit Allow/Open Settings -> `P2` system/settings wait -> `P3` fresh Camera/Photos snapshot and reducer re-evaluation |
| `C0…C4 — Camera/RI` | `C0` camera route work eligible -> `C1` graph configured -> `C2` first real preview -> `C3` interaction and first catalog both ready in either order -> `C4` marker/route publication at `t4` |
| `L0…L2 — Library` | `L0` user opens Library -> `L1` identity/order catalog visible -> `L2` visible-cell thumbnail batch published |
| `V0…V2 — Viewer` | `V0` user opens photo -> `V1` stable chrome plus bounded display rendition -> `V2` back/cancel and stale work rejected |

The stable `V1` chrome presents the independently approved `TAP-0081` Share
slice locally inside the same Photo Viewer. This presentation is neither a
route nor a page round trip: it changes no browser URL and uses no resume key,
session storage, or reducer replay. Opening, selecting, preparing, completing,
or closing it creates no TAP-0087/TAP-0008/TAP-0009 `V*` event, workload,
timing span, marker, payload-preparation state, or acceptance claim. Payload
readiness closes only the app-owned popover and records a TAP-0081-local system
boundary; no activity sheet, AirDrop target, or destination is simulated. The
underlying TAP-0087 Photo Viewer snapshot, sequence, focus, and workloads remain
unchanged.

### 3.2 Interval work budget

| Interval | Allowed | Prohibited |
| --- | --- | --- |
| `Δt0–t1` | Fixed-cost process bootstrap, dependency references, minimal local `S/I` read, passive Camera/Photos status read, and construction of the first lightweight app frame | Camera device/format enumeration, capture-session object graph, PhotoKit observer activation, catalog enumeration, pending-directory scans, poster/thumbnail work, network, App Attest, media decode, 2D/3D analysis |
| `Δt1–t2` | Pure route reduction, bounded state publication, and mounting the selected app-owned surface | Any work whose cost scales with Library count, pending-record count, media bytes, network, or camera format count |
| `Δt2–t3` | Route-owned work only: `W02` after the explicit Setup Network action; system-permission recovery after explicit actions; and, once Viewfinder/Resource Initialization is selected, `W03–W06` required camera/catalog work. User/system/network wait is labeled separately. | Post-setup App Attest (`W11`), Pending Capture recovery, video poster backfill, eager Viewer analysis, and off-screen thumbnails |
| `Δt3–t4` | Remaining direct Viewfinder/Resource Initialization blockers only: safe controls, required haptics, and a first usable Library catalog if it did not finish before preview | Orientation preparation as a blocker, unrelated refreshes, queue reconciliation, post-setup attestation, or maintenance that competes with first interaction |
| `Δt4–t5` | Observe the stable `t4` publication and release deferred-work guards. When Resource Initialization was required, `I` was committed atomically in the same transition that reached `t4`; it is not written afterward. | Treating any deferred completion as a prerequisite for Viewfinder, or delaying the `I` commit until after `t4` |
| `Δt5–tn` | Namespaced `L*`/`V*` user-triggered work plus guarded, cancellable, generation-aware maintenance away from the MainActor | Unbounded MainActor loops, stale publication, duplicate full scans caused by one logical transition, or executing TAP-0088/TAP-0089 deferred controls |

A synchronous MainActor slice remains below the 8 ms normal-operation budget
defined by [ColdPathResponsiveness.md](ColdPathResponsiveness.md). This is a
per-slice guardrail, not an invented end-to-end launch SLO. Native `t0…tn`
targets require physical-device baseline evidence before numeric limits are
approved.

## 4. Workload Registry

`Owner/executor` names a logical owner plus its real actor, queue, framework, or
system executor. These entries are not separate OS processes.

The inspector's workload record shape is fixed:

```text
observed { trigger, owner, earliest, blocks, network, evidence }
target   { trigger, owner, earliest, blocks, network, evidence }
alignment = aligned | partial | gap | deferred
```

`observed` is current-main source evidence. `target` is the required reducer and
ownership placement with its contract or Task evidence. Neither side may omit a
field or silently substitute a target statement for a current observation.
When `observed.earliest` uses a target-style interval name, it must include an
`inferred from source order` qualifier; it is never device timing evidence.
Each workload registers an inspection moment
`{ event, status, page }`, representing the lifecycle point the card should
open. Selecting the card first searches current playback history for a real
snapshot matching the complete registered moment and whose tail effects contain
that workload. It restores that matching snapshot, not the most recent arbitrary
effect or a later `cancelled`, `stale`, or unrelated terminal snapshot.

This is an atomic review-cursor change: the left UI surface and legal
operations, center phone, and right machine, timing, workload, marker,
ordered-log, sequence, and focus projections all come from the same snapshot.
Focusing only the machine/sequence while leaving another surface or phone
snapshot visible is invalid.

When current playback history has no qualifying snapshot, the same intentional
card click immediately authorizes switching to that workload's registered
canonical inspection fixture; it does not require a second confirmation button.
The registration identifies canonical initial facts and an ordered legal-event
path to the same inspection moment. The fixture is rebuilt through the normal
reducer and guards; direct snapshot mutation, synthetic events, skipped
predecessors, and fabricated `Ready`/`succeeded` states are forbidden. A
registered inspection moment at `eligible`, `running`, or `skipped` remains in
that exact real state across the catalog, phone, and inspector.

Unified inspector states are:

```text
dormant | waitingPrerequisite | eligible | scheduled | running |
waitingSystem | waitingNetwork | succeeded | failedRetryable |
failedTerminal | cancelled | stale | skipped
```

Native state remains visible beside the unified state; for example Pending
Capture `.signing` must not be replaced by the generic word `running`.

| ID | Workload and trigger | Observed current owner/executor | Scale/network | Required timing and blocker policy | Recovery/output/evidence |
| --- | --- | --- | --- | --- | --- |
| `W01` | Root Library store and observer construction on every process launch | MainActor; `TAPCamDemoApp.init`; PhotoKit observer | Constant setup, but activates PhotoKit; no network | Must move out of `Δt0–t1`. Observer activation is forbidden before an explicit Photos action when setup is incomplete. Never a Viewfinder blocker. | Process lifetime; current source: `TAPCamDemo/App/TAPCamDemoApp.swift`, `TAPCamDemo/MediaLibrary/LibraryMediaStore.swift` |
| `W02` | First-install App Attest bootstrap, currently represented only by a legacy `/healthz` preflight after the Network row action | MainActor UI state plus `URLSession.shared` today; target also uses AppAttestKit, Keychain, DeviceCheck, and the App Attest backend | Network and system cryptography; user-triggered | The Network row remains a required Setup action. After `S0`, its explicit `S1` action may run one bounded registration/verification sequence. A `/healthz` success alone is insufficient. It never runs from page appearance or foreground refresh and never becomes a later Viewfinder gate. | `bootstrapRunning -> automaticRetryWaiting/waitingNetwork -> timedOutAwaitingExplicitRetry` or `bootstrapReady`; connectivity recovery alone never starts a new sequence. Successful credential bootstrap contributes to `S`; native alignment belongs to `TAP-0008`. Current sources: `StartupGateCoordinator.swift`, `StartupBackendSecurityPreflight.swift`, `AppAttestRuntimeController.swift` |
| `W03` | Camera capability discovery when `CameraViewModel` is constructed | MainActor synchronous device/format enumeration | Scales with device/format count; no network | Forbidden in `Δt0–t1`. May start only after the Viewfinder/Resource Initialization route shell commits, with explicit state. | Cache/generation design belongs to `TAP-0083`; source: `CameraCapabilityResolver.swift`, `CameraView.swift`, `CameraViewModel.swift` |
| `W04` | Capture-session construction, configuration, start, and preview readiness | MainActor orchestration plus `tapcam.camera-capture.singlecam.session` serial queue and AVFoundation | Hardware/system wait; no network | Route-owned `Δt2–t4` blocker. Configuration alone is insufficient; real preview and safe controls are required. | Generation rejects stale results; 10 s engineering watchdog exists; source: `CaptureSessionController.swift`, `CameraPreviewView.swift` |
| `W05a` | Required first-interaction haptic preparation on Viewfinder appear/active | MainActor and UIKit haptic generators | Constant; no network | Bounded Viewfinder readiness work. It may block `t4`, never `t1`. | Re-prepare on active; source: `CameraHapticFeedbackController.swift` |
| `W05b` | Chrome-orientation notification/UI preparation | MainActor and UIDevice notifications | Constant; no network | May follow the route shell but must not become a Resource Initialization or `t4` blocker. | Reconcile on active; source: `CameraChromeOrientationController.swift` |
| `W06` | TAP Library catalog snapshot at initialization, Library entry, or invalidation | MainActor orchestration; store/fetcher actors; detached user-initiated merge | Scales with pending records and PhotoKit assets; catalog itself uses no media-byte download | First usable identity/order snapshot is a Resource Initialization blocker only when `I` is stale. Otherwise user-visible Library loading may proceed after acknowledgement. Never blocks `t1`. | Generation/stale result handling; source: `LibraryMediaStore.swift`, `DepthAlbumItemProvider.swift`, `PhotoKitLibraryMediaFetcher.swift` |
| `W07` | PhotoKit and Pending Capture change notification refresh | Callback -> MainActor debounce -> same catalog workers | Can cause repeated full scans; no required network | Deferred and coalesced. One logical queue transition must not fan out into repeated unbounded catalog scans. | Debounce/cancel stale publication; source: `LibraryMediaStore.swift`, `TAPPendingCaptureStore.swift` |
| `W08` | Video poster backfill on root mount | `LibraryVideoPosterBackfillService` actor, pending-store actor, detached utility AVAsset generation | Scales with videos and media bytes; no network | Maintenance after `t5`; never serialized ahead of the first required catalog snapshot and never a startup/permission blocker. | Per-candidate cancellation; retry next eligible maintenance window; source: `LibraryVideoPosterService.swift` |
| `W09` | Grid thumbnail resolution when a cell becomes visible | SwiftUI cell task; PhotoKit/store/cache actors; detached utility decode | Scales with visible media; grid forbids iCloud network | On-demand after Library shell/catalog publication. It blocks only its own cell rendition, not catalog identity/order or Viewfinder. | Cancelled/stale request cannot publish; source: `TAPLibraryItemCell.swift`, `DepthAlbumThumbnailPipeline.swift` |
| `W10` | Recent Library cover after camera start, foreground, revision, or worker completion | MainActor orchestration plus store/fetch/cache actors | One selected asset; conditional iCloud only for the cover | After `t5`, cancellable, never a Viewfinder blocker. iCloud wait changes only the cover state. | Request generation and cancellation; source: `CameraViewModel+Capture.swift` |
| `W11` | Post-setup App Attest health validation, recovery, or re-attestation | MainActor runtime controller; AppAttestKit actor; Keychain; DeviceCheck; `URLSession` | Conditional network; current version/build token can trigger full attestation | Earliest `t5`. This row excludes the initial required bootstrap in `W02`; later health/recovery never blocks route, preview, shutter availability, or ordinary local capture. | Timeout/reset/retry are credential-owned; source: `AppAttestRuntimeController.swift`, `AppAttestOperationTimeout.swift` |
| `W12` | Pending Capture Recovery Worker after startup delay, foreground, Library return, credential completion, capture, or video stop | `TAPPendingCaptureProcessor` actor; store actor; signer; Photos; DeviceCheck | Scales with pending records/media; conditional network during missing credential | Deferred after `t5` and guarded by camera-idle/protected-data/credential state. Not a startup blocker. Video-stop awaiting it is a current responsiveness gap. | Native states remain `pending/waitingNetwork/signing/signed/exporting/exported/failedRetryable/failedTerminal`; already-signed artifacts are exported, not routinely re-signed. Source: `TAPPendingCaptureProcessor.swift`, `TAPPendingCaptureProcessingPolicy.swift` |
| `W13` | Still thumbnail render during pending ingest | Pending-store actor with ImageIO/JPEG work | Scales with image bytes; no network | Capture-owned after shutter acknowledgement. Never startup work. | Output `thumbnail.jpg`; current renderer lacks cancellation: `TAPPendingCaptureThumbnailRenderer.swift` |
| `W14` | Video poster at recording stop | MainActor flow awaits store actor and detached utility poster generation | Scales with video; no network | Recording-stop work only. Failure may defer to `W08`; it must not make the recorded video unusable. | Source: `CameraViewModel+VideoCapture.swift` |
| `W15` | Viewer display rendition and current full analysis input when a still opens | MainActor slot state; PhotoKit/store actors; nonisolated async file/depth decode | Scales with media/depth pixels; conditional iCloud for original | Stable Viewer chrome and bounded display acknowledgement precede scalable work. RAW currently triggers eager full analysis; that observed cost must be shown until a later Task changes it. | Cancel on disappear/background; generation prevents stale publication; source: `DepthAnalysisCarouselState.swift`, `DepthAnalysisReader.swift` |
| `W16` | 2D plane-region analysis after a user seed/strictness change | MainActor state; detached utility geometry; detached user-initiated detector | Scales with depth pixels; no network | User-triggered Viewer work only. Forbidden during startup. Functional prototype interaction deferred to `TAP-0089`. | New request cancels old; partial publication is bounded; source: `DepthAnalysisPlaneRegionRequestCoordinator.swift` |
| `W17` | 3D projection payload, SceneKit installation, and motion parallax | Detached user-initiated payload; MainActor SceneKit install; CoreMotion main-queue updates | Up to bounded point sampling plus full RGB raster; no network | User-triggered Viewer work only. Forbidden during startup. Functional prototype interaction deferred to `TAP-0089`. | Signature cancels stale builds; public queued/building/installing/ready instrumentation is currently missing; source: `DepthPointCloudPreview.swift` |

### 4.1 Pending Capture terminology

The current product has one **Pending Capture Recovery Worker**, not a generic
`re-sign queue`:

- an unsigned record interrupted in `.signing` may sign again;
- an artifact that is already signed continues export/readback with its
  existing proof;
- an app update or new App Attest credential does not re-sign every existing
  signed artifact.

The workload inspector must display this distinction.

## 5. State Machines And Events

The reviewer prototype and later native instrumentation use the same conceptual
machine names. The table below is a semantic registry; it is not the approved
visualization form. The workbench must render the selected machine as a real
directed node-edge flow diagram with any recorded branch condition, current
node, and active transition. An absent condition is shown as unrecorded rather
than invented. A grid of buttons, pills, or state cards alone is insufficient
because it hides time and causality.

For `TAP-0087-r1-candidate`, the graph source is limited to node-edge
transitions recorded in the actual reducer journal, and the view is labeled
**Executed reducer path**. `machineRegistry.nodes` enumerates known node names
only; array adjacency is not evidence of a legal edge, branch, or next node and
must never be guessed as one. Rendering a full normative state graph later
requires an explicit transition registry with legal from/to edges and
conditions.

| Machine | Required states |
| --- | --- |
| `activation` | idle -> launchRequested/sceneResumed -> appFirstFrame -> routeCommitted -> terminal |
| `routeDecision` | idle -> readingFacts -> firstInstallSetup/requiredPermissionCheck/resourceInitialization/viewfinder |
| `firstInstallSetup` | notRequired -> awaitingExplicitActions or credentialRecovery -> attestationRunning/automaticRetryWaiting/timedOutAwaitingExplicitRetry or waitingSystem -> requiredReady -> completed |
| `requiredPermissionCheck` | notRequired -> inspecting -> awaitingAllow/awaitingSettings/restricted -> rechecking -> resolved |
| `resourceInitialization` | notRequired -> preparing -> cameraReadyCatalogPending or catalogReadyCameraPending -> bothReady -> markerCommitted |
| `cameraReadiness` | idle -> shell -> configuring -> previewReady -> interactive |
| `libraryCatalog` | dormant -> scheduled -> refreshing -> published/stale |
| `thumbnailPipeline` | idle -> resolving -> ready/cancelled |
| `appAttestCredential` | bootstrapIdle -> bootstrapRunning -> automaticRetryWaiting -> timedOutAwaitingExplicitRetry -> bootstrapRunning/bootstrapReady; after setup: dormant -> eligible -> preparing/waitingNetwork -> ready/failedRetryable |
| `pendingCaptureRecovery` | dormant -> eligible -> reconciling -> processing -> quiescent/blocked |
| `viewerLoading` | closed -> shell -> displayLoading -> displayReady -> returning -> closed |
| `viewerAnalysis` | deferredTAP0089 in `TAP-0087`; functional 2D/3D interactions belong to `TAP-0089` |
| `viewfinderControls` | deferredTAP0088 in `TAP-0087`; functional control interactions belong to `TAP-0088` |

Canonical reducer tokens include:

```text
SCENARIO_SELECTED
ACTIVATION_REQUESTED
APP_FIRST_FRAME_COMMITTED
INITIAL_ROUTE_COMMITTED
SETUP_ATTESTATION_TAPPED
SETUP_ATTESTATION_AUTOMATIC_RETRY_WAITING
SETUP_ATTESTATION_TIMED_OUT
NETWORK_BECAME_AVAILABLE
SETUP_ATTESTATION_RETRY_TAPPED
SETUP_ATTESTATION_COMPLETED
SETUP_PERMISSION_TAPPED
SETUP_PERMISSION_RECOVERY_TAPPED
SYSTEM_PERMISSION_RETURNED
SETUP_OPTIONAL_SKIPPED
SETUP_CONTINUE_TAPPED
PERMISSION_RECOVERY_TAPPED
PERMISSIONS_RECHECKED
CAMERA_DISCOVERY_STARTED
CAMERA_SESSION_CONFIGURED
CAMERA_PREVIEW_PRESENTED
CAMERA_INTERACTION_READY
LIBRARY_CATALOG_STARTED
LIBRARY_CATALOG_PUBLISHED
DEFERRED_WORK_RELEASED
LIBRARY_OPENED
LIBRARY_BACK_TAPPED
THUMBNAIL_BATCH_STARTED
THUMBNAIL_BATCH_PUBLISHED
PHOTO_OPENED
VIEWER_DISPLAY_READY
VIEWER_BACK_TAPPED
SCENARIO_TERMINATED
MEASUREMENT_PROFILE_CHANGED
```

Viewfinder control events and Viewer 2D/3D events may appear only as
`Deferred / child task` definitions in `TAP-0087`. They must not execute a
simulated workload until `TAP-0088` or `TAP-0089` is separately activated and
approved.

Every event is reduced once into:

- the app-owned phone surface;
- active `t0…tn` milestone and interval;
- active machine node and transition edge;
- eligible/running/blocked workload states;
- marker changes; and
- one bounded reviewer event-log entry.

The phone and inspector may not maintain independent state machines.

### 5.1 Timing-axis event projection

The primary event view is a sequence/swimlane organized by `t0…tn` points and
their `Δ` intervals. It uses at least these aligned lanes:

| Lane | Required projection |
| --- | --- |
| **UI** | The visible app-owned surface or the labeled iOS/system boundary before and after the event. |
| **Reducer** | The one canonical token, its precondition, and the resulting route/machine transition. |
| **Workload** | Work that became eligible, scheduled, running, blocked, cancelled, stale, or completed, including the actual owner/actor/queue. |
| **Marker** | `S`, `P`, `I`, or other lifecycle fact read, preserved, rejected, or committed by that transition. |

Connectors between lanes expose cause and effect: a UI operation may dispatch
one reducer event; that event may change workload eligibility; a valid
completion may publish a marker and later UI. Multiple events in one interval
remain ordered. Waiting for the user, system, or network is visibly distinct
from app CPU time. Lane items and connectors are derived only from recorded
trace effects; missing effects remain absent rather than being inferred from a
registry, display order, or expected product story.

The bounded ordered event log remains available through a **Timing / Ordered
log** switch. Both modes project the same reducer trace, sequence number, and
focused event; switching views cannot dispatch a product event or alter state.
The left-side action controls are therefore never used as substitutes for the
flow graph or timing sequence.

Reviewer workload differences are projected inside the existing **Workload**
lane. They never create a standalone comparison band, a second Workload lane,
or an additional reducer lane. Their canonical records are stored in the
prototype JSON manifest with this minimum shape:

```text
id, taskIDs, lifecycleTruthIDs, differenceType = timing | semantic,
differenceKind, checkpoint, mismatch, fix0809Disposition, fix0809Outcome
scope { path, trigger, anchorMeaning }
actual { workloadID, label, anchor, phase, qualifier, summary, evidence }
target { workloadID, label, anchor, phase, qualifier, summary, evidence }
traceBinding {
  scenarioGroupID,
  actualVisibleAfter { eventTypes, occurrence },
  targetEffect { eventTypes, workloadID, status, occurrence }
}
```

The controller loads those JSON records and derives the rendered count; it does
not hardcode a second copy. Lifecycle truth IDs are partitioned explicitly:
workload-owned mismatches render only in Workload, while route, persistence,
permission-recovery, marker-commit, and presented-state gaps remain in the
**08/09 生命周期** lane. The two ownership sets are disjoint and together cover
every active mismatch source truth. In v18 that partition is four workload-owned
truths plus five lifecycle-lane truths. The Workload projection contains eight
active difference records—seven timing and one semantic—and contains no
accepted or aligned historical record.

A workload difference preserves every canonical reducer workload effect in the
existing lane. Its manifest-owned current-main annotation appears as an
unresolved-outcome-colored **实际 · 不一致** card in the `actualVisibleAfter` reviewer
visibility/upstream
projection column only
when the selected scenario belongs to `scenarioGroupID`; the card separately
labels its explicit coarse `actual.anchor` lifecycle period.
The corresponding prototype workload is the existing reducer-trace effect that
uniquely matches event type, workload ID, resulting status, and one-based
occurrence; that existing effect becomes visibly blue and keeps its original
focus/status semantics.

When both ends exist, exactly one dashed SVG connector joins the actual card
to that blue trace effect. If the target effect is not yet in the journal, the
actual card says **既有 trace effect 尚未出现** but creates no blue substitute,
future milestone column, reducer event, workload transition, marker effect, or
phone-state change. Target lifecycle-anchor reachability is rendered separately
from the exact workload effect's canonical status, so `Eligible` or `Running`
cannot be misread as completion. Current-main anchors and `actualVisibleAfter`
remain reviewer source-order or predicate visibility projections. The selected
prototype reducer event is an upstream review checkpoint, not a claim that the
current-main workload executed there; neither placement is a native timestamp,
elapsed duration, or device-performance measurement.

### 5.2 Reviewer workbench, playback, and desktop composition

The workbench binds three regions to the same selected surface and trace:

- a left UI catalog plus contextual operations;
- a center `393 x 852` iPhone visual-truth canvas; and
- a right business/lifecycle/workload/state inspector containing the node-edge
  flow graph and timing-axis event projection.

Workload navigation obeys the same binding. A playback-history match rewinds or
advances the review cursor to the complete existing snapshot for the workload's
registered `{ event, status, page }` inspection moment, with the workload in the
tail effects. An absent match makes that card click itself the explicit fixture-
switch action: the registered canonical inspection fixture is replayed through
legal reducer events from its declared initial facts and stops at the registered
moment. Either path updates all three regions atomically; neither is a right-
inspector-only focus effect or permission to fabricate Ready.

The center canvas is the geometry authority only after the exact candidate is
owner-approved. If a native page exists without a prototype slice, the first
slice must reproduce its visible hierarchy and relative geometry one-to-one
before later SwiftUI changes consume it as a constraint. The iOS Launch Screen
remains a system-owned reference, and Settings remains a non-interactive
pending catalog entry until an approved slice exists.

The prototype's **Previous logical event** control is reviewer-only playback.
It restores the prior complete reducer snapshot and its selected trace focus;
it is not a canonical event, is not appended to the event log, and cannot start,
cancel, retry, or complete any workload. Pressing Next afterward reduces
forward from the restored snapshot through the same canonical event path.

Previous, Next, and Reset form one global review-playback row. None appears a
second time in a selected UI surface's contextual operations. This is a
presentation and ownership rule; it does not turn review playback into product
events or change the reducer semantics of Previous/Next/Reset.

That playback row precedes the Launch scenario controls in the left rail.
Contextual operations are also reducer-guarded: a phone control is listed only
when its corresponding event can legally reduce from the current snapshot.
For example, after a Setup Camera action enters `waitingSystem`, the Setup
operation list is empty; the recorded system return changes state before legal
row actions become visible again.

At the supported desktop review viewport, all three workbench regions remain
visible in one browser window without page-level scrolling. Individual
information regions may scroll internally. This layout is analysis tooling,
not a product surface or an iPad, Mac, or native runtime-dashboard requirement.

## 6. Debug And Performance Measurement

Debug/Xcode is a measurement dimension, not a route fact. It may magnify lag
through `-Onone`, debugger attachment, runtime diagnostics, logging, extra
camera profiles, queue backtrace recording, and Debug-only 3D probe output.
It cannot make a source-visible launch blocker safe or explain away a
Release-visible issue.

Use the same physical iPhone, installation context, marker state, Library
population, cache condition, and scenario for this minimum comparison:

| Build | Debugger | Purpose |
| --- | --- | --- |
| Debug | attached | Developer worst-case interaction and diagnostics |
| Debug | detached, launched from Home Screen | Separates Debug compilation from debugger attachment |
| Release/Profile | attached | Instruments optimized code while recording attachment overhead |
| Release/Profile or TestFlight | detached | Closest product baseline |

Each run records:

- exact build/commit and installation method;
- `S/P/I` facts and selected scenario;
- Library and Pending Capture counts plus cold/warm resource context;
- `Δt0–t1`, `Δt1–t2`, `Δt2–t3`, `Δt3–t4`, namespaced `S/P/C/L/V` spans, and deferred-work start;
- MainActor stalls and the workload/owner active in that interval; and
- whether the value is automated, signposted, screen-recorded, or attended.

The Web prototype uses deterministic simulated transitions only. Its displayed
durations are labels for sequencing and never device-performance evidence.

## 7. Current Mainline Gaps And Ownership

At the refreshed source-audit baseline `main@4cc02e5f12f2`, the major known
mismatches are:

| Gap | Delivery owner |
| --- | --- |
| Setup Network currently proves only `/healthz` reachability, not completion of the required first-install App Attest registration/verification; a denied state can also auto-retry after foreground refresh | `TAP-0008` after this contract/prototype gate |
| Setup completion and Resource Initialization use one legacy Boolean rather than separate `S/I` facts | `TAP-0008` and `TAP-0009` |
| No global Required Permission Check route exists | `TAP-0008` route implementation, consuming `TAP-0087` visual/state contract |
| Setup collapses `.denied` and `.restricted`; Camera/Photos share one footer Settings action and optional denied rows have no row-owned recovery | `TAP-0008` |
| A returning route can reach `CameraViewModel.start()` with Camera `.notDetermined`, which starts an implicit Camera request; Photos is not part of the root route | `TAP-0008` |
| A retained true legacy Boolean sends changed-build update/replacement/offload and restore/migration cases directly to Camera without version/schema/install-device or local credential-binding validation | `TAP-0008` and `TAP-0009` |
| `TAPCamDemoApp.init` constructs `LibraryMediaStore` and registers its PhotoKit observer on the pre-frame path | `TAP-0083` optimization after measurement |
| Returning-user root construction creates `CameraViewModel`, performs synchronous camera capability discovery, and constructs capture-session ownership before the target route shell/first-frame boundary | `TAP-0083` optimization, coordinated with `TAP-0009` readiness |
| Root `.task` awaits video-poster backfill before its first Library catalog refresh, so maintenance can delay the catalog path | `TAP-0083` or a scoped follow-up produced by its audit |
| The preview-layer `isPreviewing` KVO callback exists, but current initial readiness does not consume it as a gate; it currently feeds only path-transition presentation | `TAP-0009` |
| Resource Initialization does not gate on the first usable Library catalog snapshot or own a versioned marker | `TAP-0009` |
| The current first-install overlay says **Preparing camera** and exposes Failed/Retry/Settings branches instead of the stable **Resource Initialization / Please wait…** invariant | `TAP-0009` |
| Foreground active can start recent-cover and Pending Capture work before a root required-permission route | `TAP-0008`/`TAP-0083` integration |
| Pending worker and notification-driven catalog refresh can repeat full-directory scans | Scoped follow-up after `TAP-0083` evidence |
| RAW Viewer requests original/possibly iCloud-backed resources and eagerly begins full analysis input work alongside bounded display; this can contend with Viewer readiness and supplies later 2D/3D and existing Share inputs | Observation in `TAP-0087`; behavior changes belong to `TAP-0089` or another approved Viewer/resource Task |
| 3D workload lacks public queued/building/installing/ready state | `TAP-0089` prototype contract, then a separately approved native delivery Task |

`TAP-0087` defines and prototypes these relationships. It does not implement
native setup/readiness, optimize every workload, or claim device performance.
The current product remains iPhone-only.

## 8. `fix0809` Native Candidate Delta

The §7 table remains the immutable source-audit description of
`main@4cc02e5f12f2`. As of 2026-08-15, the owner has accepted the bounded
non-Network lifecycle path exercised from the `fix0809` native candidate on a
physical device. The delta below records that candidate and its executed-path
acceptance; it is not a rewrite of the target reducer, approval of the complete
scenario matrix, or acceptance of the frozen Network-owned boundaries.

| Candidate area | Current `fix0809` behavior | Remaining boundary |
| --- | --- | --- |
| Setup facts | Defines and validates canonical credential-bound `SetupReceipt`; reads a separate legacy Setup-completion record before the historical combined Boolean | Network is frozen, so production Continue cannot write canonical `S`; the compatibility record is never presented as credential evidence |
| Required permissions | Root priority is Setup → Camera/Photos Required Permission Check → Initialization → Viewfinder; `.limited`, `.denied`, and `.restricted` remain distinct; requests and Settings recovery are row-owned | Exact Required Permission Check visual parity remains pending owner review |
| Library observation | Store construction is observer-inert; eligible explicit/post-Setup Photos boundaries activate observation idempotently; stopping cancels queued refresh work | Device timing and large/cold Library evidence remain open |
| Camera construction | The selected route installs a shell state and defers `CameraView` mounting until a later main-actor turn; default `CameraViewModel` creation remains lazy across later parent updates | `Task.yield()` is not a rendered-frame acknowledgement; `TAP-0083` still owns measured shell/first-frame placement proof, so this mismatch remains partially implemented |
| Initialization fact | Independent atomic Application Support marker binds bundle, version, build, initialization schema, installation generation, and a ThisDeviceOnly device generation; marker preparation/fsync runs off MainActor, Application Support absence fails closed, and malformed device-generation data repairs to a new local generation | Canonical Setup restore validity still depends on future verified credential binding |
| Readiness | Active-scene Initialization consumes completed session configuration, real preview, safe shutter/primary controls, haptics, and the first usable catalog, including empty; backgrounding cancels an in-flight candidate commit | The owner accepted the bounded physical-device executed path; interruption, fault-injection, permission-recovery, update, and restore/migration cases remain open |
| Stable UI | Approved Resource Initialization title/subtitle and Camera/TAP Library readiness rows remain blocking; no public Failed, Retry, timeout, skip, or degraded branch exists | The bounded native experience was owner-accepted; exact prototype-to-native visual parity and Simulator comparison remain pending |
| Deferred local work | A two-display-tick barrier observes the committed Viewfinder frame before releasing video poster backfill and every recent-cover entry point; pending App Intent navigation waits at the same boundary | App Attest and credential/network-dependent Pending children remain frozen, so the parent `deferredWorkGuard` mismatch is only partially addressed |

The Network row, `/healthz`, initial/post-Setup App Attest executors, and
credential/network-dependent or Network-owned Pending retry policies receive no
direct change in this candidate. Required Permission Check may postpone mounting
`CameraView` and thus postpone their existing camera-entry triggers while a
required permission is blocked. `networkBootstrap` remains a confirmed mismatch
rather than an accepted target behavior.

The bounded device verdict is recorded in
`Docs/Acceptance/TAP-0041-camera-readiness.md`. It covers only the lifecycle path
the owner actually exercised; canonical `S` production/restore, the full
installation and permission-recovery matrix, measured shell/first-frame timing,
and complete `W11/W12` deferred guards remain open or frozen as stated above.
