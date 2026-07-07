# Locked Camera Capture POC PRD

本文档记录锁屏拍摄 POC 的产品边界、工程契约和排查重点。后续 Agent 应先读本文，再拆分实现任务。

## 目标

验证 TAPCam 可以在锁屏状态下由 Lock Screen / Control Center / Action Button 入口启动一个最小 Locked Camera Capture extension，展示自定义拍摄 UI，持续显示可用 viewfinder，并在不解锁的情况下完成 TAP depth photo capture。

POC 的成功标准不是“拍到任意照片”。成功产物必须是主 App 现有签名队列能够处理的未签名 TAP depth artifact：

- 单个 embedded photo 文件，使用 Release depth output profile；Phase 1 固定 HEIC + `.quality`，Phase 2 再执行 AppContext 同步的 output format 和 photo quality。
- 包含 Apple auxiliary depth data。
- 包含 TAP manifest。
- 包含空 proof slot。
- 不包含 App Attest proof body。
- 写入 `LockedCameraCaptureSession.sessionContentURL`。
- 主 App 启动后通过 `LockedCameraCaptureManager` 迁移并入队到 `TAPPendingCaptureStore`，由 `TAPPendingCaptureProcessor` 异步签名和导出。

## Grill Decision Log

本节记录逐轮 grill 后形成的明确决策。后续实现必须优先遵守这里的结论；如果实现中发现冲突，应先更新本文档再改代码。

