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

### R4 真机失败证据

2026-07-15，连接设备确认为 iPhone 15 Pro、iOS 26.5.2（23F84）。用户分别执行了无照片和有照片的 direct-open 流程：

| 场景 | `OPEN` 当次结果 | 下一次 Extension | 后续恢复 |
| --- | --- | --- | --- |
| 不拍照 | Face ID 后进入 TAP Library | 停在缩小 transition，用户观察为 freeze | 再次侧键锁屏后可进入 |
| 拍照并 `SAVED` | Face ID 后进入 TAP Library，但没有本次照片 | 同样 freeze | 手动结束两次 Extension presentation 后 `.added` 到达，照片完成导入 |

App 日志给出的严格时序为：

```text
r4_app_activity_received
-> r4_app_route_published
-> locked_camera_handoff_apply destination=tapLibrary
-> tap_library_present
-> tap_library_snapshot_loaded visiblePendingCount=0
...
用户后续手动结束 Extension presentation
...
r3_session_update kind=added
-> r3_scan_finished captureCount=1
-> r3_capture_imported status=pending
-> r3_session_invalidated
-> r3_session_update kind=removed
-> sign/export success
```

由此可以确认：

- `openApplication(for:)` 已成功触发认证和 containing App continuation；
- App route 和 Library presentation 已执行；
- R3 在系统真正发出 `.added` 后立即正常工作，照片没有丢失；
- 不拍照也会引发下一次 freeze，因此文件写入、迁移内容、pending queue、签名和 Photos export 均不是 freeze 的必要条件；
- App 首次出现不是“session content 已迁移”的 barrier。Apple 文档本来也只承诺最新目录可能在 App launch 后稍晚可用。

尚不能仅凭 App 进程日志证明系统内部是哪个 transition 状态未完成，也不能证明主 App 相机一定参与了竞争。本轮 log 开头的主 App camera configure 发生在 activity 之前，但该段也包含用户最初主动打开主 App 的正常启动，因此不能把时间先后误写成因果关系。

外部对照：Apple Developer Forums thread `822735`（Feedback `FB21966835`）在 iOS 26 报告了相同组合：调用 `openApplication(for:)` 后下一次 Extension 假启动，且 `sessionContentUpdates` 往往要等 App 或 Extension 再次打开才到达。该内容是第三方可重复性信号，不是 Apple 工程师确认：

- https://developer.apple.com/forums/thread/822735

本机 iOS 26.5 SDK 公共 `.swiftinterface` 只公开：

- `LockedCameraCaptureSession.openApplication(for:)`；
- `sessionContentURL` / `invalidateSessionContent()`；
- App-side `sessionContentUpdates`、`invalidateSessionContent(at:)` 和 appearance delay pair。

`.tbd` 中存在但 Swift interface 未公开的 transition-completion symbol。按照项目约束，它不用于探索、链接或运行时反射。

R4 判定失败。下一实验命名为 R4B，单变量是主 App landing：activity 直接切换到一个不创建 `CameraView`、不持有主 App camera `AVCaptureSession` 的 TAP Library host。Extension open、capture、session-content storage 和 R3 importer 不变。R4B 若仍 freeze，即可把当前产品所需的 direct-open 组合收敛为 iOS 26.5.2 framework blocker，并转入最小 Feedback 工程与 sysdiagnose；不再尝试 stop/remove graph、sleep/poll、appearance delay 或非公开 API。

## R4B：无 CameraView 的 App landing

### 单变量

R4 的 Extension 代码保持原样：同一个可见按钮、同一个 `NSUserActivityTypeLockedCameraCapture`、同一处公开 `session.openApplication(for:)`。R4B 不改变 capture graph、flat HEIC writer、R3 importer、pending queue 或 signing/export。

唯一行为变化位于 App activity route。旧顺序是：

```text
StartupGateView -> CameraView already hosted
-> activity writes TAPCamIntentHandoff
-> notification reaches CameraView
-> CameraView.pauseForAnalysis()
-> CameraView navigationDestination presents Library
```

R4B 顺序是：

```text
StartupGateView validates activity
-> root switches away from CameraView
-> CameraView onDisappear requests main camera stop
-> root hosts NavigationStack + DepthAlbumPickerView directly
```

`LockedCameraOpenActivityRouter` 现在只校验 activity 并记录 marker，不再写 handoff file 或发 route notification。`StartupGateView` 自己持有 `CameraRouteStore`，因此 Library 的返回按钮仍能恢复普通 CameraView。直接 Library host 不依赖 `.added`，也不宣称系统 migration 已完成。

### 探针

App root：

- `r4b_app_scene_phase`；
- `r4b_app_activity_validated`；
- `r4b_app_direct_library_route`；
- `r4b_app_camera_host_appear|disappear`；
- `r4b_app_library_host_appear|disappear`。

主 App camera：

- `r4b_main_camera_start_begin|finish`；
- `r4b_main_camera_pause_requested`；
- `r4b_main_camera_stop_requested`；
- `r4b_main_session_stop_enqueued|finished`。

Extension root：

- `r4b_extension_root_appear|disappear`。

这些 marker 只建立我们自己的对象/AVCaptureSession 顺序，不能替代 SpringBoard、ExtensionKit、RunningBoard 或 `sessionContentUpdates` 对系统 transition 的证据。

### 判定

先执行无照片流程，因为它已经排除 storage/import/signing：

1. 普通打开 App，确认 `r4b_app_camera_host_appear`；
2. 锁屏进入 Extension，不拍照，点击 `OPEN` 并认证；
3. 确认 App 出现 direct Library marker，且 camera host disappear/stop marker 出现；
4. 再次锁屏并第一次启动 Extension。

若第 4 步仍 freeze，R4B 判失败，主 App CameraView landing 不是必要条件；结合 thread `822735`，下一步是最小 Feedback 工程和 freeze 时刻 sysdiagnose。若不 freeze，再补拍照场景和 10 轮重复测试，确认不是偶然通过。

### 本地验证

2026-07-15 对 R4B build `10` 完成以下验证，未安装到设备：

