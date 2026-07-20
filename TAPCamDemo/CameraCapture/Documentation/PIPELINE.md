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
Prepared Photo Settings
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
enabled. After each successful session configuration, Runtime calls
`setPreparedPhotoSettingsArray` with the same selected HEIC/JPG + depth settings
used for the actual still capture. This is an AVFoundation latency hint only;
capture remains valid if preparation is delayed or declined.

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
