# Locked Camera Capture POC PRD v3

状态：R0、R1、R2A、R2B 真机通过；下一阶段为 R3 主 App importer

本 PRD 是 `codex/locked-camera-official-restart` 的实现契约。旧分支、旧 PRD、实验日志和历史代码只用于说明曾经观察到的现象，不再定义当前实现。

## 依据优先级

1. 当前 Xcode 26.6 内置的 Capture Extension template；
2. Apple `Creating a camera experience for the Lock Screen` 文档；
3. 当前 iOS 26.5 SDK 的公开 Swift interface；
4. 本 PRD；
5. 历史实验和第三方实现，仅作风险提示。

官方参考：

- https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen
- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession
- https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturemanager/sessioncontentupdates
- https://developer.apple.com/documentation/appintents/cameracaptureintent
- https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app
- https://developer.apple.com/documentation/avkit/avcaptureeventinteraction

## 为什么重新开始

旧实现一次引入了自定义相机 graph、AppContext、文件打包、session-content importer、轮询/waiter、多个 app-open 入口、handoff route 和 UI recovery。变量相互耦合，导致观察到 freeze、延迟导入或黑屏时无法证明根因。

D1D/D1E 又把共享 `OpenIntent` package metadata 加入 Capture Extension。真机随后连 Control 的 `Quick Action` 都不再分发，Extension 进程没有启动。D1E 删除注册文件后，依赖扫描仍将 OpenIntent 写入 `.appex` metadata，因此不是有效隔离。

当前策略不是继续修补旧实现，而是从系统入口开始逐层增加能力。每一阶段只有上一阶段真机通过后才能开始。

## 最终产品目标

1. 用户在锁屏通过 Control Center、Lock Screen control 或 Action button 启动 TAPCam；
2. Extension 立即展示自定义、持续可用的 depth camera viewfinder；
3. 用户无需解锁即可拍摄一张或多张 depth photo；
4. 内容先写入 `LockedCameraCaptureSession.sessionContentURL`；
5. 主 App 通过 `LockedCameraCaptureManager.sessionContentUpdates` 导入同一个 pending queue；
6. 签名、网络和 Photos export 继续由主 App 异步处理，不阻塞锁屏拍摄；
7. 用户明确点击左下角入口时，通过公开 API 认证并打开主 App；
8. 任何 interruption、断流或不可恢复状态都保持可见 UI，不出现无信息纯黑屏。

最终目标不等于当前 R0 的验收范围。

## R0：系统入口基线

R0 只回答一个问题：在没有 TAPCam 拍摄、传输和 handoff 业务代码时，系统能否重复、稳定地启动 Capture Extension。

### R0 包含

- 一个 `CameraCaptureIntent`，同一源文件加入 App、Control Extension 和 Capture Extension；
- Intent 使用 SDK 默认 `AppContext = Never` 和默认 authentication policy；
- 一个新的 Control kind：`TAP-NAP.TAPCamDemo.locked-camera.r0`；
- Control 的可见名称为 `TAPCam R0`，用于避免误点旧缓存组件；
- `LockedCameraCaptureUIScene`；
- 本机 Xcode template 的 `UIImagePickerController` viewfinder；
- rear camera，media types 为 image 和 movie；
- 三个只读 OSLog marker：`r0_control_widget_init`、`r0_capture_extension_init`、`r0_viewfinder_make`；
- App、Capture Extension 和 Control Extension 使用 build number `4`。

### R0 不包含

- `OpenIntent`、`AppIntentsPackage` 或其他 app-open AppIntent；
- `LockedCameraCaptureSession.openApplication(for:)`；
- URL scheme 或 `NSExtensionContext.openURL`；
- 自定义 `AVCaptureSession`、preview layer、watchdog 或状态机；
- shutter persistence、depth photo、manifest、proof slot 或文件打包；
- `sessionContentURL` 写入；
- AppContext 发布或读取；
- 主 App locked importer runtime、polling、waiter 或 appearance delay；
- Library route、pending queue、签名、网络或 Photos export；
- 左下角占位符和自定义相机 UI。

旧 importer/handoff 类型暂时只作为主 App compile-time compatibility 留在源码中。R0 已移除它们的启动入口，真机测试期间不执行。进入 R3 前必须删除或按新契约重写，不能默认复用旧流程。

## R0 产物契约

Release 构建产物必须满足：

