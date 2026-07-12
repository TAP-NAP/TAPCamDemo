# Locked Camera Capture POC PRD v3

状态：R0 official-template restart

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

- 用长期持有的 camera model 替换 `UIImagePickerController`；
- 只配置 depth-capable device、preview 和公开 `AVCaptureEventInteraction`；
- 不添加 photo output 和存储；
- root 永远可见，状态限定为 `starting/live/interrupted/unavailable`；
- 先重复 R0 的 10 次启动，再执行 5 分钟 live soak。

### R2：depth capture 与 session content

- 加入 `AVCapturePhotoOutput` 和真实 depth capture；
- 缺少 depth 的结果不提交为成功照片；
- 每次 capture 原子写入 `sessionContentURL`；
- Extension 只保存本地 raw/unsigned transfer artifact；
- 不在 Extension 中签名、联网、访问 App Group 或等待主 App；
- capture 与 app-open 完全解耦。

R2 开始前再决定 Extension 写完整 unsigned TAP artifact，还是只写最小 depth HEIC + metadata。旧 PRD 提前把完整 manifest/proof-slot packaging 定为 Phase 1 必须项是不合理约束，现已撤销。

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
