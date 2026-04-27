# Crop

v0.8 records preview crop metadata only.

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

Release does not destructively crop RGB or depth. A future destructive crop must
crop RGB and depth together and update orientation, calibration, and metadata.
