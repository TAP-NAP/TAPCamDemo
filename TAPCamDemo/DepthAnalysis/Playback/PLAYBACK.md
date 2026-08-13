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
3. `TAPVideoPlaybackSession.swift` owns fetch state, the foreground-only player
   policy, background fetch cancellation/recovery, a reference-counted lease
   for the complete original, and cleanup. `TAPVideoPlaybackProgressCoalescer`
   turns per-chunk copy progress into latest-value UI publication at no more
   than 20 Hz while preserving start and terminal samples.
4. `TAPVideoPlaybackPlayerLifecycle.swift` isolates player-item observation,
   warm-up, audio-session ownership, and seek completion.
5. `TAPVideoPlaybackScreen.swift` composes one stable viewer tree.
   `TAPVideoViewerChrome.swift` always constructs one
   `DepthViewerChromeView`; readiness changes only local accessory state.
6. `TAPVideoPlaybackTransportModel.swift` and
   `TAPVideoPlaybackTransportView.swift` own play/pause, confirmed elapsed time,
   seek generation, scrubber state, and transport accessibility identifiers.
7. `TAPVideoPlayerSurface.swift` and `TAPVideoPlayerSurfaceUIView.swift` own the
   noninteractive `AVPlayerLayer` surface and `videoRect` alignment. AirPlay,
   PiP, and background playback are unsupported.
8. Read the `Depth` folder in this order: registration policy, metadata reader
   and output, decode admission/cache, frame decoder/renderer, overlay surface,
   then `TAPVideoDepthPipeline` orchestration.

## Ownership rules

- Screen composition does not read MP4 bytes or decode depth frames.
- The session owns temporary resources and player teardown. Its original-video
  readiness is independent from AVPlayer first-frame readiness: Share is
  disabled until the original lease exists, then may open while the first
  visible frame is still warming.
- Share acquires a lease, runs the embedded proof/content-binding validator on
  those exact bytes locally, and gives the same lease to on-demand payload
  preparation. No Share path invokes backend/App Attest Verify, re-fetches the
  original, pre-generates a package, or persists a Share cache.
- Transport owns user time intent; the depth pipeline consumes confirmed
  playback time.
- Calibration alone never enables the 2D overlay. A reviewed spatial
  registration descriptor is required.
- Depth decode stays bounded by frame-size, cache-byte, and concurrent-decode
  limits. Whole-file `Data(contentsOf:)` and near-whole `subdata` copies remain
  prohibited by release source guards.
- The player sets `allowsExternalPlayback` to `false`; TAP Video remains local.
- Playback is foreground-only. Entering the background pauses the player and
  deactivates its playback audio session; no background-audio capability is declared.

Debug runtime fixtures live in `../DiagnosticsSupport`. They are compile-gated
and split into specification, generation, and harness-view files; they are not
part of Release behavior.
