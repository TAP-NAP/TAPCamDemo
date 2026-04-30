# Zoom

`ZoomCapabilityResolver` computes zoom from runtime format data. Release UI does
not expose a separate zoom selector; it exposes FOV buttons such as `13mm`,
`24mm`, `48mm`, and `77mm`. Each FOV option carries the depth-safe zoom factor
needed to configure the resolved capture device. Debug tooling may still inspect
the lower-level zoom profiles.

The FOV label and displayed zoom are semantic. The value that reaches
AVFoundation is the raw `videoZoomFactor` recorded by
`ZoomProfile.rawVideoZoomFactor`. On a depth-safe virtual format, `24mm` can
begin at raw `2.0`, so `24mm` still displays as `1x` while `48mm` travels
through the plan as raw `4.0`.

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
`0.5x / 1x / 2x / 3x` are interpreted relative to the 24mm Wide FOV baseline.
If that baseline is raw `2.0`, the visible `1x` chip requests raw `2.0`, the
visible `2x` chip requests raw `4.0`, and so on. Release filters out unsupported
FOV options; Debug can keep them visible and disabled.

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
are shown as chips; unsupported values stay disabled. Debug FOV labels display
both the resolved 35mm-equivalent FOV and the semantic zoom relative to 24mm,
for example raw `2.0` on a Dual Wide or Portrait depth format can display as
`24mm · 1x`.
