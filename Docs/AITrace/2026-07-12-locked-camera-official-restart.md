# Locked Camera Official Restart Trace

日期：2026-07-12

分支：`codex/locked-camera-official-restart`

基线：`edbd24c`（锁屏 clean-rebuild 实验之前的主 App commit）

阶段：R0 真机通过；R1 初步真机 smoke 通过，完整循环待验收

## 重启原因

上一条 `codex/locked-camera-clean-rebuild` 实验线在 D1D 引入 shared-package `OpenIntent` 后，锁屏 Control 点击不再到达 SpringBoard `Quick Action`，也没有创建 secure-capture scene 或 Extension PID。D1E 只删除 Capture Extension 的 `AppIntentsPackage` registration，但最终 `.appex` 仍因 package linkage 包含 OpenIntent action metadata；build number 提升后入口仍未恢复。

因此停止继续修改 D1C-D1E。旧分支和 commits 保留作为失败证据，新分支从主 App 基线重建系统入口。

## 官方模板证据

本机 Xcode 26.6 的模板位于：

`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Xcode/Templates/Project Templates/iOS/Application Extension/Capture Extension.xctemplate`

模板只有两个 Swift 文件：

1. `SecureCaptureExtension.swift`：`LockedCameraCaptureUIScene { session in ViewFinder(session: session) }`；
2. `ViewFinder.swift`：`UIImagePickerController`，source type 为 camera，media types 为 image/movie，camera device 为 rear。

R0 直接复刻该结构，没有自定义 capture session 或 transition 逻辑。

## R0 删除的运行路径

Capture Extension target 删除：

- `LockedCaptureCameraController.swift`；
- `LockedCapturePreviewHost.swift`；
- `LockedCaptureRootView.swift`。

同时删除或停用：

- 第二个 Open App Control；
- `TAPCamOpenAppFromLockScreenIntent`；
- URL scheme；
- AppContext publisher；
- 主 App 启动时的 locked importer runtime；
- Capture Extension 内所有 `openApplication`、session-content write、scan、packaging、watchdog、recovery 和 custom UI。

旧 importer/handoff models 仍在 App target 内保留 compile-time compatibility，但 R0 没有启动入口。它们不进入 Capture/Control Extension target，后续 R3 必须删除或重写。

## R0 新增结构

| 文件 | 职责 |
| --- | --- |
| `TAPCamLockedCameraIntent.swift` | 唯一 `CameraCaptureIntent`；默认 `AppContext = Never` |
| `TAPCamLockedCameraControlExtension.swift` | 唯一 Control kind `TAP-NAP.TAPCamDemo.locked-camera.r0` |
| `TAPCamLockedCameraCaptureExtension.swift` | 模板 `LockedCameraCaptureUIScene` |
| `TAPCamLockedCameraViewFinder.swift` | 模板 `UIImagePickerController` camera host |
| `TAPLockedCameraSessionContentTests.swift` | R0 源码边界测试 |

日志 marker：

- `r0_control_widget_init`；
- `r0_camera_capture_intent_perform`；
- `r0_capture_extension_init`；
- `r0_viewfinder_init`；
- `r0_viewfinder_make`。

## 构建与产物证据

通过：

- Release `generic/platform=iOS` build；
- Debug `generic/platform=iOS` build-for-testing；
- automatic-signing Release `generic/platform=iOS` build；
- `git diff --check`。

最终 Release bundle：

- App `CFBundleVersion=4`；
- Capture Extension `CFBundleVersion=4`，minimum iOS 18.6，extension point `com.apple.securecapture`；
- Control Extension `CFBundleVersion=4`，minimum iOS 18.6，extension point `com.apple.widgetkit-extension`。

App Intents metadata：

| Bundle | action keys |
| --- | --- |
| Main App | Main App 自有 intents + `TAPCamLockedCameraIntent` |
| Capture Extension | 仅 `TAPCamLockedCameraIntent` |
| Control Extension | 仅 `TAPCamLockedCameraIntent` |

