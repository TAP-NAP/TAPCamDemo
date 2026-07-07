# Locked Camera Capture API Notes

This note records the public API surface, the current handoff failure, and the
document assumptions that need discussion before the next code change.

## Current Finding

The latest real-device smoke shows that the `openTAPCamera` experiment is still
not a reliable left-placeholder handoff path.

Observed sequence from the attached log `a2a3225.../pasted-text.txt`:

1. The app-side import runtime starts.
2. The system reports `locked_camera_session_content_update kind=added`.
3. The importer sees `sessionCount=1`.
4. The importer packages and ingests locked capture
   `6840B833-CE01-4E6E-8D5B-431DB5ED4700` into `TAPPendingCaptureStore`.
5. The importer calls `LockedCameraCaptureManager.invalidateSessionContent(at:)`.
6. The system reports `kind=removed`.
7. Later, the left-placeholder `openTAPCamera` handoff reaches the main app.
8. The transition import logs `sessionCount=0`.

`sessionCount=0` therefore means:

- The code read `LockedCameraCaptureManager.shared.sessionContentURLs.count`.
- At that exact moment, Apple exposed no pending locked session directories to
  the containing app.
- In this log, the likely immediate cause is that the previous
  `sessionContentUpdates` import had already succeeded and invalidated the
  session directory.
- In other logs, the same value can also mean the containing app opened before
  the extension was suspended and before the system copied `sessionContentURL`.

`sessionCount` is a count of Apple-exposed session directories, not a count of
photos, pending records, or visible TAP Library cells.

## Historical `lockScreen` Transfer Strategy

The old `lockScreen` / `lockScreen_test` branches used the same Apple
handoff primitives, but a simpler file-transfer shape:

1. The extension wrote capture output under
   `LockedCameraCaptureSession.sessionContentURL`.
2. The main app used `LockedCameraCaptureManager.shared`.
3. The main app imported existing `manager.sessionContentURLs` on startup.
4. The main app kept a long-lived `for await` listener on
   `manager.sessionContentUpdates`.
5. `.initial(urls)` and `.added(url)` each triggered import for the URL.
6. Import enumerated actual `.heic` files inside the session directory.
7. The counter used for "how many captures" was `files.count`, not
   `sessionContentURLs.count`.
8. The main app invalidated the session content only after every discovered
   file had been imported into the app-owned persistence path.

Important distinction: the historical branch did not use the lower-left locked
placeholder as the data-transfer primitive. The lower-left area was a
status/progress surface; the transfer still depended on Apple's session-content
migration plus the app-side manager/importer.

`lockScreen_test` also wrote a different artifact shape from the current POC:

| Branch / POC | Extension writes | App importer reads | Capture counter |
| --- | --- | --- | --- |
| `lockScreen` | flat `TAPCam-<UUID>.heic` files already containing TAP manifest | recursive `.heic` files | actual HEIC file count |
| `lockScreen_test` | flat `TAPCam-<UUID>.heic` unsigned embedded photo artifacts | `.heic` files, then app-side signing/Photos save | actual HEIC file count |
| current POC | `<captureID>/unsigned.heic` plus `metadata.json`; app-side importer packages staging into final unsigned TAP artifact | capture directories with metadata | capture probe count, then imported pending count |

This makes the historical flat-HEIC transfer a good next experiment. It removes
the current staging metadata bundle and app-side packaging step from the
transfer question. It does not by itself solve the left-placeholder
`openApplication(for:)` race, because historical import still waits for the
system to expose `sessionContentURLs` or `sessionContentUpdates`.

## Default Real-Device Smoke Log Contract

For the default manual flow, logs should now be interpreted in layers:

1. Extension launch/control layer:
   `locked_camera_intent_perform`,
   `locked_camera_scene_content_invoked`,
   `locked_camera_root_init`,
   `first_frame`.
2. Extension write layer:
   `photo_capture_saved` with `captureDirectoryCount`,
   `flatHEICFileCount`, `metadataFileCount`, and `unsignedHEICFileCount`.
3. System migration layer:
   `locked_camera_session_content_update kind=initial|added|removed` with
   `managerSessionCount` and `captureProbeCount`.
4. App import layer:
   `locked_camera_session_import_begin`, `locked_camera_session_scan_result`,
   `locked_camera_session_import_succeeded`, and
   `locked_camera_pending_snapshot`.
5. Library presentation layer:
   `tap_library_load_begin`, `tap_library_snapshot_loaded`, and
   `tap_library_load_finish` with pending/exported/photos/item counts.
