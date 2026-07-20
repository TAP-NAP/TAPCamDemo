# Manual Control Device Limits Trace

## Goal

Record the design decision to stop treating missing ISO, shutter, and MF writes
as a TAPCam UI implementation problem. The current evidence shows that some
professional camera controls are unavailable because the active Apple camera
path does not expose them through AVFoundation on the tested device.

## User Constraints

- Stop the current grilling pass.
- Do not change Swift code in this step.
- Document that the limitation is an Apple camera/device capability issue, not
  a TAPCam support refusal.
- Keep the evidence scope honest: the available device matrix currently comes
  from one iPhone 15 Pro, so broader device claims are not supported.
- Put true source switching into roadmap instead of mixing it with Phase 1.

## Decision Summary

- Added a device-limit note for professional camera controls.
- Phase 1 remains LiDAR-backed 24mm manual-depth capture when available.
- Phase 1 `1x / 2x / 3x` zoom is preview-only, with final RGB and depth staying
  full-frame LiDAR 24mm.
- Source switching mode is deferred to roadmap and requires a different output
  contract.
- Disabled manual controls should be explained as current Apple camera path
  limitations.

## Files Updated

- `Docs/CameraManualControlDeviceLimits.md`: new reader-facing device-limit,
  Phase 1, roadmap, and validation note.
- `Docs/CameraControlsDesign.md`: links the design vocabulary to the device
  capability limit and preview-only zoom/source-switching distinction.
- `Docs/FutureCameraSpecs.md`: adds the device-limit document to the future
  camera reading path and manual-control roadmap.
- `Docs/README.md`: adds the new document to the docs map.
- `Docs/AITrace/README.md`: indexes this trace.

## Validation

No build or test command is required for this documentation-only update. The
remaining validation is attended real-device evidence, not compiler evidence.

## Open Follow-Ups

- Implement Phase 1 preview-only zoom and LiDAR-backed manual-depth selection
  in a later code pass.
- Re-run the real-device probe on iPhone 15 Pro after implementation.
- Expand device coverage before claiming support across the iPhone 15 family or
  later devices.
- Decide whether the product needs a separate hardware source-switching mode
  after Phase 1 UX feedback.

