# TAP Video / Library 发布前重构实现 Trace

日期：2026-07-11

## 目标与基线

本轮实现以 [TAPVideoLibraryPRD.md](../TAPVideoLibraryPRD.md) 和
[2026-07-10-video-library-risk-research.md](2026-07-10-video-library-risk-research.md)
为约束基线。功能尚未上线，因此 TAP Video 直接升级到
`video-manifest:v2`，不迁移未发布的 v1 video bundle；照片和 Live Photo
pending 数据不在清理范围内。

Build iOS Apps 插件用于约束 SwiftUI identity、`.task(id:)`、PhotoKit
取消语义、系统播放器 ownership、ETTrace 与 memgraph 的证据边界：ETTrace
只用于 CPU/时延，heap 必须由 memgraph ownership path 证明。

## 实现结果

### PR 0：fixture、signpost 与 codec 基础

- Debug/UI-test harness 在运行时生成 deterministic MP4，不提交 MP4/MOV。
- 场景覆盖 0/90/180/270 度、镜像、4:3/16:9、clean aperture、depth gap、
  seek discontinuity 和 180 秒 metadata stress。
- 录制 finalize/depth encode、player open/2D readiness/decode、Photos
  export/readback 均有稳定 signpost。
- `Packages/CZstd` 固定官方 zstd v1.5.7 源码、archive SHA-256 与 BSD license，
  Swift API 只暴露 bounded level-1 compress/decompress/compressBound。
- diagnostic benchmark 比较 Zstd level 1、LZFSE、LZ4 和 raw，执行 bit-exact、
  p50/p95 与 drop-counter selection；当前生产 build 固定 Zstd level 1，每帧压缩
  失败或不变小时写 raw。只有真机 corpus 证明 Zstd 未达门槛时，后续 build 才整体
  回退 LZFSE，再不通过才整体回退 raw。
- [TAPVideoManifestV2GoldenVectors.json](../Fixtures/TAPVideoManifestV2GoldenVectors.json)
  提供 manifest v2、Zstd 和 KLV v2 跨平台向量。

真实 depth corpus 与并发录制 drop gate 尚未在配对真机执行，不能把 synthetic
fixture 结果描述为该门槛已通过。

### PR 1–2：Canonical Library、poster 与 iCloud

- 根部 `@MainActor @Observable LibraryMediaStore` 合并 pending、owned Photos、
  Photos-only；app-owned capture 在 pending → exported 期间保持
  `.tapCapture(captureID)`。
- Camera cover 与 grid 读取同一排序快照；视频不会回退显示上一张照片。
- 视频在 pending ingest 后、Photos cleanup 前生成 0.12 秒 poster，失败回退
  0 秒；preferred transform、512 px 长边、JPEG 0.78、原子持久化。照片与视频
  poster 数据都保留变换后的原始比例；Library grid 在显示层固定为 1:1 中心裁切，
  Viewer 加载阶段则以 aspect-fit 显示同一比例的轻量 preview。
- 启动补全仍有本地 MP4 的缺失 poster；memory/disk cache 分别限制为
  32 MiB/96 项和 128 MiB/30 天 LRU；memory warning 清空内存 cache。
- 根部只创建一个注入式 PhotoKit actor，同一实例同时提供 catalog DTO 与媒体请求；
  `PHAsset` 在 actor 内批量 fetch 后立即映射为 Sendable DTO，不进入主 actor、Store
  或 SwiftUI state，也不再逐条同步解析 exported asset。
- PhotoKit service 以 asset ID 为边界，原图返回 Data，原视频以 `requestData`
  分块写入受管理临时 URL；取消关闭文件并删除 partial。无消费者的 `AVAsset`
  返回接口和 bridge 已删除。
- `requestData` 的 request ID 晚于 cancel/error 返回时，由共享的 exactly-once bridge
  在 ID 安装后补发 `cancelDataRequest`；file/data 两条路径都覆盖 cancel-before-ID、
  finish-before-ID 和 handler/write failure，避免后台继续下载 iCloud 原件。
- current item 才允许联网；相邻照片只加载 local thumbnail；dismiss、swipe、
  background、replacement 使用 request generation 取消旧结果。
- 照片 display preview 与 original resource 使用独立 purpose/generation；只有
  original resource 拥有 Viewer 主进度，数值按请求单调发布，避免两个 PhotoKit
  progress 流交错导致圆环回退或在 determinate/indeterminate 之间抖动。
- 视频 Viewer 也使用同一个圆形 loading overlay；原件准备期间保留 local-only、
  aspect-fit poster，video original 进度单调发布。活动加载态不显示文字卡片或取消
  按钮，返回、滑动、dismiss 和 background 继续承担取消职责。
