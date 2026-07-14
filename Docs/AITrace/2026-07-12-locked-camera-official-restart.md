# Locked Camera Official Restart Trace

日期：2026-07-12

分支：`codex/locked-camera-official-restart`

基线：`edbd24c`（锁屏 clean-rebuild 实验之前的主 App commit）

阶段：R0、R1、R2A 真机通过；下一阶段 R2B

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

旧 importer/handoff models 在 R0-R2B 期间仍保留 compile-time compatibility，但没有启动入口，也不进入 Capture/Control Extension target。R3 已删除旧执行路径并重写为 update-driven importer。

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
6. 用户确认系统自然回锁屏后再次启动 Extension 仍能一次进入，没有 freeze，也不需要再次侧键锁屏恢复。

### 自动回锁屏的判定

当前把它记录为 system dismissal，不记录为 camera interruption 或黑屏：

- 用户最终看到的是原生锁屏界面；
- R1 没有 `scenePhase`、`stopRunning()`、idle-timer override、主动 dismiss 或 app-open 代码；
- Apple 公开文档描述 Extension 被 dismiss 后由系统 suspend，但没有说明无操作时固定的 secure-capture 常亮时长；
- 当前产品不能把某个固定 idle duration 当作可控制或可承诺的 API 行为。

因此不为延长常亮增加保活逻辑。后续验收只要求：系统 dismissal 必须自然回到锁屏，并且下一次启动仍可一次进入；不能停在 Extension 黑壳、缩小动画或需要再次侧键锁屏才能恢复。用户本轮确认已经满足这项生命周期要求。

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

2026-07-14，用户确认连续执行 10 轮 R1 流程：每轮均一次进入自定义 viewfinder，没有 freeze 或无信息纯黑；hardware capture event 均产生短暂白闪；系统自然 dismissal 后下一次仍可正常进入。

白闪是 R1 的 event-delivery probe，不是曝光或文件保存结果。它证明可见 viewfinder 上的公开 `onCameraCaptureEvent` 收到了完整 `.ended` 事件。R1 没有 `AVCapturePhotoOutput`，因此本阶段预期不生成照片。

R1 最终判定通过，可以进入 R2。当前稳定基线的关键约束继续保留：scene `@State` 长期持有 model、actor 独占 session、preview layer 稳定连接、不监听 `scenePhase`、不主动 stop/teardown、不加入 app-open 或 storage。

## R2A 设计：真实 depth capture，不落盘

### 为什么先拆 R2A

旧 R2 定义同时加入 `AVCapturePhotoOutput`、depth capture、文件编码和 `sessionContentURL` 写入。若下一次启动回归 freeze，将无法区分是 camera graph、photo delegate、文件 I/O 还是系统 session-content 迁移。因此拆分为：

- R2A：只验证 `AVCapturePhotoOutput` + depth capture；
- R2B：R2A 通过后才验证 `sessionContentURL` 原子写入。

### 官方实现依据

- Apple 当前 AVCam 用一个 capture-service actor 长期持有 session 和 photo output，并以一次性 delegate + checked continuation 包装 `capturePhoto(with:delegate:)`；
- Apple `Capturing photos with depth` 要求先把 photo output 接入 session，再启用 output-level depth delivery；每次 request 还要在新 settings 上启用 depth delivery；
- `fileDataRepresentation()` 在 `embedsDepthDataInPhoto` 开启时生成包含 depth auxiliary data 的文件数据；
- R2A 不触碰 `LockedCameraCaptureSession.sessionContentURL`，因此系统复制/migration 不是本轮变量。

参考：

- https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app
- https://developer.apple.com/documentation/avfoundation/capturing-photos-with-depth
- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/sessioncontenturl

### 实现边界

