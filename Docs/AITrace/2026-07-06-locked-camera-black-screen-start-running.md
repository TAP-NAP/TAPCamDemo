# Locked Camera Black Screen StartRunning Trace

## Goal

Record the real-device black-screen failure found during the Locked Camera
Capture POC and the implementation lesson that should prevent the same mistake
from recurring.

## User Constraints

- Debug on a real device, not the simulator.
- Treat black screen as the primary risk for this POC.
- Keep the locked extension small, observable, and independent from the main
  app's full camera UI.
- Preserve the product boundary: the locked extension must not use network,
  App Group shared storage, main-app preferences, Photos writes, App Attest, or
  signing in this phase.
- Record the finding in both the POC document and the AI collaboration trace.

## Symptom

On an iPhone 15 Pro running iOS 26.5 (23F77), the lock-screen capture UI could
flash briefly and then leave the secure capture surface black. Dynamic Island
status remained visible, which made the first hypothesis look like a stuck
secure-capture shell, a preview-layer failure, or a system lifecycle bug.

## Wrong Assumption To Avoid

Do not start by assuming every lock-screen black screen is an AVCapture
interruption, SwiftUI root disappearance, or OS-level secure-capture bug. In
this case the black screen was caused by our extension process aborting during
session start.

The useful first split is:

- If our overlay remains visible, suspect preview/session/frame delivery.
- If the overlay disappears with the secure capture shell still black, suspect
  process termination, scene teardown, or an uncaught exception.
- Always pull real-device crash logs before treating the issue as a framework
  bug.

## Evidence

- Device crash logs contained repeated
  `TAPCamLockedCameraCaptureExtension` crash reports from 21:14-21:25 on
  2026-07-06.
- Termination was `SIGABRT` / `Abort trap: 6`.
- `lastExceptionBacktrace` ended in `-[AVCaptureSession startRunning]`, called
  from `LockedCaptureCameraController.configureAndStartSessionOnQueue(lens:)`.
- The extension process was visible after the fixed build was installed, and no
  new `TAPCamLockedCameraCaptureExtension-2026-07-06-213*.ips` crash reports
  appeared in the copied crash logs.

## Root Cause

The POC called `captureSession.startRunning()` before the matching
`commitConfiguration()` for `captureSession.beginConfiguration()` had completed.
`AVCaptureSession.startRunning()` raises an Objective-C exception in that
state. Swift `do/catch` does not catch Objective-C exceptions, so the extension
process aborted immediately.

The black screen was therefore not the original long-running viewfinder stall
from the historical branch. It was a new implementation crash in the fresh POC.

## Fix

- Build the input/output/session preset changes inside a bounded
  `beginConfiguration()` / `commitConfiguration()` block.
- Return any Swift-thrown configuration errors after the commit block exits.
- Call `captureSession.startRunning()` only after configuration has been
  committed.
- Keep ordering logs:
  `session_configuration_committed`, `session_start_running_begin`, and
  `session_start_running_end`.

## Files Updated

- `TAPCamLockedCameraCaptureExtension/LockedCaptureCameraController.swift`:
  commits session configuration before calling `startRunning()`.
- `Docs/LockedCameraCapturePOC.md`: records the real-device black-screen
  finding, evidence, root cause, fix, and post-fix evidence.
- `Docs/AITrace/README.md`: indexes this trace.

## Validation

- Built the app for the attached iPhone 15 Pro using the physical-device
  destination.
- Installed the fixed build to the same device.
- Launched the main app once after install to republish locked-camera app
  context.
- Pulled device crash logs after the fixed install.
- Confirmed no new 21:33+ `TAPCamLockedCameraCaptureExtension` crash report was
  present.
- Confirmed device process sampling showed both `TAPCamDemo` and
  `TAPCamLockedCameraCaptureExtension` running.
- Ran `git diff --check`.

## Open Follow-Ups

- Continue real-device lock-screen validation for first frame, still capture,
  and multi-minute soak.
- Keep investigating any future black-screen report with the process/crash-log
  split first.
- Add a small source-inspection test or lint-style assertion around session
  start ordering if this controller grows more complex.

## 2026-07-07 Follow-Up: First Library Entry Looked Empty

User-observed issue:

- Photos captured inside the locked extension could appear in TAP Library after
  waiting or after entering the library a second time.
- On the first main-app/library entry, the grid could still show the old
  snapshot, making it feel like the locked capture had been lost.

Implementation cause:

- `StartupGateView` published locked camera AppContext before importing existing
  `LockedCameraCaptureManager.sessionContentURLs`.
- `DepthAlbumPickerViewModel.load()` loaded the first `DepthAlbumItemProvider`
  snapshot without awaiting locked session content import.
- The import was asynchronous and correct, but it could finish after the first
  visible library snapshot.
- Follow-up on 2026-07-07 found two more stale-first-entry paths:
  `CameraView.openTAPLibrary()` could present Library before its fire-and-forget
  import task completed, and SwiftUI could retain the Library `StateObject` with
  a cached empty `loadIfNeeded()` snapshot across route changes.

Fix attempts and current direction:

- Added `LockedCaptureSessionContentImportCoordinator` so Startup, handoff, and
  TAP Library requests coalesced onto one import task. This reduced duplicate
  work but did not solve the immediate-handoff race.
- Startup publishes AppContext without blocking normal app launch on locked
  import.
- The one-shot locked Library route flag and settled-import wait are retained
  only as compatibility/future experiment code. They are not the Phase 1
  successful-capture path.
- Locked extension handoff must not target TAP Library in Phase 1.
  Unavailable/fallback UI uses `regenerateLockedCameraContext`. The later
  saved-placeholder `openTAPCamera` experiment landed in camera/default instead
  of Library, but still proved unreliable and is not a Phase 1 success path.
- Follow-up experiment: `CameraView` previously routed saved-placeholder
  handoff through `presentTAPLibrary(awaitingLockedCaptureImport: true)`. That
  avoided route-driven session scans, but user logs still showed the first
  Library entry could appear before system transfer completed. A later pure
  `.tapLibrary` experiment also remained racy. Status-only was the first stable
  baseline; the next experiment tests Apple's transition-delay API while
  avoiding Library as the first destination.