6. Left-placeholder handoff layer:
   extension-side `open_application_prepare`, app-side
   `locked_camera_handoff_received`, then `locked_camera_handoff_apply`.

The test sequence is:

1. Open the main app.
2. Lock the device.
3. Launch the locked extension.
4. Capture.
5. Manually unlock and enter the main app.
6. Check TAP Library.
7. Lock again.
8. Launch the locked extension.
9. Capture.
10. Use the lower-left placeholder handoff.
11. Check TAP Library.
12. Lock again.
13. Launch the locked extension again and check whether freeze occurs.

If `sessionCount == 0`, do not conclude photo loss by itself. Check whether the
extension wrote a capture (`photo_capture_saved` plus nonzero content counters),
whether the system exposed a URL (`session_content_update`), whether import
created a pending record (`locked_camera_pending_snapshot`), and whether Library
merged that pending record (`tap_library_snapshot_loaded`).

## Public API Table

| API | Availability | Owner | Use case | POC guidance |
| --- | --- | --- | --- | --- |
| `LockedCameraCaptureExtension` | iOS 18.0+ | Extension | Declares a locked camera capture extension. | Required for the capture extension target. |
| `LockedCameraCaptureUIScene` | iOS 18.0+ | Extension | Creates the locked UI scene and provides a `LockedCameraCaptureSession`. | Required. Root view must never be empty; keep controller alive with `@StateObject`. |
| `LockedCameraCaptureSession.sessionContentURL` | iOS 18.0+ | Extension | Temporary extension-container directory for captured content. The system copies it to the containing app when the extension is suspended. | Primary storage path for this POC. Do not treat it as a live shared container. |
| `LockedCameraCaptureSession.openApplication(for:)` | iOS 18.0+ | Extension | Requests opening the containing app. The system authenticates first if needed. Use `NSUserActivityTypeLockedCameraCapture`. | Valid for explicit user actions such as unavailable/regenerate. Current saved-placeholder use is unreliable: it can race session migration and can be followed by next-launch freeze. |
| `LockedCameraCaptureSession.invalidateSessionContent()` | iOS 18.0+ | Extension | Deletes the extension session contents when the extension has already ingested content via PhotoKit and does not want persistence. | Not for current POC. We need system migration into the main app, so extension must not invalidate successful captures. |
| `NSUserActivityTypeLockedCameraCapture` | iOS 18.0+ | Extension and app | Marks an `NSUserActivity` as coming from locked camera capture. | Use only as the handoff activity type for `openApplication(for:)`; route data goes in `userInfo`. |
| `LockedCameraCaptureManager.shared` | iOS 18.0+ | App | App-side entry point for migrated session content and transition helpers. | Required in the containing app. |
| `LockedCameraCaptureManager.sessionContentURLs` | iOS 18.0+ | App | Current directories containing captured session content. | Read only when import is explicitly needed. Empty does not prove no capture was made. |
| `LockedCameraCaptureManager.sessionContentUpdates` | iOS 18.0+ | App | Async sequence that reports initial, added, and removed session directories. Apple says to use this to process content as soon as it is available after app launch. | Stable primary import trigger. Keep one long-lived app-level listener. |
| `SessionContentUpdate.initial(urls:)` | iOS 18.0+ | App | Initial currently available session directories when observation starts. | Import each URL idempotently. |
| `SessionContentUpdate.added(url:)` | iOS 18.0+ | App | A newly available session directory. | Import immediately and idempotently. |
| `SessionContentUpdate.removed(url:)` | iOS 18.0+ | App | A removed session directory. | Log only; do not treat as capture failure. |
| `LockedCameraCaptureManager.invalidateSessionContent(at:)` | iOS 18.0+ | App | Tells the system the app no longer needs a migrated session directory. Apple ignores URLs outside `sessionContentURLs`. | Call only after successful pending-store import. Current code's app-side use is correct in principle. |
| `LockedCameraCaptureManager.beginDelayingAppearance()` | iOS 18.1+ | App | Tells the system the app wants to delay app launch/appearance during an extension-to-app transition. | It delays appearance only. It does not guarantee `sessionContentURLs` is non-empty. Latest smoke did not make saved-placeholder handoff reliable. |
| `LockedCameraCaptureManager.endDelayingAppearance()` | iOS 18.1+ | App | Ends the delayed app appearance. | Must pair with `beginDelayingAppearance()` if used. Not a content-transfer completion signal. |
| `AppIntent.openAppWhenRun` | iOS 16.0+ | App / App Intents / WidgetKit control | Opens the containing app after the intent runs. Deprecated in iOS 26 in favor of `supportedModes`, but still public and compatible with the current iOS 18.6 deployment target. | Use for the new alternate system-entry experiment. Keep `perform()` side-effect free: log only, then let the app open normally. |
| `AppIntent.authenticationPolicy` | iOS 16.0+ | App / App Intents / WidgetKit control | Controls whether an intent can run locked or needs authentication. | The alternate open-app control uses `.requiresAuthentication` because its UX is "authenticate, then open TAPCam", not "capture while locked". |
| `ControlWidgetButton(action:) where Action: AppIntent` | iOS 18.0+ | WidgetKit control extension | Lets a lock-screen/control-center control run an App Intent. | Use a second control kind, `TAP-NAP.TAPCamDemo.open-app`, so the existing locked camera capture control remains intact. |
| `OpenIntent` | iOS 16.0+ | App Intents | Opens an app-defined `AppValue` target. | Not used in the first alternate experiment because TAPCam only needs "open app", not "open a system-resolvable entity". Revisit if we model Library/capture records as `AppValue`. |

