# App Module

`TAPCamDemo/App` owns process-level app wiring: app entry, first-install
startup gating, App Attest runtime construction, operation timeouts, and
shared diagnostics. It deliberately does not configure cameras, package HEIC
bytes, or run the pending queue.

[ProductContract.md](../../Docs/ProductContract.md) owns the product behavior.
This README owns only the App module's implementation responsibilities; task
status and known alignment work remain in
[ProjectBoard.md](../../Docs/ProjectBoard.md).

## Code Map

| Responsibility | Code |
| --- | --- |
| SwiftUI app entry and XCTest host bypass | [TAPCamDemoApp.swift](TAPCamDemoApp.swift) |
| Root `S -> P -> I -> route` reducer, Library activation boundary, and deferred release | [StartupGateView.swift](StartupGateView.swift), [StartupGatePolicy.swift](StartupGatePolicy.swift) |
| First-Install Setup UI | [WelcomeStartupSetupView.swift](WelcomeStartupSetupView.swift) |
| Post-Setup Camera/Photos recovery UI | [RequiredPermissionCheckView.swift](RequiredPermissionCheckView.swift) |
| Independent versioned Initialization completion store | [StartupInitializationPolicy.swift](StartupInitializationPolicy.swift) |
| Camera-plus-Library readiness state and blocking surface | [CameraInitialReadinessGate.swift](../CameraCapture/UI/CameraInitialReadinessGate.swift), [CameraView.swift](../CameraCapture/UI/CameraView.swift) |
| Setup facts, required-permission facts, route priority, and current pre-release completion | [StartupGatePolicy.swift](StartupGatePolicy.swift) |
| Frozen Network-row retry and timeout policy; canonical Setup/App Attest alignment remains `TAP-0010` | [StartupSecurityPreflightPolicy.swift](StartupSecurityPreflightPolicy.swift) |
| Current `/healthz` reachability execution; not the target completion condition | [StartupBackendSecurityPreflight.swift](StartupBackendSecurityPreflight.swift) |
| Current Network, camera, photo, optional location, and optional microphone row state | [StartupGateCoordinator.swift](StartupGateCoordinator.swift) |
| App Attest runtime factory and diagnostics | [AppAttestRuntime.swift](AppAttestRuntime.swift) |
| App Attest credential preparation state | [AppAttestRuntimeController.swift](AppAttestRuntimeController.swift) |
| Public-safe App Attest UI status and key ID presentation | [AppAttestCredentialPresentation.swift](AppAttestCredentialPresentation.swift) |
| Async operation timeout helper | [AppAttestOperationTimeout.swift](AppAttestOperationTimeout.swift) |
| App Attest entitlement configuration | [TAPCamDemo.entitlements](../../TAPCamDemo.entitlements) |

## Startup Flow

```mermaid
flowchart TD
    App["TAPCamDemoApp"] --> Test{"TAPCAM_XCTEST_HOST?"}
    Test -- "yes" --> Host["XCTestHostView"]
    Test -- "no" --> Gate["StartupGateView"]
    Gate --> Facts["Read local Setup receipt,
Camera/Photos status, and
Initialization marker"]
    Facts --> Setup{"Setup receipt valid?"}
    Setup -- "no" --> Welcome["First-Install Setup"]
    Welcome --> Coord["StartupGateCoordinator"]
    Coord --> Network["Explicit Network row:
initial App Attest bootstrap"]
    Coord --> CameraPerm["Camera permission"]
    Coord --> PhotosPerm["Photo library permission"]
    Coord --> LocationPerm["Location permission optional"]
    Coord --> MicrophonePerm["Microphone permission optional"]
    Network --> Required{"Required startup checks ready?"}
    CameraPerm --> Required
    PhotosPerm --> Required
    Required -- "no" --> Welcome
    Required -- "yes" --> Continue["User presses Continue"]
    Continue --> WriteSetup["Atomically write Setup receipt"]
    WriteSetup --> Permission
    Setup -- "yes" --> Permission{"Camera and Photos usable?"}
    Permission -- "no" --> PermissionPage["Required Permission Check"]
    PermissionPage --> Permission
    Permission -- "yes" --> Marker{"Initialization marker current?"}
    Marker -- "no" --> Readiness["Resource Initialization"]
    Readiness --> Graph["Capture graph/path + real preview
and safe controls/haptics"]
    Readiness --> Catalog["First usable TAP Library
metadata snapshot"]
    Graph --> Ready{"Both readiness groups ready?"}
    Catalog --> Ready
    Ready -- "no" --> Readiness
    Ready -- "yes" --> Store["Atomically write current marker"]
    Store --> Camera["Interactive Viewfinder"]
    Marker -- "yes" --> Camera

    click App "TAPCamDemoApp.swift"
    click Gate "StartupGateView.swift"
    click Welcome "WelcomeStartupSetupView.swift"
    click Coord "StartupGateCoordinator.swift"
```

