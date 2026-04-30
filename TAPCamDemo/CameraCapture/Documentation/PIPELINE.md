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