- Follow-up lifecycle experiment: before calling `openApplication(for:)`, the
  extension now removes the SwiftUI preview host, detaches
  `AVCaptureVideoPreviewLayer.session`, removes `AVCaptureEventInteraction`,
  synchronously stops the capture session on the session queue, and removes all
  session inputs/outputs. This tests the hypothesis that the secure capture
  scene was being asked to hand off while it still owned camera/preview
  resources.
- Follow-up fix: `DepthAlbumPickerView` now performs a fresh presentation load
  when it appears, shows loading before its first snapshot, and shows a
  non-blocking locked-import waiting banner only if the awaiting route flag is
  used by a compatibility path. The current placeholder experiment does not set
  that flag. It does not wait for or trigger locked session scans from the route;
  it refreshes when the App-level import notification arrives.
- Follow-up fix: locked import now posts
  `.tapCamLockedCaptureImportDidAddPendingCaptures` only when it adds pending
  records. Mounted `CameraView` responds through
  `CaptureLifecycleCoordinator.retryPendingCaptures(...)`, so locked captures do
  not require a second camera/lifecycle event before the shared processor starts
  and still respect the existing credential-preparation guard.
- Follow-up fix: `LockedCaptureCameraController` now treats "session started but
  no first frame arrived" as a bounded recovery path. It logs
  `first_frame_watchdog_waiting`, rebuilds through `recovering`, and after the
  configured retry limit moves to visible `unavailable` instead of staying on an
  indefinite dim/black preview.
- Follow-up fix: locked still capture now explicitly sets
  `AVCapturePhotoSettings.flashMode = .off` and emits
  `photo_capture_poc_defaults`, including the Phase 1 defaults for HEIC,
  `.quality`, Flash off, Live Photo forced off, nil location, no App Attest, no
  Photos, and no network.
- 2026-07-07 user device logs showed the main app repeatedly running locked
  session import while `LockedCameraCaptureManager.sessionContentURLs` was still
  empty, including `tap_library_load` and locked handoff paths. The older
  `lockScreen` / `lockScreen_test` branches also depended on Apple exposing
  `sessionContentURLs`; they differed mainly in writing final HEICs directly
  into the session directory and importing them once updates arrived. Therefore
  the current first-entry Library miss is tracked as a late/no session-content
  exposure problem, not a pure TAP Library refresh problem.
- Follow-up fix: `scene_active`, normal app launch, and normal TAP Library open
  no longer scan locked session content. Startup only publishes AppContext.
  Locked import is owned by an App-level runtime that listens to
  `LockedCameraCaptureManager.sessionContentUpdates`.
- Failed follow-up attempt: explicit locked handoff imports added a bounded late
  poll after an empty settled import and logged
  `locked_camera_session_import_late_poll` / `_timeout`. User logs still showed
  `sessionCount=0`, so adding wait time did not fix the transfer.
- 2026-07-07 reassessment: user logs showed repeated
  `locked_camera_session_import_late_poll ... sessionCount=0`, so the previous
  "late migration window" hypothesis is insufficient. Local SDK symbol docs say
  `LockedCameraCaptureSession.sessionContentURL` is copied to the containing app
  when the extension is suspended. The POC removes immediate saved-placeholder
  TAP Library handoff from Phase 1: locked UI saves and stays live, the stable
  baseline used a status-only placeholder, and the later `openTAPCamera` plus
  transition-delay experiment is also recorded as unreliable. The long-lived
  `sessionContentUpdates` runtime remains the import owner after the system
  exposes content.
- Diagnostic implication: if the next run still shows delayed import, check for
  `locked_camera_intent_perform`, `locked_camera_scene_content_invoked`,
  `locked_camera_root_init`, `photo_capture_saved`, and then
  `locked_camera_session_content_update kind=initial/added` in the containing
  app. Absence of the root logs means the freeze is before our SwiftUI
  extension root; absence of `photo_capture_saved` means the main app has no
  valid locked content to import yet.

### Pitfall Table

