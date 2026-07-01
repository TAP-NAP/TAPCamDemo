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

## Phase 1 Decision

Phase 1 prioritizes manual-control reliability over true focal-length
switching.

When an eligible rear LiDAR 24mm depth path is available:

- Use the LiDAR-backed 24mm depth path as the active capture/control path.
- Keep ISO, shutter, AF, and MF controls attached to that active LiDAR device.
- Treat `1x / 2x / 3x` as preview-only zoom presets, not hardware source
  switching.
- Keep the final photo full-frame LiDAR 24mm.
- Keep the final depth output full-frame LiDAR 24mm.
- Do not crop RGB output.
- Do not crop depth output.
- Do not repurpose manifest crop metadata as destructive crop.
- Map tap-to-AF and metering points from the visible preview-only zoom region
  back into full-frame 24mm coordinates.
- Show a short `viewfinder edge toast` the first time the user enters 2x or 3x,
  so the user understands the zoom is preview-only and the saved photo remains
  full-frame.

If the LiDAR-backed manual-depth path is not available, TAPCam should fall back
to the best existing depth-capable capture path and capability-gate controls
from that active path. Disabled controls should explain that the current Apple
camera path does not support the requested manual control.

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

## Open Validation

The remaining evidence gap is physical device coverage:

- Re-run the probe after Phase 1 implementation on the current iPhone 15 Pro.
- Record whether `exposureTargetOffset` sign and preview brightness match the
  expected EV direction.
- Confirm ISO/S/MF writes on the LiDAR path after real readback.
- Confirm front-camera AF/MF gating avoids the observed black-screen path.
- Expand to other Apple devices before making product-wide support claims.

