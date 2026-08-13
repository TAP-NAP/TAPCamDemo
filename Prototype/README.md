# TAPCam Interactive Visual Contract

This directory is the lightweight, statically served prototype foundation for
`TAP-0006`. Its current vertical slices are the TAP Share flow owned by
`TAP-0081` and the first-install resource-initialization flow owned by
`TAP-0009`.
It is intentionally plain HTML, CSS, and JavaScript: no backend, package manager,
framework runtime, production hosting configuration, or persistent cache is
required.

## Run

From the repository root:

```sh
python3 -m http.server 4173 --directory Prototype
```

Then open `http://127.0.0.1:4173/`.

## Review TAP-0081-r2-candidate

This is the exact incremental revision based on the owner-approved geometry and
handoff flow in `TAP-0081-r1`. On 2026-08-13 the product owner approved the full
`TAP-0081-r2-candidate`: complete-original readiness gates Share, the ready bytes
receive a local integrity check without backend Verify, Failed disables TAPNAP
but keeps warned ordinary-media sharing, Needs Retry remains queue-only, and the
refined Viewer toolbar geometry is native implementation authority.

1. Choose Photo, Live Photo, or Video.
2. Choose **iCloud · Loading**. Confirm the Viewer shows original-resource
   progress and the bottom-left Share control remains present but disabled.
3. Choose **Local · Ready** or **iCloud · Ready**. Confirm the loading state is
   removed and Share becomes enabled. Use **Private queue** to make the
   queue-only 待重试 fixture available.
4. Choose **Hold for review**, tap Share, and inspect the text-free local
   integrity skeleton. It deliberately exposes no fourth credential label.
   Use **Resolve local check** to reveal 已验证, 待重试, or 失败.
5. Inspect the capability matrix. TAPNAP Package is available only for a
   verified Photo/Live Photo; Video Package, Sticker, and Link remain disabled.
   In Failed, TAPNAP stays disabled while Share Image/Video remains enabled with
   the explicit warning “无法保证可验证性”.
6. Use Fast to confirm that preparation completed within 50 ms never inserts a
   progress surface.
7. Use Threshold to inspect work that completes around 120 ms: progress appears
   after 50 ms, reaches 100%, then remains until its 400 ms minimum-visible
   duration is satisfied. Use Slow to confirm that longer progress never moves
   backwards.
8. Use Cancel, Failure, and Retry. Confirm the Viewer, media, pager region, and
   toolbar never disappear or rebuild.
9. Inspect the final system handoff boundary. The real iOS activity controller
   is deliberately not imitated.

The prototype performs no PhotoKit, iCloud, proof parsing, hashing, App Attest,
or backend request. Those fixtures describe visible state relationships only;
the native implementation owns actual resource and integrity work.

The exact state coverage, source-image hashes, native symbol intent, system
boundaries, and approval status are recorded in [manifest.json](manifest.json).

## Review TAP-0009 resource initialization

The product owner approved exact revision `TAP-0009-r1-candidate` on
2026-08-13. It remains a separate Task and visual contract from TAP Share.

1. Select **冷启动资源初始化** under Flow. This slice represents the first
   launch after a fresh install, reinstall, or app update; ordinary subsequent
   launches skip it.
2. Inspect **Preparing**: neither the camera nor the first TAP Library catalog
   is ready, and the full-screen state remains stable.
3. Select **Camera ready**: the first preview frame and controls are ready while
   the Library catalog remains pending.
4. Select **Library ready** to inspect the reverse completion order: the
   catalog may complete while the real first camera frame is still pending.
5. Select **Ready → Camera**: both readiness groups turn ready, the spinner is
   removed, and the fixture advances to the explicit camera-entry boundary.

There is deliberately no Failed, Retry, timeout, or degraded-entry surface.
Initialization is a startup invariant: abnormal noncompletion keeps this stable
UI visible and emits developer diagnostics. It is treated as a defect, not a
user-recoverable product state.

This slice is independent from TAP Share. It does not prebuild or prewarm Share,
proof parsing, hashing, ZIP creation, or the system activity controller.

## Evidence Boundary

This prototype can establish visible hierarchy, relative geometry, copy,
enabled/disabled presentation, and simulated interaction order. It cannot prove
PhotoKit or AVFoundation behavior, real iCloud transfer, local content-binding
integrity, package preparation timing, signing, backend verification,
temporary-file cleanup, haptics, native accessibility, AirDrop, third-party
destinations, or physical-device performance.

Later Tasks may add Viewfinder or other vertical slices only after reading and
mapping their relevant Product Contract states. A missing slice remains
explicit; it is not invented here.