| Implementation / idea | Original assumption | Actual symptom | Evidence | Conclusion | Principle / fix |
| --- | --- | --- | --- | --- | --- |
| Run settled locked-session import on every TAP Library presentation (`tap_library_load` / `tap_library_open`). | A short scan before the first Library snapshot would make locked captures appear sooner and would be cheap when no locked content exists. | Every Library entry could spend seconds waiting on `sessionContentURLs == 0`; Photos fetches such as `depthAlbumAssets fetched count=650` then ran repeatedly, making Library feel slow even for normal app usage. | User log showed repeated `locked_camera_session_import_wait_for_initial_update reason=tap_library_load`, eight `locked_camera_session_import_late_poll ... sessionCount=0` attempts, and repeated `requestReadWriteAccess` / `depthAlbumAssets fetched count=650`. | This was an over-heavy path. Normal Library open is not evidence that locked session content should exist. | Locked import should be owned by the App-level `sessionContentUpdates` runtime. Direct app launch and normal Library open should load TAP Library data directly. |
| Trigger locked-session import from every foreground activation (`scene_active`). | If the app becomes active after locked capture, foreground is a convenient catch-all point to pick up migrated session content. | Normal app foregrounds paid the same locked-import wait even when the user did not come from locked capture. The app could feel like it was doing hidden work before the user asked for Library. | Earlier logs contained repeated `locked_camera_session_import_wait_for_initial_update reason=scene_active` with `sessionCount=0`. | Foreground is too broad a signal. It conflates ordinary app resume with a locked-camera content handoff. | App activation should republish locked AppContext and keep the `sessionContentUpdates` listener alive, but should not scan locked session content by default. |
| Treat Library presentation as both navigation and import trigger. | Entering TAP Library is where the user expects to see the locked photos, so the route itself can start import work. | The UI route became coupled to a slow importer. Manual Library opens and locked handoff opens were indistinguishable, so every path inherited the worst-case wait. | The first implementation used `presentTAPLibraryAndImportLockedContent(...)` / `tap_library_open`, and later logs showed Library-load waits even when no locked session content existed. | Navigation intent and locked-import intent must be separated. | Do not use Library presentation as the Phase 1 import signal. Keep TAP Library loading normal app data; import comes from `sessionContentUpdates`. |
| Rely on a retained Library `StateObject` and `loadIfNeeded()` after import. | Once the importer completes, the existing Library view model should notice or refresh naturally. | The first visible Library snapshot could remain stale, making newly imported locked captures appear only after a later route/app cycle. | User observed captures appearing on a later entry, and the view model path used cached presentation state. | Import completion is not the same as first visible Library snapshot freshness. | On presentation, Library performs a fresh snapshot load and refreshes again when App-level import posts `.tapCamLockedCaptureImportDidAddPendingCaptures`. |
| Poll longer when `LockedCameraCaptureManager.sessionContentURLs` is empty. | The handoff was a timing race; waiting longer would catch the copied session directory. | The poll still timed out with `sessionCount=0`, so the app had no Apple-exposed session URL to import. | Repeated `_late_poll ... sessionCount=0` across multiple attempts. | Waiting alone does not solve the problem if the extension has not suspended or did not write session content. | Do not make TAP Library wait for a session URL that Apple has not exposed. Use the App-level `sessionContentUpdates` runtime and treat immediate saved-placeholder handoff as a failed Phase 1 path. |
| Immediate saved-placeholder `openApplication(for:)` into TAP Library with `openTAPLibraryAfterLockedCapture`. | A user tap after capture would be a clean unlock boundary and the main app could import before showing Library. | The containing app opened with `sessionCount=0`; the photo appeared only after a later lock-screen round trip. | User log showed `locked_camera_handoff_begin_delaying_appearance`, `locked_camera_session_import_begin reason=locked_camera_handoff_route sessionCount=0`, eight late polls, and timeout. | The old immediate Library import route races Apple's session-content migration and creates the exact "photo disappeared" perception. | Do not use `openTAPLibraryAfterLockedCapture` from the placeholder. |
| Treat the placeholder tap as an awaiting Library route with `openTAPLibraryAwaitingLockedImport`. | Removing direct session scans while showing an awaiting state would avoid the old race and tell the user the app is waiting for system transfer. | User still saw the first Library entry without the current locked photo, then a later force-start/freeze/reopen sequence finally surfaced the previous capture. Clicking the placeholder before capture was also disabled, which diverged from the desired "wake app" affordance. | Log showed `locked_camera_handoff_route_no_import destination=tapLibraryAwaitingLockedImport`, then normal Library/Photos loading, with no current-session content update visible before the first Library snapshot. | The awaiting route removed explicit polling, but it still made Library UI race ahead of Apple's session migration and added state the historical branch did not have. | Do not use `openTAPLibraryAwaitingLockedImport` from the placeholder. |
| Use pure `openTAPLibrary` from the placeholder. | If the route does not import or wait, the system can migrate session content independently and the main app can refresh when `sessionContentUpdates` fires. | The photo still did not appear on the first Library entry after placeholder handoff, and the next locked-extension launch could freeze. | User logs showed `locked_camera_handoff_route_no_import destination=tapLibrary` followed by normal Library loads; later `session_content_update kind=added` imports happened only on a subsequent lifecycle pass. The latest attached log again shows successful natural-path imports at lines 299-305 and 491-497, while placeholder handoffs at lines 406 and 528 precede empty first Library snapshots. | The problem is not just the route flag. Immediate app wake itself is not a reliable "extension has suspended and session content has migrated" boundary. | Phase 1 makes the left placeholder status-only. Keep `openTAPLibrary` parsing only for compatibility/future experiments, not as the current locked UI action. |
| Use `openApplication(for:)` but land on camera/default with `openTAPCamera`, while the app calls `beginDelayingAppearance()` / `endDelayingAppearance()`. | The earlier failure may have been caused by using TAP Library as the first destination and by not using Apple's transition-delay API, not by `openApplication(for:)` itself. | Latest smoke still failed the UX goal: the containing app opened to camera/default, transition import saw `sessionCount=0`, the Library did not show the expected locked capture from the handoff path, and the next locked launch could freeze. | Attached log `a2a3225...` showed `session_content_update kind=added`, `sessionCount=1`, successful pending ingest for `6840B833...`, app-side invalidation and `kind=removed`; later the `openTAPCamera` transition logged `locked_camera_session_import_begin reason=locked_camera_transition sessionCount=0`. Apple docs describe `beginDelayingAppearance` as delaying app appearance, not completing session-content migration. | This experiment is now also considered unreliable for saved-placeholder handoff. It proves `beginDelayingAppearance` does not make `sessionContentURLs` non-empty and does not remove next-launch freeze risk. | Treat saved-placeholder `openApplication(for:)` as a failed Phase 1 path. Keep `openApplication(for:)` only for explicit unavailable/regenerate recovery until a public transition-complete/migration-complete API exists. |
| Interpret `locked_camera_transition ... sessionCount=0` as "the extension photo was not transferred". | If the transition import sees no URLs, the photo must still be in the extension or lost. | The log can show a successful earlier import, followed by invalidation, then a later transition scan with zero URLs. | In the latest log, `sessionContentUpdates` imported and invalidated the session before the left-placeholder handoff reached the app. The zero count came from `LockedCameraCaptureManager.shared.sessionContentURLs.count` after the app had already told the system it no longer needed that session directory. | `sessionCount=0` is not a photo count and not enough to diagnose Library visibility. It only means no Apple-exposed session directory is currently available. | Diagnose three layers separately: session-content migration, pending-store ingest, and TAP Library/Photos visibility. Add Library item-count probes before changing more LockedCameraCapture APIs. |
| Use `LockedCameraCaptureManager.sessionContentURLs.count` as the main transfer counter. | A nonzero session URL count would correlate closely enough with the number of locked photos available to import. | The app could log `sessionCount=0` even when a previous import had already consumed and invalidated content, or before Apple had exposed the extension's `sessionContentURL`. | Historical `lockScreen` counted actual `.heic` files inside each session directory (`files.count`). Current logs only exposed session-directory count until the new capture/pending/library probes were added. | `sessionCount` is a session-directory availability signal, not a capture counter. | Always log at least four counters together: session URL count, capture/file probe count, pending-store visible count, and TAP Library merged item count. |
| Keep the current `<captureID>/metadata.json + unsigned.heic` staging bundle without comparing against historical flat HEIC transfer. | The structured bundle makes import explicit and should be equivalent to flat files once Apple copies the session directory. | User observed that historical branches transferred photos into Library more reliably, while current POC required later lifecycle turns in some flows. | Historical `lockScreen_test` wrote flat `TAPCam-<UUID>.heic` unsigned artifacts into `sessionContentURL`; current POC writes staging depth HEIC plus metadata and does app-side TAP artifact packaging. | The extra staging/package step is a real variable, even if it is not the only cause of the left-placeholder race. | Run a controlled historical-transfer experiment: extension-side package the unsigned TAP artifact, write flat HEIC, and make importer enumerate actual HEIC files. Do not migrate historical UI or lifecycle code wholesale. |
| Expect a locked capture to appear as an exported Photos asset immediately after import. | Once session content is imported, the user should see the photo in the Library. | Imported captures can enter `TAPPendingCaptureStore` but fail signing/export later, especially when App Attest is unavailable, so Photos/album views may not show them as exported assets. | Latest log showed `store locked ingest created ... status=pending`, then `AppAttestKit.AppAttestError code=2`, then `status=failedRetryable`. | Pending-store visibility and Photos/exported-asset visibility are separate. A signing failure is not a session migration failure. | Acceptance should say locked captures appear in TAP Library as pending/retry items immediately after import; exported Photos visibility depends on the normal async signing/export worker. |
| Call `openApplication(for:)` immediately after an asynchronous `stop()` enqueue. | `stopRunning()` would execute quickly enough, and the system would finish secure-capture teardown while opening the main app. | Pure `openTAPLibrary` still produced the same delayed Library visibility and a following lock-screen freeze, even without route-driven import or awaiting state. | User log showed `locked_camera_handoff_route_no_import destination=tapLibrary`, then normal Library loads; the later `session_content_update kind=added` imported two delayed sessions. | The route was simplified, but lifecycle teardown was still not proven. The extension may still have owned preview/session resources when the app handoff began. | Teardown-before-open is retained for unavailable fallback, but it does not justify using the left placeholder as an immediate Library handoff. |
| Keep the extension capture session running while requesting `openApplication(for:)`. | The system would suspend the extension and migrate `sessionContentURL` regardless of the camera session state. | The main app could open before `sessionContentURLs` exposed the just-written content, creating an empty first Library entry. | User logs repeatedly showed app-side import attempts with `sessionCount=0` after locked flows. | Stopping camera before handoff was not enough to prove migration, and the broader immediate-import handoff design is the wrong Phase 1 proof. | `openApplication(for:)` may be used for explicit user actions only. It must not be treated as proof that session content is already visible to the app. |
| Diagnose locked capture import only from main-app logs. | Main-app `sessionCount=0` logs would be enough to understand the failure. | Logs could show main-app camera captures and pending-store ingestion, but no evidence that the locked extension root launched or saved content. | User log contained `capture pipeline success` / `store ingest created` from the main app, but lacked `locked_camera_intent_perform`, `locked_camera_scene_content_invoked`, `locked_camera_root_init`, or `photo_capture_saved`. | Main-app logs alone can misattribute normal camera captures as locked capture evidence. | Device smoke must collect both control/extension and main-app logs in one timestamped run; absence of extension logs means investigate control/secure-capture launch before importer logic. |
| Use Codex-side device install/launch automation as the main smoke path. | Automating build/install/launch would make lock-screen smoke repeatable and reduce manual work. | It complicated the Xcode logging path and made it harder for the user to capture the exact extension logs they rely on. | User explicitly reported that Xcode-installed runs are needed to get the right logs, and asked Codex not to install after code changes. | For this POC, install path is part of the diagnostic setup. Changing it changes the evidence surface. | User installs/runs from Xcode; Codex does code, local compile/tests, document updates, and log analysis only. |
| Let each target use its own bundle identifier as the locked-camera OSLog subsystem. | Bundle-id subsystems would naturally separate app, control extension, and capture extension logs. | Main-app logs were visible, but extension launch/root/capture probes were absent from pasted logs, making freeze impossible to classify beyond the handoff/import side. | Current code used `Bundle.main.bundleIdentifier` for extension/control loggers, while docs asked for one `TAP-NAP.TAPCamDemo` subsystem. | Per-target subsystems fragment the evidence chain and make Console filters easy to get wrong. | Use a shared fixed subsystem, `TAP-NAP.TAPCamDemo`, for app/control/capture locked-camera probes. |
| Rename locked capture/control bundle IDs away from the historical working branch. | New POC target names and matching bundle IDs would be clearer. | Lock-screen controls can be cached by system surfaces, so bundle-id churn adds a variable while debugging first-tap freeze. | Current POC bundle IDs differed from `lockScreen_test`, where launch/import paths had worked aside from the long-run black-screen issue. | Naming clarity is less important than reducing system-cache variables during POC validation. | Keep current source/target names but align bundle IDs to historical working values: `TAP-NAP.TAPCamDemo.LockedCapture` and `TAP-NAP.TAPCamDemo.Controls`. |
| Post import-completion notifications from the importer background context. | NotificationCenter receivers could schedule their own main-thread UI work. | Runtime logged `Publishing changes from background threads is not allowed` immediately after a locked capture was imported. | The imported-capture notification was posted after async importer work; `CameraView` consumed that notification without `receive(on:)`. | Threading warnings can make Library/queue refresh appear flaky even after content import succeeds. | Post locked-import and library-change notifications on the main thread, and receive locked-import notifications on the main run loop. |