- `build-for-testing`（generic iOS Simulator、`CODE_SIGNING_ALLOWED=NO`）通过；R4B source-contract tests 已编译，但因当前没有 Booted simulator，未执行测试进程；
- Release generic iOS device build（`CODE_SIGNING_ALLOWED=NO`）通过；
- 最终 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `10`；
- 最终 Capture Extension metadata 为 `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.securecapture`，`MinimumOSVersion = 18.6`；
- source scan 只发现一处 Extension `openApplication(for:)` 调用，且没有使用非公开 transition-completion API；
- App Intents metadata 保留工程原有 `OpenTAPCameraIntent` 与 `TAPCamLockedCameraIntent`，R4B 没有新增第二个 open 入口；
- Release `.app` 内没有打包 Markdown/TXT 实验文档。

设备结论仍由用户从 Xcode 安装 build `10` 后执行上述无照片 smoke 得出；本地构建通过不能代替 secure-capture 生命周期的真机判定。

### R4B 真机结果：失败

2026-07-15，用户在 iPhone 15 Pro、iOS 26.5.2（23F84）上执行无照片流程：打开主 App、锁屏进入 Extension、点击 `OPEN` 并认证进入 App，随后再次锁屏第一次启动 Extension。第二次启动仍停在系统缩小 transition；再次侧键锁屏后才能恢复。

App 日志确认 R4B 的单变量已经生效：

```text
r4_app_activity_received
-> r4b_app_activity_validated routeSideEffects=none
-> r4b_app_direct_library_route cameraHostRequested=false
-> r4b_app_library_host_appear cameraViewCreated=false
-> r4b_main_camera_stop_requested running=false
-> r4b_main_session_stop_finished running=false action=alreadyStopped
-> r4b_app_camera_host_disappear directLibrary=true
```

因此可以继续排除：

- locked activity 校验和 direct route 没有失败；
- R4 的 file-backed handoff 与 notification 不是 freeze 的必要条件；
- direct landing 没有创建新的 `CameraView`；
- 原主 App camera host 退出时，`AVCaptureSession` 已经停止，主相机会话竞争不是必要条件；
- 本轮没有拍照，capture、session-content 写入、R3 ingest、pending signing 和 Photos export 仍不是必要条件。

但日志同时暴露了 R4B 设计文档中的过强假设：R4B 并不是“无 App 工作”的 landing。`DepthAlbumPickerView` 出现后立即执行：

```text
tap_library_load_begin
requestReadWriteAccess
depthAlbumAssets fetched count=784
tap_library_snapshot_loaded itemCount=784
```

CameraView 从 background 恢复到 activity 到达之间还排入了一次 pending-worker/recent-preview 工作。它们未被证明是 freeze 原因，但意味着 R4B 失败后不能直接把 containing App 的所有实现排除，也不能仅凭本轮升级为已确认 framework blocker。先前“R4B 若失败便直接进入 Feedback”的判定过强，现修正为继续做一次减法实验。

日志中的 `Fig`/`FigCaptureSourceRemote` 错误也出现在普通主 App camera 启动和 scene transition 附近；没有与 freeze 边界一一对应，不能单独作为根因证据。当前日志主要来自 App 进程，缺少下一次失败启动时的 ExtensionKit/RunningBoard 边界，因此也不能根据缺少 `r4b_extension_root_appear` 判断 Extension 是否已创建。

R4B 判定失败。下一实验 R4C 仅替换 App activity landing：展示一个静态 SwiftUI host，不创建 `DepthAlbumPickerView`，不访问 PhotoKit，不启动 Library view model，也不从 landing 触发 pending worker。Extension 的公开 `openApplication(for:)`、R3 app-level `sessionContentUpdates` runtime、normal CameraView 和所有签名/导入代码保持不变。

R4C 仍先执行无照片流程。若仍 freeze，Library presentation workload 被排除；此时剩余 App-owned 变量主要是长期运行的 R3 manager stream，以及 activity 到达前 CameraView 对 `.active` 的短暂响应，二者必须继续分别验证，不能合并修改。若 R4C 不 freeze，再逐层恢复 Library 数据加载以找出最小失败边界。

## R4C：静态 App landing

R4C 使用 build `11`。Extension 仍使用 R4/R4B 的同一个 Open 控件、activity 和唯一一处公开 `session.openApplication(for:)`；R3 `LockedCaptureSessionContentImportRuntime` 仍在 App root 启动。

唯一行为变化是 containing App 对 locked activity 的可见落点：

```text
StartupGateView validates activity
-> root removes CameraView
-> root displays static SwiftUI host
```

静态 host 只包含黑色背景、系统 `photo.stack` 图标和 `TAPCam` 文本。它不创建 `NavigationStack`、`DepthAlbumPickerView` 或 Library view model，不读取 PhotoKit，不访问 pending store，也没有自动跳转。它是诊断页面，不是最终 UX；用户不应在本轮检查照片，只检查下一次 Extension 是否第一次启动。

关键 marker：

- `r4c_app_activity_validated ... routeSideEffects=none`；
- `r4c_app_inert_landing_route ... cameraHostRequested=false libraryRequested=false`；
- `r4c_app_inert_host_appear ... cameraViewCreated=false libraryViewCreated=false photoKitRequested=false`；
- `r4c_app_camera_host_disappear`；
- `r4c_main_camera_stop_requested` / `r4c_main_session_stop_finished`；
- `r4c_extension_root_appear` / `r4c_extension_root_disappear`。

本轮日志中不得在 activity 后出现 `tap_library_load_begin`、`requestReadWriteAccess` 或 `depthAlbumAssets fetched`。CameraView 在 activity 之前对 scene `.active` 的响应、以及 app-level `r3_runtime_start` 仍可能存在；它们是后续独立变量，不属于 R4C。

真机流程：

1. 从 Xcode 安装 Release build `11`，普通打开主 App；
2. 锁屏进入 Extension，不拍照；
3. 点击 `OPEN` 并认证，确认只出现静态 TAPCam 页面；
4. 再次锁屏，第一次启动 Extension；
5. 记录是否 freeze，以及上述 marker 和 activity 后是否出现 Library/PhotoKit marker。

