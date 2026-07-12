# Locked Camera Official Restart Trace

日期：2026-07-12

分支：`codex/locked-camera-official-restart`

基线：`edbd24c`（锁屏 clean-rebuild 实验之前的主 App commit）

阶段：R0 真机通过，R1 待实施

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

R0 已通过。下一阶段是 R1 minimal custom viewfinder：只替换系统 `UIImagePickerController`，加入长期持有的最小 AVFoundation preview 和公开 capture-event interaction；仍不加入 photo output、session-content write、importer 或 app-open API。