### Device Smoke Boundary

- Codex-side install/launch automation is paused for locked-camera POC smoke.
- The user installs and runs from Xcode so the extension logs appear in the
  expected Xcode/Console path.
- Codex should not call `devicectl install` / `devicectl launch` after code
  changes unless the user explicitly reopens that workflow.
- Codex should still keep source-level checks, compile validation, and trace
  updates current.
- The physical secure lock-screen control tap is a manual trigger. The evidence
  to analyze is the user's exact hand-test sequence plus Xcode/Console logs.

### 2026-07-07 Xcode Smoke Interpretation

User sequence:

1. Release build installed/run from Xcode; main app ordinary capture worked.
2. Lock screen control first launch froze before the locked UI became usable.
3. User swiped out, launched again, captured one locked photo, then tapped the
   left locked Library placeholder.
4. Main app opened TAP Library, but the new locked photo did not appear.
5. User locked again, hit the same freeze, swiped out, launched locked extension
   again, did not capture, tapped the placeholder again.
6. The previous locked photo then appeared in TAP Library.

Observed log chain:

- First handoff: `locked_camera_handoff_begin_delaying_appearance`, then
  `locked_camera_session_import_begin reason=locked_camera_handoff_route
  sessionCount=0`, followed by eight
  `locked_camera_session_import_late_poll ... sessionCount=0` attempts and
  `_timeout`.