通过只表示 Library presentation workload 与 freeze 有关联，需要逐层恢复功能；失败只表示该 workload 不是必要条件，不能跳过后续 R3 stream 与 pre-activity resume 两个独立实验。

### R4C 本地验证

2026-07-15 对 build `11` 完成以下验证，未安装或操作设备：

- shared scheme 仍包含 `TAPCamDemoTests` 与 `TAPCAM_XCTEST_HOST=1`；
- generic iOS Simulator `build-for-testing` 通过，R4C source-contract tests 已编译；当前没有 Booted simulator，因此未执行测试进程；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- 最终 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `11`；
- Capture Extension 最终 metadata 仍为 `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.securecapture`，`MinimumOSVersion = 18.6`；
- Release 二进制包含 `r4c_app_activity_validated`、`r4c_app_inert_landing_route`、`r4c_app_inert_host_appear`、主相机 stop marker 与 Extension root marker；
- source scan 仍只有 `TAPCamLockedCameraOpenControl` 的一处公开 `openApplication(for:)`，没有非公开 transition-completion API；
- Release `.app` 内没有打包 Markdown/TXT 实验文档。

构建期间连接设备处于密码锁定，Xcode 重复报告 notification-proxy 无法启动；两个构建命令最终均为 exit 0。该警告不作为 R4C lifecycle 证据。

### R4C 真机结果：失败，但系统捕获暴露了新的 App 生命周期变量

2026-07-15，用户按无照片路径完成 R4C smoke：Extension 的 Open 可以进入静态 TAPCam landing，但下一次启动 Extension 仍出现 shrink/freeze，需要再次锁屏后才能恢复。因此，R4C 判定失败；Library view、PhotoKit fetch 和 landing 触发的 pending worker 都不是该现象的必要条件。

同轮 App 日志确认 locked activity 到达时：

```text
r4c_app_activity_validated ... routeSideEffects=none
r4c_app_inert_landing_route ... cameraHostRequested=false libraryRequested=false
r4c_app_inert_host_appear cameraViewCreated=false libraryViewCreated=false photoKitRequested=false
r4c_main_session_stop_finished running=false action=alreadyStopped
```

activity 后没有 `tap_library_load_begin`、`requestReadWriteAccess` 或 `depthAlbumAssets fetched`。这完成了 R4C 对 landing workload 的排除，但只说明 App 自己的静态 landing 没有发起这些工作，不能证明 SpringBoard 已完成 secure-capture transition。

另外使用 `idevicesyslog` 捕获了设备级日志：iPhone 15 Pro、iOS 26.5.2（23F84），原始文件 SHA-256 为 `2254a30b1d20f704cdc3d260d8dae8fc808005fddbb3934f266c10b17ce673ae`。该系统捕获必须与上面的 App handoff 日志分开解释：它没有覆盖到一次完整的 `openApplication(for:)` 调用，而是覆盖到随后一次系统边缘下拉/恢复动作。

捕获到的边界是：

```text
SBFluidSwitcherScreenEdgePanGestureRecognizer (DeckGrabberTongue)
-> App scene inactive
-> No capture application found
-> launchCameraCapture: NO
-> isCaptureApplication: YES
-> App scene active
```

在这次动作中，系统没有创建新的 Capture Extension PID、secure-capture scene、ExtensionKit request 或 RunningBoard assertion。因此屏幕上的停滞不是“新 Extension UI 已创建后卡住”。日志还显示 containing App 一直被分类为 `running-active-Visible`，`cameracaptured` 继续把其原始 capture session 识别为 active client，并持续产生 camera frames。

当前实现与该观测相符：`CaptureLifecycleCoordinator.scenePhaseActions` 对 `.inactive` 和 `.background` 返回空动作；主相机只在 `CameraView` 的 `onDisappear` 路径停止。系统遮罩、锁屏和认证 transition 不保证 SwiftUI camera root 从树中消失，因此 `onDisappear` 不能作为 containing App 释放 camera 的唯一生命周期边界。

本次系统捕获还存在一个测试干扰项：Xcode developer-tools assertion 在整个捕获期间保持 active。它不能单独解释 R4C 的重复用户 smoke，因为此前同类安装方式也有通过的 R1-R3 流程；但后续系统级对照应在 Xcode 安装后停止 debugger，并使用独立 device log capture，避免把调试 assertion 与产品行为混合。

## R4D：Containing App camera 跟随 scene 生命周期

R4D 的单变量是 containing App camera ownership。Extension、公开 `openApplication(for:)`、R3 `sessionContentUpdates`、静态 landing、状态栏和 safe-area UI 全部保持 R4C 原样。

实验契约：

1. `CameraView` 所在 scene 离开 `.active` 时，请求停止主 App capture session，并等待 serial session queue 确认 `stopRunning()` 完成；
2. stop 完成日志必须包含 transition ID、scene phase、session identity、调用前后 `isRunning`；
3. scene 回到 `.active` 且 CameraView 仍存在时才允许重新启动 camera；
4. 快速 `.inactive -> .active` 或 `.inactive -> .background -> .active` 必须由 generation/desired-state gate 避免旧 transition 反向覆盖最新状态；
5. R4D 不主动 teardown Capture Extension，也不在 `openApplication(for:)` 前后加入 sleep、poll、文件迁移等待或私有 API。

测试必须拆成两个场景，不能混为一个结论：

- **R4D-L（真实锁屏）**：主 App -> 侧键锁屏 -> 锁屏 Control -> Extension -> Open -> App 静态 landing -> 再次侧键锁屏 -> 第一次启动 Extension；这是 direct-open freeze 的判定路径。
- **R4D-U（已解锁系统遮罩）**：主 App -> 下拉通知/系统遮罩 -> 点击 Control；这是 `CameraCaptureIntent.perform()` 的 containing-App 路径，不用于证明 Locked Capture Extension 是否启动。

