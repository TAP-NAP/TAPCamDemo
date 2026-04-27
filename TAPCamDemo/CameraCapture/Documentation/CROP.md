# Crop

SingleCam records preview crop metadata only.

```text
Preview Crop Overlay
        |
        v
Layer Rect
        |
        v
Normalized Capture Rect
        |
        v
cropRectNormalized Metadata
        |
        v
CapturePackage
```

`CameraPreviewView` uses
`AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)` to
convert the visible preview bounds into normalized metadata coordinates.

Release does not destructively crop the image or depth map. A destructive crop
must crop both together and update orientation, calibration, and metadata.
