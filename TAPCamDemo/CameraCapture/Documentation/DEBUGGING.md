# Debugging

Debug UI adds overlays that are not compiled into Release:

- fixed-order depth selector at the viewfinder's lower-left edge;
- performance panel with recent capture job metrics;
- active capture status and failure reason.

The panel prioritizes timing: queue wait, capture, package build, embedded HEIC
packaging, Photos storage write, and total duration. Queue wait no longer
includes waiting for Core Location; the shutter uses cached location metadata
and refreshes location in the background. The panel intentionally does not show
Photos asset identifiers; those remain an output implementation detail.

If a depth row is grey, read `RGBDepthCompatibilityMatrix` output and the latest
`CaptureJobMetrics.failureReason`.