| # | Question | Decision |
| --- | --- | --- |
| 1 | POC 第一阶段拍出来的文件，是否必须是现有 TAPCam 的“深度 HEIC + manifest + 后续 App Attest 签名”格式？ | 必须。锁屏 extension 拍完后只能生成未签名 artifact；主 App 启动后把它放入现有异步签名队列。 |
| 2 | 锁屏 extension 里是否允许直接复用当前的 `CapturePackageBuilder + EmbeddedPhotoPackager` 这套 packaging 代码，只把 writer 换成 `sessionContentURL` writer？ | 允许，但只复用 capture/output 的纯本地链路；不把 App Attest、Photos、pending store、网络、主 App UI 编进 extension。 |
| 3 | 如果锁屏 extension 拍照时没有拿到 `AVCapturePhoto.depthData`，这次 POC 应该怎么处理？ | 视为不正确场景。extension 只选择支持 depth delivery 的设备/格式；配置不满足 depth 就不能进入可拍状态；拍摄结果缺少 depth data 时不写入 `sessionContentURL`、不入队，只显示可见错误或恢复 UI 并打日志。 |
| 4 | 如何定义历史“黑屏”问题？ | 不是单纯启动失败，而是 extension 已经进入 `live` 后，运行一段时间后 root UI、preview layer、capture session、camera controller 或 extension 进程状态中某一环失活，导致系统没有回锁屏但用户看到黑屏。 |
| 5 | POC 是否接受加入轻量 `AVCaptureVideoDataOutput` 作为 frame watchdog？ | 接受。它只用于记录 first/last frame 时间和活性诊断，不参与成像、存储或网络。 |
| 6 | 主 App importer 是否必须构造完整 `PackagedCaptureArtifact` 再调用现有 `TAPPendingCaptureStore.ingest(_:)`？ | 不必须，也不推荐伪造 capture pipeline 运行时对象。主 App 应增加 locked-import 专用 ingest API，把从 `sessionContentURL` 迁移回来的 unsigned locked capture 写入同样的 pending bundle，状态仍为 `.pending`，后续继续由 `TAPPendingCaptureProcessor` 签名和导出。 |
| 7 | `sessionContentURL` 里的权威产物应该是 extension 端完成的 unsigned TAP depth artifact，还是 raw transfer bundle 等主 App 再组装 manifest？ | POC 主路径选择 extension 端完成 unsigned TAP depth artifact：`.heic` 内已包含 Apple depth、TAP manifest 和 empty proof slot；主 App importer 只验证并入队。raw transfer bundle 仅作为后备方案，只有真机证明 extension 端 packaging 导致性能或生命周期问题时再实现。 |
| 8 | locked extension 的相机选择是否应在 extension 内重新计算，还是读取主 App 预先发布的选择结果？ | 主 App 应预先计算 depth-capable locked camera solution report，并通过 `CameraCaptureIntent.AppContext` 发布给 locked extension。extension 启动后读取 report 并做运行时校验。当前 POC UI 最小化，但代码边界必须允许未来复用主 App 的镜头切换、镜头选择等共享组件，避免长期双写。 |
| 9 | 未来主 App 和 locked extension 共享镜头选择/切换 UI 时，共享代码应如何组织？ | Apple 针对 app/extension 共享代码的正式建议是放入 extension-safe embedded framework，并同时嵌入 app 和 extension。POC 可以先用 extension-safe shared source layer 降低工程改动，但它只是过渡方案；长期应收敛到共享模块。共享代码不得引用 App Attest、Photos、network、App Group、`UIApplication.shared`、主 App route/store 等 app-only API。 |
| 10 | POC 是否现在就创建 `TAPCamSharedKit` embedded framework target？ | 不创建。POC 先使用 extension-safe shared source layer，降低 Xcode project、embedding/signing、target membership 和资源归属变量；文档保留长期目标：POC 稳定后再把 shared source layer 提升为 Apple 推荐的 extension-safe embedded framework。 |
| 11 | 启动验收是否先做 direct launch smoke，再做真实 Control Widget launch？ | 不分 direct-launch 验收阶段。POC 从一开始围绕真实 Control Widget / `CameraCaptureIntent` 启动链路加探针日志；用户触发或连接点击时机后，直接用日志判断 intent、extension scene、root UI、camera controller 分别是否启动。direct launch 只能作为本地排错手段，不能算验收。 |
| 12 | 启动和运行期探针日志用什么机制？ | 以结构化 `OSLog` 为主，DEBUG `print` 只做早期补充。统一 subsystem 为 `TAP-NAP.TAPCamDemo`，至少包含 `locked.launch`、`locked.lifecycle`、`locked.camera`、`locked.capture`、`locked.import` categories。每次真实启动链路生成 `launchID`，尽量贯穿 widget intent、extension scene、root view 和 camera controller。 |
| 13 | locked launch/camera/import 日志是否需要 shared helper？ | 需要。增加 extension-safe `LockedCaptureDiagnostics` / `TAPLockedDiagnostics` helper，放在 shared source layer，app、control widget、locked extension 都可引用。helper 只依赖 `Foundation`/`OSLog`，统一 categories、launchID、probe event 和 DEBUG print mirror；不做 telemetry、文件日志或网络上传。 |
| 14 | 主 App 何时发布 locked camera solution report？ | 首次需要打开主 App。主 App 不需要频繁刷新 report；只在没有 report、应用更新后、或 capture credential key reset/重新 prepare 导致 keyId 变化后重新自检并发布。report 不是照片或缓存文件，而是主 App 计算出的锁屏拍摄方案和自检结果，通过 `CameraCaptureIntent.updateAppContext(...)` 提供给 locked extension。 |
| 15 | locked extension 应该自己 full discovery，还是使用主 App 记录下来的镜头 UI 选项？ | 使用主 App 记录下来的 UI-projected lens/FOV option records。主 App 仍是完整 discovery 和镜头列表投影的来源；AppContext 只承载当前相机 UI 真正会展示的 Codable option records，而不是所有被 AVFoundation 发现的设备。locked extension 不再 full discovery，也不让 LiDAR 等未进入主 UI 镜头选择器的设备单独出现在锁屏 UI；它只把选中的 record narrow resolve 到当前 `AVCaptureDevice`/format 并校验。 |
| 16 | 锁屏 POC 是否真正支持并遵循主 App 的 Flash / Live Photo 状态？ | Flash 支持并按主 App AppContext 状态执行；Live Photo 状态可以同步到 AppContext 和 UI，但 POC capture 强制关闭。Live Photo 需要 paired MOV、音频权限、audio input、manifest v2、导入和签名绑定，暂不纳入本 POC 的成功路径。 |
| 17 | locked extension 的 AppContext 是否同步 Output Format / Photo Quality 设置？ | 同步。主 App 应把当前 output format 和 photo quality preference 投影进 locked camera AppContext；locked extension 不直接读取主 App preferences。具体是否在 POC 立即执行 HEIC/JPEG 双格式，单独决策。 |
| 18 | Output Format / Photo Quality 同步后，POC 是否立即按主 App 设置执行 HEIC/JPEG 和 photo quality？ | 分阶段执行。AppContext 可以同步 output format 和 photo quality 字段，但 Phase 1 固定使用 Release depth HEIC profile，先降低变量并证明锁屏 live、真实拍照、unsigned TAP artifact、`sessionContentURL`、主 App 入队链路。Phase 2 再按 AppContext 解析 `CaptureOutputProfile.releasePhotoDepthProfile(fileContainer:photoQualityLevel:)`，恢复 HEIC/JPEG 和 photo quality parity。Live Photo 仍强制关闭。 |
| 19 | 除 Flash / Live Photo / Output Format / Photo Quality 外，还同步哪些设置？ | Location 同步并 best-effort 执行，不可用时写 nil 且不阻塞；Microphone 同步但不执行，因为 Live Photo 在 POC 中关闭；Shutter Sound 同步并执行；Haptics 同步并执行；Guide overlay、highlight color、focus magnifier、EV、Pro controls 不纳入 POC。 |
| 20 | locked extension 里 Location best-effort 是否允许主动请求定位权限？ | 不允许。locked extension 不弹定位权限、不等待定位、不阻塞 viewfinder 或 shutter。只有已授权且能在短超时内取得位置时才写入 location；否则使用 nil。日志只记录定位授权/可用状态，不记录经纬度。 |
| 21 | 主 App 投影给 locked extension 的 lens/FOV records 是否包含 disabled options？ | 不包含。locked AppContext 只带主 App Release UI 当前会展示的 enabled lens/FOV options。Debug/诊断型 disabled option、被 discovery 发现但未进入 Release 镜头选择器的设备，都不应进入 locked UI。没有 enabled option 时进入 `unavailable`。 |
| 22 | locked extension 的最小 UI 是否显示镜头/FOV 选择器？ | 显示。POC 必须显示最小 lens/FOV selector，使用 AppContext 里的 enabled records 和 shared presentation model。默认选中主 App 默认/24mm；点击其他 option 时 narrow resolve 并重建 session。UI 不需要完整主 App chrome，但要验证 records 能组 UI、点击能切换、失败不会黑屏。 |
| 23 | locked extension 是否额外支持前后摄像头切换？ | 不额外做。locked UI 完全跟随主 App 投影出来的 enabled lens/FOV option records；如果主 App Release records 不包含 front option，locked 就不显示前后切换入口。不得在 locked extension 内发明主 App 没有的镜头入口。 |
| 24 | AppContext 缺失、过期、损坏或没有 enabled lens/FOV records 时，locked extension 是否 fallback 到 full discovery？ | 不 fallback。进入可见 `unavailable`，提示解锁打开主 App，并通过公开 `LockedCameraCaptureSession.openApplication(for:)` 路径跳转。这样避免 locked UI 和主 App UI 不一致，也避免锁屏里做慢 discovery。 |
| 25 | `unavailable` 时跳主 App 是自动触发还是用户点按钮触发？ | 必须由用户明确点击触发。`unavailable` UI 显示“解锁继续”按钮，点击后调用 `LockedCameraCaptureSession.openApplication(for:)`。不得自动跳转；调用失败时保留 fallback UI 并打日志。 |
| 26 | AppContext 的 lens/FOV record 需要新增 format fingerprint 吗？ | 第一版不新增。record 贴着现有 `FocalLengthOption` 和 `CaptureSelectionContext` 已经表达的字段做 Codable 投影：option/display labels、equivalent focal length、RGB source id/type/position、depth source id/kind、zoom id/factor、resolved capture device id/type。extension narrow resolve 后重新验证 depth delivery；只有真机证明 format resolve 不稳定时再补 format fingerprint。 |
| 27 | 主 App 何时发布 locked AppContext？ | 发布动作绑定到相机能力矩阵和 settings 投影完成，而不是泛泛 app launch。主 App 先跑 `CameraCapabilityResolver.discover()`，计算 `CapabilityMatrix.focalLengthOptions().filter(\.isEnabled)`，解析 Flash/Live Photo/Output Format/Photo Quality/Location/Mic/Shutter/Haptics 设置，再调用 `CameraCaptureIntent.updateAppContext(...)`。如果 enabled options 为空，发布明确 unavailable context 或不发布可拍 context。 |
| 28 | AppContext 发布失败时是否阻塞主 App？如何让主 App 后续重建？ | 不阻塞主 App。发布失败只影响 locked readiness，必须打日志并允许主 App 相机继续工作。locked extension 如果下次启动时发现 AppContext 缺失/损坏/过期，进入 `unavailable`；用户点击“解锁继续”时通过 `openApplication(for:)` 的 `NSUserActivity` 携带 regenerate context reason，让主 App 解锁后重新生成并再次发布。若 `updateAppContext` 本身失败，不能假设 extension 会收到新的状态。 |
| 29 | `openApplication(for:)` handoff 到主 App 后，主 App 是否直接打开相机页并重新生成 AppContext？ | 是。handoff 使用 `NSUserActivityTypeLockedCameraCapture`，`userInfo` 携带 `tapAction=regenerateLockedCameraContext` 和 reason。主 App 收到后进入相机准备路径，重新计算 capability/options/settings projection，调用 `updateAppContext(...)`，同时处理已有 session content importer；不自动重新进入 locked extension。 |
| 30 | locked extension 拍照并写入 `sessionContentURL` 后是否自动跳主 App 签名？ | 不自动触发签名；签名队列仍是主 App 的异步后处理。用户点击左下角占位符时，Phase 1 必须保留 `LockedCameraCaptureSession.openApplication(for:)` 直接调起主 App 的 UX，但打开主 App 不等于同步签名或同步迁移。E1A 实验把左下角路由到 TAP Library awaiting state，主 App 只通过长期 `sessionContentUpdates` runtime 导入，避免 handoff 阶段抢跑扫描 `sessionContentURLs`。 |
| 31 | locked extension 连续拍多张时，`sessionContentURL` 里的文件如何组织？ | 镜像主 App pending queue 的语义结构：每张照片一个 `<captureID>/` directory，目录名使用 embedded manifest `payload.id`，文件名使用固定语义名 `unsigned.heic` 或 `unsigned.jpg`。session content 中不伪造正式 `bundle.json`；主 App importer 验证目录名和 manifest id 一致后，通过 locked-import ingest API 创建正式 pending bundle。 |
| 32 | locked extension 是否沿用主 App 的 capture backpressure 上限？ | POC 沿用主 App 的 `CaptureJobQueue.defaultMaximumPendingJobs = 3` 思路，但只统计 locked extension 内正在进行的 photo capture、packaging、atomic write。已写入 `sessionContentURL` 的 capture 和主 App 签名 pending queue 不计入这个上限。达到上限时 shutter 暂时不可用并显示保存状态，viewfinder 必须继续 live。该限制是 POC 稳定性保护，不否定后续单独设计连拍/burst capture。 |
| 33 | 主 App 解锁启动后，locked session content importer 是否阻塞相机首页或签名队列？ | 不阻塞。整体设计异步优先：主 App 启动或收到 `sessionContentUpdates` 后，importer 在后台把 `sessionContentURL/<captureID>/unsigned.*` 转入 `TAPPendingCaptureStore`；相机 UI 和用户继续拍摄优先起来。导入成功的 capture 进入现有异步签名队列；导入失败只记录并保留 session content，不能卡住相机首页、shutter 或已有 pending signing/export。 |
| 34 | locked session content 重复导入或 `sessionContentUpdates` 重放时怎么处理？ | importer 必须按 `captureID = manifest.payload.id` 幂等。pending queue 已有同一 `captureID` 且 manifest/file container/depth/proof-slot 校验一致时，视为已导入并跳过重复写入，可在合适时 invalidate session content。若同一 `captureID` 对应内容不一致，视为冲突：不覆盖已有 pending record，不删除 session content，只打高优先级日志并保留给后续人工或策略处理。 |
| 35 | 锁屏拍完后，extension UI 是否显示相册/最近照片入口？ | 显示一个和主 UI 相册入口位置一致的占位入口。这个入口不是 status-only 主线，点击后必须通过 `LockedCameraCaptureSession.openApplication(for:)` 直接调起主 App。baseline commit 保留 status-only 作为可回滚负控；E1A 入口使用 `tapAction=openTAPLibraryRuntimeImport`，打开 TAP Library awaiting state，但不在 handoff 阶段调用 `beginDelayingAppearance()` 或同步扫描 `sessionContentURLs`；导入归长期 `sessionContentUpdates` runtime 负责。POC 暂不显示真实缩略图，只显示状态图标。 |
| 36 | 锁屏拍完后是否立即解锁进入 TAP Library？ | 是，左下角入口的目标 UX 是直接解锁进入主 App 的 TAP Library/等待导入状态；但“进入 Library”不承诺第一帧已经有 just-saved capture。公开 API 没有“先 programmatic dismiss 回原生锁屏、等系统迁移完成、再 URL/open 主 App”的两阶段路径；`openApplication(for:)` 只保证请求打开 containing app，不保证 `sessionContentURL` 已迁移或 `LockedCameraCaptureManager.sessionContentURLs` 非空。`beginDelayingAppearance()` 只延迟 app appearance，最新 smoke 仍看到 transition import `sessionCount=0`，因此 E1A 明确不使用 transition-delay/import 抢跑。旧 `openTAPLibraryAfterLockedCapture`、`openTAPLibraryAwaitingLockedImport`、`openTAPLibrary` 和 `openTAPCamera` saved-placeholder 路径保留为失败/不稳定对照，具体 API 说明见 [LockedCameraCaptureAPINotes.md](LockedCameraCaptureAPINotes.md)。 |
| 37 | 锁屏保存成功后，左下角占位符是否显示真实缩略图？ | POC 暂不显示真实缩略图，只显示图标状态。保存中用 spinner/保存图标，保存成功用成功图标，失败用警告图标。真实缩略图等主 App importer 入队后，由现有 TAP Library / pending thumbnail 机制显示，避免 locked extension 为缩略图引入额外解码、缓存、状态同步和隐私边界。 |
| 38 | 锁屏 extension 的状态文字是否需要完整文案和本地化？ | POC 暂不做完整本地化，只使用少量稳定短句，语言保持和当前项目默认 UI 一致。文案目标是诊断可见性，不是最终体验精修；至少覆盖 Preparing、Ready、Saving、Saved、Recovering、Unavailable、Unlock to continue 等状态。后续 UI 精进阶段再统一文案、语气和本地化。 |
| 39 | locked extension 被系统 lifecycle 打断时，如何设计才能定位黑屏原因？ | 接受黑屏取证原则：不强行保留旧 session，而是保留 root view 和 `@StateObject` camera controller，显示可见恢复状态；`scenePhase` 回到 `.active` 后统一 `rebuildSession(reason: sceneBecameActive)`。日志必须能区分 root/controller 释放、preview layer 脱离 window/layer tree、`AVCaptureSession` interruption、runtime error、session running 但无帧、以及 extension 被系统终止。 |
| 40 | 黑屏异常发生后的完整处理逻辑是否现在定死？ | 不定死。POC 当前目标是定位并避免“纯黑且无解释”的状态，而不是最终化完整恢复 UX。实现上可自行决断最小保护：异常发生时 root UI 立即进入可见 `recovering` 或 `unavailable`，记录归因日志，尽量重建 session；公开 API 不支持 extension 主动 programmatic dismiss 回系统锁屏，因此 fallback 以可见状态、用户上滑 dismiss、或用户点击 `openApplication(for:)` 解锁进入主 App 为边界。 |
| 41 | POC 是否加入 DEBUG/diagnostics-only 的可见心跳 overlay？ | 加，但只在 DEBUG 或显式 diagnostics flag 下显示，不进入正式体验。overlay 显示最小活性字段：state、scenePhase、session isRunning、lastFrameAge、previewAttached、rebuildCount、launchID 后几位。黑屏时如果 overlay 仍可见，优先怀疑 preview/session；如果 overlay 也消失，优先怀疑 root/controller lifecycle 或 extension 被系统处理。 |
| 42 | 黑屏取证是否在 extension 内写持续更新的本地诊断文件？ | 不写。POC 主取证路径是 `OSLog`、Console/sysdiagnose 和 diagnostics overlay。锁屏 extension 生命周期和存储受限，持续写日志文件会增加 IO、功耗和系统终止风险，也不保证黑屏/终止后可靠保留。`locked-transfer.json` 可以保留为每张成功 capture 的轻量诊断附带文件，但不是连续运行日志，不参与签名或真实性判断。 |
| 43 | diagnostics overlay 是否允许在 Release/TestFlight 构建中打开？ | 暂不允许。POC overlay 只在 `DEBUG` 或本地开发 diagnostics build flag 下启用。锁屏相机是系统敏感入口，Release/TestFlight 可见内部状态会影响审核、隐私和用户体验。真机取证先使用 Debug build、Console/sysdiagnose 和 OSLog；若后续需要 TestFlight 诊断，再单独设计受控开关。 |
| 44 | 历史黑屏是 live 一段时间后才出现，POC 是否定义最小真机静置/操作时长？ | 定义第一阶段 soak test：锁屏 extension 进入 `live` 后静置 5 分钟，期间不能出现纯黑无解释 UI；如发生中断或无帧，必须显示 `recovering` / `unavailable` 并打点归因。5 分钟内至少拍 3 张，覆盖保存中、保存成功、继续 live；退出后从锁屏重启 3 次，确认 launch、first frame、controller lifecycle 稳定。若 5 分钟无法复现，后续长测再扩展到 15 分钟。 |
| 45 | 实施顺序先做完整拍照写入，还是先做可启动 + live + 黑屏诊断壳？ | Phase 1 仍然诊断优先，但不能只是假 shutter。Phase 1 先打通真实锁屏启动、root 可见、`@StateObject` controller、preview/live、watchdog、session notifications、diagnostics overlay；随后在同一阶段接最小真实拍照写入：`AVCapturePhotoOutput`、depth photo、nil signer unsigned artifact、`sessionContentURL` writer；解锁进入主 App 后，valid session content 直接由 importer 进入 `TAPPendingCaptureStore`。Phase 2 再补全 TAP Library route、完整设置同步、签名/导出验证和 importer hardening。 |
| 46 | Phase 1 的 shutter 按钮和硬件 capture event 怎么处理？ | Phase 1 验收必须执行真实 capture。早期增量开发中 shutter 可以临时只记录诊断事件，但 Phase 1 完成标准是：点击 shutter 或硬件 capture event 进入 `capturing`，触发 `AVCapturePhotoOutput`，写入 `sessionContentURL`，显示 saving/saved，并回到 `live`。每个阶段都要打点，确保如果黑屏发生在 capture 周边，能区分是 live idle、photo output、packaging，还是 session content write 导致。 |
| 47 | Phase 1 的 AppContext 是否需要完整同步并执行 Flash/Live Photo/Output Format/Photo Quality 等设置？ | Phase 1 可以先不完整执行全部主 App 设置，但真实拍照必须使用明确默认策略。Codable AppContext 类型可以先设计完整字段；Phase 1 extension 主要读取 lens/FOV records 和最小 diagnostics metadata，拍照使用安全默认：Live Photo 强制关闭、无 App Attest、无 Photos、无网络、Location 不阻塞、output profile 使用当前 POC 默认 depth still 配置。Flash、Output Format、Photo Quality、Shutter Sound、Haptics 等完整主 App 设置同步和执行在 Phase 2 补齐。 |
| 48 | Q44 的第一阶段 soak test 是否仍要求真实拍照？ | 要求。5 分钟 soak 期间至少真实拍 3 张，而不是只触发假 shutter。每张都必须走 `AVCapturePhotoOutput`，验证 depth data，生成 unsigned artifact，并写入 `sessionContentURL`；解锁进入主 App 后，valid locked captures 应进入 `TAPPendingCaptureStore`，状态为 `.pending`。签名/export 仍按现有异步队列运行，不阻塞锁屏拍摄验收。 |
| 49 | Phase 1 主 App 是否需要一个 read-only session content inspector？ | 不做独立 inspector 产品功能，也不把 dry-run 作为 Phase 1 最终状态。可以在 `LockedCaptureSessionContentImporter` 内加 probe logging：导入前记录能否看到 `<captureID>/unsigned.*`、文件大小、container、manifest id、depth presence、empty proof slot；随后 valid capture 直接入 `TAPPendingCaptureStore`。早期开发可临时 dry-run 排查，但验收必须入队。 |
| 50 | `sessionContentURL` 清理由谁负责？ | 按 Apple 推荐的迁移模型：extension 不清理 session content。主 App 进入后，正式 importer 成功把 session content 导入主 App pending queue 后，由主 App 调用 `LockedCameraCaptureManager.invalidateSessionContent(at:)` 清理。临时 dry-run/probe 不算导入成功，因此不 invalidate；Phase 1 验收路径应是导入成功后清理。 |
| 51 | “不签名、不入 pending queue”的边界如何理解？ | 正确边界是：extension 不做 App Attest、不签名、不写主 App pending queue；extension 只写 `sessionContentURL`。一旦用户进入主 App，valid session content 应由 importer 进入 `TAPPendingCaptureStore`，这时才产生 pending signing 记录，并由现有 `TAPPendingCaptureProcessor` 异步签名/export。 |
| 52 | locked capture 入队后是否需要特殊 signing 触发逻辑？ | 不需要 locked-specific signing 语义。只要图片进入主 App，来源无论是主 App shutter 还是 locked extension importer，都必须进入同一个 `TAPPendingCaptureStore` pending queue，并遵守同一个 `TAPPendingCaptureProcessor` 处理路径。实现时 importer 应复用主 App 普通拍照入队后的后处理入口；不要为 locked capture 单独发明第二套 pending/signing 触发机制。 |
| 53 | locked importer 写入 pending queue 时直接复用 `TAPPendingCaptureStore.ingest(_:)`，还是新增 thin wrapper？ | 新增 thin wrapper，例如 `ingestLockedCapture(...)`，但它不能变成第二套队列。wrapper 的职责是把 `sessionContentURL/<captureID>/unsigned.*` 输入解析成主 App pending store 需要的事实：manifest、depth、empty proof slot、file container、thumbnail；最终写出的目录结构、`.pending` 状态、record 语义和 processor 路径必须与普通 `TAPPendingCaptureStore.ingest(_:)` 等价。 |
| 54 | Phase 1 锁屏 extension 写入的照片是否必须已经是可直接入 pending queue 的 unsigned TAP artifact？ | 必须。Phase 1 写入的不是普通 depth HEIC，而是包含 Apple depth data、TAP manifest、`manifest.payload.id`、empty proof slot、明确 file container、后续 App Attest 可签名 unsigned bytes 的 TAP artifact。这样主 App importer 才能直接 `ingestLockedCapture(...)` 入 `TAPPendingCaptureStore`。 |
| 55 | Phase 1 的 file container / output profile 用什么默认值？ | Phase 1 固定使用 Release depth HEIC profile，不执行完整主 App Output Format / Photo Quality 偏好。目标是先证明锁屏 live、真实拍照、unsigned TAP artifact、`sessionContentURL`、主 App 入 pending queue 这条链路；HEIC 是当前最稳的 depth artifact 路径。Phase 2 再恢复按 AppContext 同步 Output Format / Photo Quality，支持 HEIC/JPEG parity。 |
| 56 | Phase 1 的 Flash 默认值怎么定？ | Phase 1 固定 Flash off，不执行 AppContext flash。Flash 会引入额外硬件行为、曝光变化和时序变量；Phase 1 重点是验证 locked launch、live 不黑屏、真实 depth capture、unsigned TAP artifact、`sessionContentURL` 和 pending 入队链路。Phase 2 再按 AppContext 执行主 App flash 状态。 |
| 57 | Phase 1 的 shutter sound 和 haptics 默认怎么定？ | Phase 1 haptics on，shutter sound 按系统默认，不主动 suppress。点击 shutter 给轻量 haptic，帮助确认输入被接收；但不设置 `isShutterSoundSuppressionEnabled`，避免引入静音/系统策略变量。Phase 2 再按 AppContext 执行主 App shutter sound / haptics 设置。 |
| 58 | Phase 1 是否写入 Location？ | Phase 1 不写 location，固定 nil。定位在锁屏 extension 里会引入授权、缓存、时序和隐私变量；黑屏/拍照链路 POC 不需要它。Phase 2 再恢复“已有授权 + best-effort + 不阻塞”的 Location 行为。 |
| 59 | Phase 1 是否需要同步/显示 Live Photo 状态？ | AppContext 可以携带 Live Photo 状态，但 Phase 1 UI 不显示 Live Photo 控件，也不执行 Live Photo。日志记录 `livePhotoForcedOff=true` 即可。Live Photo 会引入 paired MOV、音频、manifest、导入和签名资源绑定，和当前“黑屏 + still photo depth artifact”POC 目标无关；后续如需支持应单独设计。 |
| 60 | Phase 1 固定 HEIC 时，photo quality 用哪个默认？ | 使用现有主 App 默认：`CameraPhotoQualityPreference.defaultValue == .quality`，也就是 `CapturePhotoQualityLevel.quality` / Release profile default，不新增 locked 专属质量值。Phase 1 固定默认但来源于现有系统；Phase 2 再按 AppContext photo quality 执行。 |
| 61 | 实现时从历史 `lockScreen` 分支迁移，还是新建最小 POC？ | 新建。Phase 1 在当前分支新增最小 intent/control/locked extension targets 和 source；历史 `lockScreen` / `lockScreen_test` 分支只作为 entitlement、Info.plist、scene wiring、API 用法、相册占位和日志点参考。不要直接迁移旧 UI、controller、session lifecycle 或状态机代码，避免把历史黑屏变量带进 POC。 |
| 62 | 新建 targets 的命名和 bundle id 怎么定？ | Source/target 名称保留当前 POC 命名：`TAPCamLockedCameraCaptureExtension`、`TAPCamLockedCameraControlExtension`、`TAPCamLockedCameraIntents`。Bundle ID 对齐历史可工作的锁屏入口，减少 Lock Screen control/secure capture 缓存变量：capture extension 使用 `TAP-NAP.TAPCamDemo.LockedCapture`，control extension 使用 `TAP-NAP.TAPCamDemo.Controls`。只有 Xcode/系统要求独立 App Intents extension 时，再使用 `TAP-NAP.TAPCamDemo.LockedCameraIntents`。 |
| 63 | Phase 1 的最低 iOS 编译/运行要求怎么定？ | 按 Locked Camera Capture 锁屏入口 API 的最低要求走，不人为提高到 iOS 26。本机 iPhoneOS 26.5 SDK 显示 `LockedCameraCaptureExtension`、`LockedCameraCaptureUIScene`、`LockedCameraCaptureSession`、`LockedCameraCaptureManager`、`CameraCaptureIntent`、`ControlWidget`、`StaticControlConfiguration`、`ControlWidgetButton` 和 SwiftUI `onCameraCaptureEvent(...)` 基础 overload 均为 iOS 18.0；UIKit `AVCaptureEventInteraction` 为 iOS 17.2。POC 不使用 iOS 26-only `onCameraCaptureEvent(defaultSoundDisabled:)` overload。真机锁屏启动/拍摄仍是验收方式；simulator 只做编译和纯逻辑测试。当前 repo deployment target 是 18.6，实施时不要升到 26；是否降低到 18.0 属于单独 project deployment policy 决策。 |
| 64 | 新建 locked/control targets 的 deployment target 怎么设？ | 先沿用当前工程 `IPHONEOS_DEPLOYMENT_TARGET = 18.6`。POC 不顺手降低主 App 或 extension deployment target，也不升级到 iOS 26。代码层面只使用 iOS 18.0 锁屏入口可用 API；如果发现 iOS 26-only API 能改善体验或诊断，先记录到 roadmap/to-do，后续再单独评估是否提高系统要求。 |
| 65 | 是否把数据传输策略切回历史分支？ | 作为下一组主实验接受，但不是整体回滚历史 UI/状态机。历史 `lockScreen_test` 的数据策略是 extension 把已包含 TAP manifest / empty proof slot 的 flat `TAPCam-<UUID>.heic` 写进 `sessionContentURL`，主 App 通过 `LockedCameraCaptureManager.sessionContentURLs` / `sessionContentUpdates` 枚举实际 HEIC 文件并按文件数导入。当前 POC 使用 `<captureID>/metadata.json + unsigned.heic` staging bundle，并在主 App importer 里补 manifest/proof slot，因此多了一层 app-side packaging 变量。下一步可做 flat-HEIC transfer A/B，但必须先确认共享 packaging 栈在 locked extension target 中是 extension-safe；左下角 `openApplication(for:)` 仍单独处理，因为历史策略也不是靠它完成文件迁移。 |