- Photo/Video/Live Photo 请求不把 `PHAsset` 放入 SwiftUI state；Live Photo slot
  统一拥有 `itemID + generation + purpose`，旧 cancel/progress/result 不能清掉替换
  请求；统一 overlay 明确区分 preparing、cloud-only、iCloud progress 和五类失败恢复。
- 产品 UI 只发布英文文案；`Localizable.xcstrings` 不再包含简体中文翻译。

### PR 3–5：Manifest、单 artifact 与 Photos 回读

- bounded BMFF parser 支持 32/64-bit size、UUID、截断、非法 range、duplicate
  proof/manifest 和 4,096 个 top-level box 上限；offset 使用 `UInt64`。
- SHA-256 固定 1 MiB chunk 并跳过完整 proof box；file size 使用 `fstat` 避免
  append 后 URL resource-value cache 读到旧长度。
- Depth 逐行只复制逻辑像素，保留 Float16/Float32 bit pattern；每帧 Zstd1，
  不变小时回退 raw。KLV v2 只存 frame index、PTS、codec、原始长度、
  calibration index 与 payload。
- Manifest v2 保存真实 track facts、packed depth format、calibration、registration
  状态、delivered/stored/drop 计数、真实 gap 与 synchronized delta；proofs 为空。
- 签名前和 Photos 回读后都会用 `AVAssetReader` 流式核对实际 RGB/audio/depth
  track composition、track ID/codec/dimensions/timing、每个 KLV frame index/PTS/
  codec/长度/calibration index 和 bit-exact 解码长度；单帧配置保留预算不超过
  32 MiB，不信任 manifest 自报的 sample count。
- group/KLV PTS 必须非负、严格递增并位于真实 track/presentation range；实际
  max interval 必须匹配 manifest。leading、inter-frame 和 trailing 的 missing core
  必须被签入的 gap 区间并集覆盖，禁止 `gaps=[]` 掩盖真实 discontinuity。
- AVAssetWriter 直接写 Application Support recording workspace；finalize 后只
  append manifest 与固定 60 KiB proof slot，再 rename 为单一 `artifact.mp4`。
- App Attest 前持久化 proof 外 content binding；proof 用 `pwrite + fsync` 原位写入。
  `.signing` 崩溃恢复会清空并完整重写 slot，proof 外变更进入 terminal failure。
- TAP Video 无 depth 时禁止开始；最终零有效 depth sample 不签名、不导出。
- Photos 直接接收 validated file URL，原始文件名固定为 `tap-<packageID>.mp4`。
  commit 后流式回读 original video 并完整验证 manifest/proof/content binding，
  成功后才 mark exported 和删除 pending MP4。
- 对已有 proof 的 pending/Photos/recovery 文件，先验证 bounded manifest/proof 和
  1 MiB chunk 的 streaming content binding，再允许 AVFoundation 解析 metadata
  sample；伪造候选不能在认证前诱导大 sample 物化。签名前仍先验证实际 track，
  写 proof 后只复验绑定，不重复扫描 depth track。
- `.exporting` 恢复按 filename/packageID 搜索全部视频，完整验证后取最早有效
  asset；多个有效候选记录 duplicate warning；回读失败保留 pending 与 asset ID，
  且不自动重复导出。
- Photos handoff 另有持久化三相边界：`preCommitIntent → commitAmbiguous → committed`。
  commit 前中断可安全重新创建；进入 ambiguous 后只允许 candidate/readback，禁止
  自动再次创建；Photos 返回 ID 后先持久化 committed，再做完整回读。

### PR 6：系统播放器与 bounded playback

- `AVPlayerViewController` 是唯一 transport owner，底部只保留系统 controls；
  Back、RGB/2D、opacity、Share、Delete 位于顶部 safe-area toolbar。
- overlay 使用 `contentOverlayView`，布局取 `videoBounds`；删除固定底部 clearance
  与 safe-area workaround。
- 生产 registration 只接受同一 synchronized collection、固定 depth format、无 depth
  rotation/mirror、video stabilization off、匹配 pre-connection aspect ratio 的已签
  descriptor；缺失任一条件即禁用 2D。iOS SDK 明确 `AVDepthData` 已 warp 到其
  accompanying YUV 网格，因此 2D 只需签入并重放 scale、connection rotation、
  encoded mirror 与 clean aperture；calibration/extrinsic 保留给 3D/rectification，
  不做第二次伪投影。Debug identity fixture 才允许 fixture-authored overlay。
- Depth frame 不通过帧率级 SwiftUI `@Published UIImage`；coordinator 直接更新
  Metal-backed overlay surface。