| 层 | R2A 变化 | 明确不做 |
| --- | --- | --- |
| capture actor | 新增唯一 `AVCapturePhotoOutput`、depth capability validation、一次性 delegate retention | 不增加 video-data output，不 stop/teardown session |
| model | 单一 async capture 入口、可见 capture state、短白闪 | 不把 counter 用作 scene/lifecycle gate |
| viewfinder | 最小屏幕快门；hardware event 与快门共用 capture 入口 | 不加 Library/open button、rotation、lens/flash UI |
| data | 读取 HEIC byte count、photo/depth dimensions 后立即丢弃 | 不写文件、manifest、pending queue 或 Photos |
| app | 无变化 | 不启动 importer，不解析 handoff |

关键 marker：`r2a_photo_output_configured`、`r2a_photo_trigger`、`r2a_photo_capture_requested`、`r2a_photo_capture_succeeded`、`r2a_photo_capture_failed`。成功 marker 必须同时包含非零 photo/depth dimensions；白闪本身不再算成功证据。

R2A build number 为 `6`，minimum OS 仍为 iOS 18.6，Control descriptor 和唯一 `CameraCaptureIntent` 不变。

### R2A 提交前验证

- Debug capture-extension simulator build：通过；
- `TAPLockedCameraR2ASourceContractTests`：4/4 通过；
- Release generic-device build（iOS 26.5 SDK）：通过；
- Release 产物核验：主 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `6`，`MinimumOSVersion` 均为 `18.6`；
- Capture/Control Extension 的 `Metadata.appintents` 均只包含 `TAPCamLockedCameraIntent`，没有新增 `OpenIntent`；
- `git diff --check`：通过。

构建期间出现的 `DTDKRemoteDeviceConnection ... device is passcode protected` 来自 Xcode 探测已锁定的连接真机；最终 simulator test 和 generic-device build 均成功，因此它不是本次源码或产物失败。

### R2A 真机结论

2026-07-15，用户按 PRD 中的 R2A 真机验收流程报告“一切正常，符合预期”。R2A 判定通过：屏幕与硬件入口能够完成真实 depth photo capture，连续拍摄和系统自然 dismissal 后的下一次启动未观察到 freeze、纯黑或卡在 `CAPTURING`。

这一结果只证明 camera graph + photo delegate 的稳定性。R2A 没有写 `sessionContentURL`，因此不能据此推断系统 migration、主 App importer 或 Library 可见性已经通过。

## R2B 设计：最小 session content 原子写入

### 官方契约与历史参考

- iOS 26.5 SDK 的公开 interface 表明 `LockedCameraCaptureUIScene` closure 直接提供系统创建的 `LockedCameraCaptureSession`；
- Apple 要求需要跨 Extension 生命周期保留的数据写入当前 `sessionContentURL`，并由系统在 Extension suspend 后复制到 containing app 的 data container；
- Apple 同时说明最新 session directory 在主 App 启动后可能稍晚才可用，因此 R2B 不把“App 首帧即可看见”当成 Extension writer 的职责；
- `lockScreen_test` 的 `SessionContentArtifactWriter` 采用 flat `TAPCam-<UUID>.heic`，证明最小 HEIC artifact 与现有 importer 方向兼容；旧分支的相机选择、packaging 和主动 stop 不进入本次实现。

官方参考：

- https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen
- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/sessioncontenturl
- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/sessioncontentupdates

### 单变量边界

| 层 | R2B 变化 | 明确不做 |
| --- | --- | --- |
| scene | 将当前 session 的 `sessionContentURL` 传给当前 viewfinder | 不缓存 session/URL，不监听 `scenePhase` |
| capture actor | R2A delegate 返回完整 depth HEIC data；拍摄成功后调用独立 writer | 不 stop/teardown，不访问 manager |
| writer | 后台写同目录隐藏 staging 文件，再 rename 为 flat `TAPCam-<UUID>.heic` | 不写 App Group、Photos、network、manifest 或签名 |
| UI | 只有 rename 成功后显示 `SAVED` | 不加 Library/open button |
| app | 无变化 | 不启动 `sessionContentUpdates` consumer 或 importer |

把当前 scene URL 按请求传递是刻意的生命周期约束：如果系统复用 Extension 进程或长期 camera model，下一次 scene 仍使用它自己收到的目录，不会误写到上一次 session。