## 背景问题

历史 `lockScreen` / `lockScreen_test` 分支已经验证过 extension 能够启动并显示锁屏相机 UI，但出现过更严重的运行期问题：

1. 启动初期正常，屏幕亮起，摄像头有画面。
2. 运行一段时间后画面和 UI 进入黑屏。
3. 系统没有自然回到原生锁屏。
4. 现象像是 extension 外壳仍占着前台，但 SwiftUI root、preview layer、capture session、camera controller 或系统 extension 运行状态中某一环已经失活。

因此本文档不把问题描述为“启动失败兜底”。真正要验证的是：extension 进入 `live` 之后，root UI、preview layer、capture session 和 controller 是否能持续存活；任意一环失活时，用户不能看到纯黑屏。

## 非目标

本 POC 不做以下事情：

- 不复用历史分支的完整锁屏 UI。
- 不复用主 App 的完整相机 UI。
- 不在 extension 内运行 App Attest。
- 不在 extension 内访问网络。
- 不在 extension 内访问 App Group shared container。
- 不在 extension 内读取主 App shared preferences。
- 不在 extension 内直接写 Photos。
- 不在 extension 内主动请求定位权限。
- 不尝试用私有或不存在的 API 主动 dismiss 回系统锁屏。
- 不把 no-depth capture 当作成功结果。
- 不在本 POC 中启用 Live Photo capture；Live Photo 状态可以同步和显示，但拍摄路径强制关闭。
- 不从历史 `lockScreen` 分支迁移 UI 旋转行为。当前 POC 锁定最小 UI，不新增未讨论过的旋转、动效或 chrome 行为。

历史分支只能作为 target 结构和 API 用法参考，不能作为 POC 的 UI 或状态机来源。

## 平台和 API 事实

本机 SDK 确认以下公开 API 存在：

- `LockedCameraCaptureExtension`
- `LockedCameraCaptureUIScene`
- `LockedCameraCaptureSession.sessionContentURL`
- `LockedCameraCaptureSession.openApplication(for:)`
- `LockedCameraCaptureSession.invalidateSessionContent()`
- `LockedCameraCaptureManager.sessionContentURLs`
- `LockedCameraCaptureManager.sessionContentUpdates`
- `LockedCameraCaptureManager.invalidateSessionContent(at:)`
- `CameraCaptureIntent`
- `AVCaptureEventInteraction`

本地确认路径：

- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/LockedCameraCapture.framework/Modules/LockedCameraCapture.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/_AVKit_SwiftUI.framework/Modules/_AVKit_SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/AVKit.framework/Headers/AVCaptureEventInteraction.h`

Availability confirmed from the local iPhoneOS 26.5 SDK:

| API / entry surface | Availability used by POC |
| --- | --- |
| `LockedCameraCaptureExtension`, `LockedCameraCaptureUIScene`, `LockedCameraCaptureSession`, `LockedCameraCaptureManager` | iOS 18.0 |
| `CameraCaptureIntent` and `CameraCaptureIntent.updateAppContext(...)` | iOS 18.0 |
| `ControlWidget`, `ControlWidgetConfiguration`, `ControlWidgetTemplate`, `StaticControlConfiguration`, `ControlWidgetButton` | iOS 18.0 |
| SwiftUI `onCameraCaptureEvent(isEnabled:action:)` and `onCameraCaptureEvent(isEnabled:primaryAction:secondaryAction:)` | iOS 18.0 |
| UIKit `AVCaptureEventInteraction` | iOS 17.2 |
| SwiftUI `onCameraCaptureEvent(... defaultSoundDisabled: ...)` overloads | iOS 26.0; do not use in Phase 1. |

The SDK also exposes `LockedCameraCapture` in the iPhoneSimulator 26.5 SDK, so simulator build/logic tests are allowed. Real lock-screen launch, hardware capture event, camera stream, depth capture, and black-screen soak validation remain real-device-only evidence.

The current project uses `IPHONEOS_DEPLOYMENT_TARGET = 18.6`. Locked Camera POC code must not raise deployment to iOS 26. Lowering the app/project deployment target to 18.0 is a separate product/build policy decision, not a POC requirement.

New locked/control targets should initially inherit the current project deployment target, `IPHONEOS_DEPLOYMENT_TARGET = 18.6`.

公开约束：

- 锁屏 extension 的可持久写入位置是 `sessionContentURL`。
- 主 App 使用 `LockedCameraCaptureManager` 接收 session content。
- extension 的公开解锁路径是用户交互后调用 `openApplication(for:)`。
- 没有公开 programmatic dismiss API 可以让 extension 主动退回原生锁屏。
- 启动后应尽快显示 viewfinder。
- 可见 capture view 应处理硬件 capture event。UIKit 使用 `AVCaptureEventInteraction`；SwiftUI 也有 camera capture event modifier。

Apple code organization guidance:

- Apple 的 App Extension Programming Guide 针对代码组织的建议是：如果 app 和 extension 需要共享代码，把共享代码放进 embedded framework，并把 framework 同时嵌入 app 和 extension target。
- 共享 framework 不能包含 app extension 不可用 API；如果 framework 包含这类 API，只能由 containing app 链接，不能给 extension 链接。
- extension target 使用共享 framework 时，应把 `Require Only App-Extension-Safe API` 设为 Yes；否则 Xcode 会提示链接的 dylib 对 app extension 不安全。
- 如果使用 embedded framework，Copy Files build phase 的 destination 应为 `Frameworks`。
- POC 阶段可以先用 shared source target membership 作为过渡，以减少 project churn；但共享源码必须遵守同样的 extension-safe 规则，并最终收敛到清晰共享模块。
- Apple 还说明 app extension 和 containing app 运行时不能直接访问彼此容器；这是数据共享约束，不是代码组织方式。Locked Camera POC 的数据传递使用 `CameraCaptureIntent.AppContext` 和 `sessionContentURL`，不使用 App Group/shared preferences。
- 参考：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html
- 参考：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html

## 现有主 App 边界

当前主 App 已有异步签名和导出队列：

- `TAPPendingCaptureStore.ingest(_:)` 接收 `PackagedCaptureArtifact`，写入 app-private pending bundle。
- `TAPPendingCaptureProcessor` 从 pending bundle 读取 unsigned photo，调用 App Attest 签名，然后导出 Photos。
- `TAPCaptureProvenanceWriter.signedPhotoData(...)` 要求 unsigned photo 已包含 TAP manifest 和空 proof slot。
- `EmbeddedPhotoPackager` 可以在不提供 assertion signer 的情况下生成 unsigned artifact，并通过 `TAPCaptureProvenanceWriter.writeManifest(...)` 预留 proof slot。

POC 应复用 capture/output 的本地纯链路，避免第二套 HEIC/manifest/proof-slot 写法。extension writer 只负责把 locked capture transfer 写到 `sessionContentURL`。

## 目标架构

POC 拆成四个组件。

| Component | Responsibility |
| --- | --- |
| `TAPCamLockedCameraIntents` shared source | 定义 `CameraCaptureIntent`、最小 locked camera solution report context，以及 extension/app 都可引用的轻量选择值模型。 |
| `TAPCamLockedCameraControlExtension` | Control Widget 入口，点击后触发 locked camera capture intent。 |
| `TAPCamLockedCameraCaptureExtension` | Locked Camera Capture extension，拥有最小拍摄 UI、session controller、viewfinder 和 session-content writer。 |
| Main App importer | 观察 `LockedCameraCaptureManager`，把 session content 中的 unsigned TAP depth artifacts 入队到 `TAPPendingCaptureStore`。 |

Target naming and bundle identifiers:

| Target/source | Bundle identifier |
| --- | --- |
| `TAPCamLockedCameraCaptureExtension` | `TAP-NAP.TAPCamDemo.LockedCapture` |
| `TAPCamLockedCameraControlExtension` | `TAP-NAP.TAPCamDemo.Controls` |
| `TAPCamLockedCameraIntents` shared source | No bundle id while it remains shared source target membership. |
| Optional `TAPCamLockedCameraIntents` App Intents extension | `TAP-NAP.TAPCamDemo.LockedCameraIntents`, only if Xcode/system integration requires a separate App Intents extension target. |

extension 内部建议拆分：

| Type | Responsibility |
| --- | --- |
| `LockedCaptureRootView` | 永远渲染可见 root UI；持有 `@StateObject` controller；绑定 scene phase 和 capture event。 |
| `LockedCaptureCameraController` | 长生命周期对象，拥有 `AVCaptureSession`、`AVCapturePhotoOutput`、`AVCaptureVideoDataOutput`、session queue、photo delegates、状态机和 watchdog。 |
| `LockedCapturePreviewHost` | UIKit/SwiftUI bridge，挂载 `AVCaptureVideoPreviewLayer`，报告 layer/window attach 状态。 |
| `LockedSessionContentArtifactWriter` | 把 locked capture transfer 原子写入 `sessionContentURL`。 |
| `LockedCaptureSessionContentImporter` | 主 App 侧 importer，读取 session content 并通过 locked-import ingest API 创建 pending record。 |

Locked camera app context source:

- AppContext 表示主 App 已经计算并投影过的 locked camera launch context，不是照片、文件缓存或运行时对象快照。
- AppContext 命名暂不锁死；实现命名应优先贴近现有主 App capability/selection 词汇，而不是为 locked flow 新造一套长期模型。
- 主 App 首次启动后跑完整 capability discovery，并把现有相机 UI 使用的 `CapabilityMatrix.focalLengthOptions()` 投影成 Codable/Sendable records。
- AppContext publish is tied to `CapabilityMatrix` and settings projection completion, not generic app launch.
- The publisher should compute `CapabilityMatrix.focalLengthOptions().filter(\.isEnabled)` before calling `CameraCaptureIntent.updateAppContext(...)`.
- If the enabled option list is empty, publish an explicit unavailable context or avoid publishing a capturable context.
- AppContext publish failure must not block main app startup or normal camera use.
- Publish failure should be logged as locked readiness failure and retried on a future app launch or capability/settings projection.
- If `updateAppContext(...)` fails, do not assume locked extension will receive an updated failure status.
- When locked extension detects missing/malformed/stale AppContext, its unavailable UI should offer unlock-to-app. The `NSUserActivity` passed to `openApplication(for:)` should include a regenerate-context reason so the main app can rebuild and republish after unlock.
- Handoff should use `NSUserActivityTypeLockedCameraCapture` with a public-safe `userInfo["tapAction"]`.
- `tapAction = "regenerateLockedCameraContext"` is used by unavailable/fallback UI. Main app receiving this handoff should route to camera preparation, rebuild locked AppContext, call `updateAppContext(...)`, and run session-content import if needed. It should not automatically relaunch the locked extension.
- The locked saved-state placeholder must not hand off directly to TAP Library in Phase 1. Do not use `openTAPLibraryAfterLockedCapture`, `openTAPLibraryAwaitingLockedImport`, or `openTAPLibrary` from the extension status placeholder. The follow-up `tapAction=openTAPCamera` plus `beginDelayingAppearance` / `endDelayingAppearance` experiment is also recorded as unreliable for saved-placeholder handoff: it still saw `sessionCount=0` during transition and could be followed by next-launch freeze. Keep `openApplication(for:)` for explicit unavailable/regenerate recovery unless a future public API provides transition-complete or migration-complete semantics.
- AppContext 只承载主 App Release camera UI 真正会展示的 enabled lens/FOV options，不承载所有 AVFoundation discovery 结果。例如 LiDAR 可以被 discovery 发现，但如果它没有进入当前镜头选择 UI，就不应因为 locked extension 而单独出现在锁屏 UI。
- AppContext must not carry Debug-only disabled lens/FOV options.
- If there are no enabled lens/FOV records, locked extension must enter visible `unavailable`.
- Locked extension must not add a separate front/back switch beyond the options projected by the main app. It follows the main app Release option records exactly.
- If AppContext is missing, malformed, stale, or contains no enabled lens/FOV records, locked extension must not run full discovery. It enters `unavailable` and offers unlock-to-app via `LockedCameraCaptureSession.openApplication(for:)`.
- `openApplication(for:)` must be triggered by an explicit user action, such as tapping an "Unlock to continue" button. Do not auto-launch the app from `unavailable`.
- If `openApplication(for:)` fails, keep the visible fallback UI and log the launch error.
- AppContext records 不能包含 `AVCaptureDevice`、`AVCaptureDevice.Format`、URL、用户私密路径或主 App 内部对象引用。
- 每个 lens/FOV option record 第一版只投影现有 `FocalLengthOption` 和 `CaptureSelectionContext` 已经表达的 fields：option/display labels、equivalent focal length、RGB source id/type/position、depth source id/kind、zoom id/factor、resolved capture device id/type。
- Do not add a separate format fingerprint in the first version. Add it only if real-device testing proves device/format resolve is unstable.
- Phase 1 may define the full Codable AppContext shape for later capture settings, but it should execute only lens/FOV records, minimum diagnostics metadata, and explicit POC capture defaults. Capture-affecting settings such as full Flash parity, main-app Output Format, Photo Quality, Shutter Sound, and Haptics are completed in Phase 2. Live Photo remains forced off for all POC phases.
- 主 App 用 `CameraCaptureIntent.updateAppContext(...)` 发布 app context。
- locked extension 不做 full `CameraCapabilityResolver.discover()`；它读取 `CameraCaptureIntent.appContext`，按 record 里的 device/format/output/zoom intent 做 narrow resolve 和 validation。
- extension 必须重新验证当前设备仍支持 depth delivery；验证失败时进入可见 `unavailable`，提示解锁进入主 App 刷新。
- 当前 POC 必须显示最小 lens/FOV selector，使用 shared presentation model 和 AppContext enabled records；不需要完整主 App chrome。
- 共享组件长期应收敛为 extension-safe shared module。POC 可先以 shared source layer 组织，同时加入 app target 和 locked extension target；如果改成 embedded framework，framework 必须只包含 extension-safe API，extension target 必须开启 `Require Only App-Extension-Safe API`，并在 Copy Files build phase 使用 `Frameworks` destination。
- 共享组件只能依赖值模型和 closure/adapters，不直接依赖主 App view model、route store、pending store、Photos、App Attest 或 `UIApplication.shared`。
- AppContext also needs to account for app-side camera settings that locked extension cannot read from main app preferences directly.
- Flash startup/current state must be projected into AppContext and applied to locked still-photo capture when supported.
- Live Photo startup state may be projected into AppContext for UI consistency, but POC locked capture must force Live Photo off.
- Output format and photo quality preferences must be projected into AppContext; locked extension must not read main app preferences directly.
- Phase 1 projects output format and photo quality into AppContext but uses fixed Release depth HEIC defaults. Phase 2 executes the synchronized output format and photo quality by resolving `CaptureOutputProfile.releasePhotoDepthProfile(fileContainer:photoQualityLevel:)`.

Settings projection scope:

| Setting | AppContext | POC execution |
| --- | --- | --- |
| Lens/FOV UI options | Required | Used to build locked UI and resolve selected capture path. |
| Flash | Required | Phase 1 fixed off; Phase 2 applies AppContext state when supported. |
| Live Photo | Required | AppContext may carry state; Phase 1 UI does not show it and capture is forced off. Future support requires separate design. |
| Output format | Required | Phase 1 fixed Release depth HEIC; Phase 2 executes AppContext HEIC/JPEG parity. |
| Photo quality | Required | Phase 1 fixed to existing main-app default `.quality`; Phase 2 executes AppContext quality level. |
| Location use | Required | Phase 1 fixed nil; Phase 2 best-effort only with existing authorization, no prompt, no blocking. |
| Microphone use | Required | Recorded only; not used while Live Photo is off. |
| Shutter sound | Required | Phase 1 uses system default and does not suppress; Phase 2 applies AppContext behavior. |
| Haptics | Required | Phase 1 on for shutter feedback; Phase 2 applies AppContext behavior. |
| Guide overlay | Not in POC | Ignore. |
| Viewfinder highlight color | Not in POC | Ignore. |
| Focus magnifier | Not in POC | Ignore. |
| EV / Pro controls | Not in POC | Ignore. |

## Extension 状态机

root view 永远不能为空，不能只剩纯黑背景。状态机至少包含：

| State | Meaning | Required UI |
| --- | --- | --- |
| `starting` | extension 已显示，正在配置 session，还没有可靠首帧。 | 黑色背景、可见状态文字或 spinner、预览容器占位。 |
| `live` | session running，preview layer 已 attach，frame watchdog 持续收到帧。 | viewfinder、shutter、简化状态 UI。 |
| `capturing` | 已触发 shutter，正在等待 photo output / packaging / write。 | viewfinder 保持，shutter disabled，显示 capture progress。 |
| `recovering` | live 后检测到 interruption、runtime error、frame stale 或 preview host 异常，正在重建 session。 | 保持 root UI，可见“相机恢复中”覆盖层，不能纯黑。 |
| `unavailable` | 连续恢复失败、权限不可用、depth pipeline 不可用或系统中断不可恢复。 | 固定 fallback UI，提供“解锁继续”按钮调用 `openApplication(for:)`。 |

状态机事件：

- `scenePhase` 变为 `.active`。
- `scenePhase` 变为 `.inactive` 或 `.background`。
- `AVCaptureSession.wasInterruptedNotification`。
- `AVCaptureSession.interruptionEndedNotification`。
- `AVCaptureSession.runtimeErrorNotification`。
- video data output 收到首帧。
- live 后 frame watchdog 超时。
- preview layer attach / detach 变化。
- capture succeeded。
- capture failed。
- captured photo 缺少 depth data。
- controller/root init 或 deinit。

恢复策略：

- `.active`、interruption ended、runtime error 后统一走 `rebuildSession(reason:)`。
- 重建过程必须先把 UI 状态切到 `recovering`，再停 session、清 graph、重新配置、重新 start。
- 重建失败后进入 `unavailable`，不要继续显示空 preview。
- 不在 SwiftUI `body` 或临时 view 中创建 `AVCaptureSession`、controller、photo output 或 delegates。

### Black Screen Triage Model

The POC treats the historical black screen as a diagnostic problem first. A black screen is not one bug class; logs must let us assign it to one of these layers:

| Suspect layer | Evidence to collect | Recovery / next action |
| --- | --- | --- |
| SwiftUI root lifecycle | root view init/deinit, body visible state, scene init/deinit, `@StateObject` controller identity. | If root/controller deinit unexpectedly, fix ownership and scene/root construction before tuning camera code. |
| Preview host / layer tree | preview host attach/detach, preview layer superlayer, window presence, bounds, opacity, last layout time. | If session is healthy but preview detached or zero-sized, rebuild preview host and keep fallback UI visible. |
| `AVCaptureSession` interruption | `wasInterrupted` reason, `interruptionEnded`, `isRunning`, selected device/format. | Move to `recovering`; after interruption ended or scene active, rebuild session. |
| `AVCaptureSession` runtime error | `runtimeError` notification, `AVError`, `isRunning`, recent configuration event. | Move to `recovering`; rebuild session from a clean graph. |
| Missing first frame / frame stall | session reports running, preview attached, but video data output never delivers a first frame or last frame age exceeds watchdog threshold. | Move to `recovering`; rebuild session. If repeated, enter `unavailable`. |
| Extension process/system termination | app logs stop; Console shows SpringBoard/runningboardd/mediaserverd/ReportCrash events. | Treat as system/framework or lifecycle-budget issue; collect Console logs/sysdiagnose and reduce extension work. |

Scene lifecycle policy:

- `.inactive` / `.background` is not automatically a bug.
- Root UI and controller ownership should remain stable across ordinary scene changes when the process is still alive.
- On inactive/background, log the transition, pause frame watchdog, and stop session if required by system behavior or resource pressure.
- Do not treat inactive/background as permission to render an empty root view.
- On `.active`, show `recovering` and call `rebuildSession(reason: sceneBecameActive)`.
- After rebuild, wait for first frame before returning to `live`.
- If first frame does not arrive within the watchdog threshold, continue the normal recovering/unavailable path.

POC minimum black-screen handling:

- Do not finalize the full product UX for every failure mode in this POC.
- The non-negotiable POC requirement is that the root view must not become a pure black, unexplained screen while the extension shell remains foreground.
- When watchdog/session/preview diagnostics detect a likely failure, the implementation may automatically show `recovering` or `unavailable` without waiting for a user tap.
- The visible state is both user protection and diagnostic evidence: it should say enough to show the extension is alive and logs should say which layer failed.
- There is no public API for the extension to programmatically dismiss itself back to the native lock screen. Natural paths are user/system dismissal or explicit `openApplication(for:)` after user interaction.
- Detailed post-failure UX, retry cadence, and final fallback copy can be redesigned after the POC identifies the dominant black-screen cause.

## 运行期存活性监控

历史问题发生在 `live` 之后，因此需要持续 watchdog，而不是只看启动首帧。

POC 接受加入轻量 `AVCaptureVideoDataOutput`：

- 只用于记录最后一帧时间。
- 不参与成像。
- 不写磁盘。
- 不上传网络。
- 使用独立 video output queue。
- `alwaysDiscardsLateVideoFrames = true`。

watchdog 至少记录：

- first frame timestamp。
- last frame timestamp。
- session `isRunning`。
- current state。
- preview layer 是否仍在 layer tree。
- preview host view 是否仍在 window。
- 当前 scene phase。

初始诊断阈值建议：

- `starting` 后 2 秒没有首帧：进入 `recovering` 并重建 session。
- `live` 中最后一帧超过 1.5 秒且 scene 仍 active：进入 `recovering` 并重建 session。
- 连续 2 次重建失败：进入 `unavailable`。
- 单次恢复总时间超过 8 秒：进入 `unavailable`。

这些阈值是 POC 诊断默认值，不是产品最终值。后续应根据真机日志调整。

## Capture Contract

extension 只允许进入可拍状态，当且仅当：

- 已选择 depth-capable camera/device/format。
- `AVCapturePhotoOutput.isDepthDataDeliverySupported == true`。
- photo settings 启用了 depth delivery。
- output profile 对应 Release depth photo contract。
- Flash mode resolved from AppContext is applied when photo output supports it.
- Location is best-effort with existing authorization only; no permission prompt, no startup wait, and nil must not block capture.
- Shutter sound and haptics follow AppContext.
- Live Photo request is forced off for POC.
- 当前 scene active。
- session running。
- frame watchdog 处于 live。

默认 output profile resolution:

- Phase 1 uses fixed Release depth HEIC profile.
- Phase 1 does not execute full AppContext Output Format / Photo Quality preferences.
- Phase 1 photo quality is fixed to the existing main-app default, `CameraPhotoQualityPreference.defaultValue == .quality`, which maps to `CapturePhotoQualityLevel.quality`.
- Phase 2 resolves from AppContext output format and photo quality.
- Use `CaptureOutputProfile.releasePhotoDepthProfile(fileContainer:photoQualityLevel:)` in both phases.
- Output must remain a Release depth photo profile.
- 默认镜头选择使用现有 depth-capable 发现/规划逻辑，但 UI 不暴露复杂镜头选择。

拍摄成功的最低要求：

- `AVCapturePhoto.depthData != nil`。
- `CapturePackageBuilder.makePackage(...)` 成功。
- `EmbeddedPhotoPackager.package(..., assertionSigner: nil)` 成功。
- 产物是可直接进入主 App pending queue 的 unsigned TAP artifact，不是普通 depth HEIC。
- 产物包含 Apple depth data、TAP manifest、`manifest.payload.id`、empty proof slot、明确 file container 和后续 App Attest 可签名的 unsigned bytes。
- 写入 `sessionContentURL` 成功。
- 写入文件可被主 App 重新读取、解析 manifest、读取 depth data、确认 empty proof slot。

如果 `AVCapturePhoto.depthData == nil`：

- 视为 pipeline invariant failure。
- 不写入 `sessionContentURL`。
- 不入队。
- UI 显示可见失败或恢复状态。
- 日志记录 device、format、depthDeliverySupported、settings、photo output 状态。

## Queue Structure

主 App 现有队列结构是本 POC 的权威参考。不要为 locked capture 发明一套平铺文件命名规则。

### Main App Pending Queue

主 App 当前 pending queue 由 `TAPPendingCaptureStore` 和 `TAPPendingCaptureBundlePathPolicy` 管理。每次普通 shutter capture 进入队列时：

1. `CaptureJob` 创建一个 job UUID，用于 capture/packaging/write diagnostics。
2. `EmbeddedPhotoPackager` 生成 embedded TAP depth photo。
3. `TAPDepthManifestBuilder` 在 photo 内写入 manifest，并生成 `manifest.payload.id`。
4. `TAPPendingCaptureStore.ingest(_:)` 使用 `manifest.payload.id` 作为 durable `captureID`。
5. pending queue 以 `captureID` 为目录名，文件名使用固定语义名。

Current app-private queue layout:

```text
Application Support/
  TAPCaptureLibrary/
    Pending/
      <captureID>/
        bundle.json
        unsigned.heic | unsigned.jpg
        thumbnail.jpg
        signed.heic | signed.jpg        # after App Attest signing succeeds
        paired-video.mov                # Live Photo only; not used by locked POC