- cache 上限 24 MiB、窗口 `-0.25s…+0.75s`、全局 decode 并发最多 2；seek、
  replacement、dismiss 递增 generation 并清理 output/player/temp。
- decode generation 按 player/output owner 隔离，旧 viewer 不会失效新 viewer；
  全局只共享两个物理解码槽。push 满载时立即 drop，paused/seek probe 则以可取消
  waiter 等待槽位，capacity 释放后继续，stale/cancel/invalidate 不泄漏 token。
- stale 阈值使用 `max(2 × nominalDepthInterval, 100ms)`；超过 gap 清空 overlay。
- 2D readiness 不再依赖固定 timer：正常 push 和 paused-at-zero/seek 的 bounded
  `AVAssetReader` current-window probe 都发布 generation-bound `frame/noSample/
  decodeFailed` event；probe 最多检查 256 个 metadata groups，只解最近一帧。
- PiP/AirPlay 自动切回 RGB，并只显示一次说明。

## 已执行验证

- Local `CZstd` package tests：3 tests passed，包括 pinned golden raw-fallback bound。
- 最终 Debug generic iOS Simulator `build-for-testing`：passed。
- 最终 Release generic iOS Simulator `build`：passed。
- `git diff --check`：passed。
- `Localizable.xcstrings`、golden vectors 与 Zstd source metadata：`jq empty` passed。
- repo MP4/MOV scan：0 committed media binaries。
- source hard-gate scan：生产 TAP Video 路径无 whole-MP4 `Data(contentsOf:)`、
  `data + box`、near-whole `subdata`、`depth-preview.mp4`、`unsigned.mp4`、
  `signed.mp4`、旧 `AVAsset` fetch bridge 或全局 PhotoKit fetcher。

较早一次 focused XCTest 命令让 Xcode 自动创建并 boot 了 Simulator clone；它只运行
了部分 registration/timeline/table 测试，并发现、修复了 golden Zstd destination
bound 问题。之后所有验证都限制为 generic build，没有再操作 Simulator 或真机；
该部分运行不能代替完整 PR 7 证据。

## 尚未完成的发布证据

本轮未执行完整 Simulator profiling matrix，也未替用户操作配对真机，因此以下
不能标记为通过：

- XCTest runtime suite 与 screenshot matrix；
- before/after 三轮 symbolicated ETTrace；
- 五轮 open/play/dismiss 后的 memgraph ownership path；
- 真机 15/60/180 秒、各三次的 RSS/dirty memory/thermal/drop/Photos round-trip；
- 真实 iCloud-only 照片/视频的 progress、取消和旧 callback race；
- 真实 depth corpus 的 codec p95 与 180 秒 compression-induced drop gate；
- registration landmark 小于等于 1 display pixel。

这些项目必须保留为 PR 7 的设备证据，不能由 build 成功、trace 文件大小或
synthetic fixture 推断。

## 2026-07-12 PR 7 证据补充

上述章节保留 2026-07-11 当天的历史状态。随后已完成 Simulator 完整 unit target、
system-controls/geometry/gap/seek/Dynamic Type screenshot matrix、两条可重放 profile
流程，以及五轮 `open → 2D → dismiss` 功能生命周期；详细结果与中间失败排除见
[2026-07-12-video-library-pr7-runtime-evidence.md](2026-07-12-video-library-pr7-runtime-evidence.md)。

ETTrace CPU、memgraph ownership、配对真机、真实 iCloud/Photos、thermal 和数值
registration 靶标仍未通过，不能由新增 Simulator 证据推断。

## 2026-07-14 Library 视频 2D 置灰根因与修复

### 真机 artifact 证据

从已连接 iPhone 15 Pro 回读当前 exported TAP Video 原始 `.video` 资源后确认：

- artifact 是 `video-manifest:v2`，时长约 4.2 秒；
- depth metadata track 为 `fdep` 320×240，delivered/stored 都是 126 帧，且没有
  depth gap；
- 因此这不是“没有录到 depth”或播放器无法读取 depth track；
- manifest 的 `spatialRegistration.status` 被录制端写成 `unavailable`，且没有
  registration descriptor，所以 Viewer 按 fail-closed 契约正确地禁用了 2D。

直接根因是 calibration dictionary 只允许 16 个 exact entry，而这段 126 帧录制的
`intrinsicMatrix`、`lensDistortionCenter`、正向/反向 distortion lookup table 在前 16
个样本中均逐帧不同。第 17 个 distinct calibration 令 `didOverflow = true`，旧 recorder
随后把整个 RGB↔Depth 2D registration 判为 unavailable。这里错误地把两条独立事实
绑定在了一起：