R4D-L 通过条件是：主 App 离开 active 后系统日志确认其 camera client 不再 active，并且 Open 返回后连续十轮第一次启动 Extension 都不 freeze。若 camera 已确定释放但仍 freeze，才继续隔离 R3 manager stream 或 App status-bar/safe-area；不得同时修改这些变量。

### R4D 实现：build 12

R4D 已按上述单变量实现，没有修改 Capture Extension、Open 控件、activity、R3 importer、静态 landing 或状态栏布局：

- `CaptureLifecycleCoordinator.scenePhaseActions` 在 `.inactive` 和 `.background` 返回 `.stopCamera`；
- scene callback 同步生成 UUID、递增 generation 并冻结 transition token，异步 Task 只执行该 token；每个 action 前以及异步 camera restart 返回后都再次校验 generation，较旧的 transition 不再继续改 route、刷新 preview 或启动 pending worker，只记录 `r4d_scene_transition_superseded`；
- 录像场景先完成本地 recording finalization/ingest，再释放 session，但 lifecycle stop 不等待签名或网络 worker；
- `CaptureSessionController.stopAndWait()` 把 `stopRunning()` 排入唯一 serial session queue，并在它返回后才恢复 continuation；
- stop snapshot 记录同一个 session identity、`runningBefore`、`runningAfter` 和 `stopped|alreadyStopped`；
- scene 恢复 active 且 camera root 仍存在时，使用当前 lens/FOV selection 重建 session，不强制切回默认镜头；
- 被新 generation 取代的旧 configure completion 只丢弃结果并记录 `r4d_main_camera_stale_config_ignored`，不再向 serial queue 追加一个可能停掉新 session 的过期 stop；
- `CameraView.onChange(scenePhase)` 只保留 UI 状态与 haptic/readiness 行为，不再并行发起第二条录像 stop 路径。

期望的主 App 相机日志顺序：

```text
r4d_scene_transition_received ... phase=inactive|background generation=N
-> r4d_main_camera_scene_stop_begin ... session=0x... running=true|false
-> r4d_main_camera_scene_stop_finish ... same session ... runningAfter=false
```

普通系统遮罩关闭且 CameraView 仍是当前 root 时，可以随后出现：

```text
r4d_scene_transition_received ... phase=active generation=N+1 shouldResumeCamera=true
-> r4d_scene_camera_restart_begin ... running=false
-> r4d_main_camera_scene_restart_path usesExistingSelection=true|false
-> r4d_scene_camera_restart_finish ... running=true current=true
```

Locked activity 已把 root 切到 R4C 静态 landing 后，不应再出现来自旧 CameraView 的 restart marker。连续的 `.inactive -> .background` 可能产生第二个 `alreadyStopped`，这是幂等确认，不是失败。

R4D 对 UI 假设的处理是“保留但后置”，不是排除。主 App 当前确实隐藏 status bar 并占用顶部 safe area；但设备日志已经给出更直接的 camera ownership 证据，代码中也存在对应生命周期缺口。因此 build 12 先只修 camera ownership。若 R4D 日志确认 camera client 已释放而 freeze 仍复现，才把状态栏/Dynamic Island 邻域布局作为后续单变量实验。

### R4D 本地验证

2026-07-15 对 build `12` 完成以下本地检查，未安装或操作设备：

- generic iOS Simulator `build-for-testing` 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- lifecycle policy/source-contract tests 已编译；CoreSimulatorService 当前不可访问，因此未执行测试进程；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- `git diff --check` 通过；
- 最终主 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `12`，`MinimumOSVersion` 均为 `18.6`；
- 最终 Capture Extension metadata 为 `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.securecapture`；
- source scan 仍只有 `TAPCamLockedCameraOpenControl` 中一处公开 `openApplication(for:)`，没有非公开 transition-completion API；
- Release 主 App 二进制包含完整 `r4d_*` stop/restart marker，且 `.app` 中没有 Markdown/TXT 实验文档；
- 真机结论仍必须使用 R4D-L 流程从 Xcode 安装 Release 后取得，不能由本地编译代替。

### R4D 真机结果：camera ownership 被排除

2026-07-15 的 R4D-L 真机 smoke 仍复现 freeze，但设备级日志确认 containing App camera 已在离开 `.active` 时完成同步停止：

```text
r4d_main_camera_scene_stop_begin ... running=true
r4d_main_camera_scene_stop_finish ... runningBefore=true runningAfter=false action=stopped
```

随后 `openApplication(for:)` 的系统动作被 SpringBoard 接收，API 返回 accepted，Capture Extension scene 完成 `Logical Deactivate`，进程进入 `running-suspended-NotVisible`。下一次用户感知到 freeze 时，没有新的 Capture Extension PID、Secure Capture scene、Extension root marker 或 camera configuration。侧键锁屏后，系统才 invalidates/destroys 旧 scene；销毁完成后新的 Capture Extension PID 可以正常启动。

因此需要修正之前“Extension 没有 suspend”的表述：Extension 已 suspend，但 Open 后保留的 Secure Capture scene/session 没有被下一次启动正常复用或替换。R4D 排除了 containing App AVCaptureSession 持续占用作为必要原因，也把 freeze 定位在新 Extension 代码执行之前。

完整设备日志保存在测试机工作目录外的临时捕获 `/tmp/TAPCamDemo-R4D-device-console-20260715-065911+0800.log`，SHA-256 为 `22f5a2bf37fca0d3b5eda19bbd0d1caac5026fe7eb5ceadc0685330df1afcc9d`。该文件可能随系统清理而消失，hash 和关键时序是持久记录。

用户随后再次 smoke 的 App 日志还暴露了一个 containing App 时序窗口：

```text
App active; inertLanding=false; shouldResumeCamera=true
-> locked-camera activity received
-> inertLanding=true
-> previous active transition superseded beforeAction
```

generation gate 在这次运行中阻止了相机真正重启，但完整 `StartupGateView`、Camera root、R3 manager runtime 和其他 App-owned state 仍先于 locked-camera activity 存在。R4D 只能排除相机持续 running，不能排除 containing App 的其余启动/scene 集成。

