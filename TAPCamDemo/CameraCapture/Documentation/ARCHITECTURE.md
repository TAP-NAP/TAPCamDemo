# SingleCam Architecture

```text
Presentation
     |
     v
CameraViewModel
     |
     v
CapabilityMatrix  <----  CameraCapabilityResolver
     |                         ^
     v                         |
CapturePipeline  ------>  CaptureSources  ------>  Session / Device Layer
     |
     v
CapturePackageBuilder
     |
     v
Packaging
     |
     v
Writer
     |
     v
Diagnostics / Metrics
```

The demo has one runtime capture path: `AVCaptureSession + AVCapturePhotoOutput`.
UI reads `CapabilityMatrix` values and never inspects `AVCaptureDevice`
directly. `CaptureSessionController` is the only type that mutates the session
graph.

Release presents FOV choices such as `24mm`, `48mm`, and `77mm`. Each choice
already resolves to an Apple-paired photo-depth pipeline and a depth-safe raw
`videoZoomFactor`. Debug can override to a depth-capable device to inspect
format and zoom behavior, but it still uses the same SingleCam photo path.

The capture provider produces one paired `AVCapturePhoto`. The package builder
normalizes metadata, the embedded packager writes Apple auxiliary depth plus TAP
manifest into one HEIC, and the writer saves that single artifact to Photos.

Key code: [CameraCaptureCapabilities.swift](../Capabilities/CameraCaptureCapabilities.swift),
[CameraViewModel.swift](../Presentation/CameraViewModel.swift),
[SessionConfigurationRequest.swift](../Session/SessionConfigurationRequest.swift).
