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

## SDK Symbols Not Safe To Use Yet

The iPhoneOS 26.5 SDK `.tbd` exports these symbols:

- `LockedCameraCaptureSession.openApplicationAfterTransitionCompletion(for:)`
- `LockedCameraCaptureManager.applicationDidCompleteTransition()`
- `LockedCameraCaptureSession.urlsToOpen`
- `LockedCameraCaptureSession.hasActiveSession`

However, they are absent from the public Swift interface and Apple DocC pages
visible in this Xcode installation. Treat them as unavailable for production and
do not call them via private symbol tricks. If a future Xcode exposes them in
the public Swift interface, they are worth re-evaluating because their names
match the lifecycle problem we are seeing.

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
| Q35/Q36 previously drifted toward status-only as the main path. | Status-only is useful as a baseline/negative control, but it does not satisfy the required UX: the lower-left placeholder must directly open the containing app. | Keep the baseline commit for rollback, then run direct-open experiments that change only the handoff/import mechanics. |
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
   API was being used too aggressively inside the extension.
3. Keep the status-only placeholder baseline as a committed rollback point and
   negative control. It is not the target UX.
4. E2A historical-transfer experiment: extension writes flat
   `TAPCam-<UUID>.heic` unsigned TAP artifacts directly under
   `sessionContentURL`, and the main app importer enumerates `.heic` files like
   `lockScreen_test`. This requires checking extension-safe target membership
   for the shared packaging stack before code migration. This is the experiment
   that validates the `lockScreen` / `lockScreen_test` data-transfer logic.
5. Keep the new TAP Library presentation probe: pending record count, latest
   capture IDs, merged item count, and whether the locked capture ID is present.
6. Keep the app-level `sessionContentUpdates` runtime as the only normal import
   trigger.
7. If E1B still freezes, run an extension-launch-only experiment:
   launch locked UI, do not capture, do not tap placeholder, dismiss, and relaunch
   three times. This separates secure-capture presentation freeze from content
   migration.
8. Do not use `.tbd`-only symbols until they appear in public Swift interface
   and Apple documentation.
9. If E1B still opens Library before content is visible, treat that as a UX
   waiting-state problem unless the following `sessionContentUpdates` import
   never arrives.

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