## R4E：Release containing App 最小静态 host

R4E build `13` 是一次边界级减法实验，不是产品实现。它一次移除 containing App 的业务 runtime，用于快速判断“主 App 实现整体是否参与 freeze”：

- Release 主 App 从进程启动起只创建 `LockedCameraR4EMinimalAppHost`；
- 不创建 `StartupGateView`、`CameraView`、Library 或 depth projection UI；
- 不启动 `LockedCaptureSessionContentImportRuntime`，不访问 `LockedCameraCaptureManager.sessionContentUpdates`；
- 不访问 PhotoKit，不启动 pending/signing worker，不安装自定义 orientation AppDelegate；
- 只使用 `onContinueUserActivity(NSUserActivityTypeLockedCameraCapture)` 接收 activity 并写日志；
- Capture Extension、R4 Open 控件、activity 内容和公开 `openApplication(for:)` 完全不变；
- Debug/test 构建仍保留正常主 App，R4E 只作用于用户手测所用的 Release 构建。

R4E 故意把 manager stream 和其余 App runtime 作为一个边界整体移除。若通过，再逐项恢复以定位具体组件；若失败，就不再在 CameraView、Library、签名或 importer 内继续猜测。

主 App marker：

```text
r4e_minimal_app_host_appear ...
    cameraViewCreated=false
    libraryViewCreated=false
    photoKitRequested=false
    managerStreamStarted=false
    pendingWorkerStarted=false
r4e_minimal_app_activity_received ...
r4e_minimal_app_scene_phase ... sceneCount=N sceneIDs=...
```

R4E-C1 固定流程：

1. Xcode Release 安装并打开主 App，确认只显示 `R4E MINIMAL APP`；
2. 侧键锁屏，从 Lock Screen Control 启动 Capture Extension；
3. 不拍照，点击 Extension 的 Open；
4. 完成认证并回到最小主 App；
5. 再次侧键锁屏，第一次点击 Control 启动 Capture Extension；
6. 记录是否 freeze，以及日志中是否出现新的 Extension PID/root marker。

判定：

- **不再 freeze**：containing App runtime 参与故障；后续从 manager stream 开始逐项恢复，而不是直接恢复全量 App；
- **仍 freeze**：运行时 Camera/Library/import/signing/manager 均被排除，剩余重点转向主 App target/scene 配置、entitlement/signing 以及 iOS 26 Secure Capture transition；
- `UIApplicationSupportsMultipleScenes=true` 在 R4E 中暂时保持不变，所以 R4E 不能排除 scene manifest 配置。若 R4E 仍失败，下一轮应单独对照 single-scene/template-level containing App 配置。

### R4E 本地验证

2026-07-15 对 build `13` 完成以下本地检查，未安装或操作设备：

- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- Debug generic iOS Simulator `build-for-testing` 通过，包含新增 R4E source-contract test；
- `git diff --check` 通过；
- 最终主 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `13`，`MinimumOSVersion` 均为 `18.6`；
- 最终 Capture Extension 仍为 `EXExtensionPointIdentifier = com.apple.securecapture`；
- Release 主 App 二进制包含 `r4e_minimal_app_host_appear`、`r4e_minimal_app_activity_received` 和 `r4e_minimal_app_scene_phase` marker；
- Release 主 App 二进制未找到 `r3_runtime_start` marker；完整业务源码仍属于 target，但 Release root 不创建这些对象；
- 真机必须确认首屏显示 `R4E MINIMAL APP` 后再执行 R4E-C1，不能用旧主 App UI 的日志判定本实验。

### R4E 真机结果：containing App 业务 runtime 被排除

2026-07-15 的 R4E-C1 真机 smoke 仍复现 freeze。主 App 日志只有最小 host marker：

```text
r4e_minimal_app_host_appear ...
    cameraViewCreated=false
    libraryViewCreated=false
    photoKitRequested=false
    managerStreamStarted=false
    pendingWorkerStarted=false
    sceneCount=1
r4e_minimal_app_activity_received count=1
    activityType=NSUserActivityTypeLockedCameraCapture
    sceneCount=1
```

整个流程始终只有同一个 containing App scene persistent identifier。`openApplication(for:)` 的 activity 已成功送达；之后日志只出现 `.inactive` 与 `.active` 往返，用户下一次从锁屏启动 Capture Extension 仍会 freeze。

因此 R4E 排除以下因素是 freeze 的必要条件：

- 主 App `CameraView` 或 `AVCaptureSession`；
- Library、PhotoKit 查询和 depth projection UI；
- `LockedCameraCaptureManager.sessionContentUpdates` importer；
- pending/signing worker、credential preparation 和网络；
- 自定义 orientation AppDelegate；
- 多个 containing App scene 已经同时存在这一运行时现象。

R4E 不能排除 target-level scene 声明。项目仍把 `UIApplicationSupportsMultipleScenes` 声明为 `true`；单一 `sceneCount` 只能证明本次没有同时创建第二个 scene，不能证明多 scene 路由能力声明没有参与系统 handoff 决策。

## R4F：single-scene containing App 配置对照

R4F build `14` 是 R4E 的严格单变量后续实验：

- Release containing App 继续使用完全相同的 `LockedCameraR4EMinimalAppHost`；
- Capture Extension、相机、Open 控件、activity 和 `openApplication(for:)` 均不修改；
- 不恢复 manager、importer、PhotoKit、Library、signing 或主 App 相机；
- 只把 `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes` 从 `true` 改为 `false`；
- 保留 `UISceneConfigurations` 为空字典，避免同时改变 scene 配置结构。

依据：当前 Xcode iOS `UIScene Lifecycle` 模板默认使用 `UIApplicationSupportsMultipleScenes=false`。Apple 对该 key 的定义是：只有 App 确实支持同时运行两个或更多 scene 时才设为 `true`；设为 `false` 时 UIKit 不会为 App 创建一个以上的 scene。TAPCam 当前没有多窗口产品需求，也没有实现多 scene 间共享相机、Library 或队列资源的协调，因此原来的 `true` 本身就是不准确的 capability 声明。

