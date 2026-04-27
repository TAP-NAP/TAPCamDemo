# Capture Sources

The current demo has one capture source: `SingleCamPhotoCaptureProvider`.
It produces one paired `AVCapturePhoto` result through `AVCapturePhotoOutput`,
which is where Apple returns the visible photo, depth data, calibration, and
metadata together.

```text
CaptureSourcePlan
        |
        v
SingleCamPhotoCaptureProvider
        |
        v
AVCapturePhoto + AVCapturePhoto.depthData
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

## Provider Status

| Provider | Status |
| --- | --- |
| `SingleCamPhotoCaptureProvider` | Implemented, returns paired `AVCapturePhoto` + `depthData` |

## Removed Future Skeletons

The older v0.8 draft described separate RGB, depth, RAW, and external providers.
Those are intentionally not present in runtime code because the accepted
SingleCam product flow does not support freely recombining those outputs.
Future MultiCam or external-session work should be introduced as a separate
vertical slice after alignment and packaging rules are proven.