- Later handoff: `locked_camera_session_import_begin
  reason=locked_camera_handoff_route sessionCount=1`, then
  `locked_camera_session_content_update kind=added`, staging package success,
  pending-store ingest success, session invalidation, and
  `kind=removed`.
- The log still did not include `locked_camera_intent_perform`,
  `locked_camera_scene_content_invoked`, `locked_camera_root_init`, or
  `photo_capture_saved` from the capture extension. That means the pasted logs
  prove app-side delayed session exposure, but not the first-freeze root cause.

Current interpretation:

- The delayed photo is not a TAP Library grid refresh issue. It is primarily a
  `LockedCameraCaptureManager.sessionContentURLs` exposure timing issue: the
  main app was opened by handoff before Apple exposed the extension's session
  content.
- The second launch likely caused the previous extension/session content to
  finish migration, after which the app-side importer worked correctly.
- The old immediate saved-placeholder import route, the later awaiting route,
  and the pure `openTAPLibrary` route are therefore not the Phase 1 transfer
  model. They explain the "photo appears only next time" symptom and the
  follow-on freeze after placeholder handoff.
- The first-launch freeze remains a separate launch/presentation problem until
  extension-side probes are visible in the same log stream.

Follow-up changes:

- App, control widget, and capture extension locked-camera probes now share the
  fixed OSLog subsystem `TAP-NAP.TAPCamDemo`; do not rely on per-target bundle
  identifiers for these probes.
- Locked import completion and TAP Library change notifications are delivered
  on the main thread, and `CameraView` receives the locked-import notification
  on the main run loop. This addresses the observed background-publish warning.
- The main app owns a `@StateObject` import runtime in `TAPCamDemoApp`, matching
  the historical working branch. `StartupGateView` no longer owns the
  `sessionContentUpdates` scheduler.
- The left locked placeholder no longer sends `openTAPLibrary`,
  `openTAPLibraryAfterLockedCapture`, or `openTAPLibraryAwaitingLockedImport`.
  The later `openTAPCamera` transition-delay experiment is now also considered
  an unreliable saved-placeholder path.
- `openApplication(for:)` remains gated behind explicit extension teardown logs:
  `preview_host_dismantle_ui_view`, `preview_view_prepare_for_teardown`,
  `open_application_teardown_begin`, and `open_application_teardown_end` should
  appear before `open_application_call`.
- The containing app now uses iOS 18.1+ `beginDelayingAppearance()` and
  `endDelayingAppearance()` for saved placeholder handoff, with a bounded
  `locked_camera_transition` import settle before ending the delayed appearance.
- Capture/control bundle IDs are aligned back to the historical working values:
  `TAP-NAP.TAPCamDemo.LockedCapture` and `TAP-NAP.TAPCamDemo.Controls`.
- The temporary Codex-side device-smoke script was removed. Manual Xcode
  install/run remains the real-device logging baseline.

Next Xcode smoke should look for these probes, in order:

1. `locked_camera_control_widget_init` or
   `locked_camera_control_widget_button_label_init`
2. `locked_camera_intent_perform`
3. `locked_camera_extension_init`
4. `locked_camera_scene_content_invoked`
5. `locked_camera_root_init`
6. `locked_camera_start_begin`
7. `session_configure_begin`
8. `session_start_success`
9. `first_frame`
10. `photo_capture_saved`
11. `locked_camera_session_content_update kind=initial` or
    `locked_camera_session_content_update kind=added` after the main app opens
12. `locked_camera_session_import_succeeded`

The last visible probe before a freeze determines the failing boundary.

### 2026-07-07 Saved Placeholder Handoff Reproduced Delayed Import

User sequence from attachment `c7cc7aa3.../pasted-text.txt`:

1. Opened the main app and captured several normal app photos.
2. Locked the phone, launched the locked extension, captured one locked photo.
3. Tapped the lower-left locked placeholder to enter the main app.
4. TAP Library did not show the locked photo.
5. Returned to lock screen, first locked-extension launch froze.
6. Locked again, launched the extension successfully, captured nothing, exited.
7. Manually unlocked into the main app; TAP Library then showed the previous
   locked photo.

Log interpretation:

- At first placeholder handoff, the containing app received
  `tapAction=openTAPCamera reason=saved` with `managerSessionCount=0`.
- The transition import waited for an initial update, then ran with
  `sessionCount=0 sessionURLCount=0`, imported nothing, and ended delayed
  appearance.
- The first Library snapshot after that showed `visiblePendingCount=3` and
  `itemCount=690`; the locked capture was not in the pending queue yet.