| Bundle | App Intents metadata |
| --- | --- |
| Main App | 可以包含主 App 自有 intents；必须包含 `TAPCamLockedCameraIntent` |
| Capture Extension | 只能包含 `TAPCamLockedCameraIntent` |
| Control Extension | 只能包含 `TAPCamLockedCameraIntent` |

Capture/Control Extension 不得包含 `OpenIntent`、shared intent package marker 或额外 package dependency。

Capture Extension 的 Swift source 只能包含模板 scene、template viewfinder 和共享 CameraCaptureIntent。R0 不允许通过把旧文件留在 target 但“不调用”来规避该边界。

## R0 真机验收

安装前：

1. 从 Xcode 选择当前分支和 Release configuration；
2. 安装 build `4`，打开主 App 一次并确认 camera authorization 已完成；
3. 从锁屏编辑界面移除旧 TAPCam control；
4. 新增显示名为 `TAPCam R0` 的 control。

基础循环执行 10 次：

1. 锁屏；
2. 只点击一次 `TAPCam R0`；
3. 确认一次进入 camera UI，不停在缩小动画；
4. 保持 viewfinder 可见至少 10 秒；
5. 使用侧键或系统手势退出；
6. 立即开始下一轮。

通过条件：

- 10/10 次点击均进入 Extension；
- 没有需要“再锁一次才恢复”的 freeze；
- 没有进入后纯黑；
- 日志中每次有效启动都能看到 Extension init 和 viewfinder make；
- 退出后下一次不复用未完成 transition。

R0 不验证拍照文件。`UIImagePickerController` 出现快门不代表照片已经进入 TAPCam storage。

### R0 真机结果

用户从 Xcode 安装 build `4`，使用新的 `TAPCam R0` control 后，Extension 可以正常进入。随后继续执行锁屏、启动、退出和再次启动，当前未观察到缩小动画 freeze、纯黑屏或必须再次锁屏才能恢复的现象。

该结果将 R0 判定为通过，可以进入 R1。由于 R0 同时使用了新的 build number、新 control kind、清理后的单一 CameraCaptureIntent metadata 和 Xcode template viewfinder，不能据此把旧入口失败归因到其中某一个单独变量。能够确认的是：当前设备、签名和公开 LockedCameraCapture 基础入口在最小实现下可用。

## R0 故障归因

| 最后一个证据 | 故障边界 | 下一步 |
| --- | --- | --- |
| 没有 `Quick Action Will fire` | SpringBoard/Control descriptor/index 尚未分发 | 检查 control kind、installed metadata、签名、Control 缓存；不改相机代码 |
| 有 Quick Action，没有 `r0_capture_extension_init` | secure-capture scene/Extension launch | 检查 ExtensionKit、RunningBoard、embedded appex、entitlements |
| 有 Extension init，没有 `r0_viewfinder_make` | scene content 或 SwiftUI/representable construction | 对照 Xcode template 和 scene logs |
| 有 viewfinder make，但 UI 不可见 | `UIImagePickerController` presentation/system camera host | 抓 SpringBoard/ExtensionKit/camera logs 和 sysdiagnose |
| 首次正常，退出后下一次无 Quick Action | 上一轮 system transition 或 Control registration 状态 | 记录两轮完整系统时间线，不加入业务代码 |
| R0 连续通过 | 系统入口基线成立 | 进入 R1 |

## 后续阶段

### R1：最小自定义 live camera

- Capture Extension scene 以 `@State` 长期持有一个 `@Observable` camera model，和 Apple 当前 AVCam Capture Extension 示例一致；
- scene `.task` 每次激活都可以重新请求 `start()`；不使用一次性 `hasStarted` gate，capture actor 在 session 已运行时幂等返回、已停止时重新启动；
- camera model 长期持有一个 capture service；capture service 是使用 `DispatchSerialQueue` 自定义 executor 的 actor；
- `AVCaptureSession` 只在 capture service 内创建一次，所有配置、启动和恢复都在同一个串行 executor 上执行；
- preview 使用稳定的 `AVCaptureVideoPreviewLayer` backing view，通过 `PreviewSource`/`PreviewTarget` 边界连接 session，不在 SwiftUI `body` 中创建 session；
- 只选择至少存在一个 `supportedDepthDataFormats` 的 rear RGB camera device，不主动修改 active format、zoom 或方向；
- 公开硬件拍摄入口使用 SwiftUI `onCameraCaptureEvent`，这是 `AVCaptureEventInteraction` 的 SwiftUI 接口；
- R1 收到 `.ended` 事件时只显示 90 ms 白闪并记录日志，用于证明事件被处理，不生成或保存照片；
- root 永远保留黑色基底、preview 和可见 chrome，状态限定为 `starting/live/interrupted/unavailable`；
- 监听 `wasInterrupted`、`interruptionEnded` 和 `runtimeError`；interruption ended 与 media-services reset 在同一 capture actor 内恢复 session；
- 不监听 `scenePhase`，不在 view disappear 时调用 `stopRunning()`，不在系统 transition 前手动 teardown。scene 的退出和 suspend 交给 Locked Camera Capture 系统管理；
- 不添加 photo/video data output、文件存储、importer、AppContext 或 app-open API；
- 不实现 UI rotation 或方向切换。

