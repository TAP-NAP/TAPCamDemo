# TAPCam Interactive Visual Contract

This directory is the lightweight, statically served prototype foundation for
`TAP-0006`. Its current vertical slices are the TAP Share flow owned by
`TAP-0081`, the first-install setup flow owned by `TAP-0008`, and the separate
resource-initialization flow owned by `TAP-0009`.
It is intentionally plain HTML, CSS, and JavaScript: no backend, package manager,
framework runtime, production hosting configuration, or persistent cache is
required.

## Run

From the repository root:

```sh
python3 -m http.server 4173 --directory Prototype
```

Then open `http://127.0.0.1:4173/`.

## Review TAP-0081-r3-candidate

This owner-directed candidate preserves the geometry, resource/integrity states,
and capability matrix approved in `TAP-0081-r2-candidate`. It changes only the
app-owned preparation lifecycle: choosing TAPNAP Package or another implemented
share type keeps the selector visible and immediately adds determinate progress
as a 2 px track that replaces the selected option's subtitle text inside the
exact same fixed-height subtitle slot. The title, icon, badge, row height, popover
dimensions, and every sibling position remain unchanged; the subtitle text and
track are never shown together, and no percentage or Cancel control is inserted.
Every other option remains visible but is temporarily disabled. There is no
independent preparation page, artificial reveal delay, or minimum-visible hold.
When the payload becomes ready, the app-owned popover ends immediately. The
subsequently presented iOS activity controller remains a text-only boundary and
is never imitated by this Web prototype.

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
6. Keep **Success · observable** selected and choose any implemented format.
   Confirm the original subtitle text is replaced immediately by a thin progress
   track inside the same slot, without moving the title, icon, badge, row, popover,
   or sibling rows, and that progress never moves backwards. The subtitle and
   track must not appear together; no percentage or Cancel control appears. The
   other three rows stay visible and disabled. When the payload becomes ready,
   confirm the app-owned popover closes without inserting a preparation or
   completion screen.
7. Use Cancel, Failure, and Retry. Confirm the Viewer, media, pager region, and
   toolbar never disappear or rebuild.
8. Read the System boundary note in the control panel. It documents the native
   handoff only; the real iOS activity controller and its dismissal are not
   simulated.

The prototype performs no PhotoKit, iCloud, proof parsing, hashing, App Attest,
or backend request. The observable success/failure fixtures describe visible
state relationships only; the native implementation owns actual resource,
integrity, payload-progress, and system-presentation work.

The exact state coverage, source-image hashes, native symbol intent, system
boundaries, and approval status are recorded in [manifest.json](manifest.json).

## Review owner-approved TAP-0008 first-install setup

The product owner approved exact revision `TAP-0008-r2-candidate` on
2026-08-13 with “现在原型已经确认没有问题”. It remains deliberately separate
from the already-approved TAP-0009 initialization slice.

1. Select **首次安装设置** under Flow and choose **Untouched**. Confirm that all
   five rows are idle. Merely entering or foregrounding this page performs only
   passive status refresh: no permission UI, network preflight, PhotoKit change
   observation, camera start, or background warm-up begins. The header uses the
   exact current `LaunchLogo` asset from the app catalog; it does not substitute
   a text wordmark or redraw the brand. Every setup-row icon is exported from
   the exact SF Symbol identity used by `WelcomeStartupSetupView.swift`;
   Unicode or hand-drawn approximations are forbidden.
2. Tap an individual row's **允许** button. Confirm only that row changes to
   requesting and the app-owned system-boundary note appears. The real iOS
   permission sheet is deliberately not imitated.
3. Choose **Camera tapped** to review the exact camera handoff boundary. Other
   permission rows remain idle, proving that one explicit action cannot fan out
   into unrelated requests.
4. Choose **Network failed**. Confirm Retry belongs to the network row and does
   not request any system permission.
5. Choose **Required ready**. Network, Camera, and Photos are complete;
   optional Location and Microphone are shown as skipped for this fixture, but
   they do not block **继续** and may remain untouched in the product flow.
6. Select **继续** and confirm the prototype advances to the independent
   TAP-0009 **资源初始化** screen rather than directly entering the Viewfinder.

The prototype records the app-owned state before the action and after iOS
returns. It never draws or claims control over a system permission sheet.

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
