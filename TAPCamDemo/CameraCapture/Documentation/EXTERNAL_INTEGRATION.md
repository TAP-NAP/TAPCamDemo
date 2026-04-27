# External Integration

Apps that already own a camera session can integrate without adopting
`CameraView`.

```text
Existing Camera App
        |
        v
Existing AVCaptureSession / Capture Callback
        |
        v
ExternalCapturePayload
        |
        v
ExternalCapturePackageService
        |
        v
PackagingStrategy
        |
        v
Hook Pipeline
        |
        v
Writer / Diagnostics
```

`ExternalCapturePackageService` currently enforces policy and exposes the entry
point. It does not fabricate Apple auxiliary depth for arbitrary external data.
Future implementation must validate RGB/depth alignment and calibration before
writing a release artifact.