```

Important invariants:

- `captureID` is the TAP manifest `payload.id`.
- `packageID` / `CaptureJob.id` is not the durable pending queue ID.
- `bundle.json` is created only by the main app pending store.
- `unsigned.heic` / `unsigned.jpg` is the source for async App Attest signing.
- `signed.heic` / `signed.jpg` is written only after signing succeeds.
- `paired-video.mov` belongs to Live Photo and is out of scope for locked POC.

### Locked Session Content Staging

Locked capture writes into Apple's `LockedCameraCaptureSession.sessionContentURL`, not the main app pending queue. It should mirror the main queue's per-capture directory shape without pretending to be a finished pending bundle.

Locked session content layout:

```text
sessionContentURL/
  <captureID>/
    unsigned.heic | unsigned.jpg
    locked-transfer.json                # optional diagnostics only
```

Locked staging rules:

- Each shutter press creates one independent `<captureID>/` directory.
- `captureID` must come from the embedded TAP manifest `payload.id`.
- The directory name must match the embedded manifest `payload.id`.
- `unsigned.heic` / `unsigned.jpg` must contain Apple depth data, TAP manifest, and empty proof slot.
- `locked-transfer.json` is optional diagnostics only and must not be needed for signing/export.
- `locked-transfer.json` is per-capture metadata only. It is not a continuous runtime log and must not be updated repeatedly as a heartbeat.
- Do not write `bundle.json` inside `sessionContentURL`; the main app importer owns pending record creation.
- Do not write signed files inside `sessionContentURL`; signing happens later in the main app queue.
- Do not invalidate session content from the extension.
- Cleanup follows Apple's migration model: the main app invalidates session content only after successful import into the app-owned pending queue.
- Temporary dry-run/probe logging must not invalidate session content.

### Locked Capture Backpressure

POC should keep the same conservative capture pressure model as the main app: at most 3 in-flight capture jobs inside the locked extension.

This locked-extension count includes only:

- active `AVCapturePhotoOutput` capture work;
- local package/manifest/proof-slot creation;
- atomic write into `sessionContentURL`.

This count does not include:

- capture directories already written to `sessionContentURL`;
- main App `TAPPendingCaptureStore` records;
- App Attest signing jobs;
- Photos export jobs.

When the locked extension reaches the limit:

- shutter input is temporarily disabled or ignored;
- UI shows a visible saving/backpressure status;
- viewfinder remains attached and live;
- hardware capture events are logged as backpressure-limited, not treated as camera failure.

This is a POC stability constraint. Future burst capture can replace this with a dedicated burst policy, but that policy must still keep viewfinder liveness and bounded memory pressure as hard requirements.

### Locked Import

Main app importer reads `LockedCameraCaptureManager` session content and converts locked staging directories into normal pending queue bundles.

Import flow:

1. Scan each session content directory for child directories named like capture IDs.
2. For each child directory, locate `unsigned.heic` or `unsigned.jpg`.
3. Read the photo and decode its TAP manifest.
4. Validate the directory name equals `manifest.payload.id`.
5. Validate file container, Release output policy, depth data, and empty proof slot.
6. Create a normal pending queue bundle through locked-import ingest API.
7. Generate thumbnail in the main app if possible.
8. Keep each capture independent: one failed import must not block other capture directories.
9. Invalidate the Apple session content URL only after all recognizable captures in that session content directory are successfully ingested, or after a future policy explicitly marks unrecoverable items handled.

The locked-import ingest API should be a thin wrapper, for example `ingestLockedCapture(...)`, that produces the same durable queue semantics as `TAPPendingCaptureStore.ingest(_:)` without forcing importer code to fake a full `PackagedCaptureArtifact`.

Wrapper responsibilities:

- input: `sessionContentURL/<captureID>/unsigned.heic` or `unsigned.jpg`;
- parse and validate manifest, file container, depth presence, and empty proof slot;
- generate thumbnail in the main app if possible;
- create the same app-owned pending bundle layout and `.pending` record semantics as the normal capture path;
- return enough result information for importer logging, TAP Library refresh, processor wakeup, and session content invalidation.

Wrapper non-goals:

- no second pending queue;
- no locked-specific signing state;
- no App Attest signing inside the importer;
- no Photos export inside the importer.

Once a locked capture is imported into `TAPPendingCaptureStore`, it is no longer special from the signing queue's point of view. It should have the same `.pending` semantics as a main-app shutter capture and should be processed by the existing `TAPPendingCaptureProcessor` path. Do not add a locked-only signing queue or locked-only signing trigger.

### Async-First Import Policy

Locked import follows the same async-first product rule as App Attest signing:

- Main App camera UI must not wait for locked session content import before becoming usable.
- Main App shutter must not be blocked by locked import unless a future shared resource limit proves it is necessary.
- Existing pending signing/export work must not wait for all locked session content to be imported.
- `LockedCameraCaptureManager.sessionContentUpdates` should schedule import work, not perform heavy parsing or disk moves inline on the UI path.
- Successfully imported captures enter the normal `.pending` signing queue and are processed by `TAPPendingCaptureProcessor`.
- Failed imports keep the original session content in place and log the reason; they do not delete user captures or block other captures.
- Pending list and thumbnails refresh after import completes; they are allowed to lag behind app launch.

### Idempotent Import and Conflict Policy

Locked import must be safe to run repeatedly because `sessionContentUpdates` may replay, the main app may restart, and session content may remain visible until invalidation succeeds.

Idempotency key:

- `captureID = embedded TAP manifest payload.id`.
- The `<captureID>/` directory name must match the embedded manifest id before any ingest attempt.

If the normal pending queue already contains the same `captureID`:

- Re-read enough metadata from the session content photo to validate it is the same capture.
- Confirm file container, manifest id, depth presence, and empty proof slot agree with the existing pending record.
- If consistent, skip duplicate ingest and treat the session content item as already imported.
- If every recognizable capture under that session content URL is imported or already imported, the main app may invalidate that session content URL.

If the same `captureID` maps to different content or incompatible metadata:

- Treat it as an import conflict.
- Do not overwrite the existing pending record.
- Do not delete the session content.
- Log a high-priority `locked.import` conflict event with captureID, container, session content URL identity, and mismatch reason.
- Leave final cleanup to a later explicit policy.

### Import Probe Logging

Phase 1 importer should include probe logging, but probe logging is not a product feature and must not stop the valid import path.

Before ingesting a capture, the importer should log:

- read `LockedCameraCaptureManager.shared.sessionContentURLs`;
- enumerate `<captureID>/unsigned.heic` and `<captureID>/unsigned.jpg`;
- log file size, container, manifest id, depth presence, and empty proof-slot validation;
- prove that photos written by the locked extension are visible to the main app after unlock.

After a valid probe result, the importer should:

- create `TAPPendingCaptureRecord`;
- write into `TAPPendingCaptureStore`;
- leave signing/export to the existing async `TAPPendingCaptureProcessor`;
- invalidate session content only after successful import.

The probe logging itself must not:

- start App Attest signing;
- export to Photos;
- delete session content;
- replace importer validation.

Temporary dry-run is allowed only as an early development diagnostic. It is not Phase 1 acceptance: Phase 1 acceptance requires valid locked captures to enter the main app pending queue after unlock.

## Session Content 文件约定

POC 的权威文件是 unsigned photo 本身。建议目录结构：

```text
sessionContentURL/
  <captureID>/
    unsigned.heic | unsigned.jpg
    locked-transfer.json                # optional diagnostics only
