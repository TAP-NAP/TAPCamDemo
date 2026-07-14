# TAP Video / Library PR 7 运行时证据 Trace

日期：2026-07-12

## 范围与证据边界

本轮承接 [TAPVideoLibraryPRD.md](../TAPVideoLibraryPRD.md)、
[风险研究 trace](2026-07-10-video-library-risk-research.md) 和
[重构实现 trace](2026-07-11-video-library-refactor-implementation.md)。前两份文档保留
研究阶段的历史状态；用户后续锁定的八阶段计划才是本轮实施授权。

本 trace 只把实际执行并得到结果的项目标记为通过：

- Simulator XCTest、UI fixture、截图和五轮 viewer 生命周期可以证明确定性行为；
- 源码扫描和单元测试可以证明当前常量、状态机与文件 API 契约；
- ETTrace 只能证明 CPU sample，不能证明 heap；
- memgraph 必须给出 ownership path，不能用 trace 大小、测试通过或等待两秒推断；
- 真实 capture、RSS、thermal、iCloud、Photos 字节保留和 registration 靶标仍需真机。

Build iOS Apps 插件在本轮用于 Simulator 调试、SwiftUI/system-player UI 模式、
ETTrace 与 memgraph 证据边界。没有把无法采集的性能数字补写为通过。

## 2026-07-12 后续决策覆盖：共享 viewer chrome 与自定义 transport

> 本 addendum 是播放器 UI 的当前结论。本文后续关于
> `AVPlayerViewController`、`contentOverlayView`、系统 controls、旧顶部 toolbar 和
> 旧 16 张截图矩阵的记录，只描述本轮较早阶段的历史证据，不再代表最终实现或发布契约。

用户在浏览交互复核后锁定 option B：视频改为 `AVPlayerLayer` 渲染，SwiftUI
拥有自定义 Play/Pause、elapsed/duration 和 scrubber；Photo 与 Video 复用同一个 Back、
Share、Delete 以及 `RAW` / `2D` / `3D` capsule。Video 的 `RAW` 始终可用，`2D` 只在
registration 完整时可用，`3D` 始终可见但置灰。PiP 或 AirPlay/其他外部播放开始时
自动回到 `RAW`。

这次覆盖同时移除了交互 chrome 对 `contentOverlayView` sibling ordering 的依赖：
`AVPlayerLayer` surface 不接收交互，depth surface 按 `videoRect` 排布，所有按钮和
transport 都由同一个 SwiftUI 根层负责 hit testing。

### 覆盖后的实际验证

| 验证 | 结果包或命令 | 实际结果 |
| --- | --- | --- |
| Debug 编译 | `xcodebuild build-for-testing`，同一 iPhone 17 Pro/iOS 26.5 destination | 通过 |
| Release 编译与 capability | `/private/tmp/TAPCamDemo-Viewer-Release-Final-DD` | 通过且无编译 warning；最终 built `.app/Info.plist` 回读确认 `UIBackgroundModes = [audio]` |
| shared chrome / custom-player source contract | `/private/tmp/TAPCamDemo-Viewer-Unit-Final.xcresult` | 3 focused tests、0 failures；要求共享 chrome、`AVPlayerLayer.videoRect`、custom transport、PiP player-layer seam、foreground fetch recovery 和 bounded 2D probe，并禁止视频路径回退 `AVPlayerViewController` / `contentOverlayView` |
| 2D physical hit、Play/Pause、confirmed seek、五轮生命周期 | `/private/tmp/TAPCamDemo-Viewer-Interaction-Final.xcresult` | 4 tests、0 failures；中心坐标点击 2D 后验证 Selected 与 opacity；scrubber 调整到 70% 后等待 AVPlayer-confirmed elapsed 离开 `0:00`；连续五轮均返回 fixture landing |
| AXXXL shared chrome / 中文 gap | `/private/tmp/TAPCamDemo-Viewer-AX-Final3.xcresult` | 1 test、0 failures并人工复核原始 top/bottom pixel bands；localized notice、transport、opacity、共享 action row 都在 viewport 内，3D 保持可见置灰 |

覆盖后重新生成并人工复核的五张关键截图是：

