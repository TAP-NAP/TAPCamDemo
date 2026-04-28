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

The provider must not add/remove `AVCaptureSession` inputs, outputs, or
connections. If it needs a session change, it must request it through
`SessionConfigurationRequest`, which is serialized by
`CaptureSessionController`.

The current executable provider is
[AVFoundationSingleCamPhotoProvider.swift](../Runtime/AVFoundationSingleCamPhotoProvider.swift).
It calls `AVCapturePhotoOutput.capturePhoto(with:delegate:)` after the session
has already been configured by [CaptureSessionController.swift](../Runtime/CaptureSessionController.swift).

## Provider Status

| Provider | Status |
| --- | --- |
| `SingleCamPhotoCaptureProvider` | Implemented, returns paired `AVCapturePhoto` + `depthData` |

## Removed Skeletons

There are no separate RGB, depth, RAW, registry, or external-session providers
in runtime code. Those skeletons imply arbitrary RGB/depth composition, while
the product currently relies on Apple's paired still-photo depth output from one
`AVCapturePhoto`.