R4F-C1 固定流程与 R4E-C1 相同：

1. Xcode Release 安装 build `14` 并打开最小主 App；
2. 侧键锁屏，从 Lock Screen Control 启动 Capture Extension；
3. 不拍照，点击 Extension 的 Open，认证后进入最小主 App；
4. 再次侧键锁屏，第一次点击 Control 启动 Capture Extension；
5. 记录是否 freeze，以及新的 Extension PID/root marker 是否出现。

判定：

- **不再 freeze**：错误的多 scene capability 声明参与了 Secure Capture handoff；保留 single-scene 配置，再逐步恢复产品主 App runtime；
- **仍 freeze**：排除 containing App runtime 与多 scene 声明，下一步制作与 Xcode Capture Extension 模板同构的 target/config 对照，重点检查 App Intents metadata、entitlement/signing 和 extension embedding，而不是继续修改业务 UI。

### R4F 本地验证

2026-07-15 对 build `14` 完成以下本地检查，未安装或操作设备：

- `TAPCamDemo-Info.plist`、Capture Extension plist 和 Control Extension plist 均通过 `plutil -lint`；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- Debug generic iOS Simulator `build-for-testing` 在 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 下通过，包含 R4F single-scene source-contract；
- `git diff --check` 通过；
- 最终主 App、Capture Extension、Control Extension 的 `CFBundleVersion` 均为 `14`，`MinimumOSVersion` 均为 `18.6`；
- 最终主 App `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes=false`；
- 最终 Capture Extension 仍位于主 App 的 `Extensions/` 目录，metadata 仍为 `EXAppExtensionAttributes.EXExtensionPointIdentifier=com.apple.securecapture`；
- 最终 Control Extension 仍位于主 App 的 `PlugIns/` 目录，extension point 仍为 `com.apple.widgetkit-extension`；
- Capture Extension 和 Open activity 的源码未修改，仍只有一处公开 `openApplication(for:)` 调用；
- 首次 Debug 双架构构建因 `/tmp` 空间耗尽在 `lipo` 阶段失败，不是编译错误；清理本轮临时 DerivedData 后，单一 arm64 架构重跑成功。

### R4F 真机结果：single-scene 声明被排除

2026-07-15 的 R4F-C1 真机 smoke 仍复现 freeze。包含 App 始终只有同一个 scene：

```text
r4e_minimal_app_host_appear ... sceneCount=1 sceneIDs=E5F99BDA-...
r4e_minimal_app_activity_received count=1
    activityType=NSUserActivityTypeLockedCameraCapture
    sceneCount=1 sceneIDs=E5F99BDA-...
r4e_minimal_app_scene_phase phase=inactive sceneCount=1 sceneIDs=E5F99BDA-...
r4e_minimal_app_scene_phase phase=active sceneCount=1 sceneIDs=E5F99BDA-...
```

activity 送达后，用户后续多次锁屏/启动尝试只造成同一个 App scene 在 `.inactive` 与 `.active` 间往返；日志没有出现新的 containing App scene。用户仍在下一次首次 Capture Extension 启动时看到 freeze。

因此 R4F 排除 `UIApplicationSupportsMultipleScenes=true` 是该 freeze 的必要原因。项目保留正确的 single-scene 声明，但后续不再继续修改 containing App runtime 或 scene routing。R4E 与 R4F 合并后的边界是：即使 containing App 是静态空 host、没有相机/Library/import/signing，且 UIKit 被限制为单 scene，公开 Open handoff 后仍能触发下一次 Secure Capture 启动 freeze。

## R4G：Xcode Capture Extension 模板相机 host

R4G build `15` 将实验边界移到 Capture Extension。本轮保持以下内容不变：

- Release containing App 仍是 R4E 最小静态 host；
- `UIApplicationSupportsMultipleScenes=false`；
- Control Widget、`CameraCaptureIntent`、Open activity 内容不变；
- 左下角仍复用同一个 `TAPCamLockedCameraOpenControl`，并仍只有一处公开 `openApplication(for:)`；
- 不增加等待、stop、invalidate、import、PhotoKit、签名或 URL 路由。

唯一行为变量是相机 host：

- Extension root 不再创建 `TAPCamLockedCameraModel`；
- 不启动自定义 `AVCaptureSession`、preview layer、photo output 或 session-content writer；
- 改用当前 Xcode `Capture Extension.xctemplate` 相同的 `UIImagePickerController` 配置：`.camera`、rear camera、image/movie media types；
- `UIImagePickerController` 由系统拥有相机交互和生命周期；Open 控件只作为 SwiftUI overlay；
- 增加 root appear/disappear 和 picker dismantle 探针，但不主动控制 picker 或 camera。

R4G marker：

```text
r4g_capture_extension_init
r4g_template_root_appear
r4g_image_picker_make sourceType=camera
r4_open_tap_received
r4_open_request_begin
r4_open_request_accepted
r4g_template_root_disappear
r4g_image_picker_dismantle
```

R4G-C1 固定流程：

1. Xcode Release 安装 build `15` 并打开 `R4E MINIMAL APP`；
2. 侧键锁屏，第一次启动 Capture Extension；
3. 确认看到系统 `UIImagePickerController` 相机 UI 和左下区域的 Open 控件；
4. 本轮不拍照，直接点击 Open，认证后进入最小主 App；
5. 再次侧键锁屏，第一次点击 Control 启动 Capture Extension；
6. 记录是否 freeze，以及第二次是否出现新的 `r4g_capture_extension_init`、`r4g_template_root_appear` 和 `r4g_image_picker_make`；
7. 同时记录第一次 Open 后是否出现 `r4g_template_root_disappear` 与 `r4g_image_picker_dismantle`。

判定：