- `video_performance_raw_paused_shared-chrome_en_L.png`；
- `video_performance_raw_playing_shared-chrome_en_L.png`；
- `video_performance_2d_playing_shared-chrome_en_L.png`；
- `video_performance_2d_shared-chrome_en_AXXXL.png`；
- `video_depth-gap_2d_shared-chrome_zh-Hans_AXXXL.png`。

第一次覆盖后 AXXXL 人工复核发现两个断言本身没有捕获的布局问题：动态字体会把
icon-only glyph 放大到固定 tap target 外；全屏 safe-area inset 为零时，中文 gap notice
的固定 top offset 会压住 Back。最终实现只把纯图标 glyph 的视觉 Dynamic Type 限制为
`.large`（状态文案和 VoiceOver label/value 继续遵循系统设置），transport 通过
`ViewThatFits` 自适应，并把系统/gap notice 放入 Back 下方、有 viewport 宽度上限的纵向
stack；上表最后一轮是这些修复后的重跑结果。

最终收口还修复了几类 UI 测试不容易直接暴露的生命周期问题：buffering 仍保持播放意图；
seek 使用 generation、完成状态和 item identity 防止旧任务恢复播放；Viewer 消失会显式
invalidate transport；RAW 不启动 depth decode/cache；后台只保留 ready player，未完成
fetch 在前台以新 generation 自动恢复；2D 暂停状态收到 memory warning 后会 bounded probe
当前帧。相邻视频 swipe 目前只有机制审计，没有双视频 fixture 的 item-identity 运行断言，
仍作为非阻塞覆盖缺口保留。

这些新测试和截图证明 Simulator 中的共享 chrome、物理点击、selected/disabled 状态和
自定义 transport 行为；不证明真机 PiP/AirPlay route、VoiceOver 完整体验、CPU、RSS 或
heap ownership。它们不会把本文后续保留的旧 system-player 截图或历史修复描述重新认定
为最终证据。

## 测试环境与 fixture

| 项目 | 本轮配置 |
| --- | --- |
| Simulator | iPhone 17 Pro，iOS 26.5，固定同一台已启动 simulator |
| Build | Debug，独立 Derived Data；先 `build-for-testing`，再 `test-without-building` |
| Fixture | Debug/UI-test 专用，运行时生成 MP4，不把 MP4/MOV 提交到仓库 |
| Viewer 路由 | `NavigationStack` + `navigationDestination`，与生产 push 路由一致 |
| 播放 owner | `AVPlayer` + `AVPlayerLayer`；SwiftUI 自定义 transport |
| 自定义 chrome | Photo/Video 共用 SwiftUI Back、Share、Delete、RAW/2D/3D capsule；与 transport 同属根交互层 |
| 证据产物 | `.xcresult` 和 PNG 保存在本机临时证据目录，不提交到源码仓库 |

Fixture 覆盖 0/90/180/270 度、镜像、4:3、16:9、clean aperture、depth gap、
seek discontinuity、15 秒 playback 和 180 秒 metadata stress。性能流程支持 autoplay
与确定性 seek schedule；每次启动携带稳定 scenario，viewer 内部继续使用
`itemID + generation + purpose` 取消旧工作。

录制、depth encode、manifest append、hash、proof、Photos export/readback、player
open、2D readiness、depth decode 和 gap clear 均有 signpost。它们为后续 profile
提供区间，不等于本轮已经采集 CPU 或内存数据。

## 先前 PR7 基线证据（播放器 UI 行已被上方 addendum 覆盖）

先前基线的本地易失证据以 `$PR7_RESULTS/<bundle>` 表示；上方 addendum 另行记录了本轮
最终 `/private/tmp` 结果包，便于当前工作站直接复核。

| 层级 | 最终结果包或命令 | 结果 |
| --- | --- | --- |
| 编译 | `xcodebuild build-for-testing`，固定 iPhone 17 Pro/iOS 26.5 与独立 Derived Data | 通过 |
| Release 编译 | `xcodebuild build`，Release，generic iOS Simulator | 通过 |
| 完整 unit target | `unit-full-20260712-K2.xcresult` | `TAPCamDemoTests` 全部通过，包含最终 hard-gate tests |
| TAP Video hard gates | `PR7-hard-gates-20260712-C.xcresult` | streaming、playback budget 与 release source guard 通过 |
| 系统 controls + 生命周期 | `ui-navigation-20260712-A2.xcresult` | controls 显示/隐藏与五轮 `open → 2D → dismiss` 通过 |
| 几何、gap、seek | `ui-geometry-gap-20260712-I2.xcresult` | 2 tests，0 failures |
| Accessibility Dynamic Type | `ui-accessibility-20260712-G2.xcresult` | 英文 2D 与简体中文 gap 的 AXXXL 截图通过 |
| 两个 profile 交互流程 | `ui-performance-flows-20260712-J2.xcresult` | 2 tests，0 failures；只证明流程可重放，不是 ETTrace |

