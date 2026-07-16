# TAP Video Playback

The playback module opens a Photos, pending, or debug-fixture TAP Video without
loading the whole MP4 into memory. The root
`TAPVideoDepthPlaybackView` remains a small route shell; this folder owns the
screen, resource lifecycle, player, transport, stable chrome, and depth path.

## Reading order

1. `TAPVideoPlaybackRoute.swift` and `TAPVideoPlaybackDeletion.swift` define
   source navigation and delete policy.
2. `TAPVideoPlaybackResourceLoader.swift` resolves the original video resource
   and bounded loading preview.
3. `TAPVideoPlaybackSession.swift` owns fetch state, the player lifecycle,
   foreground/background transitions, share preparation, and cleanup.
4. `TAPVideoPlaybackPlayerLifecycle.swift` isolates player-item observation,
   warm-up, audio-session ownership, and seek completion.
5. `TAPVideoPlaybackScreen.swift` composes one stable viewer tree.
   `TAPVideoViewerChrome.swift` always constructs one
   `DepthViewerChromeView`; readiness changes only local accessory state.
6. `TAPVideoPlaybackTransportModel.swift` and
   `TAPVideoPlaybackTransportView.swift` own play/pause, confirmed elapsed time,
   seek generation, scrubber state, and transport accessibility identifiers.
7. `TAPVideoPlayerSurface.swift` and `TAPVideoPlayerSurfaceUIView.swift` own the
   noninteractive `AVPlayerLayer` surface, PiP seam, `videoRect` alignment, and
   external-playback observation.
8. Read the `Depth` folder in this order: registration policy, metadata reader
   and output, decode admission/cache, frame decoder/renderer, overlay surface,
   then `TAPVideoDepthPipeline` orchestration.

## Ownership rules

- Screen composition does not read MP4 bytes or decode depth frames.
- The session owns temporary resources and player teardown.
- Transport owns user time intent; the depth pipeline consumes confirmed
  playback time.
- Calibration alone never enables the 2D overlay. A reviewed spatial
  registration descriptor is required.
- Depth decode stays bounded by frame-size, cache-byte, and concurrent-decode
  limits. Whole-file `Data(contentsOf:)` and near-whole `subdata` copies remain
  prohibited by release source guards.
- PiP and external playback show the system RGB path; the app-owned depth
  overlay remains local.

Debug runtime fixtures live in `../DiagnosticsSupport`. They are compile-gated
and split into specification, generation, and harness-view files; they are not
part of Release behavior.
