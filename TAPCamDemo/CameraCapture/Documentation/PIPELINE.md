# Pipeline

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

This is the only running capture path in v0.8.

## Streaming RGB + Depth Debug

```text
AVCaptureSession
        |
        +--> AVCaptureVideoDataOutput
        |
        +--> AVCaptureDepthDataOutput
        |
        v
AVCaptureDataOutputSynchronizer
        |
        v
Synchronized RGB Frame + Depth Frame
```

v0.8 documents this path and leaves provider interfaces for it. It is not run.

## MultiCam

MultiCam is reserved for multiple independent camera inputs. It must use
`AVCaptureMultiCamSession`, check support, hardware cost, and system pressure,
and prove RGB/depth alignment before Release can embed depth as authoritative
HEIC auxiliary data.
