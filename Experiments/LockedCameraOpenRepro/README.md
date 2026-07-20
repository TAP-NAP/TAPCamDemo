# Locked Camera Open Reproduction (R5)

This standalone project isolates the iOS 26 locked-camera transition after
`LockedCameraCaptureSession.openApplication(for:)`.

It deliberately contains no TAPCam camera code, session-content storage,
`LockedCameraCaptureManager`, PhotoKit, App Attest, network access, signing
queue, pending queue, App Group, or custom containing-app navigation.

## Identity

- App display name: `TAPCam LCC Repro`
- App bundle ID: `TAP-NAP.TAPCam.LockedCameraOpenRepro`
- Capture bundle ID: `TAP-NAP.TAPCam.LockedCameraOpenRepro.Capture`
- Control bundle ID: `TAP-NAP.TAPCam.LockedCameraOpenRepro.Controls`
- Control kind: `TAP-NAP.TAPCam.LockedCameraOpenRepro.control`

## Device setup

1. Open `LockedCameraOpenRepro.xcodeproj` directly.
2. Select the `LockedCameraOpenRepro` Release scheme and the physical device.
3. Run the app once and grant camera access. Confirm the app says `Authorized`.
4. Add the `LCC Repro` control to the Lock Screen.

Do not use the TAPCam control for this experiment.

## R5-C0: no-Open baseline

1. Lock the device and launch `LCC Repro`.
2. Confirm the system camera UI and the lower-left `OPEN` control are visible.
3. Do not tap `OPEN`. Press the side button to end the extension.
4. Repeat launch and side-button dismissal five times.

Pass: every launch creates a new `lccr5_capture_extension_init`,
`lccr5_capture_root_appear`, and `lccr5_picker_make` sequence without freeze.

## R5-C1: bare Open handoff

1. Launch `LCC Repro` from the Lock Screen.
2. Do not capture content. Tap `OPEN` and authenticate.
3. Confirm `TAPCam LCC Repro` opens and its handoff count increments.
4. Lock the device again.
5. Launch `LCC Repro` once and record whether the zoom-out transition freezes.
6. If it freezes, press the side button once and try one more launch.

The Open request creates only
`NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)`. It has no
title, `userInfo`, delay, storage, import, stop, teardown, or retry behavior.

## Required log stream

Capture all processes using subsystem:

```text
TAP-NAP.TAPCam.LockedCameraOpenRepro
```

Expected handoff markers:

```text
lccr5_open_tap
lccr5_open_begin
lccr5_open_accepted
lccr5_capture_root_disappear
lccr5_picker_dismantle
lccr5_app_activity_received
```

Also preserve SpringBoard, ExtensionKit, runningboardd, and RunningBoard logs for
the same timestamp. Xcode's app console alone normally omits capture-extension
markers.