最终 Debug 与 Release `.app` 均检查过，没有把 README、AITrace/Docs Markdown 或 golden
vector JSON 误打包进产品。

两条可重放流程为：

1. `open → RGB → 2D → play 10s → dismiss`；
2. `open → 2D → seek 3s/10s/6s → resume → dismiss`。

第二条流程在最终版本中会先进入 2D，再执行自动 seek；因此未来 ETTrace 不会再把
RGB-only 流程误当成 depth decode/registration 压力流程。

### 历史 system-player 截图矩阵

最终截图目录包含 16 张有效 PNG：

- 8 张 2D geometry：0/90/180/270、mirrored、4:3、16:9、clean aperture；
- 4 张系统 controls：RGB/2D × shown/hidden；
- 2 张 gap/seek：简体中文 signed depth gap、seek discontinuity；
- 2 张 AXXXL：英文正常 2D、简体中文 signed depth gap。

人工复核确认：

- 系统 controls 隐藏时已完全淡出，显示时仍由 `AVPlayerViewController` 拥有；
- 顶部只保留 Back、RGB/2D、opacity、Share、Delete；
- AXXXL 下 RGB/2D 图标不重叠，opacity slider 保持可操作；
- 简体中文 gap 文案完整换行并位于 slider 下方，不覆盖视频 transport；
- geometry fixture 的 overlay 随 encoded transform、mirror、aspect 和 clean aperture
  改变，不使用固定底部 clearance。

系统 controls 显示时出现的系统 fullscreen 图标属于 `AVPlayerViewController`。当前
公开 API 不能在保留整套系统 transport 的同时单独移除该图标，因此它不被当成第二个
自定义退出按钮。

## 本轮发现并修复的问题

### 当前 custom-player 收口

1. **Photo/Video chrome 漂移**：共享 `DepthViewerChromeView` 现在同时拥有 Back、Share、
   Delete 和 RAW/2D/3D capsule；Video 的 3D 保持可见但 disabled。
2. **2D 按钮无法点击**：播放器 surface 不接收交互，完整 chrome 位于 SwiftUI 根交互层，
   UI test 使用物理中心坐标点击并验证 Selected 状态。
3. **transport 与 seek 竞态**：buffering 视为 active playback intent；seek 只在 generation、
   item identity 与完成状态仍匹配时提交，并在 disappear 时显式 invalidate。
4. **RAW/2D 工作边界**：RAW 不 attach metadata output 或保留 depth cache；进入 2D 才启动，
   gap、seek、memory warning 都清旧 overlay 并对当前 generation 做 bounded probe。
5. **后台生命周期**：ready player 为自动 PiP 保留；未完成 local/iCloud fetch 会取消并在
   foreground 用新 generation 恢复，不会留下 hidden idle 黑屏。
6. **AXXXL localized notice**：纯图标 glyph 保持稳定视觉尺寸；状态文案继续响应 Dynamic
   Type；notice 和 chrome 都锁在 viewport 内，原始截图 bands 人工复核无遮挡。

### 先前 system-player 阶段（历史）

1. **顶部 controls 无法点击**：仅把 SwiftUI toolbar 画进非交互 overlay surface
   会丢失 hit testing。现在由 `contentOverlayView` 中独立的
   `UIHostingController<AnyView>` 承载交互 toolbar，Metal overlay surface 本身继续
   不接收触摸。
2. **AXXXL chrome 重叠**：图标 toolbar 随 accessibility text 无限放大会破坏固定的
   播放手势区域。图标/slider chrome 固定在 `.large`，真正的状态文案继续遵循用户的
   Dynamic Type。
3. **gap notice 覆盖 opacity slider**：notice top offset 现在同时考虑 toolbar 与
   slider；AXXXL 中文可完整换行。

### Fixture 与 UI 自动化

1. **重复打开后 fixture 消失**：player cleanup 曾删除 harness 拥有的源文件父目录。
   fixture source 现在由 harness 持有，单个 viewer dismiss 不再删除它。
