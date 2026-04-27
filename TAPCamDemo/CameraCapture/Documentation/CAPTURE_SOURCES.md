# Capture Sources

Capture sources are provider interfaces for producing RGB, depth, and RAW data.
They are extension points, not session owners.

```text
CaptureSourcePlan
        |
        +--> RGBCaptureProvider
        +--> DepthCaptureProvider
        +--> RawCaptureProvider
```

## Safety Boundary

Providers must not add/remove `AVCaptureSession` inputs, outputs, or
connections. If a provider needs a session change, it must request it through
`SessionConfigurationRequest`, which is serialized by
`CaptureSessionController`.

The current executable provider is
[AVFoundationSingleCamPhotoProvider.swift](../CaptureSources/AVFoundationSingleCamPhotoProvider.swift).
It calls `AVCapturePhotoOutput.capturePhoto(with:delegate:)` after the session
has already been configured by [CaptureSessionController.swift](../Session/CaptureSessionController.swift).

## v0.8 Provider Status

| Provider | Status |
| --- | --- |
| `SingleCamPhotoCaptureProvider` | Implemented, returns paired `AVCapturePhoto` + `depthData` |
| `RGBCaptureProvider` | Interface only |
| `DepthCaptureProvider` | Interface only |
| `RawCaptureProvider` | Interface only |
| External providers | Interface/documentation only |

## External Flow

```text
Existing Camera App
        |
        v
Existing Capture Callback
        |
        v
ExternalCapturePayload
        |
        v
ExternalCapturePackageService
        |
        v
Packaging / Hooks / Writer
```

Release still enforces `EmbeddedPhotoPackager` only. External input cannot use
sidecar or bundle strategies to bypass the release data policy.
