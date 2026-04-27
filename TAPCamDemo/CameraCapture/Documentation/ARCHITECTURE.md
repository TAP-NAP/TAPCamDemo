# Architecture

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
Hook Pipeline
     |
     v
Writer
     |
     v
Diagnostics / Metrics
```

The main dependency direction is downward. UI reads `CapabilityMatrix` values;
it does not inspect `AVCaptureDevice`. `CaptureSessionController` is the only
type that mutates the session graph. Providers produce data. Packagers write
file containers. Hooks run after packaging and before writing.

Key code: [CameraCaptureCapabilities.swift](../Capabilities/CameraCaptureCapabilities.swift),
[CameraViewModel.swift](../Presentation/CameraViewModel.swift),
[SessionConfigurationRequest.swift](../Session/SessionConfigurationRequest.swift).
