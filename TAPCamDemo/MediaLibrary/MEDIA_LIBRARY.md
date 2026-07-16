# MediaLibrary

`MediaLibrary` is the framework boundary between TAP Library/Viewer policy and
PhotoKit callbacks. Callers use scalar request keys and `LibraryMediaFetching`;
they do not own `PHImageRequestID`, continuations, or PhotoKit result-dictionary
interpretation.

## Code map

| Responsibility | Code |
| --- | --- |
| Public protocol, request keys, and media value models | `LibraryMediaFetching.swift` |
| PhotoKit client/fetcher actor | `PhotoKitLibraryMediaFetcher.swift` |
| Exactly-once install/cancel/finish primitive | `PhotoKitRequestLifecycle.swift` |
| Shared resource bridge plus Data/file sink strategies | `PhotoKitResourceRequest.swift` |
| Display-image callback adapter | `PhotoKitImageRequest.swift` |
| Live Photo callback adapter | `PhotoKitLivePhotoRequest.swift` |
| Public-safe PhotoKit error mapping | `PhotoKitMediaFetchFailure.swift` |
| Viewer loading/progress/failure overlay | `LibraryMediaFetchOverlay.swift` |

## Concurrency contract

- Request-ID and continuation installation each happen at most once.
- Cancellation before installation cancels a later request ID immediately.
- Cancellation, success, and failure compete for one terminal completion.
- Stale/degraded callbacks cannot complete a newer request.
- Resource-to-Data and resource-to-file use the same lifecycle and bridge; only
  their sinks differ.
- Image and Live Photo adapters keep their distinct PhotoKit callback semantics
  instead of entering one giant generic result interpreter.

Focused tests cover cancellation before/after install, cancel followed by an
error callback, concurrent terminal/install races, degraded image and Live
Photo callbacks, iCloud-only probes, and file write failure cleanup.