Capture/Control Extension 没有 `extract.packagedata`，target dependency graph 没有 shared OpenIntent package。

签名检查：

- `codesign --verify --deep --strict` 在系统信任环境中返回 `valid on disk` 和 `satisfies its Designated Requirement`；
- App、Capture Extension、Control Extension 的 TeamIdentifier 均为 `UD3269PSCB`；
- code-sign entitlements 的 application identifiers 分别为 `UD3269PSCB.TAP-NAP.TAPCamDemo`、`UD3269PSCB.TAP-NAP.TAPCamDemo.LockedCapture`、`UD3269PSCB.TAP-NAP.TAPCamDemo.Controls`；
- 三个 provisioning profiles 都包含当前 iPhone 15 Pro UDID `00008130-001A4CEE26D0001C`；
- Capture/Control 使用同一 Xcode-managed wildcard development profile，最终 binary entitlements 已展开为各自 concrete application identifier。当前没有 team、device 或 bundle identifier mismatch 证据。

`TAPCamLockedCameraIntent` metadata：

- system protocol：`CameraCapture`；
- authentication policy：SDK default，`isAuthPolExplicit=false`；
- type-specific metadata 为空；
- 无 AppContext parameter；
- 无 `OpenIntent`。

`openAppWhenRun=true` 是 `CameraCaptureIntent` system protocol 的生成 metadata，不是本项目重新加入的 direct-open intent。

## R0 真机测试流程

1. Xcode 选择 `codex/locked-camera-official-restart` 和 Release；
2. 安装 build `4`，打开主 App 一次；
3. 从锁屏移除旧 TAPCam control；
4. 添加可见名称为 `TAPCam R0` 的新 control；
5. 执行 10 轮：锁屏 -> 单击 control -> 观察 10 秒 -> 侧键/手势退出 -> 再锁屏；
6. 暂不测试 app-open、文件保存或 Library。

## 日志判定表

| 现象 | 必要日志 | 解释 |
| --- | --- | --- |
| Control 点击完全无响应 | 无 Quick Action | Control descriptor/index/dispatch gate |
| Quick Action 有，Extension marker 无 | 无 `r0_capture_extension_init` | ExtensionKit/RunningBoard/scene launch gate |
| Extension init 有，viewfinder marker 无 | 无 `r0_viewfinder_make` | scene content/view construction gate |
| viewfinder make 有，仍不可见 | 系统 camera host/presentation gate | 需要设备统一日志和 sysdiagnose |
| 第一次正常、第二次不分发 | 第二轮无 Quick Action | 上一轮 system transition 未恢复或 descriptor state 异常 |
| 10 轮均正常 | 每轮均有 init/make | R0 通过，进入 R1 |

## 当前不能得出的结论

- R0 没有拍照保存，不能判断 `sessionContentURL` 或 importer；
- R0 没有 `openApplication(for:)`，不能判断 direct-open freeze；
- R0 使用系统 `UIImagePickerController`，不能判断自定义 AVFoundation graph；
- build number 和新 control kind 同时变化，因此若入口恢复，只能证明清理后的 R0 bundle 可用，不能单独证明旧问题是版本缓存还是 OpenIntent metadata。

## R0 真机结果

用户从 Xcode 安装 build `4` 并使用新的 `TAPCam R0` control：

1. 首次点击可以正常进入 Capture Extension；
2. 继续进行锁屏、启动、退出和再次启动，当前未观察到异常；
3. 没有出现缩小动画 freeze；
4. 没有出现进入后的纯黑屏；
5. 没有出现必须再按一次侧键才能恢复下一次启动。

用户未提供精确循环次数，因此 trace 不写成虚假的 `10/10` 计数；按当前重复 smoke 结果，R0 判定通过。

### 结果解释

