# Focus and Temporary EV Native Camera Comparison

本文档用于对齐 TAPCam 对焦框、临时 EV 条、阻尼和焦点保留策略。结论基于三类证据：

- Apple iPhone User Guide, iOS 26: [Use iPhone camera tools to set up your shot](https://support.apple.com/en-nz/guide/iphone/iph3dc593597/ios) and [Use the Camera Control on iPhone](https://support.apple.com/en-nz/guide/iphone/iph0c397b154/ios).
- 本机 SDK: `/Applications/Xcode.app/.../iPhoneOS26.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVCaptureDevice.h`.
- 当前 TAPCam 源码和测试：`CameraPreviewStageView.swift`, `CameraView.swift`, `CameraViewModel.swift`, `CameraControlService.swift`, `CameraUXPreferences.swift`, `TAPCameraCapturePresentationTests.swift`.

## Decision

TAPCam 的临时 EV 条是对焦框的视觉伴随控件，不应该要求用户按住那根条拖动。目标行为是：

- 用户点按 viewfinder 后出现对焦框和临时 EV 条。
- 临时 EV 条保留在对焦框旁边，作为靠近对焦框的细线和太阳游标位置反馈。
- 对焦框可见时，用户在 viewfinder 内做全局上下滑动即可调整同一份 temporary focus EV。
- EV 调整不重新对焦，不隐藏对焦框，不改变 focus anchor。
- AE/AF Lock 后，对焦框、lock badge、临时 EV 条继续保留；临时 EV 仍可调整，除非后续产品决定锁定态只允许全局 EV。
- 引入阻尼是为了匹配 AVFoundation 曝光生效的可见延迟：手势输入可以即时接收，但 marker 和写入节奏要限速/平滑，避免预览亮度落后时让用户感觉软件卡顿。

## Native Camera Baseline

Apple 的用户文档给出的原生相机语义是：

- iPhone Camera 默认自动设置 focus 和 exposure，并用人脸检测平衡多人曝光。
- 用户点按屏幕移动 focus area。
- focus area 旁边出现曝光调整控件，用户上下拖动调整曝光。
- 长按 focus area 直到出现 `AE/AF Lock` 后，后续拍摄保留手动 focus/exposure；再次点屏幕解锁。
- 另一个独立入口是 Camera Control：支持选择 Exposure 并滑动调整；支持按住 Camera Control 临时锁定 AE/AF，松开即解除。

这里需要区分两层：

- Apple 官方文案说的是“在 focus area 旁边上下拖动曝光控件”，不是底部横向参数条。
- TAPCam 的产品要求进一步扩大 hit region：只要对焦框可见，viewfinder 内全局上下滑动都调整临时 EV。临时 EV 条仍承担视觉反馈，但不再是唯一可拖热区。

## AVFoundation Constraints

AVFoundation 只提供底层相机状态和写入接口，不提供 Apple Camera App 的 UI 状态机。和本设计相关的约束是：

- `focusPointOfInterest` 是归一化坐标，默认中心点；设置它本身不会启动对焦，必须再设置 `focusMode` 才应用。
- `exposurePointOfInterest` 同样是归一化坐标；设置它本身不会启动曝光调整，必须再设置 `exposureMode` 才应用。
- `exposureTargetBias` 单位是 EV；在 continuous auto exposure 或 locked exposure 下影响测光和实际曝光，在 custom exposure 下只影响 metering。
- `setExposureTargetBias(_:completionHandler:)` 的 completion 对应“设置应用到第一帧”的时间戳，因此 preview 亮度变化天然可能晚于手势输入。
- `isAdjustingFocus` 表示设备正在执行自动 focus scan，可用于判断焦点是否稳定。
- `subjectAreaChangeMonitoringEnabled` 触发的是场景/光照/主体变化通知；SDK 说客户端可能希望 refocus、adjust exposure 或 white balance，但不是强制自动重对焦。

## Implemented TAPCam Behavior

当前实现将 tap-to-focus、临时 EV 和 lock 收敛到同一个 Apple-like 用户模型：

- `CameraPreviewStageView.focusGestureLayer` 在 AF 模式下点按 viewfinder，显示 `focusTargetOverlay` 并调用 `onTapFocusPoint(capturePoint)`。
- 长按通过 450 ms 延迟实现；如果起点在现有对焦框内，升级当前目标为 lock；如果在框外，用长按起点重新对焦并 lock。
- `CameraFocusTargetOverlay` 明确区分 `focusing`, `focused`, `locked`。初始 focus scan 不隐藏；`focused` 后再次 `focusStarted` 或 `subjectAreaChanged` 会隐藏；`locked` 忽略这些 runtime 事件。
- `CameraView.focusAtPreviewPoint` 在新 AF tap 时把 temporary focus EV 重置为 0。
- `CameraPreviewStageView.focusExposureScrub()` 只在 focus overlay 可见且 `focusMode == .auto` 时生效。scrub 热区提升到 viewfinder 层，不要求按住对焦框或 EV rail。
- EV scrub 开始后会取消 pending long press，并抑制同一手势尾部的 tap-to-focus，避免调 EV 时重新建立 focus anchor。
- `FocusEVAdjustmentView` 是 display-only：无刻度、无顶部固定太阳、无独立 `DragGesture`；只显示靠近对焦框的细线和移动的 `sun.max.fill` 游标。
- `CameraView.adjustTemporaryFocusEVOffset` 只更新 temporary EV，然后通过 `effectiveAutoExposureBias = globalEVBias + temporaryFocusEVOffset` 写入曝光补偿；这条路径没有调用 `hideFocusTargetOverlay()`。
- `CameraView.finishTemporaryFocusEVAdjustment` 在 scrub 结束时取消 debounce 并立即 flush 最终 effective exposure bias。
- `CameraView.clearFocusSession` 在 UI 回到 `none` 时清空 temporary EV，并在自动曝光路径恢复 continuous auto camera controls；非自动曝光 Pro 路径只恢复 autofocus，避免偷改 ISO/S 用户意图。

实现状态和仍需校准的点：

| Topic | Implemented | Remaining calibration |
| --- | --- | --- |
| 临时 EV 热区 | 对焦框可见时，viewfinder 内全局上下滑动调整 temporary focus EV；rail 只作为视觉反馈。 | 真机确认底部 FOV selector / shutter / toolbar 的手势优先级。 |
| EV 条视觉 | 去掉刻度和顶部固定太阳；只保留靠近对焦框的细线，移动游标是 `sun.max.fill`。 | 真机确认 2pt gap 和太阳尺寸在亮背景下仍可读。 |
| EV 条拖动 | rail 不持有独立 drag；手指落在 rail 上也走同一个 viewfinder-wide scrub。 | 如需 VoiceOver 可调节动作，应单独补 accessibility adjustable action。 |
| 阻尼 | marker 用约 120 ms ease-out 平滑跟随；AV write 对 step 值去重，约 70 ms debounce，松手 flush。 | 真机根据 preview 亮度实际生效延迟微调 80-140 ms 区间。 |
| 对焦框消失 | 没有固定 TTL；runtime invalidation 会隐藏非锁定框；view disappear / MF 会清空 session。 | `focused` 后的短暂 `isAdjustingFocus` 是否需要 250-400 ms grace window，必须真机采样后决定。 |
| EV 是否影响消失 | EV 写入路径不隐藏 overlay，不重新对焦，不改变 focus anchor。 | 无。 |
| Session 清理 | focus session 清空时 temporary EV 回到 0，runtime 回到 continuous baseline 或只恢复 autofocus。 | 镜头切换路径仍需真机确认是否要更早显式触发 clear。 |

## Focus Retention Rules

推荐采用以下状态规则：

1. `none -> focusing(point)`: 用户点按 viewfinder。显示对焦框和临时 EV 条；temporary EV 重置为 0。
2. `focusing(point) -> focused(point)`: runtime `isAdjustingFocus` 回到 false。保留对焦框，不用 TTL 自动消失。
3. `focused(point) -> focusing(newPoint)`: 用户点按新位置。替换 focus anchor，temporary EV 重置为 0。
4. `focused(point) -> focused(point)`: 用户在 viewfinder 内上下滑动 temporary EV。只改 EV，不改 focus anchor。
5. `focused(point) -> none`: subject-area change，镜头/模式切换，进入 MF，view 消失，显式取消，或确认后的 runtime focus invalidation。
6. `locked(point) -> locked(point)`: subject-area change、runtime focus cycle、temporary EV drag 都不取消锁定。
7. `locked(point) -> none`: 用户点屏幕解锁、切模式/镜头、进入 MF、view 消失，或显式取消。

`focused -> none` 是目前最需要真机校准的地方。SDK 的 subject-area notification 是“可能需要重新对焦/曝光”的提示，不代表 UI 必须立刻消失；而 `isAdjustingFocus` 可能因为系统轻微微调而短暂翻转。第一阶段建议：

- 保留 `subjectAreaChanged` 作为强失效信号，但记录真机频率。
- 对 `focused` 后的 `focusStarted` 加 250-400 ms grace window；如果只是短暂抖动并很快 settled，可以保留框；如果持续 scan 或伴随 subject-area change，再隐藏。
- 锁定态继续忽略 subject-area 和 focus cycle。

## Temporary EV Gesture Rules

当前手势模型：

- 只有 focus overlay 可见且 `focusMode == .auto` 时，viewfinder-wide vertical scrub 生效。
- scrub 的起点不需要落在对焦框或 EV rail 上；只要在 preview content area 内，不在底部 FOV selector / shutter / toolbar 上即可。
- 垂直位移映射到 temporary EV，例如继续沿用 `focusExposureScrubPointsPerEV = 96` 的量级。
- 上滑增加 EV，下滑降低 EV，和 Apple Camera 的视觉方向一致。
- 触发时不重新派发 tap focus。drag 开始后应抑制同一手势尾部的 tap-to-focus。
- rail 自身不持有独立 drag 状态。
- drag 结束时清理 scrub start offset，并立即写入最终 bias。

## Damping Rules

阻尼要解决的是 perceived latency，而不是让相机更慢：

- Raw gesture target: 手势每次移动都计算目标 temporary EV，按 step clamp。
- Visual marker: 用低通或 spring 追随 target，避免 marker 比真实预览亮度领先太多。
- AV write: 对实际 `setExposureTargetBias` 做 step-level dedupe 和 70-100 ms throttle；drag end 立即 flush。
- Haptics: 仍以 target EV 的 step 变化触发；0 EV 可更强，整数 EV 可次强。
- Accessibility adjustable action: 不走动画阻尼的完整延迟；每次 increment/decrement 应可预测地到达下一个 step。

当前实现指标：

- marker latency 约 120 ms，不能让用户觉得拖不动。
- AV write 不超过每约 70 ms 一次，且只写 step 变化后的值。
- 松手后最终值立即 flush，不等待上一个 throttle 周期自然结束。

## Implementation Notes

实现集中在 `CameraPreviewStageView` 和 `CameraView`：

- `focusExposureScrub` 在 preview overlay 层作为 viewfinder-wide gesture。
- `FocusEVAdjustmentView.evRail` 不再有独立 `DragGesture`，只做视觉反馈。
- rail 刻度和顶部固定太阳已移除；移动游标使用太阳图标；rail 宽度和 gap 已收紧。
- vertical scrub 和 tap-to-focus 之间用 `shouldSuppressNextTapFocus` 做手势仲裁。
- `onAdjustTemporaryFocusEV` 仍是 Stage 到 CameraView 的唯一调整回调；Stage 不知道 AVFoundation 写入。
- `onFinishTemporaryFocusEVAdjustment` 只表达用户松手，用于 flush 最终 effective exposure bias。

不要在这个改动中扩大 scope：

- 不改 global `Basic EV` 的底部 `ticked adjustment strip`。
- 不引入 ISO/S/MF 专业控制。
- 不改 capture artifact、manifest、Photos metadata 或 pending record。
- 不把临时 EV 写进签名/证明链。

## Acceptance Checklist

- Tap viewfinder shows focus frame and temporary EV rail.
- Drag up/down anywhere inside the preview while the focus frame is visible adjusts temporary EV.
- Dragging temporary EV does not hide the focus frame.
- Dragging temporary EV does not call tap-to-focus again and does not change focus anchor.
- The rail marker visibly follows the value with damping; preview exposure catches up without feeling stalled.
- New tap replaces the focus anchor and resets temporary EV.
- AE/AF Lock keeps the focus frame, lock badge, and temporary EV rail visible through subject-area and focus runtime events.
- Non-locked focus remains visible after settle and is not hidden by a fixed timer.
- Runtime invalidation behavior is tested on device and documented before tightening or relaxing the grace window.