R2B build number 为 `7`。关键 marker：`r2b_photo_trigger`、`r2b_photo_capture_requested`、`r2b_photo_processed`、`r2b_session_write_begin`、`r2b_session_write_succeeded`、`r2b_session_write_failed`。本阶段只验证 Extension 写入和生命周期稳定性；系统 migration 的 app-side observation 从 R3 开始。

### R2B 提交前验证

- Debug capture-extension simulator build：通过；
- `TAPLockedCameraR2BSourceContractTests`：4/4 通过；
- Release generic-device build（iOS 26.5 SDK）：通过；
- Release 产物核验：主 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `7`，`MinimumOSVersion` 均为 `18.6`；
- Capture/Control Extension 的 `Metadata.appintents` 仍只包含 R0 的 `TAPCamLockedCameraIntent`，没有新增 `OpenIntent`；
- Capture Extension 源码不包含 `openApplication(for:)`、`LockedCameraCaptureManager`、`scenePhase`、`stopRunning()`、`URLSession` 或 App Group 路径；
- `git diff --check`：通过。

首次编译发现顶层 viewfinder 已接收 session URL，但屏幕快门所在的 nested controls 未显式接收该值。已改为 `ViewFinder -> Chrome -> PhotoControls` 的只读值传递；hardware event 和屏幕快门现在都把当前 scene URL 传给同一个 model capture 方法。没有引入全局缓存、environment 单例或 scene lifecycle hook。

R2B 尚未真机验收。构建成功只证明 API、并发边界和 bundle 产物成立，不能代替锁屏下的真实文件保护、系统 suspend 或 relaunch 验证。

### R2B 真机结论

2026-07-15，用户报告行为与 R2B 预期一致。Extension UI 进入 `SAVED`，按当前代码路径意味着 depth HEIC 已完成同目录 staging + rename；主 App 随后记录 `tap_library_present ... managerSessionCount=1`，说明系统已迁移并向 `LockedCameraCaptureManager` 暴露一个 session content directory。

日志解释边界：

- `managerSessionCount=1` 表示一个 session directory，不表示一张照片；
- 所提供日志主要附着于主 App，没有 `r2b_*`，因此不能从该片段逐行还原 Extension callback；
- `nw_endpoint_flow_failed...` 后续 credential assertion 成功，属于主 App 网络路径；
- Fig/FigSandbox 行之后主 App capture、签名、Photos export 均成功，且用户未观察到 freeze/黑屏，因此不作为 R2B lifecycle failure；
- R2B 没有 importer，故该 session directory 此时不进入 Library 是预期行为。

R2B 判定通过。R3 将从新的最小 app-side consumer 开始，不启用旧 importer 中的固定等待、轮询、handoff appearance delay 或把 session count 当照片数的逻辑。

## R3 设计：系统 update 驱动的最小 importer

### 先删除什么

R3 没有修补旧 coordinator。旧执行路径的以下行为全部移除：

- handoff 到达后主动扫描 `sessionContentURLs`；
- 等待 initial update 的 continuation + timeout；
- 500ms fixed interval late polling；
- Library presentation 前阻塞导入；
- `beginDelayingAppearance/endDelayingAppearance`；
- 把 manager directory count 当 capture delivery 状态。

`StartupGateView` 恢复为普通首次启动 gate，不再处理实验性的 locked handoff、URL route 或 neutral waiting UI。R4 需要 app-open 时必须从公开 API 的最小 route 重新加入，不能复活上述导入耦合。

### 新数据流

```text
LockedCameraCaptureManager.sessionContentUpdates
  -> .initial(urls) / .added(url)
  -> scan flat TAPCam-<UUID>.heic
  -> validate HEIC + auxiliary depth
  -> add TAP manifest and proof slot in the main App
  -> idempotent TAPPendingCaptureStore ingest using filename UUID
  -> Library/worker notification
  -> invalidateSessionContent(at:) only when the whole directory succeeded
```

该顺序解决两个独立问题：

