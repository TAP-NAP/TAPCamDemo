# TAPCamDemo

[English](README.md) | 简体中文

## 用途

TAPCamDemo 是用于拍摄、签名和分享 TAP 照片、Live Photo 与视频的 iPhone
应用，在设备支持时同时记录深度。应用提供媒体图库、播放、深度图、平面分析和点云视图。

## 使用

用 Xcode 打开 [TAPCamDemo.xcodeproj](TAPCamDemo.xcodeproj)，选择 `TAPCamDemo`
scheme。应用面向运行 iOS 18.6 及以上版本的 iPhone。真机拍摄与签名需要在构建设置中
配置签名团队和 `APP_ATTEST_BACKEND_URL`；服务器接口见
[后端契约](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/BackendContract.md)。

在仓库根目录执行以下命令，无需连接设备即可编译应用和测试目标：

```sh
xcodebuild build-for-testing \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

运行单元测试和应用宿主测试时，选择已启动的 iPhone 模拟器，将 `<UDID>` 替换为其标识：

```sh
xcrun simctl list devices booted
xcodebuild test \
  -project TAPCamDemo.xcodeproj \
  -scheme TAPCamDemo \
  -configuration Debug \
  -destination 'id=<UDID>' \
  -only-testing:TAPCamDemoTests
```

运行 UI 测试时改用 `-only-testing:TAPCamDemoUITests`；指定测试套件时使用
`-only-testing:TAPCamDemoTests/<SuiteName>`。检查实际执行的测试数量。
安装 SwiftLint 后，可运行 `Scripts/lint-tap-video-refactor.sh` 检查指定范围内的
TAP Video 代码结构。模拟器测试覆盖确定性逻辑与 UI；真实拍摄、深度、Photos 和
App Attest 需要执行相应的[真机验收](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/Acceptance.md)。

## 简要原理

```text
相机拍摄 → 媒体与 manifest → 待处理队列 → 哈希与 App Attest 证明
         → Photos 导出与回读 → 图库、播放与分析
```

拍摄规划解析设备支持的配置，运行时完成采集，输出层嵌入 manifest。待处理队列负责
已完成文件的签名和导出，相机可继续使用。完整性检查基于签名覆盖的文件字节；
媒体解码用于播放和分析。

## 目录结构

| 目录 | 职责 |
| --- | --- |
| [TAPCamDemo/App](TAPCamDemo/App) | 应用入口、启动、设置、App Attest 和 App Intents。 |
| [TAPCamDemo/CameraCapture](TAPCamDemo/CameraCapture) | 拍摄规划、会话运行、文件输出、相机 UI 和 Playground。 |
| [TAPCamDemo/PendingCaptureQueue](TAPCamDemo/PendingCaptureQueue) | 采集结果入队、存储、签名、导出和重试。 |
| [TAPCamDemo/TAPLibrary](TAPCamDemo/TAPLibrary) | 媒体访问、目录索引、图库、查看器和分享。 |
| [TAPCamDemo/DepthAnalysis](TAPCamDemo/DepthAnalysis) | 深度解码、热图、平面及照片/视频点云。 |
| [TAPCamDemo/Diagnostics](TAPCamDemo/Diagnostics) | 日志、采集指标和性能记录。 |
| [Assets.xcassets](TAPCamDemo/Assets.xcassets)、[Resources](TAPCamDemo/Resources)、[en.lproj](TAPCamDemo/en.lproj)、[zh-Hans.lproj](TAPCamDemo/zh-Hans.lproj) | 视觉资源、随包声明和本地化权限文案。 |
| [TAPCamDemoTests](TAPCamDemoTests)、[TAPCamDemoUITests](TAPCamDemoUITests) | 单元/应用宿主测试、测试样本和 UI 自动化。 |
| [Scripts](Scripts)、[Tools/ContentBindingVerifier](Tools/ContentBindingVerifier) | 指定范围的 lint 命令及 JavaScript 字节绑定工具与测试。 |
| [TAPCamDemo.xcodeproj](TAPCamDemo.xcodeproj) | 构建目标、共享 scheme、构建设置和 Swift 包依赖锁定。 |

## 依赖

[TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/README.md)
是产品、UI、产物和共享 API 要求的规范来源。本应用采用的产物契约固定于
[`16242f01674d5c8b771b93e2cb46bc42a039d174`](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/CONTRACTS.md)。

[server](https://github.com/TAP-NAP/server) 提供所配置的 App Attest HTTP 服务，
不属于源码或构建依赖；其 API 要求仍以服务端契约为准。构建应用无需检出其他 TAP 仓库。

Xcode 根据 [Package.resolved](TAPCamDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)
解析以下依赖：

| 包 | 版本 | 用途 |
| --- | --- | --- |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 0.9.20 | 打包用于分享的 `.tapnap` 文件。 |
| [zstd](https://github.com/facebook/zstd) | 1.5.7 | 通过 `libzstd` 压缩 TAP 深度帧。 |

采集、渲染和 Photos 访问使用 Apple 框架；App Attest 通过 DeviceCheck 调用，凭据元数据
保存在 Keychain。更新契约固定版本时，须逐字节
比较[本地扩展测试向量](TAPCamDemoTests/Fixtures/tap-video-extensions-v1.json)与
[对应契约向量](https://github.com/TAP-NAP/TAPArtifactContracts/blob/16242f01674d5c8b771b93e2cb46bc42a039d174/examples/vectors/tap-video-extensions-v1.json)。