## Alternate AppIntent/OpenIntent System Entry

This experiment is intentionally separate from
`LockedCameraCaptureSession.openApplication(for:)`.

The new path adds a second lock-screen control:

1. `TAPCam` continues to invoke `TAPCamLockedCameraIntent` and launches the
   secure locked camera UI.
2. `Open TAPCam` invokes `TAPCamOpenAppFromLockScreenIntent`, requires
   authentication, and opens the containing app through App Intents.
3. The intent does not scan `sessionContentURLs`, does not wait for locked
   capture import, does not route TAP Library, and does not write handoff
   state.

This cannot fully replace the in-extension lower-left placeholder because the
user must first leave the secure capture UI and return to the lock screen
control surface. Its value is diagnostic and UX-oriented: if it opens the main
app without the next-launch freeze seen after `openApplication(for:)`, then the
problem is likely specific to the secure-capture extension handoff boundary,
not to "opening the app from the lock screen" in general.

## SDK Symbols We Must Not Use

The iPhoneOS 26.5 SDK `.tbd` exports these symbols:

- `LockedCameraCaptureSession.openApplicationAfterTransitionCompletion(for:)`
- `LockedCameraCaptureManager.applicationDidCompleteTransition()`
- `LockedCameraCaptureSession.urlsToOpen`
- `LockedCameraCaptureSession.hasActiveSession`

However, they are absent from the public Swift interface and Apple DocC pages
visible in this Xcode installation. They are recorded here only as a pitfall:
do not call them, do not use private symbol tricks, and do not include them in
the experiment matrix. Re-evaluate only if a future Xcode exposes an equivalent
API in the public Swift interface and documentation.

## Why `openApplication(for:)` Is Suspicious Here

Apple documents `openApplication(for:)` as a request to open the containing app,
not as a request to finish secure-capture teardown or complete session-content
migration.

For this POC, left-placeholder tap after a saved capture combines too many
state transitions:

1. stop preview/session;
2. suspend or dismiss the extension;
3. copy `sessionContentURL` into the containing app container;
4. authenticate and launch the app;
5. route the app UI;
6. import and invalidate migrated session content;
7. show a fresh TAP Library snapshot.

The current public API does not expose a "wait until migration complete, then
open app" call. `beginDelayingAppearance()` helps with UI appearance timing, but
the latest smoke shows it does not make `sessionContentURLs` available during
the handoff.

## Library Semantics To Keep Separate

There are two different user-visible ideas that are easy to conflate:

- Pending TAP Library state: imported locked captures should become
  `TAPPendingCaptureStore` records, including `.pending`, `.signing`, and
  `.failedRetryable`.
- Photos / exported depth album state: a capture appears here only after signing
  and export succeed.

The latest log shows the locked capture was ingested into pending store, then
App Attest signing failed with `AppAttestKit.AppAttestError code=2`, causing a
`failedRetryable` state. That should still be visible in TAP Library as a
pending item with retry status, but it should not be expected to appear as an
exported Photos asset.

If the UI still does not show the pending record, the next diagnostic should log
`visiblePendingRecords` and `DepthAlbumItemProvider` item IDs/counts on TAP
Library presentation, not keep changing LockedCameraCapture APIs.