1. synchronized `AVDepthData` 到 accompanying YUV 网格的 2D 映射是否成立；
2. 每一帧是否有可索引的 metric camera calibration，供未来 3D/rectification 使用。

Apple 的 [`AVDepthData`](https://developer.apple.com/documentation/avfoundation/avdepthdata)
契约说明 depth map 已按同帧 YUV 图像的镜头畸变进行 warp；
[`AVCaptureDataOutputSynchronizer`](https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer)
负责把 RGB/depth output 放进同一时间匹配 collection。当前 2D renderer 消费的是已签名
YUV-space registration descriptor，并不消费 per-frame camera calibration。

### 实施修复

- registration descriptor 继续严格要求 synchronized pair、有效 RGB/depth dimensions、
  clean aperture、RGB connection transform、depth 0°/不镜像、stabilization off 和匹配
  aspect ratio；不再要求 calibration table 完整或不溢出。
- exact calibration table 仍固定最多 16 项，KLV `calibrationIndex` 仍可选；新增签入
  manifest 的 `calibrationCoverage`，分别记录 indexed、camera calibration 缺失、table
  overflow 后未索引的 stored sample 数及 overflow 状态。三类计数必须覆盖全部 stored
  depth sample。
- 签名前和 Photos 回读 validator 允许 registered 2D frame 没有 calibration index，
  但会逐帧核对 index range，并核对实际 indexed/unindexed 数量与 manifest coverage。
- `DepthFormat` 连续性只比较真正写入 KLV 的 packed layout；CVPixelBuffer 的
  `sourceRowStride` 是采集时 padding，单独变化不再错误禁用 2D。
- warm/cold 两条录制图路径都显式把 depth connection 固定为 rotation 0、not mirrored；
  recorder 必须实际观察到该 connection，避免前置 TrueDepth 或新设备默认值造成下一次
  registration failure。
- Library 回读视频资源时优先 Photos original `.video`，仅在缺少 original 时回退
  `.fullSizeVideo`，避免 adjusted resource 丢失 TAP 自定义 box。

旧 artifact 已把 `unavailable` 状态和缺失 descriptor 签入 proof，不能在播放器端推导
近似 descriptor 或原地改写；当前功能未上线，开发数据需要在新 build 上重新录制。

### 回归证据

- Debug generic iOS Simulator `build-for-testing`：通过。
- Release generic iOS Simulator `build`：通过。
- iPhone 17 Pro / iOS 26.5 Simulator 聚焦 suite：通过，包括 runtime-generated MP4
  depth track validator、空 metric calibration table 仍启用 production 2D descriptor、
  packed stride continuity、PhotoKit original resource priority、manifest golden vector 和
  source-level 2D gate guard；结果保存在
  `/private/tmp/TAPCamDemo-2D-Fix-DerivedData/Logs/Test/Test-TAPCamDemo-2026.07.14_23-53-50-+0800.xcresult`。
- iPhone 15 Pro Debug device build：通过，并已把最终 build 安装、启动到连接设备。
- 最终 build 上新录制的两条 TAP Video record 均进入 `signed`、Photos
  `committed`、record `exported`；用户在实机 Library 中直接确认 RGB 视频可播放、
  胶囊 2D 可点击且 depth overlay 随视频正常播放。该交互链路标记为实机通过。
- `git diff --check`：通过。

### Depth 校验边界

“由受信任的 TAP Capture 流程在同一次录制中取得 RGB 与 depth，并把实际字节一起
签名”是 provenance 目标；“depth 能否正确叠到 RGB 像素位置”是独立的 2D capability。
因此实现和后续 review 必须使用三层边界：

1. **必须拒绝 artifact**：身份、proof 或 content digest 不一致；没有实际 depth track
   或零个可安全读取的 depth sample；KLV range、尺寸、codec 或解压长度违反 bounded
   parser 安全约束。这些条件说明文件不是有效 TAP Video 或无法安全消费。
2. **只禁用 2D**：签名的 registration descriptor 缺失、未知或与 RGB/depth 的同步、
   rotation、mirror、clean aperture、dimensions 不一致。此时 RGB 播放、签名和导出
   不受影响；禁止播放器自行猜测近似映射。
3. **只记录质量告警**：calibration 缺失或 table overflow、已声明 gap/drop、同步误差
   和部分 coverage。它们不证明 artifact 不真实，也不应单独让 2D 置灰；播放到 gap
   时只清空该时间段的 overlay。

Capture setup 会主动固定 depth rotation/mirror 与 RGB stabilization 等可控不变量；异常
时把精确 reason code 签入 manifest，避免再以一个泛化的 `unavailable` 掩盖原因。
Calibration 保留给未来 metric 3D/rectification 使用，不再作为当前 YUV-space 2D overlay
的前置条件。