- **不再 freeze**：问题位于自定义 Extension 相机/UI runtime 与 Secure Capture Open transition 的交互；后续以官方 picker lifecycle 为基线，逐层恢复自定义 preview 与 capture；
- **仍 freeze，且第一次 picker 已 dismantle**：自定义 Extension 相机 runtime 也被排除；下一步新建与 Xcode 模板同构的干净 target/project，检查 App Intents metadata、entitlement/signing、bundle identity 和 embedding；
- **仍 freeze，且 picker 未 dismantle**：公开 Open 被 accepted 后，系统没有拆除官方模板 camera host；需要结合 SpringBoard/ExtensionKit/RunningBoard 日志判断是 stale Secure Capture scene，还是当前 target 配置阻止 teardown。

R4G 仅验证无拍照的 C1 生命周期。`UIImagePickerController` 的 capture delegate 与 TAP session-content 保存未接入，本轮不能用于评价照片保存或导入；这不是产品实现，也不会替代后续自定义 depth capture。

### R4G 本地验证

2026-07-15 对 build `15` 完成以下本地检查，未安装或操作设备：

- Debug generic iOS Simulator `build-for-testing` 在 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 下通过；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过；
- 最终主 App、Capture Extension 和 Control Extension 的 `CFBundleVersion` 均为 `15`，`MinimumOSVersion` 均为 `18.6`；
- 最终主 App 继续声明 `UIApplicationSupportsMultipleScenes=false`；
- Capture Extension 继续嵌入主 App 的 `Extensions/`，extension point 为 `com.apple.securecapture`；
- Control Extension 继续嵌入主 App 的 `PlugIns/`，extension point 为 `com.apple.widgetkit-extension`；
- Release Capture Extension 二进制包含 `r4g_capture_extension_init`、`r4g_template_root_appear`、`r4g_image_picker_make sourceType=camera`、`r4g_template_root_disappear` 和 `r4g_image_picker_dismantle`；
- active root 源码中只有一处 `openApplication(for:)`，且 Open 路径不包含 capture、session-content、import、PhotoKit、签名、等待或显式 stop；
- 旧自定义相机源码仍属于 Capture Extension target，因此对应类型 metadata 仍可能出现在二进制中，但 active root 不创建这些类型。R4G 验证的是运行时宿主替换，不是 target 文件级清空；若 R4G 仍 freeze，下一轮应使用全新模板 target/project 做文件级与配置级净化；
- 当前没有 Booted Simulator，因此没有执行 `test-without-building`；真机 C1 smoke 仍由用户从 Xcode Release 安装后完成。

### R4G 真机结果：官方 picker host 仍未消除 freeze

2026-07-21 的 R4G-C1 真机 smoke 仍复现相同故障：第一次从 Capture Extension 调用公开 `openApplication(for:)` 可以完成认证并进入最小主 App；再次锁屏后，第一次启动 Capture Extension 仍停在 Lock Screen 缩小动画，侧键重新锁屏后下一次才能进入。

这轮用户提供的 Xcode 控制台片段仍只有 `r4e_minimal_app_*` marker。名称保持 `r4e` 是因为 R4G 只替换 Capture Extension host，containing App 仍复用 R4E 最小 host；它不代表设备运行了旧 build。另一方面，Xcode 当前附着的是主 App 进程，因此没有采集到第一次 Open 后的 `r4g_template_root_disappear`、`r4g_image_picker_dismantle`，也没有采集到 freeze 时是否产生新的 Capture Extension PID。由此只能确认“R4G 行为仍失败”，不能从这份 App-only 日志确认 picker 是否被 dismantle。

R4G 已经证明：把 active Capture Extension root 换成 Xcode 模板式 `UIImagePickerController`，同时保持 containing App 为静态空 host，仍不足以修复 Open 后的下一次启动 freeze。下一步不再继续在 TAPCamDemo target 内删 UI 或业务对象，而是切换到全新 project、target、bundle identity 和 embed graph；这是为了排除历史工程配置、App Intents metadata、签名身份和残留 target membership，而不是尝试另一种产品相机实现。

## 公开 API 与外部同症状记录

截至本轮使用的 iOS 26.5 SDK，`LockedCameraCaptureSession` 的公开 Swift interface 仍只提供以下与当前问题直接相关的 session 操作：

```swift
var sessionContentURL: URL { get }
func openApplication(for userActivity: NSUserActivity) async throws
func invalidateSessionContent() async throws
```

`LockedCameraCaptureManager` 公开提供 `sessionContentURLs`、`sessionContentUpdates`、`invalidateSessionContent(at:)`，以及用于控制 containing App 内容出现时机的 `beginDelayingAppearance()` / `endDelayingAppearance()`。SDK 没有公开的“先结束 Secure Capture scene，再打开主 App”、主动 dismiss Extension 或强制完成 handoff transition API。因此 R5 不调用私有符号，也不人为拼装 teardown 顺序。

