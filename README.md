# TAPCamDemo SingleCam Photo-Depth Demo

TAPCamDemo is an iOS SingleCam photo-depth demo. Release capture is presented
as field-of-view choices such as `13mm`, `24mm`, `48mm`, and `77mm`; each
choice resolves to a concrete RGB source, compatible Apple-paired depth source,
and depth-safe zoom factor before capture. Front capture is entered through the
camera-switch button and hides the rear FOV selector. The app captures a
standard photo-depth HEIC only when Apple can produce paired depth through one
`AVCaptureSession + AVCapturePhotoOutput` pipeline.

Current non-goals: hash, signing, watermarking, destructive final crop,
MultiCam capture, RGB/depth streaming synchronizer, RAW provider runtime,
external session scaffolding, sidecar JSON, and debug bundles.

## Data Flow

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
CaptureSourcePlan ---> Runtime Session Controller
     |
     v
CapturePipeline
     |
     v
CapturePackage
     |
     v
EmbeddedPhotoPackager
     |
     v
PhotoLibraryWriter
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

The app does **not** run two independent sessions for RGB and depth. It also
does not include a MultiCam runtime path; unsupported independent camera-input
pairings are recorded as manifest/diagnostic facts instead of silently falling
back to another capture source.

The camera keeps the SingleCam session configured before the shutter is enabled,
prewarms `AVCapturePhotoOutput` with the depth HEIC settings used for capture,
and starts shutter work on touch-down. Location metadata is best-effort: capture
uses a recent cached `CLLocation` when available and refreshes location in the
background instead of waiting on Core Location during the shutter path.

## Code Map

| Responsibility | Code |
| --- | --- |
| App entry | [TAPCamDemoApp.swift](TAPCamDemo/App/TAPCamDemoApp.swift) |
| SwiftUI screen | [CameraView.swift](TAPCamDemo/CameraCapture/UI/CameraView.swift) |
| UI state and actions | [CameraViewModel.swift](TAPCamDemo/CameraCapture/UI/CameraViewModel.swift), [selection](TAPCamDemo/CameraCapture/UI/CameraViewModel+Selection.swift), [capture](TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift), [debug](TAPCamDemo/CameraCapture/UI/CameraViewModel+Debug.swift) |
| Preview + crop metadata bridge | [CameraPreviewView.swift](TAPCamDemo/CameraCapture/UI/CameraPreviewView.swift) |
| FOV/RGB/depth/zoom/crop capabilities | [CapabilityMatrix.swift](TAPCamDemo/CameraCapture/Planning/CapabilityMatrix.swift), [CameraCapabilityResolver.swift](TAPCamDemo/CameraCapture/Planning/CameraCapabilityResolver.swift), [ZoomCapabilityResolver.swift](TAPCamDemo/CameraCapture/Planning/ZoomCapabilityResolver.swift) |
| Pairing plan and session request | [CapturePlan.swift](TAPCamDemo/CameraCapture/Planning/CapturePlan.swift) |
| Session owner | [CaptureSessionController.swift](TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift) |
| Default photo provider | [AVFoundationSingleCamPhotoProvider.swift](TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift) |
| Pipeline and metrics | [CapturePipeline.swift](TAPCamDemo/CameraCapture/Runtime/CapturePipeline.swift), [CaptureJobMetrics.swift](TAPCamDemo/CameraCapture/Support/CaptureJobMetrics.swift) |
| Logical package | [CapturePackage.swift](TAPCamDemo/CameraCapture/Output/CapturePackage.swift) |
| Packaging model | [CapturePackager.swift](TAPCamDemo/CameraCapture/Output/CapturePackager.swift) |
| Embedded HEIC packager | [EmbeddedPhotoPackager.swift](TAPCamDemo/CameraCapture/Output/EmbeddedPhotoPackager.swift) |
| TAP manifest schema | [TAPDepthManifestSchema.swift](TAPCamDemo/CameraCapture/Output/TAPDepthManifestSchema.swift) |
| Photos writer | [PhotoLibraryWriter.swift](TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift) |
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

`payload` is encoded independently from `proofs`, so placeholder proof records
do not affect the payload bytes. The app does not generate hashes or signatures.

## TAP Manifest Capture Nodes

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
`depthBackend` are still emitted for older readers, but current readers should
prefer the nodes above. `photoLens.requestedFocalLengthLabel` records the
user-facing FOV label that drove the capture choice.

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
