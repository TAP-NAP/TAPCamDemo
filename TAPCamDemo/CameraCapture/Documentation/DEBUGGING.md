# Debugging

Debug UI adds overlays that are not compiled into Release:

- fixed-order depth selector at the viewfinder's lower-left edge;
- performance panel with recent capture job metrics;
- active capture status and failure reason.

The panel prioritizes timing: queue wait, capture, package build, embedded HEIC
packaging, Photos storage write, and total duration. Queue wait no longer
includes waiting for Core Location; the shutter uses cached location metadata
and refreshes location in the background.

When packaging succeeds, Debug expands the `embed` row into:

- `manifestBuild`: TAP manifest construction from capture facts.
- `baseHEIC`: `AVCapturePhoto.fileDataRepresentation(with:)`.
- `rgbDigest`: primary HEIC decode to canonical RGBA8 plus SHA-256.
- `depthDigest`: `AVDepthData` conversion to `DepthFloat32` plus SHA-256.
- `metadataDigest`: canonical manifest payload JSON plus SHA-256.
- `appAttest`: App Attest assertion generation.
- `xmpInject`: ImageIO HEIC copy path with TAP XMP metadata merged.
- `xmpVerify`: readback check that the TAP XMP manifest survived insertion.

The panel intentionally does not show Photos asset identifiers; those remain an
output implementation detail.

If a depth row is grey, read `RGBDepthCompatibilityMatrix` output and the latest
`CaptureJobMetrics.failureReason`.