2. **fixture 生成阻塞 MainActor**：同步 AVAssetWriter 工作导致 readiness/UI polling
   饥饿。container 与签名构造移入 detached utility work。
3. **`fullScreenCover` 制造假系统关闭按钮**：旧 harness 路由与生产不一致，并在
   screenshot 中产生额外的系统 X。改用生产同型 `NavigationStack` 后消失。
4. **controls 截图状态标反**：只查 `Play` 且点击画面中心会误触 Play/Pause。现在同时
   识别 Play、Pause、Play/Pause，并在空白 player space 切换 chrome；隐藏优先等待
   系统 auto-hide。
5. **seek profile 未进入 2D**：最终测试先等待 registration readiness、选择 2D，
   再执行 `[3, 10, 6]` seek schedule。

### 测试基础

1. 四个 source contract test 已随当前接口更新：首次 readiness、PhotoKit progress
   alias、manual-control boundary 和 Locked Camera host handoff。
2. Presentation state-machine test 过去以 wall-clock deadline 计时；MainActor 被其他
   suite 工作延迟时会产生假 timeout。现在按实际 poll 次数计算逻辑预算，并保留结束前
   最后一轮检查。
3. App Attest runtime 与 depth presentation 两组共享状态测试改为 serialized，避免
   suite concurrency 消耗生产 30 秒 timeout；没有放宽生产超时语义。

## 文件与资源硬门槛

最终源码扫描结果：

- TAP Video `artifact.mp4` 主链路不使用完整 MP4 `Data(contentsOf:)`；
- 没有 `data + box` 或 near-whole MP4 `subdata`；测试中仅有小型 synthetic box 拼接；
- 生产 Swift 不含 `depth-preview.mp4`、`unsigned.mp4`、`signed.mp4`；
- 仓库没有 `.mp4`、`.mov`、`.m4v`、`.avi` 或 `.hevc` fixture；
- streaming hash chunk 为 1 MiB，manifest read 上限 1 MiB，proof slot 为 60 KiB；
- depth validator 的组合 frame buffer 上限为 32 MiB；
- playback frame pool 上限为 24 MiB；push/probe 共用全局最多两个 decode slot。

24 MiB 与 2 不只是默认值：cache/decode admission initializer 会把未来调用方传入的
更大值 clamp 到发布上限，同时仍允许测试注入更小预算。Repository source guard 会递归
扫描生产 target 的旧 artifact 名，并对 TAP Video 文件路径禁止 whole-file `Data`、旧
Data API 与 near-whole `subdata` 回归。

这些是源码与单元测试证据，不是 RSS 或 AVFoundation 内部 allocation 证据。Live Photo
旧路径仍存在整段 paired-video `Data` 读取；它不是本轮新增的 TAP Video artifact 路径，
应进入独立 streaming-hash 后续项，不能借 TAP Video 扫描结果宣称一并修复。

## 不作为最终证据的中间产物

- 较早的 `unit-full-20260712-B2/C2` 暴露了 source contract 漂移与并发 timeout；H2
  验证了对应修复，最终加入 hard-gate tests 后由 K2 取代。
- `PR7-hard-gates-20260712-A` 的 source guard 曾把 thumbnail 的通用 `artifactURL`
  误报为 MP4 whole-file read；规则收紧后由 C 取代，A 不作为最终证据。
- 较早 screenshot bundle 曾因旧 controls 状态判断导致整个 bundle 失败；其中方法级
  截图不再作为最终结果引用，已由 A2、I2 与 G2 取代。
- `diagnostic_2d-control-missing.png` 是修复 hit testing 前的失败诊断，不属于最终 16 张
  screenshot matrix。
- 早期 shown/hidden 文件名对应了相反的系统 chrome 状态；最终矩阵已重新生成。
- XCTest 五轮生命周期通过只证明 route、task 和 fixture 可结束；没有 memgraph 时，
  不能据此声明 player、metadata output、texture 或 temp file 已释放。

## ETTrace：流程就绪，CPU 证据未采集

本轮确认本机 ETTrace 可用，并准备了不污染当前 dirty worktree 的隔离源码副本。现有
build 没有链接 ETTrace framework，也没有可用于 symbolication 的匹配 dSYM，因此不能
对现有 app 直接产出可信 profile。