R1 使用 build number `5`。Control kind 和可见名称仍保持 R0 的 `TAP-NAP.TAPCamDemo.locked-camera.r0` / `TAPCam R0`，因为本阶段只允许替换 viewfinder；不能通过同时换 Control descriptor 掩盖自定义 camera graph 的问题。

R1 没有 `AVCaptureVideoDataOutput`，所以没有逐帧 callback，也不能记录 first/last frame timestamp。当前证据边界是 `startRunning/isRunning`、preview-layer attachment、可见画面和系统 notification。若 session 报告 live 但画面停止，顶部 `TAPCam R1 / LIVE` chrome 仍保持可见，用户不会只看到无信息纯黑；frame-level watchdog 必须作为后续独立实验评估，不能混进本阶段。

#### R1 真机验收

安装 build `5` 后继续使用现有 `TAPCam R0` control，不删除或重新添加 control。

基础循环执行 10 次：

1. 锁屏后只点击一次 control；
2. 确认直接进入带 `TAPCam R1` chrome 的自定义 viewfinder；
3. 确认状态从 `STARTING` 进入 `LIVE`，预览持续可见至少 10 秒；
4. 每轮触发一次系统支持的 camera capture hardware event，确认出现短暂白闪；
5. 使用侧键或系统手势退出；
6. 立即开始下一轮。

随后执行一次 5 分钟 live soak：保持 Extension 前台，在系统允许的时间内观察 preview；如果系统按自身锁屏策略自然 dismiss，记录为 system dismissal，不把它误报为黑屏。

通过条件：

- 10/10 次均一次进入，不停在锁屏缩小动画；
- 没有需要再次侧键锁屏才能恢复的 freeze；
- 每次进入都能从 `STARTING` 到 `LIVE` 并看到真实 camera preview；
- preview 异常时仍能看到状态 chrome/fallback，不出现无信息纯黑；
- hardware event 每次只产生白闪和 `r1_capture_event_ended`，不会产生照片；
- soak 期间没有卡死、无 UI 黑屏或不可恢复 interruption；
- 日志能把 session interruption/runtime error 与 preview attachment 分开定位。

#### R1 初步真机结果

用户从 Xcode 安装 build `5` 后确认当前行为正常：可以进入自定义锁屏 camera UI，没有观察到 freeze 或无信息纯黑。无操作一段时间后，系统会结束当前 secure-capture presentation 并回到原生锁屏界面；它不再像部分历史实现那样持续常亮数分钟。

用户随后确认：每次系统自然回到原生锁屏后，再次点击 Control 都可以正常进入 Extension，没有出现 freeze，也不需要再次按侧键锁屏恢复。该结果通过了 R1 最关键的“上一轮 system dismissal 不污染下一轮 launch”生命周期 gate。

该现象当前归类为可接受的 system dismissal，而不是黑屏故障，依据是最终可见状态为原生锁屏，而不是 Extension 外壳仍占前台但内容变黑。R1 源码没有 `UIApplication.isIdleTimerDisabled`、`scenePhase`、`stopRunning()`、主动 dismiss 或 app-open 路径，因此没有证据表明 TAPCam 主动改变了系统 idle timeout。

Apple 文档说明 capture extension 被 dismiss 后由系统 suspend，并要求 Extension 在活动期间保持有效 camera view；文档没有说明无操作时的固定常亮时长，也没有提供让 Extension 控制 secure-capture idle timeout 的公开契约。本次“自动回到原生锁屏”因此只能结合可见行为推断为 system-owned presentation policy，而不能从公开 API 证明具体 timeout 原因。因此：