- 当前设备和 iOS 版本能够正常运行公开 LockedCameraCapture 基线；
- App、Capture Extension、Control Extension 的当前签名和 bundle 组合可用；
- 旧版本“完全无法进入”不是设备永久状态，也不是 LockedCameraCapture 在该设备上普遍不可用；
- R0 一次移除了多个旧变量，不能单独证明根因是 OpenIntent metadata、旧 control cache、自定义 UI，还是它们的组合；
- 后续不得为了寻找历史单一根因而把这些变量重新混入稳定基线。每次只从 R0 增加一个能力。

## 下一步门槛

R0 已通过。R1 minimal custom viewfinder 已完成实现：只替换系统 `UIImagePickerController`，加入长期持有的最小 AVFoundation preview 和公开 capture-event interaction；仍不加入 photo output、session-content write、importer 或 app-open API。

## R1 官方参考

2026-07-12 重新下载并检查 Apple 当前 `AVCam: Building a camera app` sample。该 sample 更新于 2026-05-23，Capture Extension 的关键结构是：

1. Extension scene 用 `@State private var camera = CameraModel()` 长期持有 model；
2. scene content 只渲染 camera view，并在 `.task` 内 `await camera.start()`；
3. `@MainActor @Observable CameraModel` 长期持有 `CaptureService`；
4. `CaptureService` 是 actor，使用 `DispatchSerialQueue` 作为 custom executor，并且只持有一个 `AVCaptureSession`；
5. preview 使用 `AVCaptureVideoPreviewLayer` backing view 和 `PreviewSource`/`PreviewTarget` 边界；
6. SwiftUI view 通过 `onCameraCaptureEvent` 处理硬件 camera capture event；
7. session interruption、interruption ended 和 media-services reset 都在 capture service 内处理。

参考地址：

- https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app
- https://developer.apple.com/documentation/avkit/avcaptureeventinteraction
- https://developer.apple.com/videos/play/wwdc2025/253/

当前工程仍维持 minimum iOS 18.6。iOS 18 的 `onCameraCaptureEvent` 是同步 action；iOS 26 新增 async action 和 default-sound control。R1 使用 iOS 18 已公开的同步入口，避免仅为了诊断 probe 提升 deployment target。

## R1 实现

| 文件 | R1 职责 |
| --- | --- |
| `TAPCamLockedCameraCaptureExtension.swift` | scene 以 `@State` 持有唯一 camera model，并只保留一个 `.task` 启动入口 |
| `TAPCamLockedCameraModel.swift` | `starting/live/interrupted/unavailable` UI 状态、service event 消费、hardware-event 白闪 probe |
| `TAPCamLockedCaptureService.swift` | custom-executor actor、唯一 session、depth-capable rear device、interruption/runtime recovery |
| `TAPCamLockedCameraPreview.swift` | 稳定 preview layer、session connection、window/layer attachment 日志 |
| `TAPCamLockedCameraViewFinder.swift` | 永远存在的 root、preview、可见状态 chrome、公开 `onCameraCaptureEvent` |
| `TAPLockedCameraSessionContentTests.swift` | R1 source boundary，阻止 storage/open/importer/manual teardown 混入 |

R1 build number 为 `5`。Control kind、Control 可见名称和唯一 `CameraCaptureIntent` 保持 R0 不变，确保本轮唯一运行变量是自定义 camera viewfinder。

### 生命周期取舍

R1 不监听 `scenePhase`，不在 `onDisappear` 中 stop session，也不在任何 transition 前主动 teardown camera。这不是遗漏，而是为了保持 Apple scene 模板的系统所有权边界。Extension dismiss/suspend 由系统完成；camera actor 只处理 camera-domain interruption 和 runtime reset。

Model 不设置一次性 `hasStarted` gate。若系统复用 Extension 进程并再次执行 scene `.task`，`start()` 会重新进入 capture actor：session 仍运行时幂等返回，session 已停止时重新 `startRunning()`。这样不会把“model 仍存活”错误等同于“camera session 仍存活”。