## Document Assumptions To Discuss

These are contradictions or over-strong assumptions in the current PRD:

| Document claim | Why it is questionable now | Proposed discussion |
| --- | --- | --- |
| Q35/Q36 previously drifted toward status-only as the main path. | Status-only is useful as a baseline/negative control, but it does not satisfy the desired UX. The better split is: shutter saves, importer imports, and the lower-left placeholder only opens the main app. E2B failed because it opened TAP Library awaiting import, not because the button must own import. | Test E3A as open-only: `openApplication(for:)` should only open the containing app's default route. It must not trigger Library waiting/import logic. |
| Q33 says main App startup/import should not block UI. | True for app responsiveness, but it means "open app" does not guarantee the first visible Library snapshot includes just-migrated locked content. | Define whether immediate visibility means pending-store visibility after natural `sessionContentUpdates`, or a hard requirement for the same tap that opens the app. |
| Q36 implies transition-delay APIs may solve the saved handoff. | `beginDelayingAppearance()` delays app appearance, not session-content migration. Latest smoke saw `sessionCount=0` during the delayed transition. | Mark transition delay as diagnostic-only unless a future public API provides migration-complete semantics. |
| "lib has no extension photo" is ambiguous. | Pending store, TAP Library grid, and Photos/exported album are separate layers. The log proves pending ingest happened, while signing/export failed. | Add exact acceptance language: after locked import, the capture must appear as a TAP Library pending item even if signing/export later fails. |

## Recommended Next Experiments

1. E1A direct-open/runtime-import: lower-left locked placeholder calls
   `LockedCameraCaptureSession.openApplication(for:)` with
   `tapAction=openTAPLibraryRuntimeImport`. The main app opens the TAP Library
   awaiting state, skips `beginDelayingAppearance()` and any handoff-time
   `sessionContentURLs` scan, then lets the long-lived
   `sessionContentUpdates` runtime import content when Apple exposes it. This
   validated the historical import lifecycle only, not the historical file
   layout. The latest smoke still saw delayed content exposure and next-launch
   freeze, so E1A is recorded as failed for the UX goal.
2. E1B minimal direct-open: keep E1A's `openTAPLibraryRuntimeImport` route, but
   call `openApplication(for:)` directly from the extension without the POC's
   pre-open teardown (`isPreviewHostVisible = false`, watchdog cancel,
   `stopRunning()`, and input/output removal). This checks whether the handoff
   API was being used too aggressively inside the extension. Main-app logs must
   show `reason=e1b_minimal_runtime_import_after_saved_capture` or
   `reason=e1b_minimal_runtime_import_placeholder`; otherwise the log cannot
   distinguish E1B from the earlier E1A build. The latest smoke confirmed E1B
   still fails: direct-open reached the app with `managerSessionCount=0` and the
   next locked launch froze.
3. E1C light-route direct-open: keep the same minimal extension-side
   `openApplication(for:)`, but use `tapAction=openTAPCameraRuntimeImport` and
   route the main app to camera/default instead of TAP Library awaiting import.
   The handoff reason is `e1c_light_route_after_saved_capture` or
   `e1c_light_route_placeholder`. This avoids Photos fetches and pending-worker
   retries during the system-owned secure-capture transition. If E1C passes,
   the Library/Photos/pending-worker route is part of the freeze trigger; if it
   fails, direct-open itself is the likely lifecycle boundary problem.
4. E1D neutral direct-open: use `tapAction=openTAPNeutralRuntimeImport` and
   `reason=e1d_neutral_route_after_saved_capture`, and show a neutral root view
   instead of constructing `CameraView` or TAP Library. This removes app-side
   camera startup from the direct-open transition. The latest smoke confirmed
   E1D still fails: the neutral handoff reached the app with
   `managerSessionCount=0`, the user still saw delayed Library visibility, and
   the following locked launch froze before a later lifecycle turn imported the
   photo. E1 route variants are now considered exhausted for Phase 1.
5. Keep the status-only placeholder baseline as a committed rollback point and
   negative control. It is not the target UX.
6. E2A/E2B split the historical branch strategy into two findings. The flat
   `TAPCam-<captureID>.heic` root-file transfer works, but combining that shape
   with direct-open does not currently work. E2A is confirmed for the
   no-direct-open transfer path:
   repeated smokes logged `locked_camera_session_capture_found
   reason=session_content_update layout=flat-heic`, including a later run with
   three captures across two sessions and summary `found=3 imported=3 skipped=0
   failed=0 invalidated=2`. The same stability smoke did not reproduce freeze or
   the historical black screen under repeated manual locks and lock timeout.
