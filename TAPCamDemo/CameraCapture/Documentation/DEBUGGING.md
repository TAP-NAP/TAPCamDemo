# Debugging

Debug UI adds overlays that are not compiled into Release:

- fixed-order depth selector at the viewfinder's lower-left edge;
- performance panel with recent capture job metrics;
- active capture status and failure reason.

The panel prioritizes timing: queue wait, capture, package build, embedded HEIC
packaging, pending-store write, and total duration. Queue wait no longer
includes waiting for Core Location; the shutter uses cached location metadata
and refreshes location in the background.

When foreground packaging succeeds, Debug expands the `embed` row into the
submetrics recorded by the shutter-time packager:

- `manifestBuild`: TAP manifest construction from capture facts.
- `baseHEIC`: `AVCapturePhoto.fileDataRepresentation(with:)`.
- `xmpInject`: ImageIO HEIC copy path with TAP XMP metadata merged.
- `xmpVerify`: readback check that the TAP XMP manifest survived insertion.

Digest and App Attest work now happens later in the async pending processor, so
it is not represented by the foreground capture job's `embed` timing.

The panel intentionally does not show pending capture identifiers or Photos
asset identifiers; those remain output implementation details. The camera's
TAP Library entry point shows progress while the foreground capture-write queue
is nonempty, but it is not a signing/export progress indicator.

If a depth row is grey, read `RGBDepthCompatibilityMatrix` output and the latest
`CaptureJobMetrics.failureReason`.