计划中的下一步是只在隔离副本链接/嵌入 framework、启用 matching dSYM，再对两条 UI
流程各跑三次 `--multi-thread`，只分析处理后的 `output_*.json`。但本次会话的外部执行
批准额度在写入隔离 instrumentation helper 时已耗尽，工具拒绝继续；同一限制也阻止了
后续 profile。为避免绕过批准边界，本轮停止在准备阶段。

因此目前没有：

- before/after CPU sample；
- symbolicated hot stack；
- player open、RGB→2D、seek 或 dismiss 的 ETTrace p50/p95。

UI flow result bundle 不能替代这些数字。

## Memgraph：采集方案就绪，ownership 未证明

五轮生命周期测试已经提供 baseline/after-five handshake，并可在 capture 模式各停留
30 秒。计划对以下对象执行 baseline/after-five `leaks`、memgraph 与 trace tree：

- `TAPVideoDepthPlaybackViewModel`、metadata output、player controller/coordinator；
- hosting controller、Metal overlay、`CAMetalLayer`/texture；
- frame cache、decode admission owner、Task 与受管理临时文件；
- 对应 system `AVPlayer`、item、output 与 controller ownership chain。

启动 capture hold 所需的 Simulator 环境写入同样被本次批准额度阻止，因此没有生成
memgraph，也没有 ownership path。24 MiB pool 常量和五轮 UI pass 不能标记内存门槛
通过。

## 真机与外部状态

配对的 iPhone 15 Pro 在本轮离线，未执行安装、录制或 Photos/iCloud 操作。以下证据
仍待设备在线后完成：

- Release 15/60/180 秒，各三次，覆盖设备实际 depth camera plan；
- RSS、dirty memory、disk、encode/decode p50/p95、drop counter 与 thermal；
- 真实 depth corpus 的 Zstd/LZFSE/raw selection 和 180 秒无 compression-induced drop；
- Photos commit、original 回读、强杀恢复与唯一有效 asset；
- iCloud-only 照片/视频 progress、cancel、background 与 stale callback race；
- registration 靶标小于等于 1 display pixel。

## 发布门槛状态

| 门槛 | 当前状态 | 证据边界 |
| --- | --- | --- |
| TAP Video 无整文件 MP4 `Data`/旧 artifact/提交媒体 fixture | 通过 | 源码扫描 + unit contract |
| hash/parser/validator 1 MiB chunk、组合 buffer ≤32 MiB | 通过配置 | 源码 + unit；非 RSS |
| playback pool ≤24 MiB、decode jobs ≤2 | 通过配置 | 源码 + unit；待 memgraph/运行采样 |
| geometry、mirror、clean aperture、gap、seek UI | Simulator 通过 | deterministic fixture + screenshot |
| 共享 Photo/Video chrome、可点击 2D 与 custom transport | Simulator 通过 | 本文 addendum 的 source contract、physical-hit、Play/Pause、scrubber UI tests 与三张新截图 |
| 五轮 open/2D/dismiss 功能生命周期 | Simulator 通过 | XCTest；不证明释放 |
| 完整 unit target | 通过 | K2 result bundle |
| local ready → overlay、RGB→2D p95 | 未测量 | 需要 profile/signpost 统计 |
| 2D RSS 增量、180 秒 RSS 曲线 | 未测量 | 需要 memgraph + 真机 |
| ETTrace CPU before/after 三轮 | 未采集 | 批准额度阻塞 |
| memgraph ownership path | 未采集 | 批准额度阻塞 |
| Camera cover 与 Library 第一项/identity | unit 通过 | 真实 Photos lifecycle 待真机 |
| iCloud loading/cancel/stale callback | unit 通过 | 真实 iCloud 待真机 |
| Photos commit 强杀后唯一有效 asset | 状态机 unit 通过 | 真实 Photos round-trip 待真机 |
| registration landmark ≤1 display pixel | 未证明 | screenshot 不替代数值靶标 |
| 180 秒无 compression-induced drop | 未证明 | 需要真机 Release capture |

结论：PR7 的 Simulator 功能、布局、可重放 profile 流程和源码硬门槛已经形成可审核
证据；CPU、heap ownership、真机 capture、Photos/iCloud、thermal 与数值 registration
仍是发布阻断项，不能把本轮标记为完整发布验收通过。