Notification observer task 弱持有 capture actor，model 的 event consumer 弱持有 model，避免 observer task 反向永久保活 Extension camera graph。对象释放时日志分别为 `r1_camera_model_deinit`、`r1_capture_service_deinit` 和 `r1_preview_deinit`。

### R1 诊断 marker

- Extension/model：`r1_capture_extension_init`、`r1_camera_model_init`、`r1_camera_model_start_begin`、`r1_camera_model_start_finish`；
- session：`r1_capture_service_init`、`r1_session_configure_begin`、`r1_session_configure_finish`、`r1_session_start_finish`；
- preview：`r1_preview_make`、`r1_preview_session_connected`、`r1_preview_window`；
- event：`r1_capture_event_ended`；
- fault：`r1_session_interrupted`、`r1_session_interruption_ended`、`r1_session_runtime_error`；
- release：`r1_camera_model_deinit`、`r1_capture_service_deinit`、`r1_preview_deinit`。

R1 没有 video-data output，因此没有 first-frame/last-frame timestamp。它只能证明 session running、preview layer 已连接、UI 可见以及系统 interruption。frame-level liveness 需要独立阶段，不在本轮偷偷加入第二个 output。

### R1 明确排除

- `UIImagePickerController`；
- `AVCapturePhotoOutput` 和 `AVCaptureVideoDataOutput`；
- `sessionContentURL` 和任何文件写入；
- `LockedCameraCaptureManager` 和主 App importer；
- `openApplication(for:)`、OpenIntent、URL route；
- AppContext、网络、签名和 pending queue；
- `scenePhase` 驱动的 start/stop；
- UI rotation、zoom、lens selector、flash 和缩略图。

### R1 当前验证

- Capture Extension Debug generic-device compile：通过；
- Debug simulator `build-for-testing`：通过；
- `TAPLockedCameraR1SourceContractTests`：4/4 case 通过；
- unsigned Release generic-device build：通过；
- automatic-signing Release generic-device build：通过；
- `git diff --check`：通过；
- final App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `5`，minimum OS 均为 iOS 18.6；
- Capture/Control `extract.actionsdata` 都只包含 `TAPCamLockedCameraIntent`，没有 `extract.packagedata`；
- `codesign --verify --deep --strict` 在系统信任环境中返回 `valid on disk` 和 `satisfies its Designated Requirement`；
- Capture Extension application identifier 为 `UD3269PSCB.TAP-NAP.TAPCamDemo.LockedCapture`；
- Control Extension application identifier 为 `UD3269PSCB.TAP-NAP.TAPCamDemo.Controls`；
- 真机安装：由用户从 Xcode 执行，Agent 未主动安装。

Simulator 只执行 source-contract test，不作为 camera、secure-capture scene 或 lock-screen transition 的行为证据。

### R1 风险与约束表

| 设计点 | 本阶段做法 | 防止的问题 | 仍需真机回答 |
| --- | --- | --- | --- |
| session ownership | scene `@State` -> model -> actor -> single session；start 可重复、graph 配置幂等 | SwiftUI 重建导致 session/controller 释放，或一次性 gate 阻止第二次启动 | scene 重复进入时是否始终恢复到 live |
| session serialization | `DispatchSerialQueue` custom executor | main-thread blocking、并行 graph mutation | 真机启动耗时和 interruption recovery |
| preview ownership | stable preview-layer backing view | preview host 临时化、layer 脱离 tree | layer connected 后是否持续有真实画面 |
| root fallback | black base + persistent header + explicit status | preview 异常时只剩无信息纯黑 | 黑流发生时 status/chrome 是否仍可见 |
| scene transition | 不监听 `scenePhase`，不主动 stop/teardown | app 自行干预 secure transition，引入下一次 freeze | 系统退出后下一次启动是否继续稳定 |
| hardware input | public `onCameraCaptureEvent`，仅白闪/log | 未安装 capture interaction 被系统判定为无有效相机体验 | hardware event 是否稳定送达且不改变退出行为 |
| depth choice | 只选择有 depth formats 的 rear RGB device，不改 active format | R1 误选无 depth 路径或提前引入 format/zoom 变量 | 当前设备是否选到预期 virtual camera |
| frame diagnosis | 不加 video-data output | 为 watchdog 新增 output，改变 graph 后无法归因 | 当前只能靠可见 preview；逐帧健康需后续单变量实验 |

