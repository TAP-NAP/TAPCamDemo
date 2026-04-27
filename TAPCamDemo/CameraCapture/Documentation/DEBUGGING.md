# Debugging

Debug UI adds overlays that are not compiled into Release:

- fixed-order depth selector at the viewfinder's lower-left edge;
- performance panel with recent capture job metrics;
- active capture status and failure reason.

Metrics include capture, package build, packaging, Photos write, total duration,
queue wait, pending job count, pairing mode, selected RGB source, selected depth
source, zoom factor, crop mode, and failure reason.

If a depth row is grey, read `RGBDepthCompatibilityMatrix` output and the latest
`CaptureJobMetrics.failureReason`.