1. 系统 migration 的到达时机只由 `sessionContentUpdates` 表达，App 不再猜测 suspend/copy 何时完成；
2. 文件名 UUID 同时作为 pending `captureID`，即使进程在 ingest 后、invalidate 前退出，下一次 `.initial` 也只返回已有 record，不会重复生成照片。

隐藏 `.tmp` 由 scanner 跳过。任何可见但不符合 R2B 命名协议的 entry、HEIC/depth/manifest 打包失败或 pending ingest 失败都会保留 session directory，避免在未确认数据已接管时删除系统副本。空且无异常 entry 的 session 可以清理。

R3 不在 importer 内直接持有 App Attest client，也不等待 signing/export。`ingestLockedCapture` 完成后发 notification，现有 `CameraView` lifecycle worker 按正常异步队列继续处理。

### R3 可观测点

Build number 为 `8`。核心 marker：

- `r3_runtime_start`；
- `r3_session_update kind=initial|added|removed`；
- `r3_import_begin`；
- `r3_scan_finished captureCount=... unexpectedEntryCount=...`；
- `r3_capture_imported` / `r3_capture_import_failed`；
- `r3_session_invalidated` / `r3_session_retained` / `r3_session_invalidate_failed`。

当前 manifest 的 lens identity 使用明确 fallback，因为 R2B flat HEIC 没有保存完整 selection context。这不会改变真实 HEIC auxiliary depth 的读取和签名队列验证；精确 lens context 属于后续产品化阶段，不应与 R3 migration gate 混测。

### R3 本地验证

- `xcodebuild build-for-testing` 针对 `iPhone 17` Simulator 完成，测试源码与 App/Extension targets 编译通过；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下完成；
- 构建产物确认 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `8`，最低系统版本仍为 `18.6`；
- Capture/Control Extension 的 App Intents metadata 仍只有 `TAPCamLockedCameraIntent`，没有重新加入独立 OpenIntent route；
- focused test runner 两次未能在 Simulator 中 materialize/launch，断言没有开始执行，因此不能记为测试通过或测试失败。该阻塞属于本机 Simulator runner 环境，R3 仍需真机 smoke 验收；
- R3 不安装到实机，继续由用户从 Xcode 安装 Release build 并收集完整系统/Extension/App 日志。

### R3 真机结论

2026-07-15，用户确认锁屏拍摄自然结束后，照片可在同一轮主 App Library 中看到。日志提供了两组完整证据：

1. 单张 session：`.added -> captureCount=1 -> pending ingest -> r3_session_invalidated -> .removed -> sign/export success`；
2. 两张 session：`.added -> captureCount=2 -> 两个不同 captureID ingest -> r3_session_invalidated -> .removed`。Library 首次 snapshot 已显示 `visiblePendingCount=2`，随后两张均 export success。

两组均为 `unexpectedEntryCount=0`，没有 `r3_capture_import_failed`、`r3_session_retained`、`r3_session_invalidate_failed`、sign/export failure 或 retry-count 增长。该结果验证：

- 系统 `.added` 足以触发导入，不需要主动轮询；
- pending ingest 完成即允许 Library 可见，不需要等待签名/Photos export；
- 多张照片共享一个 session directory 时会逐文件导入，session count 不能当照片 count；
- invalidate 后系统发出 `.removed`，成功路径完成闭环；
- 日志中的 `managerSessionCount=12` 与本轮实际新增 session/capture 数不一致，再次证明 `sessionContentURLs.count` 不应作为 delivery、照片数量或等待完成的计数器。R3 已不读取该值，仅保留旧 UI 日志中的观测输出。

Fig/FigSandbox 与短暂 Network.framework 行没有对应业务失败，不能解释为本轮 locked-camera lifecycle 问题。R3 核心真机 gate 判定通过；失败 session 保留与下次 `.initial` 幂等重试继续作为鲁棒性用例，不阻塞进入 R4。

## R4：公开 App-open 单变量实现

### 官方依据

