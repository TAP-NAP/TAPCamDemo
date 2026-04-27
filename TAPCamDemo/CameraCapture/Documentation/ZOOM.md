# Zoom

`ZoomCapabilityResolver` computes zoom from runtime format data. Release UI does
not expose a separate zoom selector; it exposes FOV buttons such as `13mm`,
`24mm`, `48mm`, and `77mm`. Each FOV option carries the depth-safe zoom factor
needed to configure the resolved capture device. Debug tooling may still inspect
the lower-level zoom profiles.

```text
Selected FOV Option
        |
        v
Resolved RGB Source + compatible Depth Source
        |
        v
Active Format + Active Depth Format
        |
        v
ZoomCapabilityResolver
        |
        v
Depth-safe ZoomFactor Range
        |
        v
FOV Option UI
```

When a compatible depth source is resolved, candidate zoom factors such as
`0.5x / 1x / 2x / 3x` become FOV labels only if they are inside the depth-safe
range or the format explicitly supports zoom outside those ranges. Release
filters out unsupported FOV options; Debug can keep them visible and disabled.

## Debug Depth Override Zoom

Debug has a separate depth-device override path. Selecting a Debug depth device
switches the single-cam preview/capture pipeline to that device, then computes
zoom from that device's active photo-depth format. This is not a second camera
paired with the Release FOV selection.

The Debug zoom panel reads:

- `supportedVideoZoomRangesForDepthDataDelivery`
- `zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported`
- `minAvailableVideoZoomFactor`
- `maxAvailableVideoZoomFactor`
- `videoMaxZoomFactor`

Continuous ranges are shown with a slider and chips. Discrete depth zoom values
are shown as chips; unsupported values stay disabled. Debug FOV labels multiply
the selected depth device's base 35mm-equivalent focal length by
`videoZoomFactor`, for example `24mm · 2x`.