- Later, after the second lock-screen round trip, the app received
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`.
- The importer packaged staging capture
  `3C9AC1BD-C550-4F67-9A96-0315ABB3B2BE`, ingested it as pending, invalidated
  the session, and logged `visiblePendingCount=4`.
- The next Library snapshot showed `itemCount=691` and `itemSources=pending:4`.

Conclusion:

- The photo was not lost. It was written by the extension and became importable
  only after the saved-placeholder handoff had already opened the containing
  app and rendered the first Library snapshot.
- `sessionCount=0` was not a wrong capture counter in this log. It correctly
  reported that Apple had not yet exposed a migrated session directory to the
  containing app at that moment.
- The saved-placeholder `openApplication(for:)` path remains the strongest
  suspect for both symptoms: first Library entry missing the locked photo, and
  the next locked launch freezing before a clean extension UI.
- The logs still lacked extension-side `photo_capture_saved` /
  `open_application_prepare` probes, so extension log visibility must remain
  part of the next smoke.

Follow-up experiment:

- Baseline commit keeps the lower-left placeholder status-only as a rollback
  and negative-control state.
- E1A restores the required UX: the lower-left placeholder calls
  `openApplication(for:)` with `tapAction=openTAPLibraryRuntimeImport`.
- E1A deliberately opens TAP Library awaiting import but does not call
  `beginDelayingAppearance()` and does not do handoff-time
  `sessionContentURLs` scanning. Import ownership stays with the app-level
  `sessionContentUpdates` runtime. This validates only the historical
  runtime-import lifecycle, not the historical flat-HEIC transfer layout.
- Passing E1A means: `open_application_call` appears for
  `openTAPLibraryRuntimeImport`, the main app logs
  `locked_camera_transition_delay_skipped`, Library enters awaiting state, a
  later `session_content_update kind=added` imports the pending item, and the
  next locked launch does not freeze.

### 2026-07-07 Successful No-Immediate-Handoff Transfer

User-reported operation:

- With the left locked placeholder not opening the old immediate Library import
  route, the flow did not freeze.
- After capturing inside the locked extension, the photo appeared normally in
  the main app.

Log evidence:

- `locked_camera_session_import_runtime_start` appeared during main-app runtime.
- `locked_camera_session_content_update kind=added` arrived from
  `LockedCameraCaptureManager.sessionContentUpdates`.
- The importer ran with `reason=session_content_update sessionCount=2`.
- Two locked staging captures were packaged:
  `82B2A70B-026A-4406-AC27-6D919025A3B8` and
  `F4F4C690-A79C-47FF-9FAD-C3BBABA7F920`.
- Both were ingested into the normal pending queue with `status=pending`, and
  both session content URLs were invalidated.
- The import finished as `sessions=2 found=2 imported=2 skipped=0 failed=0
  invalidated=2`.

Interpretation:

- This confirms the current Phase 1 transfer model for this operation:
  save in the locked extension, let the system expose session content, then let
  the main app's long-lived `sessionContentUpdates` runtime import it.
- The later `AppAttestKit.AppAttestError code=2` failures happened after pending
  ingest, during signing retry. They should be tracked as App Attest/backend
  credential availability, not as locked-camera transfer loss.
- The pasted log still does not include extension-side probes such as
  `locked_camera_root_init` or `photo_capture_saved`; user observation confirms
  no freeze in this operation, but freeze-boundary classification still needs
  extension logs when a freeze does occur.

### 2026-07-07 Repeated No-Immediate-Handoff Transfer

User-reported operation:

- The user repeated the smoke path and still did not enter TAP Library from the
  lower-left placeholder.
- The perceived flow was normal.

Log evidence:

- The log contains no old immediate-Library path markers:
  `openTAPLibraryAfterLockedCapture`, `locked_camera_handoff_route`,
  `locked_camera_session_import_late_poll`, `tap_library_load`, or
  `tap_library_open`.
- First new locked import:
  `locked_camera_session_content_update kind=added`, then
  `locked_camera_session_import_begin reason=session_content_update
  sessionCount=1`, then `locked_camera_session_import_succeeded` for
  `5719E669-1B07-4A9E-9565-EDBFC1F13041`, finishing with
  `sessions=1 found=1 imported=1 skipped=0 failed=0 invalidated=1`.
- Second new locked import:
  the same `session_content_update` path succeeded for
  `EE77D4D4-1345-4088-B129-AAAC4F9933B7`, again finishing with
  `sessions=1 found=1 imported=1 skipped=0 failed=0 invalidated=1`.

Interpretation:

- This is a second positive observation that avoiding the old immediate import
  route plus using the App-level `sessionContentUpdates` runtime is the stable
  transfer path.
- The dominant remaining noise in the log is repeated
  `AppAttestKit.AppAttestError code=2` during signing retries. That is
  downstream of locked import and should not be conflated with transfer loss or
  Library visibility.

Validation:

- `xcodebuild build -project TAPCamDemo.xcodeproj -scheme TAPCamDemo
  -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath
  /private/tmp/TAPCamDemoDerivedDataLockedDevice` passed.
- `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme
  TAPCamDemo -destination 'generic/platform=iOS' -derivedDataPath
  /private/tmp/TAPCamDemoDerivedDataLockedDeviceTests
  -skip-testing:TAPCamDemoUITests` passed, compiling the updated test sources
  without launching a simulator.
- Built app embeds `TAPCamLockedCameraCaptureExtension.appex` under
  `Extensions` with `EXExtensionPointIdentifier = com.apple.securecapture`.
- Built app embeds `TAPCamLockedCameraControlExtension.appex` under `PlugIns`
  with WidgetKit extension point.
- `git diff --check` passed.
- 2026-07-07 follow-up build for the attached iPhone passed:
  `xcodebuild build -destination 'id=00008130-001A4CEE26D0001C'`.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` passed.
- 2026-07-07 follow-up install to the attached iPhone succeeded with bundle id
  `TAP-NAP.TAPCamDemo`.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` was rerun
  after the immediate-Library-route adjustment and passed.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` was rerun
  after the settled-import/session-content-update wait adjustment and passed.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` was rerun
  after the foreground-resume settled-import adjustment and passed.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` was rerun
  after the missing-first-frame watchdog adjustment and passed.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` was rerun
  after the explicit Flash-off/defaults logging adjustment and passed.
- 2026-07-07 follow-up `git diff --check` passed after converting locked import
  to explicit route/session-update signals and adding the pitfall table.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` passed
  after the over-heavy-path removal and route-flag adjustment.
- 2026-07-07 follow-up physical iPhone Debug build passed for device id
  `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`.
- 2026-07-07 follow-up install to the same iPhone succeeded with bundle id
  `TAP-NAP.TAPCamDemo`, and `devicectl device process launch
  --terminate-existing TAP-NAP.TAPCamDemo` launched the main app.
- 2026-07-07 follow-up built-product inspection confirmed
  `TAPCamLockedCameraCaptureExtension.appex` under `Extensions/` with
  `com.apple.securecapture` and
  `TAPCamLockedCameraControlExtension.appex` under `PlugIns/` with
  `com.apple.widgetkit-extension`.
- A temporary Codex-side device-smoke script was tried and then removed from the
  repo after the user clarified that Xcode-installed runs are required for the
  needed logs.
- 2026-07-07 follow-up `build-for-testing` for `generic/platform=iOS` passed
  after the fixed-subsystem logging and main-thread notification adjustments.

