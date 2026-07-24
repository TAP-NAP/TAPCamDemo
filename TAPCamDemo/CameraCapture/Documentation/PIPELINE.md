# SingleCam Pipeline

## Still Photo + Depth

```text
Depth-capable Device / Virtual Device
        |
        v
AVCaptureSession
        |
        v
AVCapturePhotoOutput
        |
        v
Depth Delivery Enabled
        |
        v
capturePhoto(with:delegate:)
        |
        v
AVCapturePhoto
        |
        v
Photo Data + Depth Data + Metadata
```

This is the only running capture path. RGB image data, Apple auxiliary depth,
and photo metadata come from the same `AVCapturePhotoOutput` request.

## Shutter Latency

The camera starts and configures the SingleCam session before the shutter is
enabled. Still-photo settings are created at capture time from the resolved
HEIC/JPG + depth output token. Runtime deliberately does not retain optional
prepared-photo settings across camera-graph changes: Standard and LiDAR paths
use different physical capture sources, and repeated switching must not overlap
old asynchronous preparation with the next graph transaction.

The shutter control starts capture on touch-down rather than waiting for the
default SwiftUI button release action. Location is not awaited on the shutter
path: the view model uses a recent cached `CLLocation` if available and kicks
off a best-effort background refresh for later captures. If no recent location
exists, the manifest and staged photo file are saved without location metadata.

Foreground shutter work ends when the unsigned photo file has been written into the
app-private TAP Library pending store. While this capture-write queue is
nonempty, the TAP Library entry point is disabled and shows progress so entering
Library cannot stop the camera session before queued captures have landed on
disk. This gate does not cover App Attest signing or Photos export: once a
pending record exists, Library can open and display its pending/signing/exporting
status while the asynchronous worker continues.

## Camera-Path Reconfiguration

Standard, front-camera, and rear LiDAR PRO paths share one serialized capture
session controller. The viewfinder frost is presentation-only: it does not
disable the preview connection while Runtime replaces the video input. Crop
metadata publication pauses until the preview is rendering again.

Each PRO-related configuration has a 10-second watchdog. A timeout does not
enqueue another configuration behind a potentially blocked AVFoundation call;
the controller is quarantined and a single no-op queue probe must complete
before Retry is enabled. Once Runtime returns, PreviewLayer gets a separate
three-second readiness deadline. Remember Last State is persisted only after
both Runtime and the post-configuration preview are ready.

## Debug Override

```text
Debug Depth Device
        |
        v
Single AVCaptureSession
        |
        v
AVCapturePhotoOutput
        |
        v
AVCapturePhoto + depthData
```

Debug selection is not a second camera layered on top of Release FOV. It
switches preview and capture to the selected depth-capable device, then tests
depth-safe zoom on that same SingleCam pipeline.

Streaming synchronizers, MultiCam, RAW, external-session capture, and sidecar
outputs are not runtime paths in this demo.
