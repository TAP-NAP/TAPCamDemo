# SingleCam Architecture

```text
UI
     |
     v
CameraViewModel
     |
     v
CapabilityMatrix  <----  CameraCapabilityResolver
     |                         ^
     v                         |
CaptureSourcePlan  ---->  Runtime
                                      |
                                      v
                         CaptureSessionController
     |
     v
CapturePipeline
     |
     v
CapturePackage
     |
     v
Output
     |
     v
Support Metrics
```

The demo has one runtime capture path: `AVCaptureSession + AVCapturePhotoOutput`.
UI reads `CapabilityMatrix` values and never inspects `AVCaptureDevice`
directly. `CaptureSessionController` is the only type that mutates the session
graph.

Release presents FOV choices such as `24mm`, `48mm`, and `77mm`. Each choice
already resolves to an Apple-paired photo-depth pipeline and a depth-safe raw
`videoZoomFactor`. Debug can override to a depth-capable device to inspect
format and zoom behavior, but it still uses the same SingleCam photo path.

The runtime provider produces one paired `AVCapturePhoto`. Output code keeps the
logical `CapturePackage` separate from the embedded HEIC artifact, then writes
Apple auxiliary depth plus the TAP manifest into one Photos asset.

## Directory Roles

| Directory | Role |
| --- | --- |
| `UI` | SwiftUI composition, preview bridge, release FOV controls, Debug controls, and view-model extensions. |
| `Planning` | AVFoundation discovery models, compatibility checks, depth-safe zoom resolution, FOV labels, crop metadata, and immutable capture plans. |
| `Runtime` | The single executable capture path: session graph owner, photo provider, capture jobs, and async pipeline orchestration. |
| `Output` | Logical package, embedded HEIC packaging, TAP manifest schema/building/encoding, and Photos writing. |
| `Support` | Shared errors, location lookup, and product-level capture metrics. |

Key code: [CameraViewModel.swift](../UI/CameraViewModel.swift),
[CapabilityMatrix.swift](../Planning/CapabilityMatrix.swift),
[CapturePlan.swift](../Planning/CapturePlan.swift),
[CaptureSessionController.swift](../Runtime/CaptureSessionController.swift),
and [EmbeddedPhotoPackager.swift](../Output/EmbeddedPhotoPackager.swift).
