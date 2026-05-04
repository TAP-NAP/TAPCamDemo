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

The runtime provider produces one paired `AVCapturePhoto`. Runtime prewarms the
photo output with the same HEIC + depth settings it later captures, and the UI
starts shutter work on touch-down. Output code keeps the logical
`CapturePackage` separate from the embedded HEIC artifact, then stages Apple
auxiliary depth plus an unsigned TAP manifest in the TAP Library pending store.
The async TAP Library worker later signs the staged HEIC and exports it into the
TAPCamDepth Photos album. Location metadata is best-effort cached support data;
capture never waits on Core Location.

The camera UI distinguishes foreground capture writes from background
attestation. TAP Library is blocked only while queued shutter jobs are still
being captured, packaged, and written into the pending store. After a pending
record exists, Library remains available even if that record is still waiting
for network, signing, or exporting.

## Directory Roles

| Directory | Role |
| --- | --- |
| `UI` | SwiftUI composition, preview bridge, release FOV controls, Debug controls, and view-model extensions. |
| `Planning` | AVFoundation discovery models, compatibility checks, depth-safe zoom resolution, FOV labels, crop metadata, and immutable capture plans. |
| `Runtime` | The single executable capture path: session graph owner, photo provider, capture jobs, and async pipeline orchestration. |
| `Output` | Logical package, embedded HEIC packaging, TAP manifest schema/building/encoding, and Photos export helpers. |
| `Support` | Shared errors, cached location refresh, and product-level capture metrics. |

Key code: [CameraViewModel.swift](../UI/CameraViewModel.swift),
[CapabilityMatrix.swift](../Planning/CapabilityMatrix.swift),
[CapturePlan.swift](../Planning/CapturePlan.swift),
[CaptureSessionController.swift](../Runtime/CaptureSessionController.swift),
and [EmbeddedPhotoPackager.swift](../Output/EmbeddedPhotoPackager.swift).