- 不把“必须常亮数分钟”设为验收要求；
- 不为了延长常亮时间加入 idle-timer hack 或生命周期保活；
- 系统自然回锁屏本身不是失败；
- 只有停在缩小动画、Extension UI freeze、无信息纯黑，或下一次无法一次进入，才判定为生命周期失败。

用户提供的本次日志主要来自主 App，没有 `r1_*`、`LockedCameraR1`、Extension process、session interruption/runtime error 或 deinit marker。因此日志不能证明 Extension 的精确 suspend/terminate 时间线；R1 的验收依据是用户可见行为和定量循环。

#### R1 最终真机结果

2026-07-14，用户完成连续 10 轮锁屏启动、hardware capture event 和退出循环：

- 10/10 次均一次进入自定义 viewfinder；
- 没有 freeze、无信息纯黑或需要再次按侧键恢复；
- hardware capture event 每轮均触发短暂白闪；
- 白闪只证明公开 capture-event interaction 收到 `.ended` 事件，R1 不包含 `AVCapturePhotoOutput`，因此不会生成照片；
- Extension 由系统自然结束并回到原生锁屏后，下一轮仍可一次进入。

R1 判定通过。后续阶段必须保留这一生命周期结构，不加入 `scenePhase` teardown、主动 stop/dismiss 或把 app-open 与 camera cleanup 绑定。

### R2A：真实 depth photo capture，不落盘

- 在 R1 的唯一 capture actor 内加入一个长期持有的 `AVCapturePhotoOutput`；
- output 接入 session 后检查并启用 `isDepthDataDeliveryEnabled`；
- 每次拍摄创建新的 HEVC `AVCapturePhotoSettings`，请求并嵌入 filtered depth；
- 屏幕快门和 hardware capture event 只调用同一个 async capture 方法；
- delegate 必须同时取得 `fileDataRepresentation()` 和非空 `depthData` 才报告成功；
- R2A 只在内存中读取 byte count、photo dimensions 和 depth dimensions，随后丢弃数据；
- 不取得 `LockedCameraCaptureSession`，不写 `sessionContentURL`，不启动 importer，不打开主 App；
- 不修改 R1 的 scene/session 生命周期结构，也不加入主动 stop/teardown。

R2A 使用 build `6`，Control kind/name 继续保持 R0 baseline。它只回答“增加真实 photo/depth capture graph 后，锁屏 Extension 是否仍稳定”，不回答内容迁移或 Library 可见性。

#### R2A 真机验收

1. 从 Xcode 安装 Release build `6`，保留现有 `TAPCam R0` control；
2. 连续 10 轮执行“锁屏 -> 一次进入 Extension -> 屏幕快门拍一张 -> hardware event 再拍一张 -> 系统方式退出”；
3. 每次成功后确认底部状态显示非零 depth dimensions；
4. 另在同一次 Extension 会话连续拍摄 5 张，确认每次从 `CAPTURING` 回到 `DEPTH ...`；
5. 最后一轮等待系统自然回锁屏，再确认下一次仍可一次进入。

通过条件：所有请求都有 depth 成功结果；preview 在拍摄前后持续可见；没有 freeze、无信息纯黑、卡在 `CAPTURING` 或需要再次侧键恢复。主 App Library 没有这些照片是 R2A 的预期行为。

真机结论（2026-07-15）：用户按上述验收流程报告行为全部正常并符合预期。R2A 判定通过；真实 photo/depth capture graph 没有破坏 R1 的启动、拍摄、系统 dismissal 或下一次启动生命周期。

### R2B：session content 原子写入

- 将 `LockedCameraCaptureUIScene` 当前提供的 `session.sessionContentURL` 按拍摄请求传入，不把 URL 缓存在长期 camera actor 中；
- 把 R2A 已生成的完整 depth HEIC 写入当前 `sessionContentURL`；
- 每张照片先写同目录临时文件，再原子 rename 成最终 flat artifact；
- 最终文件名为 `TAPCam-<UUID>.heic`，临时文件为隐藏 `.tmp`，后续 importer 只识别最终 HEIC；
- Extension 只保存本地 unsigned transfer artifact；
- 不在 Extension 中签名、联网、访问 App Group 或等待主 App；
- capture/storage 与 app-open 完全解耦。

R2B 使用 build `7`，选择“最小 flat depth HEIC”作为唯一 artifact，不写 metadata、manifest 或 proof slot。原始 HEIC 已包含 RGB 与 depth auxiliary data；进入主 App pending queue 后再按正常流程补齐 manifest 和签名。旧 PRD 提前把完整 packaging 定为 Extension 必须项是不合理约束，现已撤销。