`StartupGatePolicy` remains the required/optional entry: initial App Attest,
Camera, and Photos are required; Location and Microphone are optional and may
be skipped. The setup UI may continue to present the first operation as
Network Access, but successful generic reachability is not completion. The row
completes only after the initial App Attest registration/verification succeeds.

`StartupGateCoordinator` owns passive status reads and the operations started
by each setup row. It does not own the camera-readiness gate.
`StartupSecurityPreflightPolicy` owns the bounded retry interval, deadline, and
wall-clock timeout used by the current Network row. The remaining generic
`/healthz` path is not canonical App Attest credential evidence;
its replacement and canonical receipt delivery are owned by `TAP-0010`. One explicit
Network action starts one bounded sequence. After timeout, only the setup
page's explicit Retry action may begin another sequence; appearance, foreground
return, and passive status refresh must not do so.

Continue writes the canonical structured Setup receipt only when its credential
binding is valid. Until TAP-0010 supplies that binding, the current
`SetupCompletionRecord` preserves the mounted completion path without converting
`/healthz` into credential evidence. Resource Initialization owns a different marker and stays visible
until camera-interactive readiness and the first usable TAP Library metadata
snapshot are both ready. Session
configuration by itself is not enough. Resource Initialization has no product
Failed, Retry, timeout, skip, or degraded branch. Marker preparation and fsync
run off MainActor, storage fails closed when Application Support is unavailable,
and local deferred work waits for a committed Viewfinder-frame barrier.

Later App Attest health/recovery and Pending Capture Queue retry begin only
after the interactive route barrier as independent background work. They do not
participate in the first interactive-frame gate or turn ordinary local capture
into a network requirement.

## Explicit Setup Actions

Every setup operation belongs to its own visible action:

- Camera, Photos, Location, and Microphone may show a system prompt only from
  the corresponding row's explicit **Allow** button.
- Initial App Attest bootstrap may begin only from the Network row's explicit
  action or its explicit Retry action after a timed-out sequence.
- Page appearance, `Continue`, scene foregrounding, returning from Settings,
  unrelated retry work, and background maintenance may refresh passive status
  only. They must not request permission or start a Network attempt.
- Before a row's explicit action, no protected media fetch, observer,
  backfill, write, capture warmup, or similar work may activate in a way that
  can request that permission. Maintenance may run only when the already-read
  authorization state permits it.
- A denied or restricted result is handled by that row or, after setup, by the
  affected feature. It is never requested repeatedly in the background.

OS authorization and the app's data-use preference are separate. Location
metadata and Live Photo/TAP Video audio are used only when both layers permit
them. The first successful Microphone authorization may enable data use only
when the user has never chosen; a saved opt-out remains authoritative.

## Completion Marker And Later Launches

Pre-release builds read only the current records; old development keys require
clearing the app container or deleting and reinstalling. The active model separates:

- a canonical structured Setup receipt shape, valid only with independently
  verified local credential binding; until the frozen Network work supplies
  that binding, a clearly non-canonical `SetupCompletionRecord` preserves the
  existing first-install completion path; and
- a versioned Resource Initialization marker, written only after both readiness
  groups succeed. It is stored as one atomically replaced Application Support
  file and binds bundle, version, build, initialization schema, installation
  generation, and a non-migrating local device generation.

The Setup receipt includes a local binding to the initial App Attest credential
for the installation generation. It can be checked locally without making a
network request on every launch. A restored receipt without that local
credential binding returns to Setup recovery. A later backend/credential
health failure does not silently erase Setup or block Viewfinder; it is handled
by post-entry App Attest and Pending Capture recovery.

Returning users still re-read Camera and Photos. Revoking either enters
Required Permission Check and automatically re-evaluates the route after the
targeted status refresh. It does not replay first-install Setup. Location and
Microphone remain optional feature-context permissions.

## Post-Setup App Attest Runtime Flow

The required first-install branch is separate: the Setup Network row explicitly
starts the bounded App Attest registration/verification operation and gates
Continue until it succeeds. The sequence below begins only after Setup has a
valid receipt; it describes deferred health/recovery from Camera or Settings and
does not redefine the Network row or ordinary camera-entry routing.

