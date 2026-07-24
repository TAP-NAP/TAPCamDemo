# Camera Manual Control Device Limits

This document records the current product interpretation of professional camera
controls in TAPCamDemo. It separates what the app can design around from what
Apple exposes for a specific active camera device, format, and depth pipeline.

## Current Evidence

The current evidence comes from one attended real-device probe only:

- Device: iPhone 15 Pro.
- OS observed during the probe: iOS 26.5.
- Scope: rear photo-depth capture paths relevant to ISO, shutter, AF, and MF.

This is not a full iPhone 15 family matrix, not a cross-iOS guarantee, and not
evidence for other Pro, Pro Max, non-Pro, iPad, or future devices. Broader
claims need a larger device matrix.

Observed behavior on this device:

| Active camera path | Depth | Tap AF | Custom ISO/S | MF lens position |
| --- | --- | --- | --- | --- |
| `BuiltInTripleCamera` Release 24/48/77mm-style plans | Preserved | Supported | Not supported | Not supported |
| `BuiltInLiDARDepthCamera @ 1x` | Preserved | Supported | Supported | Supported |

The same probe showed the LiDAR depth zoom range as `1.0...1.0`. TAPCam should
not assume LiDAR `videoZoomFactor` values above 1x are depth-safe on this
device.

Front-camera MF is a separate risk. The current implementation notes an
observed black-screen risk when writing custom lens position in a front depth
capture graph, so the first stage disables the AF/MF switch on the front camera
until a safer device matrix and UX validation exist.

## Product Interpretation

The missing ISO, shutter, and MF writes on the tested Triple Camera depth path
are not product UI gaps that TAPCam can fix by adding more controls. They are
active-device capability limits exposed by Apple through AVFoundation.

TAPCam can:

- Discover the active device and format capabilities at runtime.
- Prefer a capture path whose Apple-exposed capabilities match the product
  goal when available.
- Gate controls by the active device capability snapshot.
- Explain disabled controls as current Apple camera/device limitations.
- Keep unsupported writes out of Runtime.

TAPCam cannot safely:

- Force custom ISO, shutter, or lens-position writes onto an Apple camera path
  that does not expose those capabilities.
- Promise that every iPhone 15-family depth capture path supports professional
  manual controls.
- Treat one iPhone 15 Pro probe as a complete device-support matrix.

## Photographer Mode v1 Decision

Photographer Mode prioritizes a reliable, internally consistent manual-depth
path. It supports Photo and TAP Video and uses an all-or-nothing eligibility
rule.

Standard mode:

- Never opts into LiDAR merely because the device provides it.
- Preserves the existing capture path, Basic EV, lens selector, and release UI.
- Does not expose ISO, shutter, or MF controls.

Photographer Mode is eligible only when runtime discovers a rear LiDAR 24mm /
1x path that simultaneously preserves depth and supports custom ISO, custom
shutter duration, tap AF, and MF lens-position writes. When active:

- Use that LiDAR-backed 24mm / 1x path as the capture and control device.
- Attach `EV`, `ISO`, `S`, and `AF/MF` to the same active device; show `ƒ` as
  read-only.
- Hide the lens selector. Do not offer 2x / 3x preview presets in PRO.
- Keep the final photo and depth output on the fixed full-frame LiDAR 24mm path.
- Do not crop RGB or depth output and do not repurpose manifest crop metadata as
  destructive crop.

If that complete eligible path is unavailable, Photographer Mode is
`unavailable`: hide the PRO entry and keep Standard fully usable. TAPCam does
not expose a partially disabled professional toolbar on a fallback camera path.

PRO activation and deactivation require asynchronous session reconfiguration.
The UI must retain the last preview frame under frosted glass and disable
capture/control interaction until the destination session is ready. This is why
availability, Standard, activating, active, deactivating, and failure are
separate runtime states instead of one Boolean.

The same frosted transition applies between active rear PRO and the front
camera. Front entry temporarily suspends the rear PRO intent and uses automatic
or tap focus only; returning rear restores PRO if it remains eligible. This
suspension does not update the persisted Remember Last State preference.

## Roadmap: Source Switching Mode

True source switching is a later roadmap item, not Phase 1.

In that mode:

- `24mm` may use LiDAR when it is the best depth/manual-control path.
- Other focal lengths may switch to Triple, Wide, Tele, or another Apple camera
  path.
- ISO, shutter, AF, and MF availability must be recomputed from the active
  Apple camera path.
- Disabled controls should remain explanatory: the reason is that the current
  Apple camera path does not expose the requested control.
- The output contract must be redefined, because switching source means the app
  can no longer claim every final RGB/depth capture is full-frame LiDAR 24mm.

This roadmap is intentionally separate from multi-camera quality enhancement.
Any future LiDAR-control plus higher-quality RGB fusion would need a separate
design for synchronization, alignment, fusion, manifest representation,
validation, and scoring.

The runtime product-mode plan is recorded in
[CameraProControlsBuildIsolationPlan.md](CameraProControlsBuildIsolationPlan.md).
That plan keeps Standard and Photographer Mode separate by active camera path
and session readiness; this document explains why Apple active-device
capabilities determine whether PRO can be offered at all.

## Open Validation

The remaining evidence gap is physical device coverage:

- Re-run the probe after Phase 1 implementation on the current iPhone 15 Pro.
- Record whether `exposureTargetOffset` sign and preview brightness match the
  expected EV direction.
- Confirm ISO/S/MF writes on the LiDAR path after real readback.
- Confirm AF -> MF first locks `AVCaptureLensPositionCurrent`, and that only an
  actual MF-strip drag sends a numeric lens-position write.
- Confirm MF magnification keeps one main PreviewLayer and renders the inset
  from the PRO graph's preview-sized VideoDataOutput through an
  AVSampleBufferDisplayLayer; it must not add a second PreviewLayer or move the
  device zoom factor.
- Confirm continuous MF drag uses one in-flight write plus one latest pending
  value, and that AVFoundation completion (not a fixed debounce) advances the
  stream.
- Confirm MF tap runs focus-only AF at the selected point, waits for the
  request-local settle cycle, locks `AVCaptureLensPositionCurrent`, and keeps
  the shutter disabled until locked readback completes.
- Confirm rapid taps, slider drag during assist, PRO/front switching, and
  background cancellation cannot publish an old focus result or leave UI in MF
  while the device remains in AF.
- Confirm front-camera AF/MF gating avoids the observed black-screen path.
- Confirm Standard never selects the LiDAR input on eligible hardware.
- Confirm frost stays visible until both Standard/PRO and rear/front destination
  previews are interactable.
- Expand to other Apple devices before making product-wide support claims.
