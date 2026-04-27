# RGB / Depth Pairing

Release lets the user choose a rear field of view first. The capability layer
then resolves that FOV option into a concrete visual RGB source, a compatible
depth source row, and a depth-safe zoom factor before validating whether Apple
can produce the pair through the SingleCam photo-depth pipeline. Front capture
is selected by the camera-switch control, not by the rear FOV selector.

```text
Selected FOV Option
        |
        v
Resolved RGB Source + selected/automatic Depth Source
        |
        v
RGBDepthCompatibilityMatrix
        |
        v
RGBDepthPairingCoordinator
        |
        v
CaptureSourcePlan
```

## Compatibility Rules

`RGBDepthCompatibilityMatrix` reports `.compatible` only when the depth row
resolves to the same `AVCaptureDevice` as the RGB source, or to a virtual device
whose `constituentDevices` contain the selected RGB source. Other independent
camera pairings are reported as unsupported for the current SingleCam runtime.

| Status | Meaning |
| --- | --- |
| `compatible` | Still photo + depth can run through SingleCam |
| `requiresMultiCam` | Outside the current SingleCam runtime |
| `unsupportedFormat` | Candidate device has no photo-depth format |
| `unsupportedZoom` | Selected zoom is outside the depth-safe range |
| `releasePackagingUnsupported` | Would violate single embedded photo policy |

Depth rows stay in fixed order in Debug. Changing FOV updates each row's state
but does not reorder it. Release hides the Debug depth rows and shows only FOV
options that can produce embedded photo depth.

Debug depth-device override is intentionally decoupled from this Release
pairing row. When an engineer selects a Debug depth device, that device becomes
the single active preview/capture pipeline. The app does not claim that the
Release FOV source and the Debug depth device are independent synchronized
sources; those are outside the current runtime.

## Capture Gate

Only `pairingMode == rgbWithApplePairedDepth` can capture. Unsupported
plans may still configure RGB preview, but shutter capture is blocked.
