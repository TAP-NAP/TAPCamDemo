# Multi-Format Photo Research Trace

## Goal

Research how TAPCamDemo should add HEIC and JPEG output support while respecting
the currently selected camera, depth delivery, and real photo quality limits.
This trace records the investigation only; it does not implement the new output
profiles.

## User Constraints

- Keep the code readable for a reviewer starting from zero context.
- Prefer dedicated code for dedicated product behavior instead of hidden
  fallback paths.
- Consider whether the selected camera and active format actually support the
  requested photo container, codec, depth data, and resolution.
- Keep AI collaboration traceable through `Docs/AITrace`.

## References Checked

- Apple Developer Documentation:
  - `AVCapturePhotoOutput`
  - `AVCapturePhotoSettings`
  - `AVCaptureDevice.Format.supportedMaxPhotoDimensions`
  - `AVCapturePhotoOutput.maxPhotoDimensions`
- Local Xcode 26.5 iPhoneOS SDK headers:
  - `AVCapturePhotoOutput.h`
  - `AVCaptureDevice.h`
  - `AVDepthData.h`

The web documentation pages require JavaScript in this environment, so the
specific API constraints below come from the local Apple SDK headers.

## Current Code Findings

- The only executable Release output profile is
  `CaptureOutputProfile.releasePhotoDepthHEIC`.
- That profile is intentionally HEIC-depth only:
  - container: `embeddedPhotoDepthHEIC`
  - codec preference: `.hevc`
  - depth delivery: enabled
  - embedded depth: enabled
  - depth required: true
  - quality prioritization: `.quality`
- `CapturePhotoCodec` already names both `.hevc` and `.jpeg`, but JPEG is not
  currently an executable Release profile.
- `CapturePhotoOutputCapabilitySnapshot` only records codec support, depth
  support, configured depth state, and maximum quality prioritization. It does
  not yet record file container support, per-container codec support, or max
  photo dimensions.
- `SingleCamPhotoSettingsFactory` sets codec, depth flags, and quality
  prioritization, but does not set `AVCapturePhotoSettings.maxPhotoDimensions`.
- `CaptureSessionController` sets `session.sessionPreset = .photo` and
  `photoOutput.maxPhotoQualityPrioritization`, but does not set
  `AVCapturePhotoOutput.maxPhotoDimensions`.
- `EmbeddedPhotoPackager`, `TAPCaptureProvenanceWriter`,
  `TAPDepthHEICReader`, and `PhotoLibraryWriter.saveDepthHEIC` are explicitly
  built around a signed HEIC-depth artifact.
- `PhotoLibraryWriter` writes Photos resources with `UTType.heic.identifier`.

## Apple API Constraints That Matter

- `AVCapturePhotoOutput.availablePhotoCodecTypes` must contain the requested
  compressed codec, such as JPEG or HEVC, after the output has been added to a
  session with a video source.
- `AVCapturePhotoOutput.availablePhotoFileTypes` and
  `supportedPhotoCodecTypes(for:)` must be checked when choosing a concrete file
  container such as HEIC or JPEG.
- `AVCaptureDevice.Format.supportedMaxPhotoDimensions` lists the allowed still
  photo dimensions for the active format.
- `AVCapturePhotoOutput.maxPhotoDimensions` should be set before
  `startRunning()` because changing it can reconfigure the capture pipeline.
- `AVCapturePhotoSettings.maxPhotoDimensions` defaults to the smallest
  dimensions in `supportedMaxPhotoDimensions`.
- `AVCapturePhotoSettings.maxPhotoDimensions` must match a supported dimension
  for the current active format and be no larger than the output's configured
  max dimensions.
- `photoQualityPrioritization = .quality` can improve capture quality by letting
  AVFoundation spend more time on processing, but it is not a resolution,
  compression, or file-size guarantee.
- Depth, portrait effects matte, and semantic segmentation matte embedding are
  documented as supported in HEIF and JPEG, but TAPCamDemo still needs real
  device evidence before treating JPEG as an equivalent signed TAP depth
  artifact.

## Main Diagnosis

The low output size is probably not primarily caused by HEIC versus JPEG. The
stronger explanation is that the current pipeline never sets
`maxPhotoDimensions`, while Apple says per-shot `maxPhotoDimensions` defaults to
the smallest supported dimensions. The current `.quality` setting only affects
quality-versus-speed prioritization.

Therefore the first implementation should improve and log still-photo
resolution selection before adding visible HEIC/JPEG controls.

## Recommended Iteration Order

1. Add a max-photo-dimensions policy.
   Extend the capability snapshot with the active format's
   `supportedMaxPhotoDimensions`, choose the largest supported dimensions by
   product policy, set `photoOutput.maxPhotoDimensions` during session
   configuration, and set `settings.maxPhotoDimensions` for each capture.

2. Add real capture diagnostics.
   Log available codecs, available file types, per-file-type codec support,
   selected max dimensions, actual flattened bytes, and decoded image pixel
   width/height. This should be Debug-only and public-safe.

3. Add dedicated output profiles.
   Keep the current HEIC-depth profile as the default signed TAP artifact. Add a
   separate JPEG profile only after deciding whether JPEG is a signed TAP depth
   artifact or a visual RGB export.

4. Update packaging and storage only for the chosen product meaning.
   If JPEG becomes a signed TAP artifact, update the resource plan, manifest,
   content digest, Photos writer UTType, validator, reader, and tests together.
   If JPEG is only a visual export, keep it outside the current TAP depth export
   gate.

## Open Questions

- Should JPEG be a first-class TAP depth artifact, or only a user-visible RGB
  derivative/export?
- Do target devices preserve depth and TAP XMP in JPEG after Photos round-trip?
- Do target cameras expose 24MP max dimensions, and if so should the app opt in
  to deferred photo delivery?
- Should portrait effects matte or semantic segmentation mattes become part of
  the future product contract, or remain out of scope for TAP depth analysis?

## Reading Order

1. `Docs/FutureCameraSpecs.md`, especially the future output profile checklist.
2. `TAPCamDemo/CameraCapture/Output/CaptureOutputProfile.swift`.
3. `TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift`.
4. `TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift`.
5. `TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift`.
6. `TAPCamDemo/CameraCapture/Output/EmbeddedPhotoPackager.swift`.
7. `TAPCamDemo/CameraCapture/Output/TAPCaptureProvenanceWriter.swift`.
8. `TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift`.
9. `TAPCamDemoTests/TAPCaptureOutputProfileTests.swift`.

## Score Status

No implementation score is assigned in this trace because this round is
research-only. The implementation score should apply to the eventual
multi-format plan, not to this investigation note.

## Validation

- Code and documentation were inspected.
- Apple SDK headers were inspected locally.
- No build or test command was run because no product code changed.
