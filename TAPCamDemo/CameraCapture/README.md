# CameraCapture: SingleCam Photo-Depth Code Guide

Capture one Apple-paired photo-depth HEIC from a semantic field-of-view choice.

## Overview

`CameraCapture` is the camera module for TAPCamDemo. Release UI lets the user
choose a field of view such as `24mm`, `48mm`, or `77mm`; Planning resolves that
choice into one compatible Apple photo-depth pipeline; Runtime captures one
`AVCapturePhoto`; Output embeds Apple auxiliary depth plus the TAP manifest into
one HEIC and saves it to Photos.

```text
UI
 |
 v
Planning
 |
 v
Runtime
 |
 v
Output
 |
 v
Support
```

The only executable capture path is `AVCaptureSession + AVCapturePhotoOutput`.
The module doesn't run separate RGB/depth sessions, doesn't write sidecars, and
doesn't let UI inspect AVFoundation devices directly.

## Getting Started

Build and run on a device to exercise real camera and depth capture. Simulator
can compile the module and run unit tests, but it doesn't provide the physical
depth-capable camera pipeline needed for live capture.

Start with [CameraView](x-source-tag://CameraCaptureRootView). It composes the
preview, Release FOV selector, Debug depth override controls, shutter button,
and recent-photo entry point. It delegates all camera decisions to
`CameraViewModel`.

```swift
CameraPreviewView(
    session: viewModel.session,
    onCropRectChanged: { rect in
        viewModel.updatePreviewCropRect(CropRectNormalized(metadataRect: rect))
    }
)
```

[View in Source](x-source-tag://CameraCaptureRootView)

## Select a Release FOV

Release selection begins with a `FocalLengthOption`, not a raw camera device.
Each option already contains the RGB source, depth source, and raw depth-safe
zoom that Planning resolved.

```swift
selectedRGBSourceID = option.rgbSource.id
selectedZoomID = option.zoom.id
selectedFocalLengthOptionID = option.id
await configureCurrentSelection()
```

[View in Source](x-source-tag://SelectReleaseFOV)

`configureCurrentSelection()` is the bridge from UI state into a runtime plan.
The important detail is that it passes `preferredZoomFactor`, the real raw
`videoZoomFactor`, into Planning. This preserves nonstandard FOV mappings such
as `48mm -> raw 4.0`.

```swift
let plan = CaptureSourcePlan.make(
    rgbSource: rgbSource,
    depthSource: depthProfile,
    selectionMode: depthSelectionMode,
    selectedZoomID: selectedZoomID,
    selectedZoomFactor: preferredZoomFactor,
    cropRectNormalized: previewCropRectNormalized
)
```

[View in Source](x-source-tag://ConfigureCurrentSelection)

## Discover Camera Capabilities

Planning begins by discovering AVFoundation devices and converting them into
stable value models. This keeps SwiftUI from duplicating device-type checks.

```swift
let discoveredSources = allDevices
    .map { makeCameraProfile(device: $0, depthCandidates: depthCandidates) }
    .sorted { lhs, rhs in
        if lhs.fixedOrder == rhs.fixedOrder {
            return lhs.displayName < rhs.displayName
        }
        return lhs.fixedOrder < rhs.fixedOrder
    }
```

[View in Source](x-source-tag://DiscoverCameraCapabilities)

## Build Release FOV Options

`CapabilityMatrix` builds Release FOV chips by asking for a compatible depth
source and depth-safe zoom for each target FOV. Release only shows options that
can produce embedded photo depth.

```swift
let requestedZoomFactor = FocalLengthLabelResolver.releaseVideoZoomFactor(
    for: rgbSource,
    targetEquivalentMillimeters: targetFOV,
    formatSelection: seedDepthSource?.formatSelection
)
let depthSource = bestCompatibleDepthProfile(
    for: rgbSource,
    preferredZoomFactor: requestedZoomFactor
)
```

[View in Source](x-source-tag://BuildReleaseFOVOptions)

## Validate RGB and Depth Pairing

Compatibility is deliberately conservative. A depth row is compatible when it
resolves to the same `AVCaptureDevice` as the RGB source, or to an Apple virtual
device that contains that RGB source as a constituent.

```swift
if candidate.device.uniqueID == rgbSource.device.uniqueID
    || candidate.device.containsConstituent(rgbSource.device) {
    return Result(
        status: .compatible,
        reason: nil,
        resolvedDevice: candidate.device,
        formatSelection: formatSelection
    )
}
```

[View in Source](x-source-tag://EvaluateRGBDepthCompatibility)

## Resolve Depth-Safe Zoom

Zoom is format data, not a hardcoded lens rule. `ZoomCapabilityResolver` reads
`supportedVideoZoomRangesForDepthDataDelivery` from the active candidate format
and appends the selected raw FOV zoom when it isn't one of the fixed Debug
chips.

```swift
if let selectedZoomFactor,
   profiles.contains(where: { $0.matchesRawVideoZoomFactor(selectedZoomFactor) }) == false {
    profiles.append(
        CameraCapabilityResolver.makeZoomProfile(
            zoom: selectedZoomFactor,
            minimumZoom: minimumZoom,
            maximumZoom: maximumZoom,
            depthDeliveryRanges: depthRanges,
            allowsZoomOutsideDepthDeliveryRanges: allowsOutsideDepthRanges,
            requiresDepthSafeZoom: requiresDepthSafeZoom
        )
    )
}
```

[View in Source](x-source-tag://ResolveDepthSafeZoom)

## Make the Capture Plan

`CaptureSourcePlan.make` is the last Planning step. It converts selected UI
state into a `CaptureSourcePlan`, which is the only shape Runtime is allowed to
execute.

```swift
let selectedZoom = selectedZoomID.flatMap { id in
    zoomCapability.zoomProfiles.first(where: { $0.id == id })
}
?? selectedZoomFactor.flatMap { zoom in
    zoomCapability.zoomProfiles.first(where: { $0.matchesRawVideoZoomFactor(zoom) })
}
?? zoomCapability.zoomProfiles.first(where: \.isEnabled)
```

[View in Source](x-source-tag://MakeCaptureSourcePlan)

## Configure the SingleCam Session

`CaptureSessionController` is the only type that mutates `AVCaptureSession`.
When the current graph already matches the requested device, format, output, and
depth state, the controller reuses the graph and applies only the raw zoom. This
is what prevents FOV-only changes from tearing down the virtual-camera input.

```swift
if canReuseCurrentGraph(
    session: session,
    photoOutput: photoOutput,
    plan: plan
) {
    try applyZoom(zoom, to: plan.resolvedCaptureDevice)
    return makeConfigurationResult(
        plan: plan,
        photoOutput: photoOutput,
        request: request
    )
}
```

[View in Source](x-source-tag://ConfigureSingleCamSession)

The reuse check compares the active graph to the requested plan, including
photo preset, input device, compatible visual format signature, output presence,
and depth-delivery state.

[View in Source](x-source-tag://ReuseSingleCamGraph)

## Capture the Photo and Depth Data

The provider captures through `AVCapturePhotoOutput`. It doesn't configure the
session; it only starts the photo request and forwards the produced
`AVCapturePhoto`.

```swift
settings.isDepthDataDeliveryEnabled = true
settings.embedsDepthDataInPhoto = true
settings.isDepthDataFiltered = true
settings.photoQualityPrioritization = .quality
```

[View in Source](x-source-tag://CaptureSingleCamPhotoDepth)

## Run the Async Pipeline

After the shutter tap, the pipeline captures, builds the logical package,
packages the HEIC, writes it to Photos, and records metrics. The preview remains
attached to the running session while this happens.

```swift
let captureResult = try await photoDepthProvider.capturePhotoDepth(job: job, context: context)
let capturePackage = try CapturePackageBuilder.makePackage(
    job: job,
    context: context,
    captureResult: captureResult
)
let artifact = try await packager.package(capturePackage)
let writeResult = try await writer.write(artifact)
```

[View in Source](x-source-tag://RunSingleCamCapturePipeline)

## Build the Logical Package

`CapturePackage` is the logical capture result. It keeps source, pairing, zoom,
crop, photo, and settings facts together, but it doesn't decide how bytes are
written.

```swift
guard captureResult.photo.depthData != nil else {
    throw TAPDepthCaptureError.missingDepthData
}
```

[View in Source](x-source-tag://BuildCapturePackage)

## Package an Embedded HEIC

`EmbeddedPhotoPackager` is the Release-safe physical packaging strategy. It uses
Apple's `fileDataRepresentation(with:)`, builds the TAP manifest, and injects
that manifest into the HEIC XMP metadata.

```swift
let manifest = try TAPDepthManifestBuilder.makeManifest(capturePackage: capturePackage)
guard let baseHEICData = capturePackage.photo.fileDataRepresentation(with: customizer) else {
    throw TAPDepthCaptureError.unableToCreatePhotoData
}
let finalHEICData = try TAPDepthHEICWriter.injectingManifest(manifest, into: baseHEICData)
```

[View in Source](x-source-tag://PackageEmbeddedDepthHEIC)

## Build and Inject the TAP Manifest

The manifest builder maps planning/runtime facts and Apple photo metadata into
the published TAP manifest schema. The schema keys and enum raw values are the
external contract.

```swift
let payload = TAPDepthManifest.Payload(
    id: captureID,
    capturedAt: TAPDateFormatting.iso8601.string(from: context.capturedAt),
    sessionMode: selectionContext.sessionMode,
    pairingMode: selectionContext.pairingMode,
    alignmentStatus: selectionContext.alignmentStatus,
    sourceAPIs: .avFoundationPhotoDepth,
    capture: TAPDepthManifest.Capture(
        resolvedSettingsUniqueID: photo.resolvedSettings.uniqueID,
        requestedCodec: capturePackage.requestedCodec.rawValue,
        depthDataDeliveryEnabled: true,
        embedsDepthDataInPhoto: true,
        depthDataFiltered: capturePackage.depthDataFiltered,
        photoQualityPrioritization: capturePackage.photoQualityPrioritization.tapDescription
    ),
    ...
)
```

[View in Source](x-source-tag://BuildTAPDepthManifest)

The HEIC writer copies the original image source into a destination while
merging XMP metadata. That avoids a pixel decode/re-encode step and preserves
Apple auxiliary depth/disparity attachments.

```swift
guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &copyError) else {
    let reason = copyError?.takeRetainedValue().localizedDescription ?? "unknown image copy error"
    throw TAPDepthCaptureError.imageCopyFailed(reason)
}
```

[View in Source](x-source-tag://InjectTAPManifestIntoHEIC)

## Save to Photos

The writer receives a completed `PackagedCaptureArtifact`; it doesn't inspect
hardware, choose pairing, or decide packaging. It saves the single embedded HEIC
to the `TAPCamDepth` album and returns the asset identifier.

```swift
let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
    artifact.photoData,
    capturedAt: artifact.capturedAt,
    location: artifact.location
)
```

[View in Source](x-source-tag://WritePackagedArtifactToPhotos)

## Debug Override

Debug depth selection is an override of the same SingleCam path. Selecting a
Debug depth-capable device makes that device the preview, RGB photo, and
`AVCapturePhoto.depthData` source.

```swift
isDebugDepthOverrideActive = true
depthSelectionMode = .debugDepthOverride
selectedRGBSourceID = rgbSource.id
selectedZoomID = nil
selectedFocalLengthOptionID = nil
```

[View in Source](x-source-tag://SelectDebugDepthDevice)

## Bug Notes

These two regressions are worth reading because they explain why the current
Planning and Runtime boundaries are shaped so tightly.

### PR #3: 48mm Fell Back to the 24mm View

[Pull request #3](https://github.com/TAP-NAP/TAPCamDemo/pull/3) fixed a mapping
loss between semantic FOV labels and raw `videoZoomFactor` values.

On the iPhone 15 Pro depth-capable virtual-camera format used during debugging,
the depth-safe raw zoom range started at `2.0`, not `1.0`. That means the Release
chips were semantic labels over raw zoom values:

- `24mm -> raw 2.0`
- `48mm -> raw 4.0`
- `77mm -> raw 6.417`

The broken path calculated the correct `48mm` option, but only passed a generic
zoom ID into Planning. When that ID wasn't present in the fixed zoom catalog,
Planning fell back to the first enabled depth-safe zoom, which was raw `2.0`.
The UI said `48mm`, while Runtime applied the `24mm` view.

The fix is the current `selectedZoomFactor` thread:

- UI passes the real raw zoom from `FocalLengthOption`.
  [View in Source](x-source-tag://ConfigureCurrentSelection)
- `ZoomCapabilityResolver` appends that raw zoom when it is not one of the fixed
  Debug chips.
  [View in Source](x-source-tag://ResolveDepthSafeZoom)
- `CaptureSourcePlan.make` uses the raw value as a first-class fallback when the
  selected zoom ID does not resolve.
  [View in Source](x-source-tag://MakeCaptureSourcePlan)

### PR #4: 77mm Briefly Flashed the 24mm View

[Pull request #4](https://github.com/TAP-NAP/TAPCamDemo/pull/4) fixed preview
flicker when switching into or out of `77mm`.

The symptom was a short flash of the `24mm` view before the preview settled on
`77mm`. The root cause was session graph churn: a FOV-only change could remove
and re-add the virtual camera input even though the selected device, visual
format, depth state, and output were already compatible. During that graph
transition, AVFoundation could briefly present the virtual device's wide
baseline before the requested raw zoom landed.

The fix is the current graph-reuse path:

- `CaptureSessionController` remains the only type that mutates
  `AVCaptureSession`.
  [View in Source](x-source-tag://ConfigureSingleCamSession)
- If the current graph already matches the requested SingleCam plan, Runtime
  reuses the graph and applies only the raw `videoZoomFactor`.
  [View in Source](x-source-tag://ReuseSingleCamGraph)
- Runtime still applies zoom around configuration commits so virtual-device
  format changes cannot silently reset the requested view.
  [View in Source](x-source-tag://ConfigureSingleCamSession)

## Documentation Map

The files under `Documentation/` are internal engineering notes. Use this order
when you need a deeper read than the code guide above:

| Document | Read it when you need to understand |
| --- | --- |
| [ARCHITECTURE.md](Documentation/ARCHITECTURE.md) | The module layout, dependency direction, and `UI -> Planning -> Runtime -> Output -> Support` ownership. |
| [PIPELINE.md](Documentation/PIPELINE.md) | The one executable capture path: `AVCaptureSession + AVCapturePhotoOutput`. |
| [APPLE_DEPTH_LIMITATIONS.md](Documentation/APPLE_DEPTH_LIMITATIONS.md) | Apple's depth-device, format, calibration, and FOV constraints. |
| [RGB_DEPTH_PAIRING.md](Documentation/RGB_DEPTH_PAIRING.md) | Why Release only exposes Apple-paired photo-depth choices and how unsupported pairings are rejected. |
| [ZOOM.md](Documentation/ZOOM.md) | Raw `videoZoomFactor`, semantic FOV labels, and depth-safe zoom ranges. |
| [CROP.md](Documentation/CROP.md) | Preview crop metadata versus destructive final crop. |
| [CAPTURE_SOURCES.md](Documentation/CAPTURE_SOURCES.md) | Why the demo has a single photo-depth provider seam instead of RGB/Depth/RAW provider stacks. |
| [PACKAGING.md](Documentation/PACKAGING.md) | The difference between logical packages, embedded HEIC packaging, TAP manifest injection, and Photos writing. |
| [DEBUGGING.md](Documentation/DEBUGGING.md) | Debug panels, metrics, queue state, and what remains after temporary FOV diagnostics were removed. |