```

JSON 只能作为诊断文件，不参与签名、导出或数据真实性判断。主 App importer 必须从 photo 的 TAP manifest 和文件内容恢复核心事实。

写文件要求：

- 先写临时文件，再原子 move 到最终文件名。
- 文件名不得依赖用户输入。
- `<captureID>` directory name must match embedded manifest `payload.id`.
- 写入完成后记录 byte count、capture ID、depth availability、profile ID、file container、photo quality。
- 写入完成后记录 flash mode and Live Photo disabled state for diagnostics.
- 不在 extension 内 invalidate session content。主 App 成功入队后再调用 `LockedCameraCaptureManager.invalidateSessionContent(at:)`。
- 写入成功后不得自动调用 `openApplication(for:)`。保持 locked camera live，允许继续拍摄。

## Main App Import Contract

主 App importer 应做：

1. 启动时读取 `LockedCameraCaptureManager.shared.sessionContentURLs`。
2. 持续监听 `sessionContentUpdates`。
3. 对每个 session content directory 查找 `<captureID>/unsigned.heic` 或 `<captureID>/unsigned.jpg`。
4. 读取 unsigned photo。
5. 验证 file container、manifest、directory captureID、Release output policy、depth data、empty proof slot。
6. 通过专用 locked-import ingest API 创建等价 `TAPPendingCaptureRecord`，不要伪造完整 `PackagedCaptureArtifact`。
7. 写入 `TAPPendingCaptureStore`，状态为 `.pending`。
8. 每个 capture directory 独立导入；单个失败不阻塞其他 capture directory。
9. 所有可识别 capture directories 成功入队后 invalidate 对应 session content URL。
10. 触发或等待现有 `TAPPendingCaptureProcessor` 签名和导出。
11. 主 App 启动时只发布下一次锁屏入口需要的 AppContext，并启动 App 级长期 `sessionContentUpdates` 监听；不要把 locked import 挂到普通 Library 路由、foreground resume 或 `StartupGateView` 的一次性任务上。
12. Locked import 的 Phase 1 主信号是 `LockedCameraCaptureManager.sessionContentUpdates`，包括 `.initial` 中已有的 session URLs 和后续 `.added`。监听器收到更新后异步调度导入。
13. Camera -> TAP Library normal route should present Library immediately without locked session polling. The Library view owns a normal snapshot load for direct app usage.
14. Phase 1 不再从 locked saved-state placeholder 发起任何 TAP Library handoff。`openTAPLibraryAfterLockedCapture`、`openTAPLibraryAwaitingLockedImport`、`openTAPLibrary` 只保留为兼容解析或未来实验，不由左下角占位符触发；导入仍由 `sessionContentUpdates` 驱动。
15. TAP Library should force a fresh presentation load each time it appears, not only rely on a cached `loadIfNeeded()` snapshot. SwiftUI may keep the Library `StateObject` alive across route changes, and a cached empty snapshot can otherwise survive until a second manual refresh.
16. When locked import adds pending records, post a main-app notification and let the mounted `CameraView` ask `CaptureLifecycleCoordinator` to run the existing pending retry policy. This is a wakeup for the shared queue, not a locked-specific signing path.
17. Main app foreground resume (`scenePhase == .active`) must not scan locked session content by default. Use the long-lived `sessionContentUpdates` scheduler for real locked session updates.

importer 不应在 session content 目录里直接签名，也不应在导入失败时删除用户产物。失败应保留 session content 并记录日志，直到后续重试或人工处理策略明确。

## UI Scope

POC UI 只需要证明流程，不需要完整相机体验：

- 全屏黑色背景。
- live preview。
- 最小 lens/FOV selector。
- shutter button。
- Saved/status placeholder at the same bottom-chrome position as the main camera UI's recent photo button.
- 简短状态文字。
- capture progress。
- recovering overlay。
- unavailable fallback。
- unlock continue button。

不做：

- 深度分析 UI。
- 完整相册 grid/list UI。
- Pro controls。
- Live Photo。
- 网络状态 UI。
- 复杂品牌化界面。

POC copy policy:

- Use a small fixed set of visible status strings.
- Prefer diagnostic clarity over polished marketing copy.
- Keep language consistent with the current project default UI language.
- Do not add full localization in this phase.
- Required state coverage: Preparing, Ready, Saving, Saved, Recovering, Unavailable, Unlock to continue.

Diagnostics-only heartbeat overlay:

- Include a small visible overlay only in DEBUG builds or when an explicit diagnostics flag is enabled.
- Do not ship it as normal Release UI.
- Do not enable it in Release/TestFlight for this POC.
- If TestFlight diagnostics become necessary later, design a separate controlled switch and privacy review.
- Keep it compact and readable over the viewfinder.
- Suggested fields: `state`, `scenePhase`, `isRunning`, `lastFrameAge`, `previewAttached`, `rebuildCount`, and the last characters of `launchID`.
- If the overlay remains visible during a black-screen report, root SwiftUI is still alive and the next suspect is preview/session/frame delivery.
- If the overlay disappears with the viewfinder, prioritize root/controller lifecycle, scene teardown, or extension/system termination.

### Locked TAP Library Affordance

The locked UI should keep the same control layout mental model as the main camera UI:

- Left bottom control is a TAP Library / recent photo placeholder.
- Center bottom control is shutter.
- Right bottom control is only present if the locked POC exposes a real shared option; do not invent extra controls.

For POC, the left placeholder does not read the main app album or pending queue. It reflects locked capture progress:

- `ready`: show the normal placeholder icon, such as `photo.on.rectangle`, with a lock badge if useful.
- `capturing` / `packaging` / `saving`: show a saving/progress icon or spinner.
- `saved`: show a success icon, such as `checkmark.circle.fill`, for a short visible confirmation.
- `failed`: show a failure icon, such as `exclamationmark.triangle.fill`, and keep root UI visible.
- POC does not render a real thumbnail in the locked extension. Real thumbnails appear only after the main app importer creates a pending record and the existing TAP Library thumbnail path refreshes.

Interaction:

- The committed baseline is status-only and exists only as a rollback/negative-control state.
- The target UX requires the left placeholder to call `LockedCameraCaptureSession.openApplication(for:)` from a user tap. E1A uses `tapAction=openTAPLibraryRuntimeImport` and opens TAP Library's awaiting-import state.
- E1A must not call `beginDelayingAppearance()` or run a handoff-time `sessionContentURLs` scan; import readiness still comes from the App-level `sessionContentUpdates` runtime.
- Old saved-state Library/camera handoff actions (`openTAPLibraryAfterLockedCapture`, `openTAPLibraryAwaitingLockedImport`, `openTAPLibrary`, `openTAPCamera`) remain failed or unstable comparison paths, not the current action.
- Do not use URL schemes, `UIApplication.open`, or another app-launch workaround from inside the locked extension to simulate "dismiss first, then open TAP Library". Publicly supported extension-to-app handoff remains `LockedCameraCaptureSession.openApplication(for:)`.
- `LockedCameraCaptureManager.beginDelayingAppearance()` and `endDelayingAppearance()` are transition-delay APIs, not session-content migration completion APIs. Do not recreate transition waiting with TAP Library route polling.
- After save, the locked extension keeps the viewfinder live; the user may continue shooting or naturally dismiss/unlock through the system.
- Main app import readiness comes from the App-level `sessionContentUpdates` runtime. When the main app opens and Apple has exposed session content, the importer should ingest captures into the normal pending queue before or during the next Library refresh.
- A retained TAP Library view model must refresh on each presentation. `loadIfNeeded()` remains useful for cached model tests, but the product route should call a presentation load that rebuilds the item snapshot after app-level locked import has added pending records.
- After locked import creates pending records, the main app should wake the existing pending worker through the same lifecycle-coordinated pending retry policy used by normal captures and foregrounding.
- Signing/export remains asynchronous after the capture enters `TAPPendingCaptureStore`; the synchronous part is only the local import from Apple's session content into the app-private pending queue.
- The unavailable/fallback unlock button is separate: it uses `tapAction=regenerateLockedCameraContext` and routes to camera preparation instead of forcing TAP Library.
- The locked extension must not auto-open the app after save; only explicit user actions such as tapping the placeholder or unavailable fallback may call `openApplication(for:)`.

Historical reference:

- `lockScreen_test:TAPCamDemoLockedCapture/TAPCamLockedCaptureViewFinder.swift` already had a left locked-album placeholder with progress icons.
- Current main UI uses `CameraCaptureControlsView.recentPhotoButton` for the same bottom-left TAP Library affordance.
- The POC may reuse the interaction idea, but should not bring back the full historical locked UI architecture wholesale.

## Hardware Capture Events

可见 capture view 必须处理硬件 capture event。

实现选项：

- UIKit preview host 上安装 `AVCaptureEventInteraction`。
- 或 SwiftUI root 使用 camera capture event modifier。

行为：

- enabled 只在 `live` 且 `canCapture == true` 时为 true。
- primary event ended 触发 capture。
- capture 不可用时禁用 interaction，让系统默认行为恢复。
- 事件收到、忽略、执行 capture 都要打日志。

## Launch Probe Contract

POC 必须优先打通真实 Control Widget 启动链路，而不是用 direct launch smoke 代替验收。为排查“组件可见但点击无法启动 extension”，必须在启动链路上放置探针日志。

Required probes:

- Control Widget provider/body 初始化。
- Control Widget button action 绑定的 intent type。
- `CameraCaptureIntent.perform()` begin/end/error。
- `CameraCaptureIntent.appContext` read/update begin/end/error。
- Locked Camera extension `@main` init/body。
- `LockedCameraCaptureUIScene` content closure invoked。
- root view init。
- root view first body appearance。
- camera controller init。
- state transition to `starting`。
- first attempt to configure session。

Logging mechanics:

- Primary mechanism is structured `OSLog`.
- DEBUG builds may mirror critical launch probes to `print` for immediate Xcode console visibility.
- Fixed locked-camera subsystem: `TAP-NAP.TAPCamDemo`. App, control widget, and
  capture extension locked-camera probes must use this same subsystem instead
  of each target's bundle identifier.
- Suggested categories: `locked.launch`, `locked.lifecycle`, `locked.camera`, `locked.capture`, `locked.import`.
- Generate a `launchID` for each real Control Widget / `CameraCaptureIntent` launch chain.
- Pass `launchID` through `CameraCaptureIntent.AppContext` when available.
- If app context is unavailable, log `launchID unavailable` explicitly instead of silently dropping correlation.
- Logs are optimized for future Agent diagnosis, not human-facing UI.
- Implement logging through a small extension-safe diagnostics helper instead of scattering raw `Logger(subsystem:category:)` calls and stringly typed probe names.
- The helper should live in the shared source layer and be target-membered into app, control widget, and locked extension.
- The helper may define fixed categories plus lightweight `LockedCaptureLaunchID` and `LockedCaptureProbeEvent` value types.
- The helper must not write files, upload telemetry, access App Group, or reference app-only APIs.

Launch-chain acceptance:

- 真实锁屏或 Control Center 入口点击后，日志能显示 intent 是否执行。
- 如果 intent 执行但 extension scene 没起来，问题集中在 intent-to-extension handoff / target metadata。
- 如果 scene closure 执行但 root view 不显示，问题集中在 SwiftUI root / scene lifecycle。
- 如果 root view 显示但 camera controller 不启动，问题集中在 controller ownership 或 task scheduling。
- direct launch 只能用于排错，不作为 POC 验收通过条件。

Real-device smoke boundary:

- For this POC, the real-device evidence baseline is a build installed and run
  from Xcode by the user. That preserves the Xcode console/logging path used for
  lock-screen extension diagnosis.
- Codex should not install or launch the app on the phone after code changes.
  Codex should run local compile/tests when useful, update docs/trace, and
  state which log probes to inspect in the next manual smoke.
- The secure lock-screen control tap remains manual. Treat the user's exact
  hand-test steps and timestamps as the acceptance input.

## 日志和诊断

必须使用统一 subsystem/category。日志要能回答黑屏前发生了什么。

Every black-screen report should be classifiable as one of: root/controller released, preview detached, session interrupted, runtime error, running-without-frames stall, or process/system termination. If logs cannot make that distinction, the POC diagnostics are incomplete.

Diagnostics overlay visibility should also be logged when enabled so visual observations can be matched with Console output.

Do not add a continuously updated local diagnostic log file inside the locked extension. Continuous file logging increases IO, power, and lifecycle risk in the exact surface being tested. Use `OSLog`, Console/sysdiagnose, and the diagnostics overlay for runtime forensics. `locked-transfer.json` remains optional per-capture metadata only.

extension 必打点：

- extension scene init。
- extension scene deinit。
- root view init/deinit。
- camera controller init/deinit。
- session configure begin/end。
- session start/stop begin/end。
- selected device、format、depth support。
- photo output depth support。
- first frame。
- last frame stale。
- preview host attached/detached。
- preview layer superlayer/window 状态。
- scene phase change。
- state transition。
- `AVCaptureSession.wasInterruptedNotification`，包括 reason。
- `AVCaptureSession.interruptionEndedNotification`。
- `AVCaptureSession.runtimeErrorNotification`，包括 `AVError`。
- shutter event。
- capture begin/end, including flash mode and Live Photo disabled state。
- photo depth present/missing。
- packaging begin/end。
- sessionContentURL write begin/end。
- saved state shown without auto-launching the main app。

主 App importer 必打点：

- manager initial URLs。
- session content added/removed。
- file discovered。
- file validation success/failure。
- pending store ingest success/failure。
- invalidate session content success/failure。
- processor start/sign/export result。

真机排查时 Console/Xcode Devices 过滤：

- extension process name。
- app process name。
- TAPCam subsystem。
- SpringBoard。
- runningboardd。
- mediaserverd。
- camera。
- ReportCrash。

黑屏后立刻记录精确时间戳、iOS build，并抓 sysdiagnose。

## 验收标准

基础启动：

- 锁屏上可以找到 TAPCam control。
- 点击 control 后启动 Locked Camera Capture extension。
- extension 首屏不是空白或纯黑。
- extension 尽快显示 viewfinder。
- root UI 日志显示 controller/session 没有意外 deinit。

live 稳定性：

- viewfinder 进入 live 后 watchdog 持续收到帧。
- 静置测试中，UI 不退化为纯黑。
- 触发 interruption 或 runtime error 后，状态机进入 `recovering`，并显示可见 overlay。
- 不可恢复时进入 `unavailable`，仍然显示可见 fallback。

First-stage real-device soak test:

- Launch the locked extension from the real lock-screen/control path.
- Wait for `live` and first frame.
- Leave it visible and idle for 5 minutes.
- During those 5 minutes, the UI must not become a pure black unexplained screen.
- If interruption, runtime error, preview detach, or frame stall happens, the UI must show `recovering` or `unavailable` and logs must classify the cause.
- Capture at least 3 real photos during the 5-minute run, covering `AVCapturePhotoOutput`, depth presence, unsigned artifact creation, `sessionContentURL` write, saving, saved, and return-to-live behavior.
- After unlocking into the main app, valid locked captures must be imported into the main app pending queue. Signing/export remains asynchronous and must not block the locked-capture acceptance path.
- Dismiss and relaunch from the lock screen 3 times, verifying launch path, first frame, and controller lifecycle logs each time.
- If the first 5-minute run cannot reproduce the historical issue, a later long-run pass can extend the soak window to 15 minutes.

Current attended smoke checklist:

1. User installs/runs the current build from Xcode.
2. User opens the main app once and confirms ordinary capture still works.
3. User locks the iPhone.
4. User launches TAPCam from the lock-screen control.
5. Observe whether the extension root appears, whether a status overlay is visible, and whether the viewfinder reaches live.
6. If the surface freezes or turns black, record whether any TAPCam text/overlay is still visible. Visible overlay points to preview/session/frame delivery; no overlay points to root/lifecycle/process handling.
7. Capture one real photo with the on-screen shutter or hardware capture event.
8. Confirm the locked UI shows a saved state and returns to live.
9. Baseline smoke: validate the natural dismiss/unlock path, then open TAP Library and confirm the App-level importer has brought in the new pending item. It should not require a second locked-extension launch to make the previous photo appear.
10. Do not perform saved-placeholder handoff as a Phase 1 success path. If a compatibility build still allows it, treat it as a diagnostic experiment only; logs should prove whether `open_application_call`, `locked_camera_transition_delay_begin`, `locked_camera_transition_delay_end`, and any later `session_content_update kind=added` occurred.
11. If the diagnostic handoff path freezes, check whether `locked_camera_transition_delay_end` is missing; if import appears late, check whether `session_content_update kind=added` arrived after the delay ended.
12. If capture or import fails, preserve the Xcode/Console log window and exact visible state before retrying.

拍摄：

- 锁屏状态下点击 shutter 可以 capture。
- 硬件 capture event 可以触发 capture。
- 无需解锁即可写入 `sessionContentURL`。
- captured photo 必须包含 depth data。
- 缺少 depth data 时不写文件、不入队。

导入和签名：

- 主 App 启动后 importer 发现 session content。
- unsigned TAP depth artifact 进入 `TAPPendingCaptureStore`。
- pending record 状态为 `.pending`。
- 现有 `TAPPendingCaptureProcessor` 可以签名。
- 签名后可以导出 Photos。
- session content 只在成功入队后 invalidate。

诊断：

- 如果再次出现 live 后黑屏，日志可以区分：
  - session interruption。
  - runtime error。
  - video frames 停止。
  - preview layer 脱离 layer tree。
  - SwiftUI root/controller 被释放。
  - extension 进程被系统终止。

## 实施顺序

Phase 1: Launch, live preview, minimal capture/import, and black-screen diagnostics.

1. 新建最小 shared intent target/source，定义最小 `CameraCaptureIntent` 和 launch probes。
2. 新建最小 Control Widget target/source，提供锁屏入口，并记录 widget/action probes。
3. 新建最小 Locked Camera Capture extension target/source，加入 extension scene/root UI/controller probes。
4. 通过真实 Control Widget / `CameraCaptureIntent` 启动链路验证 probe sequence，定位“点击无法启动”所在边界。
5. 实现主 App locked camera app context 生成：把现有 `focalLengthOptions()` 投影成 extension-safe Codable records，并通过 `CameraCaptureIntent.updateAppContext(...)` 发布。Phase 1 可以定义 Flash/Live Photo/output/photo quality 等字段，但 extension 只执行明确 POC capture defaults。
6. extension 读取 app context，并对 selected lens/FOV record 做 narrow resolve/validate。
7. 接入最小 `AVCaptureSession + AVCaptureVideoDataOutput`，实现 `starting -> live`。
8. 接入 preview host 和 hardware capture event。
9. 实现 state machine、watchdog、session notification logging。
10. 实现 diagnostics-only heartbeat overlay。
11. 接入 `AVCapturePhotoOutput`，使用 POC capture defaults：Release depth HEIC、photo quality `.quality`、Flash off、Live Photo forced off、location nil、shutter haptics on、system default shutter sound、no App Attest、no Photos、no network。
12. 接入 fixed Release depth HEIC still output profile，使用现有 Release profile default photo quality，并要求 captured photo 包含 depth data。
13. 主 App 导入阶段复用 `TAPCaptureProvenanceWriter.writeManifest(...)`，把 locked staging HEIC 升级为含 TAP manifest 和 empty proof slot 的 unsigned TAP artifact。
14. extension 写 `sessionContentURL/<captureID>/unsigned.heic` staging；主 App importer 成功升级并入队后再 invalidate session content。
15. Phase 1 shutter/hardware event 执行真实 capture：进入 `capturing`，记录 capture/photo/package/write 阶段，显示 saving/saved，并回到 `live`。
16. 实现主 App locked importer 的最小入队路径：读取 `LockedCameraCaptureManager.sessionContentURLs`，记录 session content 可见性和 unsigned photo 基本校验，通过 thin wrapper `ingestLockedCapture(...)` 把 valid capture 写入 `TAPPendingCaptureStore`，状态为 `.pending`；后处理复用主 App普通拍照入队后的同一 processor 入口，不增加 locked-only signing 机制。
17. 成功导入 pending queue 后，主 App 调用 `LockedCameraCaptureManager.invalidateSessionContent(at:)` 清理对应 session content。
18. 完成 Phase 1 真机验证：真实锁屏启动、first frame、5 分钟 soak、至少 3 次真实 capture、主 App 解锁后入 pending queue、3 次 relaunch、无纯黑无解释 UI，或能明确归因。

Phase 1 execution checklist:

- [x] Create fresh minimal targets/sources: `TAPCamLockedCameraIntents`, `TAPCamLockedCameraControlExtension`, and `TAPCamLockedCameraCaptureExtension`.
- [x] Embed control and locked capture extension products into the main app with the correct app-extension destinations.
- [x] Keep deployment target at the current project value, `18.6`, and avoid Phase 1 iOS 26-only API.
- [x] Implement `CameraCaptureIntent` and app context model with launch/probe logging.
- [x] Implement static Control Widget entry that invokes the locked camera capture intent.
- [x] Implement locked extension scene/root UI that is always visible.
- [x] Add long-lived `@StateObject` camera controller with explicit `starting`, `live`, `capturing`, `recovering`, and `unavailable` state.
- [x] Add preview host, `AVCaptureSession`, `AVCaptureVideoDataOutput`, frame heartbeat, and session notification logging.
- [x] Add hardware capture event handling with a visible capture button.
- [x] Add POC still capture path: HEIC, `.quality`, Flash off, Live Photo off, no location, no App Attest, no Photos, no network.
- [x] Keep importer recognition for legacy diagnostic `sessionContentURL/captures/<captureID>/photo.heic`, but do not use it as the current extension write path.
- [x] Require captured photo depth data before accepting the capture.
- [x] Write locked depth HEIC staging into `sessionContentURL/<captureID>/unsigned.heic` with `metadata.json`.
- [x] Package the locked capture as an unsigned TAP depth artifact during main-app import instead of sending raw POC HEIC into pending.
- [x] Embed TAP manifest and empty proof slot before treating `unsigned.heic` as a final TAP artifact for pending ingest.
- [x] Add main app AppContext publisher from existing enabled lens/FOV options.
- [x] Add main app locked session content importer skeleton.
- [x] Add pending queue ingest wrapper for final locked unsigned TAP artifact handoff; direct calls still reject depth HEIC staging before final artifact packaging.
- [x] Keep the locked saved-state placeholder lightweight and no-Library-handoff. Unavailable fallback still uses `regenerateLockedCameraContext`; the saved-state `openTAPCamera` experiment is now recorded as unreliable and should not be the Phase 1 success path.
- [x] Start a main App-level locked import runtime so `sessionContentUpdates` `.initial` / `.added` events import captures without relying on a Library route or second lock-screen launch.
- [x] Add focused simulator-safe tests for path policy, importer layout recognition, and pending-store ingest.
- [x] Add focused simulator-safe tests for AppContext projection and state-machine behavior.
- [x] Run `xcodebuild build-for-testing` and record compile evidence.
- [ ] Complete separate real-device lock-screen launch/capture/black-screen soak validation.

Phase 1 implementation checkpoint, 2026-07-06:

- New targets are wired into `TAPCamDemo.xcodeproj`: `TAPCamLockedCameraCaptureExtension` as an ExtensionKit secure capture extension, `TAPCamLockedCameraControlExtension` as a WidgetKit control extension, and `TAPCamLockedCameraIntents` as shared source for the main app and both extensions.
- The main app publishes `TAPCamLockedCameraContext` from the existing `CapabilityMatrix.focalLengthOptions()` path. The extension does only narrow device validation from recorded values; it does not recompute the full capability matrix.
- The locked extension has an always-visible SwiftUI root, a long-lived `@StateObject` controller, preview host, AppContext-backed lens/FOV selector, `AVCaptureEventInteraction`, session interruption/runtime-error observers, frame heartbeat, preview-layer state logging, and a watchdog that routes missing-first-frame/frame-stall failures through `recovering` with a bounded retry count before visible `unavailable`.
- The current shutter path requires `AVCapturePhoto.depthData`, uses Release-style HEIC photo settings (`isDepthDataDeliveryEnabled`, `embedsDepthDataInPhoto`, filtered depth, `.quality`), and writes `unsigned.heic` plus `metadata.json` under `LockedCameraCaptureSession.sessionContentURL/<captureID>/`.
- The extension-written `unsigned.heic` starts as a locked depth HEIC staging file. It has Apple auxiliary depth but is not allowed into pending until the main App importer upgrades it.
- The main app importer now recognizes direct `<captureID>/unsigned.heic` session content and legacy `captures/<captureID>/photo.heic` diagnostic content. For `locked-depth-heic-staging`, it re-reads actual depth, builds a minimal Release-policy TAP manifest, calls `TAPCaptureProvenanceWriter.writeManifest(...)` to embed the manifest and empty proof slot, writes the final `locked-unsigned-tap-artifact` bytes into an app-owned temporary import file, and then imports that file into pending. The Apple session content remains read-only until successful `invalidateSessionContent`.
- `TAPCamDemoApp` owns a `@StateObject` `LockedCaptureSessionContentImportRuntime`, matching the historical working branch pattern. The runtime runs `LockedCaptureSessionContentImportScheduler` over `LockedCameraCaptureManager.sessionContentUpdates`, so `.initial` and `.added` session-content events schedule background import work outside `StartupGateView` and outside TAP Library routing.
- The pending queue has a locked-import wrapper that writes final locked unsigned TAP artifacts into the same `TAPPendingCaptureStore` bundle tree with `.pending` status. The wrapper still rejects raw staging markers if called directly, so the pending processor does not try to sign a file that lacks a TAP manifest and empty proof slot.
- Simulator build evidence: `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/TAPCamDemoDerivedDataLockedPOC` passed. Remaining warnings are pre-existing Swift 6 migration warnings outside the locked camera POC files.
- Focused simulator test evidence: `xcodebuild test -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/TAPCamDemoDerivedDataLockedPOC -only-testing:TAPCamDemoTests/TAPLockedCameraSessionContentTests` passed. It covers the shared direct path policy, direct plus legacy importer layout recognition, final-marker pending-store ingest into the same pending bundle semantics, duplicate locked ingest returning the existing pending record, rejection of raw staging captures at the pending-store boundary, AppContext projection from enabled main-app FOV options, locked extension lens/FOV selector source boundaries, startup scheduling of `sessionContentUpdates`, shared lock-camera UI state visibility/capture gates, and metadata persistence of the resolved capture-device position.

Phase 1 visibility checkpoint, 2026-07-07:

- User-observed issue: captures taken inside the locked extension eventually appeared in TAP Library, but not on the first main-app/library entry. This made the flow feel like locked captures were lost until the user left and re-entered the library.
- Root cause in the POC implementation: Startup ran `publishCurrentContextIfAvailable()` before import, TAP Library could load its first `DepthAlbumItemProvider` snapshot without awaiting locked session content import, and the camera route could present Library before the manual/open-handoff import task finished. A retained `DepthAlbumPickerViewModel` could also keep a cached empty snapshot across route changes.
- First attempted fix: add a small `LockedCaptureSessionContentImportCoordinator` actor to coalesce explicit locked import requests. This reduced duplicate scans, but the latest device logs proved the immediate Library handoff still ran before Apple exposed `sessionContentURLs`.
- 2026-07-07 device-log follow-up: user-provided logs showed `locked_camera_session_import_begin reason=tap_library_load sessionCount=0`, with `locked_camera_handoff` / `locked_camera_handoff_route` coalescing into the same empty import. This means the first-entry Library miss was not just a stale UI snapshot: the main app was running the importer before Apple had exposed any `LockedCameraCaptureManager.sessionContentURLs`. The same logs showed repeated `scene_active` imports followed by repeated `locked_camera_context_published`, making active-phase context publication a likely contributor to the first lock-screen-control presentation shrink/freeze.
- Follow-up fix: `scene_active`, normal app launch, and normal TAP Library open no longer scan locked session content. The App-level import runtime listens to `sessionContentUpdates`; TAP Library routing is not an import trigger.
- Reassessment after the late-poll logs: repeated `_late_poll sessionCount=0` proves that the missing-photo problem is not solved by making TAP Library wait longer or by delaying the main-app appearance. Apple's SDK says `sessionContentURL` is copied to the containing app's data container when the extension is suspended, so Phase 1 no longer uses immediate locked-placeholder `openApplication(for:)` as the transfer proof. The next investigation target is whether the extension actually reaches `photo_capture_saved`, then later produces `locked_camera_session_content_update kind=added`.
- Queue wakeup fix: when `LockedCaptureSessionContentImporter` imports at least one capture, it posts `.tapCamLockedCaptureImportDidAddPendingCaptures`; mounted `CameraView` responds by calling `retryPendingCapturesAfterLockedImport()`, which goes through `CaptureLifecycleCoordinator.retryPendingCaptures(...)` and the existing `TAPPendingCaptureProcessor`.
- Handoff finding: extension `openApplication(for:)` no longer targets TAP Library from the left placeholder. Unavailable UI passes public-safe `tapAction=regenerateLockedCameraContext`. The left saved-state `openTAPCamera` experiment also remained unreliable after smoke, so saved-placeholder app handoff is no longer a Phase 1 success path.
- 2026-07-07 physical-device checkpoint: `xcodebuild build` passed against iPhone device id `00008130-001A4CEE26D0001C`; `xcodebuild build-for-testing` passed for `generic/platform=iOS`; `devicectl device install app` installed bundle id `TAP-NAP.TAPCamDemo`. `devicectl device process launch` still failed while the phone was locked, so the next attended smoke step is manual unlock, open app once, then lock-screen/control launch and capture.
- Verification: `xcodebuild build -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TAPCamDemoDerivedDataLockedDevice` passed. Built app contains `TAPCamLockedCameraCaptureExtension.appex` under `Extensions` with `EXExtensionPointIdentifier = com.apple.securecapture`, and `TAPCamLockedCameraControlExtension.appex` under `PlugIns` with WidgetKit extension point. `git diff --check` passed.
- Device-SDK test compile evidence: `xcodebuild build-for-testing -project TAPCamDemo.xcodeproj -scheme TAPCamDemo -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TAPCamDemoDerivedDataLockedDeviceTests -skip-testing:TAPCamDemoUITests` passed after the foreground settled-import change, compiling the updated test sources without launching a simulator.
- Real-device install/smoke status: device discovery and direct install now work with device id `00008130-001A4CEE26D0001C`; latest Debug-iphoneos build installs successfully as bundle id `TAP-NAP.TAPCamDemo`. `devicectl device process launch` is currently denied by SpringBoard because the phone is locked, so attended smoke resumes after manually unlocking the phone once and letting the main app launch.
- 2026-07-07 follow-up device status: `xcrun devicectl list devices` first listed `harold_android` / iPhone 15 Pro (`8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`) as `unavailable`, then later as `connected`. After reconnect, `xcodebuild build -destination id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7` passed, `devicectl device install app` installed bundle id `TAP-NAP.TAPCamDemo`, and `devicectl device process launch --terminate-existing TAP-NAP.TAPCamDemo` launched the main app successfully. `devicectl device info lockState` reported `unlockedSinceBoot: true`.
- Follow-up capture-default hardening: locked still capture now explicitly sets `AVCapturePhotoSettings.flashMode = .off` and logs `photo_capture_poc_defaults` with `fileContainer=heic`, `photoQuality=quality`, `flashMode=off`, `livePhotoForcedOff=true`, `location=nil`, `appAttest=false`, `photos=false`, and `network=false`. This makes the Phase 1 capture defaults auditable in device logs instead of relying on implicit AVFoundation defaults.
- Latest connected-device reinstall: after the capture-default hardening, `xcodebuild build -destination id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7` passed, `devicectl device install app` reinstalled `TAP-NAP.TAPCamDemo`, and `devicectl device process launch --terminate-existing TAP-NAP.TAPCamDemo` launched the main app successfully.
- Built-app inspection after the connected-device install: the app contains `PlugIns/TAPCamLockedCameraControlExtension.appex` and `Extensions/TAPCamLockedCameraCaptureExtension.appex`; the secure capture extension declares `EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.securecapture`; the control extension declares `NSExtensionPointIdentifier = com.apple.widgetkit-extension`; main-app entitlements include `com.apple.developer.devicecheck.appattest-environment = development`.
- 2026-07-07 over-heavy-path follow-up: normal app launch, `scene_active`, and
  manual TAP Library entry no longer trigger locked session content scans.
  Locked import is now driven by `LockedCameraCaptureManager.sessionContentUpdates`
  from the App-level runtime; the old one-shot locked handoff route flag is not
  the Phase 1 capture-success path. The physical-device smoke baseline is
  user-installed Xcode run output, not Codex `devicectl` installation.
- Validation after the over-heavy-path follow-up: `git diff --check` passed,
  `xcodebuild build-for-testing -destination 'generic/platform=iOS'` passed,
  `xcodebuild build -destination id=8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`
  passed, `devicectl device install app` installed `TAP-NAP.TAPCamDemo`, and
  `devicectl device process launch --terminate-existing TAP-NAP.TAPCamDemo`
  launched the main app. Built product inspection again confirmed
  `com.apple.securecapture` for the locked capture extension and
  `com.apple.widgetkit-extension` for the control extension.
- Remaining real-device gap: attended lock-screen/control smoke still needs user-side interaction: lock the iPhone, launch the locked camera control, wait for first frame/live UI, capture at least one depth photo, dismiss/unlock/open the main app naturally, and confirm the new pending item appears through the App-level import runtime rather than after a second locked-extension launch.
- Watchdog hardening: `LockedCaptureCameraController` now records when it begins waiting for the first frame. If no first frame arrives within the watchdog threshold, it logs `first_frame_watchdog_waiting`, enters `recovering`, rebuilds the session, and after the bounded retry limit logs `frame_watchdog_recovery_attempt` and moves to visible `unavailable` instead of waiting forever on a dim/black preview.
- Separate user-observed issue to validate on device: when the phone is not actually locked, pulling down to Notification Center and launching the locked camera extension can make the notification/lock surface shrink and then hang. Treat this as a distinct presentation/lifecycle scenario from the historical post-live black screen. Required evidence is scenePhase, root init/body, extension process lifetime, preview layer state, and whether `LockedCaptureCameraController.handleScenePhase(_:)` sees a clean active transition.

Default manual smoke flow for the locked-camera POC:

1. Open the main app once.
2. Lock the device.
3. Launch the locked extension.
4. Capture one photo.
5. Manually unlock and enter the main app.
6. Check TAP Library.
7. Lock the device again.
8. Launch the locked extension again.
9. Capture one photo.
10. Tap the lower-left status placeholder.
11. Check TAP Library.
12. Lock the device again.
13. Launch the locked extension again and check whether freeze occurs.

Counter interpretation for that flow:

- `sessionCount` / `sessionURLCount` means
  `LockedCameraCaptureManager.shared.sessionContentURLs.count`. It is the
  number of Apple-exposed session directories at that moment.
- `captureProbeCount` means the importer found current-POC capture directories
  with readable `metadata.json`. It is closer to "how many locked captures can
  be imported".
- `flatHEICFileCount` is the historical-transfer counter candidate for
  `TAPCam-<UUID>.heic` flat files.
- `visiblePendingCount` means the app-owned pending queue contains records that
  TAP Library should be able to render even before signing/export succeeds.
- `itemSources=pending:X|owned:Y|photos:Z` means the first Library snapshot has
  actually merged pending queue records and Photos assets into UI items.

Current experiment sequence:

| ID | Experiment | Operation | Pass signal | Fail signal | Next step |
| --- | --- | --- | --- | --- | --- |
| E1 | Status-only placeholder baseline | Capture in locked extension; tap lower-left placeholder once; manually dismiss/unlock/open main app; relaunch locked extension. | Log shows `locked_album_placeholder_tapped_status_only`, no `open_application_call`, later `session_content_update kind=added`, Library `itemSources` gains the pending capture, and next launch does not freeze. | Freeze still occurs, or no `session_content_update` after manual dismiss/unlock. | Keep as rollback/negative-control state, not target UX. |
| E1A | Direct-open with runtime import | Capture in locked extension; tap lower-left placeholder; main app opens TAP Library awaiting import. | Log shows `open_application_call tapAction=openTAPLibraryRuntimeImport`, then main app `locked_camera_transition_delay_skipped`; no handoff-time `locked_camera_transition` import; later `session_content_update kind=added` imports and Library refreshes. | Next locked launch freezes, or `sessionContentUpdates` never arrives/imports. | This validates the historical runtime-import lifecycle only, not the historical flat-HEIC transfer layout. |
| E2A | Historical flat-HEIC transfer | Extension writes flat `TAPCam-<UUID>.heic` unsigned TAP artifact directly in `sessionContentURL`; importer enumerates actual HEIC files. | `flatHEICFileCount > 0`, importer imports by HEIC file count, Library shows pending item on first manual open. | HEIC appears only after a second lifecycle turn. | This validates the `lockScreen_test` data-transfer strategy. |
| E2B | Historical flat-HEIC transfer plus direct open | E2A data layout plus E1A `openTAPLibraryRuntimeImport` handoff. | Direct-open UX works while importer still counts actual HEIC files and invalidates after import. | Same delayed visibility/freeze as current staging layout. | If E2B fails like E1A, the dominant issue is direct-open lifecycle, not current staging bundle. |
| E3 | Launch-only freeze isolation | Launch locked extension, do not capture, do not tap placeholder, dismiss, repeat three times. | No freeze; root/first-frame probes appear each time. | Freeze occurs without capture or handoff. | Investigate control intent, secure-capture scene, root/controller lifecycle, and camera start independently of data transfer. |
| E4 | Unavailable-only openApplication | Force missing/invalid AppContext, tap explicit unavailable unlock button. | App opens and context republish runs; no saved session content is involved. | App open or next launch freezes. | `openApplication(for:)` itself is unsafe in this integration, not only saved-placeholder handoff. |
| E5 | Extension log visibility audit | During E1/E3, Console/Xcode filter fixed subsystem `TAP-NAP.TAPCamDemo` and extension process. | Extension logs include `locked_camera_scene_content_invoked`, `locked_camera_root_init`, `photo_capture_saved`, and status tap logs. | Only main-app logs appear. | Fix logging capture/filtering before further lifecycle conclusions. |

Flow matrix for the current delayed-import/freeze investigation:

| Flow | User action | Expected system/content behavior | What the latest logs showed | Interpretation | Next evidence needed |
| --- | --- | --- | --- | --- | --- |
| A. Capture, then tap locked placeholder using E1A | This is the current direct-open/runtime-import experiment. | Placeholder calls `openApplication(for:)` with `tapAction=openTAPLibraryRuntimeImport`; the main app opens TAP Library awaiting import, skips transition-delay import, and waits for App-level `sessionContentUpdates`. | Older actions failed differently: `openTAPLibraryAfterLockedCapture` produced `sessionCount=0` late-poll timeouts; `openTAPLibraryAwaitingLockedImport` still showed an empty first Library entry; pure `openTAPLibrary` still delayed import and left the next locked-extension launch prone to freeze. | E1A tests whether direct-open can work when handoff-time import/delay is removed. It does not test the historical flat-HEIC transfer layout. | Look for `openTAPLibraryRuntimeImport`, `locked_camera_transition_delay_skipped`, later `session_content_update kind=added`, and no next-launch freeze. |
| A2. Capture, then tap locked placeholder to open app camera/default | This was the follow-up public-API experiment after rejecting direct Library handoff. | Main app receives `NSUserActivityTypeLockedCameraCapture`, routes to camera/default, calls `beginDelayingAppearance()` for `reason=saved`, runs one bounded `locked_camera_transition` settle/import, then calls `endDelayingAppearance()`. | Latest smoke still saw `locked_camera_transition ... sessionCount=0`; the user still did not get reliable immediate Library visibility, and the next locked launch could freeze. | The issue is not only "Library as first destination". `openApplication(for:)` plus transition delay still is not a migration-complete boundary. | Treat saved-placeholder `openTAPCamera` as a failed diagnostic path. Keep app handoff only for explicit unavailable/regenerate recovery until Apple exposes a public migration/transition-complete API. |
| B. Capture, dismiss locked UI without opening main app, then open main app later | Extension writes session content and is allowed to suspend/dismiss before the containing app imports. | `sessionContentUpdates` should emit `.initial` or `.added`; importer should ingest without a Library-route poll. | Latest successful log showed `locked_camera_session_content_update kind=added`, `sessionCount=2`, two staging packages, two pending ingests, and `imported=2 skipped=0 failed=0 invalidated=2`. | This is now the confirmed Phase 1 transfer model for this operation. | Repeat this path to check stability; if it stays stable, remaining work is first-tap freeze classification and extension-side log visibility. |
| C. Launch locked extension again after a previous capture | System may finish/migrate previous session content while setting up the new secure capture surface. | This should no longer be required for import. | Latest log showed a later launch/handoff with `sessionCount=1`, `kind=added`, package success, pending ingest success, invalidate success. | The previous POC depended on a second lock-screen round trip to expose content, which is not acceptable. | Check whether App-level runtime logs `locked_camera_session_content_update kind=initial/added` on first main-app open after capture. |
| D. First lock-screen control tap after main app run | Control widget starts `CameraCaptureIntent`, then secure capture scene/root should appear. | Logs should show `locked_camera_intent_perform`, `locked_camera_scene_content_invoked`, `locked_camera_root_init`, then controller start. | Latest pasted logs did not include these extension-side probes. User saw shrink/freeze before usable UI. | Freeze is still unclassified: it may be before intent, between intent and scene, inside scene/root, or during camera start. | Locked-camera logs now use one fixed subsystem, `TAP-NAP.TAPCamDemo`; next Xcode smoke should filter for `locked_camera_` and verify which probe is the last visible one. |
| E. Main app TAP Library opened normally | User opens Library without locked-camera handoff. | No locked session import should run; Library should load existing app pending/Photos data directly. | Earlier logs showed `tap_library_load` waits; this was removed. | Normal Library should no longer be slowed by locked session polling. | Confirm no `locked_camera_session_import_begin reason=tap_library_load/open` appears during normal Library entry. |

Historical branch comparison:

- `lockScreen` / `lockScreen_test` imported from `LockedCameraCaptureManager.sessionContentUpdates` and existing `sessionContentURLs`; they did not make immediate locked Library handoff the primary transfer proof.
- `lockScreen_test` held its importer as a `@StateObject` in `TAPCamDemoApp` and kept import state on the main actor. Current POC should follow that ownership shape: `TAPCamDemoApp` owns a long-lived import runtime, and `StartupGateView` only handles AppContext publishing / user-activity routing.
- `lockScreen_test` wrote HEIC files directly under Apple's session content directory and imported any discovered HEIC. Current POC writes structured `<captureID>/unsigned.heic + metadata.json` and then packages into a pending unsigned TAP artifact. That current design keeps the locked extension small, but it is now a suspect variable. The next transfer experiment should try the historical flat `TAPCam-<UUID>.heic` shape after confirming the shared packaging stack is safe for the locked extension target.
- `lockScreen` had UI/chrome rotation logic. Do not migrate that into the current POC.

Next manual Xcode smoke log probes:

1. `locked_camera_control_widget_init` or `locked_camera_control_widget_button_label_init`
2. `locked_camera_intent_perform`
3. `locked_camera_extension_init`
4. `locked_camera_scene_content_invoked`
5. `locked_camera_root_init`
6. `locked_camera_start_begin`
7. `session_configure_begin`
8. `session_start_success`
9. `first_frame`
10. `photo_capture_saved`
11. `locked_album_placeholder_tapped_status_only` if the lower-left placeholder is tapped during E1
12. no `open_application_call` during E1 placeholder tap
13. `locked_camera_session_content_update kind=initial` or `kind=added`
14. `locked_camera_session_scan_result`
15. `locked_camera_session_import_succeeded`
16. `locked_camera_pending_snapshot`
17. `tap_library_snapshot_loaded`

If a freeze happens, the last visible probe before the freeze is the current
failure boundary. If the next log still contains only app-side import probes,
the diagnostic problem is log collection/filtering, not yet camera logic.

Successful no-immediate-Library-handoff transfer evidence, 2026-07-07:

- User-reported operation: no freeze, no immediate saved-placeholder handoff,
  locked capture later appeared in the main app.
- App-side log evidence: `locked_camera_session_import_runtime_start`, then
  `locked_camera_session_content_update kind=added`, then
  `locked_camera_session_import_begin reason=session_content_update
  sessionCount=2`.
- Import result: two captures were packaged and ingested into the normal pending
  queue:
  `82B2A70B-026A-4406-AC27-6D919025A3B8` and
  `F4F4C690-A79C-47FF-9FAD-C3BBABA7F920`.
- Cleanup result: both Apple session content URLs were invalidated after import,
  and the import finished with `sessions=2 found=2 imported=2 skipped=0
  failed=0 invalidated=2`.
- Follow-on signing failed with `AppAttestKit.AppAttestError code=2`; this is a
  pending signing/backend credential issue, not a locked session-content
  transfer failure.

Repeated no-immediate-Library-handoff transfer evidence, 2026-07-07:

- User-reported operation: repeated runs still did not enter TAP Library from
  the lower-left placeholder, and the perceived flow was normal.
- Negative evidence: the pasted log did not contain the old immediate handoff
  path (`openTAPLibraryAfterLockedCapture`, `locked_camera_handoff_route`,
  `locked_camera_session_import_late_poll`, or `tap_library_load/open`).
- Positive evidence: two more independent `session_content_update` imports
  succeeded:
  `5719E669-1B07-4A9E-9565-EDBFC1F13041` with
  `sessions=1 found=1 imported=1 skipped=0 failed=0 invalidated=1`, and
  `EE77D4D4-1345-4088-B129-AAAC4F9933B7` with the same successful summary.
- Interpretation: the lightweight status-only placeholder plus App-level
  `sessionContentUpdates` runtime is the confirmed rollback/negative-control
  baseline, not the final UX. E1A restores direct open while preserving runtime
  import ownership. The later `openTAPCamera` plus transition-delay experiment
  remains recorded as unreliable for saved-placeholder handoff.

Real-device black-screen finding, 2026-07-06:

- Device: iPhone 15 Pro, iOS 26.5 (23F77), installed build `TAP-NAP.TAPCamDemo` 0.2 (2).
- Symptom: lock-screen UI could flash briefly and then the secure capture surface stayed black.
- Evidence: copied device crash logs contained repeated `TAPCamLockedCameraCaptureExtension` reports from 21:14-21:25. Termination was `SIGABRT`, with `lastExceptionBacktrace` ending in `-[AVCaptureSession startRunning]` from `LockedCaptureCameraController.configureAndStartSessionOnQueue(lens:)`.
- Root cause in the POC implementation: `captureSession.startRunning()` was called before the matching `commitConfiguration()` for `beginConfiguration()`. The Objective-C exception is not catchable by Swift `do/catch`, so the extension process aborted and left the lock-screen secure capture shell black.
- Fix: commit the session configuration first, then call `startRunning()`. Keep `session_configuration_committed`, `session_start_running_begin`, and `session_start_running_end` logs as ordering probes.
- Post-fix evidence: real-device build installed at 21:33; copied crash logs after the install contained no `TAPCamLockedCameraCaptureExtension-2026-07-06-213*.ips`; process sampling at 21:35 showed both `TAPCamDemo` and `TAPCamLockedCameraCaptureExtension` running.
- AITrace / wrong-answer note: see `Docs/AITrace/2026-07-06-locked-camera-black-screen-start-running.md`.

Phase 2: Settings parity, importer hardening, and signing/export verification.

19. 执行完整 AppContext 拍照相关设置：Flash、Output Format、Photo Quality、Location best-effort、Shutter Sound、Haptics；Live Photo 仍按 POC policy forced off。
20. harden `LockedCaptureSessionContentImporter`：幂等、冲突处理、partial failure、retry、thumbnail、TAP Library refresh。
21. 接入 App 启动路径和 locked regenerate-context / open-TAP-Library handoff，启动 importer、pending processor，并在需要时重新生成 AppContext。
22. 补充 focused tests：locked camera app context projection、record narrow resolve、importer、path policy、manifest/depth/proof-slot validation、状态机纯逻辑。
23. 真机验证锁屏启动、live 静置、拍摄、主 App 导入、签名导出。

## Roadmap / To-do

- Evaluate iOS 26-only SwiftUI `onCameraCaptureEvent(... defaultSoundDisabled: ...)` overloads after Phase 1. They may improve shutter-sound handling or async event ergonomics, but they must not enter Phase 1 or raise deployment target without a separate product decision.
- Revisit lowering deployment target from 18.6 to the API minimum 18.0 only as a separate app-wide build policy and regression task.

## Agent 注意事项

- 不要把历史 `lockScreen` 分支整体 merge 回来。
- 不要把主 App 的完整相机 UI 编进 extension。
- 新建 locked/control targets 先沿用当前工程 deployment target 18.6；不要为了 POC 升到 iOS 26。
- iOS 26-only API 只能进入 roadmap/to-do，不能进入 Phase 1 实现。
- POC 当前 UI 可以最小化，但不要把镜头选择/切换做成长期独立实现；共享值模型和 extension-safe UI 组件应能被 app 与 extension 同时引用。
- 不要在 extension target 中加入 App Attest、Photos、network、App Group、shared preferences 依赖。
- 优先保持 extension target 小而可观测。
- 任何 SwiftUI view 都不能在 `body` 中创建 capture session 或 controller。
- controller、photo output、video output、preview host、photo delegates 必须有明确强引用生命周期。
- root view 必须始终渲染可见 UI。
- 所有恢复路径必须经过状态机，不允许散落在 view callback 中直接 start/stop session。
- 真机日志优先级高于推测。如果系统终止 extension 但外壳卡黑，需要最小复现、Console 日志和 sysdiagnose 提 Feedback。
