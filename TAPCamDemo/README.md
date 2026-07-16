# TAPCamDemo Source Tree

This source root is split by product responsibility, not by framework target.
The iOS app target compiles all Swift files under this tree.

## Module Map

```mermaid
flowchart TD
    App["App\nstartup + App Attest runtime"] --> Camera["CameraCapture\nlive SingleCam capture"]
    Camera --> Library["TAPLibrary\npending queue + export"]
    Library --> Media["MediaLibrary\nPhotoKit request boundary"]
    Media --> Analysis["DepthAnalysis\nphoto + TAP Video inspection"]
    Library --> Analysis
    App --> Library

    click App "App/README.md"
    click Camera "CameraCapture/README.md"
    click Library "TAPLibrary/README.md"
    click Media "MediaLibrary/MEDIA_LIBRARY.md"
    click Analysis "DepthAnalysis/README.md"
```

| Module | README | Owns |
| --- | --- | --- |
| App | [App/README.md](App/README.md) | App root, first-install permissions, App Attest runtime, diagnostics. |
| CameraCapture | [CameraCapture/README.md](CameraCapture/README.md) | UI, planning, AVFoundation photo/TAP Video runtime, logical packages, unsigned artifact handoff. |
| TAPLibrary | [TAPLibrary/README.md](TAPLibrary/README.md) | Serialized pending repository, signing/export orchestration, retry states, workspace and cleanup collaborators. |
| MediaLibrary | [MediaLibrary/MEDIA_LIBRARY.md](MediaLibrary/MEDIA_LIBRARY.md) | PhotoKit catalog/fetch boundary, shared request lifecycle, resource/image/Live Photo adapters. |
| DepthAnalysis | [DepthAnalysis/README.md](DepthAnalysis/README.md) | TAP photo and video readback, Library routes, playback, depth overlays, planes, and point cloud. |

## Boundary Rules

- `App` can decide when the camera surface is available, but does not prebuild
  camera runtime objects.
- `CameraCapture` is the only module that mutates `AVCaptureSession`.
- `CameraCapture` writes unsigned artifacts to `TAPLibrary`; it does not export
  to Photos directly.
- `TAPLibrary` owns App Attest capture proof injection and Photos export.
- `MediaLibrary` owns PhotoKit callback/request bridging; UI and domain stores
  consume its scalar async interface.
- `DepthAnalysis` reads saved or pending photo/video artifacts; it does not
  mutate capture output or live camera state.