#### R2B 真机验收

1. 从 Xcode 安装 Release build `7`，保留现有 `TAPCam R0` control；
2. 锁屏启动后分别使用屏幕快门和 hardware capture event，确认每次从 `CAPTURING` 进入 `SAVED <depthWidth>x<depthHeight> #N`；
3. 同一 Extension 会话连续拍摄 5 张，确认序号递增且没有卡在写入阶段；
4. 连续 10 轮执行“锁屏 -> 一次进入 -> 拍摄 -> 系统方式退出 -> 再次启动”；
5. 至少一次等待系统自然回锁屏，再确认下一次可以一次进入；
6. 日志中每次拍摄应依次出现 `r2b_photo_processed`、`r2b_session_write_begin`、`r2b_session_write_succeeded`，且最终文件名唯一。

通过条件：每次 capture 都完成 depth HEIC rename；preview 在写入前后持续可用；无 freeze、纯黑、卡在 `CAPTURING` 或需要再次侧键恢复。R2B 尚未启动主 App importer，因此 Library 不出现照片是预期行为；系统 suspend 后是否发出 `.initial/.added` 留给 R3 验证。

真机结论（2026-07-15）：用户报告 R2B 行为全部符合预期。Extension 中的 `SAVED` 只会在最终 HEIC rename 成功后出现；随后主 App 日志显示 `managerSessionCount=1`，证明系统已向 containing app 暴露一个 session directory。这个值不是照片数量。所提供 Console 片段主要来自主 App，因此没有 `r2b_*` Extension marker；结合可见 `SAVED` 状态与 manager directory evidence，R2B 判定通过。

### R3：主 App importer 与 pending queue

- App 启动时建立一个长期 `sessionContentUpdates` consumer；
- `.initial` 和 `.added` 都是导入触发器；
- 不用固定等待、轮询 `sessionContentURLs` 或把 session count 当照片数；
- 成功导入同一个 `TAPPendingCaptureStore` 后才 invalidate session directory；
- signing/export 继续异步，不能阻塞相机或导入；
- Library 通过 pending-store notification 更新，不要求用户第二次进入。

### R4：认证并打开主 App

- 只使用公开 `LockedCameraCaptureSession.openApplication(for:)`；
- activity type 使用 `NSUserActivityTypeLockedCameraCapture`；
- 左下角按钮唯一职责是请求打开 App；
- 点击前不 stop camera、不扫描文件、不等待 migration、不导入、不签名；
- 主 App route 和 importer 独立处理；
- 必须同时验证打开成功、最新 session delivery 和下一次 Extension launch。

iOS 26 `OpenIntent` 不再作为 secure-capture 内打开 containing App 的替代方案。它曾改变 Extension metadata 并破坏更早的 Control dispatch gate。

### R5：产品 UI 与压力测试

- 接入主 App 投影后的 lens/FOV selector、flash 和 output preference；
- 再评估 AppContext；
- 加入保存状态和左下角占位符，POC 阶段不显示真实缩略图；
- interruption、runtime error、media-services reset、thermal、memory pressure；
- 5/15 分钟 soak、多次拍摄、重复锁屏和 app-open 压力测试；
- unavailable 保留可见界面，用户可选择解锁继续。

## 不可接受的实现

- 在同一个实验同时修改 Control、camera、storage、importer 和 app route；
- 把 `openApplication(for:)` 当 session-content migration barrier；
- 在 Extension 中调用网络、App Group、主 App preferences 或 signing backend；
- 使用私有 transition-completion symbol；
- 为了“结束生命周期”手动 teardown camera 后再 open；
- root view 条件性变为空或只剩黑色背景；
- 把 `sessionContentURLs.count` 命名或解释为照片数量；
- 未检查最终 `.app/.appex` metadata 就只根据源码判断 target 配置；
- 在上一 gate 真机失败时继续叠加下一阶段功能。

## 提交与实验纪律

- 每个阶段先提交代码和文档，再进行真机 smoke；
- 每个单变量实验一个独立 commit；
- 失败实验保留在原分支，不通过 destructive reset 删除证据；
- 每次安装使用新的 build number；影响 Control descriptor 时使用新的可见 control kind/name；
- Agent 负责构建、产物检查和日志分析；用户从 Xcode 安装并执行锁屏物理触发；
- 真机结果必须写入 `Docs/AITrace` 后才能进入下一阶段。