- `LockedCameraCaptureSession.openApplication(for:)` 是 Extension 请求打开 containing App 的公开方法；系统在需要时负责认证；
- activity 使用 `NSUserActivityTypeLockedCameraCapture`，App 会收到 continuation callback，可用 `userInfo` 恢复具体 UI；
- Apple WWDC24 明确要求只因用户与 Extension UI 交互而调用该方法；
- Apple 同时说明最新 session directory 可能在 App 启动后稍晚到达，推荐消费 `sessionContentUpdates`。因此 activity 与 `.added` 没有固定顺序，不能通过 wait、poll 或 appearance delay 人为绑定。

参考：

- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/openapplication(for:)
- https://developer.apple.com/documentation/lockedcameracapture/nsuseractivitytypelockedcameracapture
- https://developer.apple.com/videos/play/wwdc2024/10204/?time=1111

### 实现边界

Build number 为 `9`。新增共享 `TAPCamLockedCameraOpenActivity`，只表达 `tapLibrary` destination。Capture Extension 的 `TAPCamLockedCameraOpenControl`：

- 只持有当前 scene 的 `LockedCameraCaptureSession`；
- 不持有 session-content URL、camera model、capture service 或 App-side store；
- tap 后直接构造系统 activity 并 `await session.openApplication(for:)`；
- requesting 时防重复点击；失败后显示 `TRY AGAIN`，不清理或停止任何资源；
- 在非-live fallback 上仍显示。

主 App 的 `LockedCameraOpenActivityRouter` 只验证 destination，保存 `.tapLibrary` route 并发 notification。`StartupGateView` 恢复一个且仅一个系统 activity handler，但没有恢复 R3 删除的 coordinator、wait/poll、neutral screen 或 appearance delay。

R4 顺手移除 `CameraView` 两条旧日志中的 `managerSessionCount`，因为 R3 真机已证明该 directory snapshot 不等于照片数或 delivery 状态；这只是消除误导性观测，不改变 route/importer 行为。

### R4 marker

- Extension tap：`r4_open_tap_received`；
- API 调用前：`r4_open_request_begin`；
- API 正常返回：`r4_open_request_accepted`；
- API 抛错：`r4_open_request_failed domain=... code=...`；
- App continuation：`r4_app_activity_received`；
- App route 发布：`r4_app_route_published`；
- 随后的 route、Library 和 content migration 继续使用 `locked_camera_handoff_apply`、`tap_library_present` 与 `r3_*` marker。

`r4_app_activity_received` 是 App 确实收到 continuation 的权威 marker。Extension 在成功切换时可能先被系统 suspend，故缺少 `r4_open_request_accepted` 本身不能判为 open 失败；若 tap marker 也缺失，才应先检查触控路径。

### R4 本地验证

- 第一次 `build-for-testing` 发现 Open 控件内部枚举名 `State` 遮蔽 SwiftUI `@State` property wrapper；仅改名为 `OpenState` 后重新构建通过。该问题是编译期命名冲突，不是 lifecycle 现象；
- `xcodebuild build-for-testing` 针对 `iPhone 17` Simulator 完成，App、Capture/Control Extension 与 R4 source-contract 测试源码编译通过；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下完成；
- Release 产物中 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `9`；
- Capture Extension 保持 `EXExtensionPointIdentifier=com.apple.securecapture`、`MinimumOSVersion=18.6`；
- Capture Extension `Metadata.appintents/extract.actionsdata` 仍只有 `TAPCamLockedCameraIntent` 与 CameraCapture system protocol，没有生成第二个 action 或 `OpenIntent`；
- Release `.app` 内没有打包 Markdown 文档；
- source scan 确认 Capture Extension 只有一处 `openApplication(for:)`，位于 R4 Open 控件；该控件源码不含 `sessionContentURL`、capture、stop、invalidate 或 sleep；
- CoreSimulator device-list service 本轮未返回可用设备，因此没有声称 focused source-contract 已执行。真机认证、activity continuation、content 到达顺序和下一次 Extension launch 仍由用户从 Xcode 安装 Release build `9` 后验证；
- 构建期间连接真机处于密码锁定状态，Xcode 重复报告 notification-proxy 无法启动，但两个构建命令最终均为 exit 0；未安装或操作设备。
