# TAPCamDemo Camera Capture v0.8

TAPCamDemo is a reusable iOS camera-capture pipeline. v0.8 presents rear capture
as field-of-view choices such as `13mm`, `24mm`, `48mm`, and `77mm`; each
choice resolves to a concrete RGB source, compatible Apple-paired depth source,
and depth-safe zoom factor before capture. Front capture is entered through the
camera-switch button and hides the rear FOV selector. The app captures a
standard photo-depth HEIC only when Apple can produce paired depth through one
`AVCaptureSession + AVCapturePhotoOutput` pipeline.

Current non-goals: hash, signing, watermarking, destructive final crop, running
MultiCam capture, and running RGB/depth streaming synchronizer.

## Data Flow

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
RGBDepthPairingCoordinator ---> Session / Device Layer
     |
     v
CapturePipeline
     |
     v
CapturePackageBuilder
     |
     v
EmbeddedPhotoPackager
     |
     v
PhotoLibraryCaptureArtifactWriter
```

## Implemented Capture Path

```text
Selected FOV Option
        |
        v
Resolved RGB Source + compatible Depth Source + depth-safe Zoom
        |
        v
RGBDepthCompatibilityMatrix
        |
        v
AVCaptureSession + AVCapturePhotoOutput
        |
        v
AVCapturePhoto image + AVCapturePhoto.depthData
        |
        v