Current real-device blocker:

- Device discovery and install worked earlier through direct device id
  `00008130-001A4CEE26D0001C`.
- `xcrun devicectl device process launch --device 00008130-001A4CEE26D0001C
  --terminate-existing TAP-NAP.TAPCamDemo` repeatedly failed because the phone
  was locked: SpringBoard denied the request with reason `Locked`.
- After resuming at 2026-07-07 07:36 CST, CoreDevice no longer located the old
  device identifier for launch. `xcrun devicectl list devices` listed
  `harold_android` as iPhone 15 Pro with identifier
  `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`, but state `unavailable`; Xcode
  `-showdestinations` did not list a physical iPhone destination.
- Follow-up `devicectl list devices` still listed the same iPhone 15 Pro as
  `unavailable`, and `xcodebuild -showdestinations` still did not list a
  physical destination.
- Later follow-up on 2026-07-07 saw the same device become `connected`.
  `xcodebuild build -destination id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`
  passed, `devicectl device install app` installed `TAP-NAP.TAPCamDemo`, and
  `devicectl device process launch --terminate-existing TAP-NAP.TAPCamDemo`
  launched the main app successfully.
- A later reinstall after the capture-default hardening also passed build,
  install, and main-app launch on the same connected iPhone 15 Pro.
- Built-app inspection confirmed the secure capture extension is embedded under
  `Extensions/` with
  `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.securecapture`
  and the control extension is embedded under `PlugIns/` with
  `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- Real-device smoke resumes after the user manually unlocks once and keeps the
  phone in a launchable state: open main app, publish AppContext, lock, launch
  locked extension, capture, naturally dismiss/unlock/open the main app, and
  verify the pending record appears through the App-level import runtime.

Separate presentation issue to validate:

- When the phone is not actually locked and the user pulls down Notification
  Center, launching the locked camera extension can shrink the notification UI
  and hang.
- Treat this separately from the historical post-live black screen. Capture
  scenePhase, extension process lifetime, root init/body, preview layer state,
  and controller active transition logs before changing camera session logic.

### 2026-07-07 E1A Direct-Open Runtime-Import Result

User-reported operation:

- Opened the main app and captured normally.
- Locked the phone, launched the extension, captured, then manually locked /
  unlocked and opened the main app Library. This natural path imported normally.
- Locked the phone again, launched the extension, captured, then tapped the
  lower-left placeholder. The main app opened to Library but remained in the
  waiting-for-locked-capture state. After the next lock-screen launch froze and
  the user locked/unlocked again, the photo was imported.

Log evidence:

- Natural path succeeded first:
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`, then import succeeded for
  `721213DC-4137-4629-828D-7ED35F8B7109`.
- E1A direct-open path was active:
  `locked_camera_handoff_received destination=tapLibraryAwaitingLockedImport
  tapAction=openTAPLibraryRuntimeImport
  reason=runtime_import_after_saved_capture managerSessionCount=0`.
- The app skipped the old transition-delay path as intended:
  `locked_camera_transition_delay_skipped ... openTAPLibraryRuntimeImport`.
- The app opened Library awaiting import with no session content exposed yet:
  `tap_library_present ... awaitingLockedCaptureImport=true
  managerSessionCount=0`.
- The actual session content arrived only later:
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`, then import succeeded for
  `448DD9E8-1FC7-4232-8910-6CAC5890B7FC` and Library refreshed to
  `visiblePendingCount=4`.

Interpretation:

- E1A failed the UX goal: direct-open still opened the app before iOS exposed
  the extension's `sessionContentURL`, and the next locked launch still froze.
- E1A did prove the old `beginDelayingAppearance()` / handoff-time import path
  is not the only cause. The failure remains when transition delay and
  handoff-time `sessionContentURLs` scanning are removed.
- The next direct-open experiment should simplify the extension-side API use:
  call `openApplication(for:)` without first hiding the preview, cancelling the
  watchdog, stopping `AVCaptureSession`, or removing inputs/outputs. That
  isolates whether our pre-open teardown is interfering with the system-owned
  secure-capture transition.

### 2026-07-07 E1B Minimal Direct-Open First Smoke

User-reported operation:

- Opened the main app and captured normally.
- Locked the phone, launched the extension, captured, then manually locked /
  unlocked and opened the main app Library. This natural path imported normally.
- Locked the phone again, launched the extension, captured, then tapped the
  lower-left placeholder. The main app opened to Library but remained in the
  waiting-for-locked-capture state. After the next lock-screen launch froze and
  the user locked/unlocked again, the photo was imported.

Log evidence:

- Natural path again succeeded first:
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`, then import succeeded for
  `4B626FB3-2438-45B6-9693-5313966A467B`.
- Direct-open again arrived in the main app before session content was exposed:
  `locked_camera_handoff_received destination=tapLibraryAwaitingLockedImport
  tapAction=openTAPLibraryRuntimeImport reason=runtime_import_after_saved_capture
  managerSessionCount=0`.
- The old transition-delay path was still skipped:
  `locked_camera_transition_delay_skipped ... openTAPLibraryRuntimeImport`.
- Library entered awaiting state with `managerSessionCount=0`, then repeatedly
  loaded a snapshot with `visiblePendingCount=3`.