7. E2B flat-HEIC plus direct-open is confirmed failed in the same shape as E1:
   the app received `openTAPLibraryRuntimeImport` with
   `reason=e2b_flat_heic_runtime_import_after_saved_capture` while
   `managerSessionCount=0`, TAP Library waited, session content arrived later as
   `sessionContentUpdates kind=added`, flat HEIC package/import then succeeded,
   and the next locked launch froze once before recovery. This rules out current
   staging bundle shape as the cause and keeps direct-open lifecycle as the main
   risk.
8. E3A open-only split-responsibility experiment: keep the E2A flat HEIC write
   and app-level `sessionContentUpdates` import model, but make the left
   placeholder's only responsibility opening the containing app. Use
   `tapAction=openTAPMainAppOnly`; route to camera/default; do not present TAP
   Library awaiting import; do not call a handoff-time `sessionContentURLs`
   scan. This is confirmed failed as a UX/stability target: it ruled out
   Library waiting/import work as the cause, but the session content still
   arrived later and the next locked launch froze once.
9. E3B system-only `openApplication(for:)` experiment: keep the
   `lockscreen_test` flat HEIC write/import line, but strip the lower-left open
   down to the public system call. The extension creates a plain
   `NSUserActivityTypeLockedCameraCapture` activity with no TAPCam
   `tapAction`, no `reason`, and no source marker, then passes it to
   `LockedCameraCaptureSession.openApplication(for:)`. The main app ignores
   this empty activity instead of saving a handoff or presenting Library. This
   is now confirmed failed after the signing/export server fix: the queue can
   sign/export normally, but the empty activity still reproduces the delayed
   session-content exposure / next-launch freeze shape.
10. E3B2 system-only plus local teardown tests the remaining lifecycle
   hypothesis. The extension still creates the same empty
   `NSUserActivityTypeLockedCameraCapture` activity and the main app still
   ignores it, but before calling `openApplication(for:)` the extension hides
   the preview host, cancels the frame watchdog, removes preview/session
   outputs and inputs, clears the video sample-buffer delegate, and stops
   `AVCaptureSession`. Required logs are
   `open_application_teardown_begin tapAction=systemOnly`,
   `open_application_teardown_end tapAction=systemOnly ... isRunning=false`,
   then `open_application_system_only_call`. Because extension OSLog lines have
   been missing from some pasted logs, E3B2 also sets the ignored activity title
   to `TAPCam Locked Camera E3B2 Teardown Complete` after teardown and before
   `openApplication(for:)`; the main app logs `activityTitle` for ignored empty
   locked-camera activities without changing routing.
11. E3C app-owned activity is a later fallback only. It may isolate whether
   `NSUserActivityTypeLockedCameraCapture` itself is involved, but it is heavier
   than Apple's recommended activity type and should not be the current main
   path.
12. Keep the new TAP Library presentation probe: pending record count, latest
   capture IDs, merged item count, and whether the locked capture ID is present.
13. Keep the app-level `sessionContentUpdates` runtime as the only normal import
   trigger.
13. Run an extension-launch-only experiment:
   launch locked UI, do not capture, do not tap placeholder, dismiss, and relaunch
   three times. This separates secure-capture presentation freeze from content
   migration.
14. Do not use `.tbd`-only symbols until they appear in public Swift interface
   and Apple documentation.
15. Do not treat a neutral/direct-open route as a transfer-complete boundary.
   If the app opens before content is visible, the evidence so far points to
   system-owned migration timing rather than a missing TAP Library refresh.

## Source References

- Apple LockedCameraCapture overview:
  https://developer.apple.com/documentation/lockedcameracapture
- `LockedCameraCaptureSession.openApplication(for:)`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/openapplication(for:)
- `LockedCameraCaptureSession.sessionContentURL`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/sessioncontenturl
- `LockedCameraCaptureManager.sessionContentUpdates`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/sessioncontentupdates
- `LockedCameraCaptureManager.sessionContentURLs`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/sessioncontenturls
- `LockedCameraCaptureManager.invalidateSessionContent(at:)`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/invalidatesessioncontent(at:)
- `LockedCameraCaptureManager.beginDelayingAppearance()`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/begindelayingappearance()
- `LockedCameraCaptureManager.endDelayingAppearance()`:
  https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/enddelayingappearance()