HEIC primary image + Apple auxiliary depth + TAP XMP manifest
```

The app does **not** run two independent sessions for RGB and depth. MultiCam is
reserved for future independent camera-input pairings and is documented in
[MULTICAM_TODO.md](TAPCamDemo/CameraCapture/Documentation/MULTICAM_TODO.md).

## Code Map

| Responsibility | Code |
| --- | --- |
| App entry | [TAPCamDemoApp.swift](TAPCamDemo/App/TAPCamDemoApp.swift) |
| SwiftUI screen | [CameraView.swift](TAPCamDemo/CameraCapture/Presentation/CameraView.swift) |
| UI state and actions | [CameraViewModel.swift](TAPCamDemo/CameraCapture/Presentation/CameraViewModel.swift) |
| Preview + crop metadata bridge | [CameraPreviewView.swift](TAPCamDemo/CameraCapture/Presentation/CameraPreviewView.swift) |
| FOV/RGB/depth/zoom/crop capabilities | [CameraCaptureCapabilities.swift](TAPCamDemo/CameraCapture/Capabilities/CameraCaptureCapabilities.swift) |
| Pairing plan and session request | [SessionConfigurationRequest.swift](TAPCamDemo/CameraCapture/Session/SessionConfigurationRequest.swift) |
| Session owner | [CaptureSessionController.swift](TAPCamDemo/CameraCapture/Session/CaptureSessionController.swift) |
| Default photo provider | [AVFoundationSingleCamPhotoProvider.swift](TAPCamDemo/CameraCapture/CaptureSources/AVFoundationSingleCamPhotoProvider.swift) |
| Pipeline and metrics | [CapturePipeline.swift](TAPCamDemo/CameraCapture/Pipeline/CapturePipeline.swift), [CaptureJobMetrics.swift](TAPCamDemo/CameraCapture/Diagnostics/CaptureJobMetrics.swift) |
| Logical package | [CapturePackage.swift](TAPCamDemo/CameraCapture/Processing/CapturePackage.swift) |
| Packaging model | [CapturePackager.swift](TAPCamDemo/CameraCapture/Packaging/CapturePackager.swift) |
| Embedded HEIC packager | [EmbeddedPhotoPackager.swift](TAPCamDemo/CameraCapture/Packaging/EmbeddedPhotoPackager.swift) |
| TAP manifest schema | [TAPDepthManifest.swift](TAPCamDemo/CameraCapture/Packaging/EmbeddedPhoto/TAPDepthManifest.swift) |
| Photos writer | [PhotoLibraryWriter.swift](TAPCamDemo/CameraCapture/Writers/PhotoLibraryWriter.swift) |
| Analysis models and HEIC readback | [DepthAnalysisModels.swift](TAPCamDemo/DepthAnalysis/DepthAnalysisModels.swift), [DepthAnalysisReader.swift](TAPCamDemo/DepthAnalysis/DepthAnalysisReader.swift) |
| Depth / mask / plane / cloud tools | [AnalysisTools](TAPCamDemo/DepthAnalysis/AnalysisTools) |
| Saved-image album and analysis UI | [DepthAlbumPickerView.swift](TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift), [DepthAnalysisView.swift](TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift) |

## HEIC Layout

| HEIC location | Contents | Authority |
| --- | --- | --- |
| Primary image item | Visible RGB image from `AVCapturePhoto.fileDataRepresentation(with:)` | Authoritative RGB image |
| Auxiliary data | Apple depth/disparity attachment | Authoritative depth map |
| EXIF/GPS/TIFF | Compatibility metadata and short pointer | Compatibility mirror |
| XMP `tapdepth:Manifest` | TAP JSON manifest at `tapdepth:Manifest` | Authoritative TAP metadata |

`payload` is the future canonical signing input. `proofs` remains outside
`payload` and is reserved for future hash/signature records.

## Manifest v0.8 Additions

Important payload nodes:

| Field | Meaning |
| --- | --- |
| `rgbSource` | Resolved visual source for the final RGB photo |
| `depthSource` | Requested compatible depth row and resolved AVFoundation device |
| `pairing` | Pairing mode, compatibility status, release allowance, alignment status |
| `zoom` | Requested/actual zoom and depth-safe zoom ranges |
| `crop` | Preview-only normalized crop metadata |
| `resolvedSession` | Actual `AVCaptureDevice` used for the still photo-depth pipeline |
| `alignment` | TAP interpretation rule for Apple auxiliary depth alignment |

Legacy v1 fields such as `selectedDepthCamera`, `selectedZoom`, `photoLens`, and
`depthBackend` are still emitted for older readers, but v0.8 readers should use
the nodes above. `photoLens.requestedFocalLengthLabel` records the user-facing
FOV label that drove the capture choice.

Depth analysis fields are also embedded in the same manifest:

| Field | Meaning |
| --- | --- |
| `depth.metricUnit` | Unit after native/conversion interpretation, currently meters for metric analysis |
| `depth.conversionPath` | Whether the data was native metric depth or converted from disparity |
| `depth.pixelFormat` | Auxiliary depth/disparity pixel format code |
| `alignment.depthToImage` | Alignment rule for matching Apple auxiliary depth to the primary image |

## Documents

- [ARCHITECTURE.md](TAPCamDemo/CameraCapture/Documentation/ARCHITECTURE.md)
- [PIPELINE.md](TAPCamDemo/CameraCapture/Documentation/PIPELINE.md)
- [APPLE_DEPTH_LIMITATIONS.md](TAPCamDemo/CameraCapture/Documentation/APPLE_DEPTH_LIMITATIONS.md)
- [CAPTURE_SOURCES.md](TAPCamDemo/CameraCapture/Documentation/CAPTURE_SOURCES.md)
- [RGB_DEPTH_PAIRING.md](TAPCamDemo/CameraCapture/Documentation/RGB_DEPTH_PAIRING.md)
- [ZOOM.md](TAPCamDemo/CameraCapture/Documentation/ZOOM.md)
- [CROP.md](TAPCamDemo/CameraCapture/Documentation/CROP.md)
- [PACKAGING.md](TAPCamDemo/CameraCapture/Documentation/PACKAGING.md)
- [HOOKS.md](TAPCamDemo/CameraCapture/Documentation/HOOKS.md)
- [EXTERNAL_INTEGRATION.md](TAPCamDemo/CameraCapture/Documentation/EXTERNAL_INTEGRATION.md)
- [DEBUGGING.md](TAPCamDemo/CameraCapture/Documentation/DEBUGGING.md)

## Depth Analysis Module

Depth analysis is intentionally separate from capture. The camera pipeline
produces standards-compatible HEIC + Apple auxiliary depth + TAP manifest; the
analysis module reads saved photo bytes and builds heatmaps, valid masks,
point-cloud previews, and approximate plane candidates.

Single-photo RGB-D analysis can estimate visible-surface depth and approximate
coplanarity. It is not full 3D reconstruction: there is no stable world
coordinate system, no hidden geometry behind visible objects, and no multi-frame
mesh.

For a depth pixel `(u, v)` with metric depth `Z`, the analysis module uses the
pinhole model from `AVCameraCalibrationData.intrinsicMatrix`:

```text
X = (u - cx) / fx * Z
Y = (v - cy) / fy * Z
Z = depthMeters
```

## Reading From Photos

Photos may provide edited derivatives or thumbnails. For verification, always
request original `.photo` resource bytes with `PHAssetResourceManager`, then
parse them with ImageIO.

## Release Data Policy

Release output is a single embedded photo artifact. Release builds must not
write sidecar JSON, debug bundles, raw bundles, independent depth files,
independent metadata files, metrics files, or intermediate capture artifacts.

If a requested RGB/depth pair cannot be embedded as a valid Apple photo-depth
HEIC, capture is rejected instead of silently generating another file.
