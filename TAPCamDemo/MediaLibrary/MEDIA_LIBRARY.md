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
| Canonical identity/order snapshot plus permission-safe change-observer activation | `LibraryMediaStore.swift` |

## Concurrency contract

- Request-ID and continuation installation each happen at most once.
- Cancellation before installation cancels a later request ID immediately.
- Cancellation, success, and failure compete for one terminal completion.
- Stale/degraded callbacks cannot complete a newer request.
- Resource-to-Data and resource-to-file use the same lifecycle and bridge; only
  their sinks differ.
- Image and Live Photo adapters keep their distinct PhotoKit callback semantics
  instead of entering one giant generic result interpreter.

## Startup observation boundary

`LibraryMediaStore` is safe to construct during app wiring, but construction is
observer-inert by default. `StartupGateView` explicitly activates the TAP
Library notification observer and `PHPhotoLibraryChangeObserver` only after an
eligible Photos boundary: either the Photos row has just completed explicitly,
or post-Setup routing passively confirms usable Photos access. Activation and
deactivation are idempotent; deactivation also cancels queued and in-flight
catalog refreshes so a stale callback cannot cross a revoked-permission route.

Resource Initialization consumes only the first usable identity/order metadata
snapshot. A successful empty catalog is usable. It does not wait for iCloud
originals, thumbnail decoding, poster generation, hashing, or ZIP work.

Focused tests cover cancellation before/after install, cancel followed by an
error callback, concurrent terminal/install races, degraded image and Live
Photo callbacks, iCloud-only probes, and file write failure cleanup.