- The new locked content arrived only later:
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`, then import succeeded for
  `6EE842C6-C8A0-4AE1-BEDE-2F571118563A`, and Library refreshed to
  `visiblePendingCount=4`.

Interpretation:

- Behaviorally, E1B still failed the direct-open UX in the same way as E1A.
- The pasted log did not include extension-process probes such as
  `open_application_minimal_handoff`, `open_application_prepare`, or
  `open_application_call`. It also still showed the E1A-era reason string
  `runtime_import_after_saved_capture`, so this log cannot independently prove
  whether the minimal extension branch ran.
- The next patch changes only the `NSUserActivity.reason` values for the
  runtime-import handoff to `e1b_minimal_runtime_import_*`, so the main-app log
  can prove which handoff variant is installed even when extension-process logs
  are absent.

### 2026-07-07 E1B Minimal Direct-Open Confirmed Failure

User-reported operation:

- Opened the main app and captured normally.
- Locked the phone, launched the extension, captured, then manually locked /
  unlocked and opened the main app Library. This natural path imported normally.
- Locked the phone again, launched the extension, captured, then tapped the
  lower-left placeholder. The main app opened to Library but remained in the
  waiting-for-locked-capture state. After the next lock-screen launch froze and
  the user locked/unlocked again, the photo was imported.

Log evidence:

- The handoff is confirmed to be the E1B build because the main-app log includes
  `reason=e1b_minimal_runtime_import_after_saved_capture`.
- At handoff, the app still saw no exposed session content:
  `locked_camera_handoff_received ... tapAction=openTAPLibraryRuntimeImport
  reason=e1b_minimal_runtime_import_after_saved_capture managerSessionCount=0`.
- The old transition-delay path was still skipped:
  `locked_camera_transition_delay_skipped ... e1b_minimal_runtime_import`.
- Library entered awaiting state with no session content exposed:
  `tap_library_present ... awaitingLockedCaptureImport=true
  managerSessionCount=0`.
- The pasted log contains the successful natural import before the handoff:
  `locked_camera_session_content_update kind=added`, import succeeded for
  `F2DBB483-91E8-4800-9C65-91D477C87679`, and Library reached
  `visiblePendingCount=7`.
- The pasted log segment does not include a later `session_content_update
  kind=added` for the direct-open capture before it ends; user observation says
  that import happened only after the following lock/unlock cycle.

Interpretation:

- E1B is now confirmed failed. Removing extension-side pre-open teardown did not
  make `openApplication(for:)` a migration-complete boundary.
- The remaining direct-open failure is not explained by
  `beginDelayingAppearance()`, handoff-time import scans, or our manual
  `AVCaptureSession` teardown.
- Next useful experiments should change a different variable: either avoid
  presenting TAP Library / Photos / pending-worker surfaces during direct open
  (E1C), or verify the historical flat-HEIC transfer layout (E2A/E2B).

### 2026-07-07 E1C Light-Route Direct-Open Result

User-reported operation:

- Opened the main app and captured normally.
- Locked the phone, launched the extension, captured, then manually locked /
  unlocked and opened the main app Library. This natural path imported normally.
- Locked the phone again, launched the extension, captured, then tapped the
  lower-left placeholder. The user still observed the old pattern: the just
  captured photo was not immediately visible, the next locked-extension launch
  froze, and the photo appeared after another lock/unlock cycle.

Log evidence:

- The handoff is confirmed to be E1C:
  `locked_camera_handoff_received destination=camera
  tapAction=openTAPCameraRuntimeImport reason=e1c_light_route_after_saved_capture
  managerSessionCount=0`.
- The transition-delay path was skipped:
  `locked_camera_transition_delay_skipped destination=camera
  tapAction=openTAPCameraRuntimeImport`.
- The app did not enter the awaiting Library route. `locked_camera_handoff_apply`
  showed `routeAwaitingImport=false`, and later `tap_library_present` logs used
  `awaitingLockedCaptureImport=false`.
- The app still saw no session content at handoff time:
  `managerSessionCount=0`.
- The session content arrived only later:
  `locked_camera_session_content_update kind=added managerSessionCount=1
  captureProbeCount=1`, then import succeeded for
  `7AA1782E-ED10-4BE3-A8D1-783DEE95D217`.

Interpretation:

- E1C rules out TAP Library awaiting state as the root cause.
- E1C does not rule out main-app camera startup as a variable: after the handoff,
  logs immediately show main-app camera capture-output/photo-settings
  configuration, which means the main app likely grabbed camera resources while
  the system was still unwinding the secure-capture transition.
- The next experiment should direct-open to a neutral app route that does not
  create `CameraView`, does not fetch Photos, and does not present TAP Library.
  If that still freezes, the remaining suspect is the system/direct-open
  lifecycle itself rather than our app's first route.

### 2026-07-07 E1D Neutral Direct-Open Result

User-reported operation:

- Opened the main app and captured normally.
- Locked the phone, launched the extension, saw one freeze, then launched again,
  captured, manually locked/unlocked, and opened the main app Library. This
  natural path imported normally.
- Locked the phone again, launched the extension, captured, then tapped the
  lower-left placeholder. The main app opened through the neutral handoff route,
  but Library still showed the waiting/delayed state. The next locked-extension
  launch froze; after another lock/unlock cycle, the photo was imported.

Log evidence:

- The handoff is confirmed to be E1D:
  `locked_camera_handoff_received destination=lockedImportNeutral
  tapAction=openTAPNeutralRuntimeImport
  reason=e1d_neutral_route_after_saved_capture managerSessionCount=0`.
- The transition-delay path was skipped:
  `locked_camera_transition_delay_skipped destination=lockedImportNeutral`.
- The app rendered the neutral route:
  `locked_camera_neutral_handoff_presented` and
  `locked_camera_neutral_handoff_appear`, both with `managerSessionCount=0`.
- The first direct-open did not expose the just-written session content to the
  app. Later, after another lifecycle turn, the app saw:
  `locked_camera_handoff_received ... reason=e1d_neutral_route_placeholder
  managerSessionCount=1`, then `locked_camera_session_content_update kind=added
  managerSessionCount=1 captureProbeCount=1`.
- That later update imported successfully:
  `locked_camera_session_staging_packaged
  captureID=13DC8812-9611-49DE-941F-983884D10D44`, followed by
  `store locked ingest created`, `locked_camera_session_import_succeeded`, and
  session content invalidation.

Interpretation:

- E1D rules out TAP Library awaiting state, immediate Photos fetch, transition
  delay/import polling, and first-route `CameraView` construction as sufficient
  causes of the saved-placeholder failure.
- The remaining E1-class suspect is the direct `openApplication(for:)` lifecycle
  itself: it can open the containing app before Apple's secure-capture session
  content migration is visible, and it can be followed by a frozen next
  locked-extension launch.
- Further E1 route variants are unlikely to be useful. The investigation should
  split into E2A and E3:
  - E2A: reproduce the historical `lockScreen_test` flat-HEIC data-transfer
    layout without direct-open, to understand why historical imports were
    visible reliably.
  - E3: launch the locked extension without capture or placeholder handoff, to
    classify the first/next-launch freeze independently of content transfer.