Apple Developer Forums 的用户帖子 [`LockedCameraCaptureManager` practically unusable since iOS 26](https://developer.apple.com/forums/thread/822735) 描述了与 TAPCam 相同的序列：`openApplication(for:)` 后，再次从锁屏启动只发生 zoom-out、Extension 不出现，同时 `sessionContentUpdates` 延迟或不稳定；帖子提供的 Feedback 编号为 `FB21966835`。这是独立开发者提供的同症状证据，不是 Apple 工程师确认、系统缺陷定论或修复承诺。官方支持路径仍是 [`Creating a camera experience for the Lock Screen`](https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen) 中公开的 `openApplication(for:)`。

## 工程结构与显示名称审计

Xcode 的 “Rename Embed App Extensions to Embed Foundation Extensions” 推荐项只是给传统 `.appex` copy phase 改名，以便和 ExtensionKit extension 的 embed phase 区分。当前 TAPCamDemo 以及 R5 的实际产品结构都是：

- Control Widget 是 Foundation/App Extension，嵌入主 App 的 `PlugIns/`；
- Locked Camera Capture Extension 是 ExtensionKit extension，嵌入主 App 的 `Extensions/`；
- 两类 extension 没有被放进同一个 copy phase。

因此推荐重命名本身不会修复 Secure Capture 生命周期。R5 直接采用 `Embed Foundation Extensions` 和 `Embed ExtensionKit Extensions` 两个明确命名，消除命名噪声。

安装后显示 `TAPCam`，而 project/target 名和 bundle identifier 含 `TAPCamDemo`，也是正常且彼此独立的配置：用户可见名称来自最终 App 的 `CFBundleDisplayName`；系统识别 containing App、Control 和 Capture Extension 使用各自的 bundle identifier、签名和 embedding 关系。R5 故意同时使用全新的显示名称与 bundle identity，便于在设备上和 TAPCam 产品包严格区分。

## R5：全新 project 与 bundle identity 的最小 Open 复现

R5 位于 `Experiments/LockedCameraOpenRepro/LockedCameraOpenRepro.xcodeproj`，是独立可安装的诊断 App，不引用 TAPCamDemo target 或产品源码。它使用以下新身份：

- App display name：`TAPCam LCC Repro`；
- App bundle ID：`TAP-NAP.TAPCam.LockedCameraOpenRepro`；
- Capture bundle ID：`TAP-NAP.TAPCam.LockedCameraOpenRepro.Capture`；
- Control bundle ID：`TAP-NAP.TAPCam.LockedCameraOpenRepro.Controls`；
- Control kind：`TAP-NAP.TAPCam.LockedCameraOpenRepro.control`。

R5 的 containing App 只负责首次请求 Camera authorization、显示当前授权状态、接收 `NSUserActivityTypeLockedCameraCapture` 并记录 scene phase。它不创建相机、不读取 session content、不启动 manager stream、PhotoKit、Library、App Attest、签名、网络、pending queue、App Group 或自定义导航。

Capture Extension 使用 Xcode 模板式 `UIImagePickerController(.camera)` 作为可见 viewfinder。左下角 Open 的唯一行为是创建无 `title`、无 `userInfo` 的 `NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)`，然后直接调用一次：

```swift
try await session.openApplication(for: activity)
```

它不拍摄或保存内容，不等待 importer，不 stop/dismantle picker，不 invalidate session content，不延迟，不重试。Control、Capture 和 App 三个 target 共享同一个最小 `CameraCaptureIntent` 定义，避免产品工程中的 intent 变体或 metadata 参与实验。

### R5 marker

所有进程使用 subsystem `TAP-NAP.TAPCam.LockedCameraOpenRepro`，并在 marker 中携带 PID：

```text
lccr5_intent_perform
lccr5_capture_extension_init
lccr5_capture_root_appear
lccr5_picker_make
lccr5_open_tap
lccr5_open_begin
lccr5_open_accepted | lccr5_open_failed
lccr5_capture_root_disappear
lccr5_picker_dismantle
lccr5_app_init
lccr5_app_host_appear
lccr5_app_scene_phase
lccr5_app_activity_received
```

必须从 Console 按 subsystem 跨进程采集；只看 Xcode 主 App console 会再次丢失 Capture Extension 的 init/disappear/dismantle 证据。

### R5-C0：不 Open 的生命周期基线

1. 首次打开 `TAPCam LCC Repro`，完成 Camera authorization，并添加名为 `LCC Repro` 的 Lock Screen Control；
2. 锁屏启动 `LCC Repro`，确认系统 camera UI 与左下角 Open 可见；
3. 不点击 Open，直接侧键锁屏结束；
4. 重复五次。

每次都应产生新的 Capture Extension PID/init/root/picker marker 且不 freeze。C0 失败意味着新工程本身的签名、Control-to-Capture 绑定或 Secure Capture 配置不成立，此时不能进入 C1。

### R5-C1：裸 `openApplication(for:)`

1. 从 Lock Screen 启动 `LCC Repro`，不拍照；
2. 点击 Open 并认证，确认进入 `TAPCam LCC Repro` 且 handoff count 增加；
3. 再次侧键锁屏；
4. 只点击一次 `LCC Repro`，记录是否在 zoom-out transition freeze；
5. 若 freeze，侧键锁屏一次后再启动一次，并保存同一时间窗的 subsystem、SpringBoard、ExtensionKit 和 RunningBoard 日志。

判定：

- **R5-C0 与 C1 都通过**：问题来自 TAPCamDemo 历史 project/target/signing/metadata 集成；以 R5 project graph 为规范，逐项迁入产品能力；
- **C0 通过、C1 freeze**：全新 bundle identity、干净 embedding、模板 picker、空 containing App 和裸 activity 下仍复现；这将大幅支持 iOS 26 Secure Capture/Open transition 缺陷假设，应把 R5 作为 Feedback 的最小工程；
- **C0 失败**：先审计 Xcode 实际签名产物、embedded provisioning profiles、entitlements、App Intents metadata 和设备上是否点中了 `LCC Repro` Control，不讨论 Open 生命周期。

### R5 本地验证

2026-07-21 已完成以下不安装设备的验证：

- Xcode 能解析独立 project、三个 target 和共享 scheme；
- 三个 source plist 均通过 `plutil -lint`；
- Debug generic iOS Simulator build 通过；
- Release generic iOS device build 在 `CODE_SIGNING_ALLOWED=NO` 下通过且无 warning；
- 最终 App 的 `CFBundleDisplayName=TAPCam LCC Repro`、minimum OS 为 iOS 18.6、device family 为 iPhone；
- Capture Extension 位于 `Extensions/` 且 extension point 为 `com.apple.securecapture`；
- Control Extension 位于 `PlugIns/` 且 extension point 为 `com.apple.widgetkit-extension`；
- 三个 target 的最终产物都包含 App Intents metadata；
- Release Capture Extension 二进制包含全部 `lccr5_*` lifecycle marker，不包含 manager/session-content/PhotoKit/URLSession 路径；
- App 和 Extension 的 source membership 只包含 R5 目录中的最小文件，没有链接 TAPCamDemo 产品源码。

尚未执行自动签名或真机安装。用户将从 Xcode 手动安装，以保留其正常 Release 日志流程；安装后还需要检查实际签名的 `.app`、两个 embedded `.appex` 的 provisioning profile 与 entitlements，再执行 R5-C0/C1。