### R1 真机步骤

1. Xcode 选择当前分支、Release configuration，安装 build `5`；
2. 保留现有 `TAPCam R0` control，不删除/重加；
3. 执行 10 轮“锁屏 -> 单击 control -> 观察 10 秒 -> hardware capture event -> 系统方式退出”；
4. 确认每轮一次进入 `TAPCam R1 / LIVE`，hardware event 有白闪且没有照片；
5. 再执行 5 分钟 live soak；
6. 若异常，记录精确时间与最后一个 R1 marker，不先加入 storage 或 app-open 代码。

## R1 初步真机结果

用户安装 build `5` 后报告：

1. 当前锁屏 Extension 行为正常，可以进入自定义 camera UI；
2. 没有观察到缩小动画 freeze；
3. 没有观察到 Extension 外壳留在前台的无信息纯黑；
4. 无操作一段时间后，secure-capture presentation 会自然结束并回到原生锁屏；
5. 与部分历史实现相比，当前版本不会在无操作时持续常亮数分钟。

### 自动回锁屏的判定

当前把它记录为 system dismissal，不记录为 camera interruption 或黑屏：

- 用户最终看到的是原生锁屏界面；
- R1 没有 `scenePhase`、`stopRunning()`、idle-timer override、主动 dismiss 或 app-open 代码；
- Apple 公开文档描述 Extension 被 dismiss 后由系统 suspend，但没有说明无操作时固定的 secure-capture 常亮时长；
- 当前产品不能把某个固定 idle duration 当作可控制或可承诺的 API 行为。

因此不为延长常亮增加保活逻辑。后续验收只要求：系统 dismissal 必须自然回到锁屏，并且下一次启动仍可一次进入；不能停在 Extension 黑壳、缩小动画或需要再次侧键锁屏才能恢复。

### 本次日志分析

附件：`aa04002a-7e8a-487e-95b0-ed097801508a/pasted-text.txt`

| 日志证据 | 判定 |
| --- | --- |
| 没有任何 `r1_*` / `LockedCameraR1` marker | 这份输出未包含 Capture Extension 的日志流 |
| 没有 `r1_session_interrupted` / `r1_session_runtime_error` | 不能把自动回锁屏归因到 AVFoundation interruption 或 runtime error |
| 没有 model/service/preview deinit marker | 不能从这份日志证明 scene 是 suspend、process termination 还是 presentation dismissal |
| `Protected data is unavailable`，pending worker 停止 | 主 App 正确识别设备处于锁定、受保护数据不可访问状态；与 R1 camera graph 无直接因果关系 |
| 后续 worker reconcile 完成 | 主 App 后续重新获得受保护数据访问；不代表 locked session migration，因为 R1 尚未写 session content |
| `Fig*`、CoreHaptics、AudioSession、Accounts 和 network 输出 | 均出现在主 App camera/credential/Library 时间线；没有伴随 R1 fatal、crash 或 Extension transition marker，不能单独作为 R1 故障证据 |

本次日志不改变代码。若后续重新出现 freeze/黑屏，采集必须包含 process `TAPCamLockedCameraCaptureExtension` 或 subsystem `TAP-NAP.TAPCamDemo` / category `LockedCameraR1*`，并同时保留 SpringBoard、ExtensionKit 和 RunningBoard 时间线。

### 当前 gate

R1 获得一次用户可见 smoke 通过，但尚未收到精确的 10 轮启动计数、hardware event 结果和完整 soak 记录，因此暂不写成最终 R1 acceptance，也不开始 R2 photo output/storage。