```mermaid
sequenceDiagram
    participant UI as Camera or Settings UI
    participant Controller as AppAttestRuntimeController
    participant Factory as AppAttestRuntimeFactory
    participant Kit as AppAttestKit client
    participant Backend as HTTPS backend

    UI->>Controller: prepareCredentialIfNeeded()
    Controller->>Factory: make()
    Factory->>Factory: Parse APP_ATTEST_BACKEND_URL
    Factory->>Kit: Build DefaultAppAttestClient
    Controller->>Kit: prepareIfNeeded(photo_keyid)
    Kit->>Backend: Register or reuse credential metadata
    Backend-->>Kit: keyId
    Kit-->>Controller: AppAttestCredential
```

Debug and Release builds use `https://www.tapnap.net`. Debug signs with
development App Attest metadata; Release and TestFlight sign with production
metadata.
The app target also sets `APP_ATTEST_ENVIRONMENT` to `development` for Debug and
`production` for Release, then injects that value into
[`TAPCamDemo.entitlements`](../../TAPCamDemo.entitlements).

## Boundaries

- App startup can decide whether the user may enter the camera surface.
- App startup must not pre-create `CameraViewModel` or camera runtime objects.
- `StartupGatePolicy` is the source of truth for required versus optional
  First-Install Setup checks. Initial App Attest, camera, and photo library remain
  required; location and microphone remain optional. Current generic
  `/healthz` completion is an implementation gap, not the target requirement.
- `StartupGateView` owns the route reducer and keeps the current pre-release
  Setup completion separate from the Resource Initialization marker. Invalid
  canonical Setup data fails closed and never falls back to old development keys.
- `CameraInitialReadinessGate` and `CameraView` own camera-interactive
  readiness; App code must not replace that gate with a timer or a
  configuration-completed flag.
- Authorization refresh is passive. Only explicit setup-row actions may call
  the permission/bootstrap methods described above. Required Permission Check
  may perform only a targeted passive refresh after its explicit system
  boundary.
- `APP_ATTEST_BACKEND_URL` must be an HTTPS base URL with a domain host.
- Shared diagnostics categories are declared in `TAPDiagnostics`: `AppAttest`,
  `PendingCapture`, `SecurityPreflight`, and `PhotoLibrary`. Public error
  summaries must be safe for OSLog `.public` interpolation.
- `PhotoIntegrityReadiness` is the Release presentation boundary for protection
  readiness. Release Settings exposes only `Not Ready`, `Preparing`, `Ready`,
  or `Preparation Failed`; it does not expose App Attest terminology or key
  identifiers. Runtime code may keep the real key id for readiness checks, and
  Debug Settings may use the redacted presentation with generic failure text
  instead of raw localized errors.
- `AppAttestBackendPresentation` is the public-safe backend summary boundary.
  Runtime code keeps the real backend URL for requests and credential health
  tokens, but Settings UI and public OSLog lines use `backendPublicSummary`.
- App Attest credential names and key ids are logged as private. `photo_keyid`
  is currently fixed and non-PII, but future credential names may encode user,
  tenant, install, or session identity.
- `CODE_SIGN_ENTITLEMENTS` must point at `TAPCamDemo.entitlements` so App
  Attest setup is visible in the checkout.
- First-install App Attest bootstrap is bounded by a tested retry/timeout policy
  so a single explicit Network action cannot become a multi-minute unbounded
  attempt sequence.
- Backend preflight URL logs stay public only because
  `APP_ATTEST_BACKEND_URL` parsing rejects localhost, bare IP addresses,
  endpoint paths, query strings, and fragments.
- Tests use `TAPCAM_XCTEST_HOST=1` to avoid entering permission and camera
  startup flows in app-hosted unit tests.
- UI smoke tests that intentionally exercise the real camera app set
  `TAPCAM_UI_TEST_REAL_APP=1`. That override keeps app-hosted unit tests fast
  while allowing `TAPCamDemoUITests` to launch `StartupGateView` and the real
  capture UI.

## Related Documents

- [ProductContract.md](../../Docs/ProductContract.md)
- [StartupLifecycleContract.md](../../Docs/StartupLifecycleContract.md)
- [ProjectBoard.md](../../Docs/ProjectBoard.md)
- [Docs/AppAttest/README.md](../../Docs/AppAttest/README.md)
- [TAPCamDemoTests/README.md](../../TAPCamDemoTests/README.md)
