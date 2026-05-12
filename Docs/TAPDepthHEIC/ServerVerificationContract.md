# TAP Depth HEIC 服务端验证契约

本文档描述当前 TAPCamDemo 代码已经实现的 TAP Depth HEIC 打包、签名、验签流程，并给服务端实现者一份可执行的验证契约。

本文档只说明已有代码和建议的服务端接口，不要求客户端代码必须已经实现所有建议接口。

## 1. 文档状态

当前代码已经实现：

- 单张 HEIC 文件输出，RGB 是 primary image item，深度是 Apple auxiliary depth 或 disparity attachment。
- TAP 自定义 manifest 写入 XMP `tapdepth:Manifest`。
- foreground capture 先生成 unsigned HEIC 并进入 pending store。
- pending processor 后台重新读取 unsigned HEIC，计算内容 digest，生成 App Attest assertion proof，再把 proof 写回 manifest。
- 本地分析面板可以从已保存 HEIC 中读取 manifest、重算 digest、验证 request binding、调用 AppAttestVerifyKit 验证 attestation 和 assertion。

当前代码尚未完整实现：

- 对外开放的图片验证服务端 API。
- 统一的 TAP 图片验证失败原因枚举。
- 生产 HTTP 模式下完全不请求 challenge endpoint 的长期 challenge signer。

因此本文档把内容分成两类：

- **代码事实**：当前仓库里已经存在的类型、字段、计算方式。
- **服务端建议**：为了让第三方验证端或服务器实现完整验签，需要补齐的 API、存储和错误码约定。

## 2. 代码对应关系

| 主题 | 当前代码位置 |
| --- | --- |
| App Attest backend mode、HTTPS 配置、固定 credential name | `TAPCamDemo/App/AppAttestRuntime.swift:15`, `:44`, `:179` |
| manifest schema、XMP namespace、proof 字段 | `TAPCamDemo/CameraCapture/Output/TAPDepthManifestSchema.swift:27`, `:31`, `:357` |
| manifest JSON canonical encoder | `TAPCamDemo/CameraCapture/Output/TAPDepthManifestEncoding.swift` |
| HEIC XMP 写入和读取 | `TAPCamDemo/CameraCapture/Output/TAPDepthHEICWriter.swift:31`, `:62`, `:115`, `:141` |
| EXIF UserComment 指针和标准 EXIF/GPS 写入 | `TAPCamDemo/CameraCapture/Output/TAPPhotoFileMetadataCustomizer.swift:33`, `:57` |
| foreground capture 传入 `assertionSigner: nil` | `TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift:65` |
| capture 后触发 pending signing | `TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift:82`, `:127` |
| pending processor 后台签名 | `TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift:22`, `:46`, `:116`, `:123` |
| RGB、depth、metadata hash 计算 | `TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift:56`, `:113`, `:154`, `:196` |
| App Attest assertion proof 生成 | `TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift:20`, `:31`, `:38`, `:41` |
| proof.value 的 JSON 结构 | `TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift:63`, `:72` |
| 本地图片验签步骤 | `TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift:484`, `:524`, `:533`, `:547`, `:594` |
| request binding 校验规则 | `TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift:702` |
| 现有 App Attest 后端基础契约 | `Docs/AppAttest/BackendContract.md` |
| local debug 固定 challenge 说明 | `Docs/AppAttest/LocalDebug.md` |

## 3. 服务端配置现状

当前已有文档在 `Docs/AppAttest`：

- `BackendContract.md`：定义 App Attest 后端边界，包括 challenge、attestation、credential status、assertion record。
- `LocalDebug.md`：说明 local debug backend 和固定 challenge。
- `SecurityNotes.md`：说明生产 challenge、防重放、服务端验证职责。
- `ClientUsage.md`：说明客户端如何 prepare credential 和 generate assertion。

当前客户端读取 Info.plist 中的配置：

```text
APP_ATTEST_BACKEND_MODE=localDebug
APP_ATTEST_LOCAL_CHALLENGE=TapTapNapNap123123

APP_ATTEST_BACKEND_MODE=http
APP_ATTEST_BACKEND_URL=https://api.example.com
```

代码事实：

- `APP_ATTEST_BACKEND_MODE=http` 时，`APP_ATTEST_BACKEND_URL` 必须是 `https` URL。
- `APP_ATTEST_BACKEND_MODE=localDebug` 时，challenge 默认是 `TapTapNapNap123123`，并要求至少 16 bytes。
- 照片签名使用固定 credential name：`photo_keyid`。
- 当前 HTTP backend 的基础 endpoint 是：
  - `POST /app-attest/challenges`
  - `POST /app-attest/attestations`
  - `POST /app-attest/credentials/status`
- 当前 HTTP backend 对 assertion result 的 record 是客户端侧 no-op；服务端如果要审计 assertion，应在自己的验证 API 中记录。

## 4. Challenge 模式

TAP Depth HEIC 的 assertion challenge 可以有两种模式。

### 4.1 一次性服务端 challenge

这是 App Attest 标准推荐模式。

签名时：

```text
client
  |
  | requestChallenge(purpose=assertion, credentialName=photo_keyid)
  v
server returns one-time challenge
  |
  | DCAppAttestService.generateAssertion(keyId, clientDataHash)
  v
assertionEnvelope.requestBinding.challengeSHA256 = SHA256(rawChallenge)
```

服务端验证时必须检查：

- challenge 存在。
- purpose 是 `assertion`。
- credentialName 是 `photo_keyid`。
- challenge 未过期。
- challenge 未使用。
- `SHA256(rawChallenge)` 等于 `requestBinding.challengeSHA256`。
- 验证成功后把 challenge 标记为已使用。

优点：

- 服务端能做每次签名级别的 nonce 防重放。
- 可以阻止旧 assertion 被拿来伪装成新业务请求。

缺点：

- 每次照片签名都需要网络请求。
- 离线拍摄或弱网拍摄需要 pending 重试。

### 4.2 长期 challenge

这是为了开放验证、离线签名和第三方解析器更容易接入的模式。

长期 challenge 的含义：

```text
rawChallenge = verifier-defined static bytes
challengeId = stable id, for example "tapcam-photo-v1"
challengeSHA256 = base64url(SHA256(rawChallenge))
```

签名时不需要为每张照片生成新的服务端 challenge。客户端只要能拿到长期 challenge 原文，就可以生成：

```text
assertionEnvelope.requestBinding.challengeSHA256 = base64url(SHA256(longTermChallenge))
```

服务端验证时也不需要查一条一次性 challenge 记录，而是：

```text
expectedChallengeSHA256 = base64url(SHA256(configuredLongTermChallenge))
require requestBinding.challengeSHA256 == expectedChallengeSHA256
```

代码对应关系：

- 当前 `localDebug` backend 已经是固定 challenge 模式，见 `AppAttestRuntime.swift:97` 和 `:137`。
- 当前生产 HTTP 模式仍会通过 `DefaultAppAttestClient.generateAssertion` 触发 backend challenge 流程。
- 如果不改客户端代码，生产服务器可以在 `POST /app-attest/challenges` 对 assertion 每次返回同一个长期 challenge。
- 如果希望真正“每次签名不请求服务器”，需要在客户端提供一个 production 可用的 static challenge backend 或修改 AppAttestKit 的 assertion challenge 注入方式。

安全边界：

- 长期 challenge 不是一次性 nonce。
- 长期 challenge 不能提供“每张照片只能被验证一次”的服务端防重放。
- 长期 challenge 仍然能把 assertion 绑定到图片内容 digest、captureID、path、method、nonce。
- 把同一张图片和同一个 proof 重复提交给验证端，应该仍然验证通过。这更像“文件真实性验证”，不是“一次性业务请求验证”。
- 如果服务端需要阻止重复提交同一张照片，应基于 `captureID`、content digest、assertion counter 或业务数据库做去重，而不是依赖长期 challenge。

推荐：

- credential attestation 注册阶段仍建议使用服务端校验和服务端存公钥。
- 照片 assertion 阶段可以选择长期 challenge，尤其适合开放第三方验证。
- 文档和 API 响应必须明确标记 `challengeMode`，避免把长期 challenge 误认为一次性防重放 nonce。

建议配置：

```text
TAP_ASSERTION_CHALLENGE_MODE=static
TAP_ASSERTION_CHALLENGE_ID=tapcam-photo-v1
TAP_ASSERTION_CHALLENGE_VALUE_BASE64URL=<base64url raw challenge bytes>
```

## 5. TAP Depth HEIC 文件结构

```text
TAP Depth HEIC
|
+-- primary image item
|   |
|   +-- RGB 可见图像
|       写入阶段：AVCapturePhoto.fileDataRepresentation(with:) 生成 base HEIC。
|       代码位置：EmbeddedPhotoPackager.package，TAPPhotoFileMetadataCustomizer。
|
+-- Apple auxiliary data
|   |
|   +-- depth 或 disparity attachment
|       写入阶段：TAPPhotoFileMetadataCustomizer.replacementDepthData 返回 photo.depthData。
|       代码位置：TAPPhotoFileMetadataCustomizer.swift:45。
|
+-- EXIF / GPS / TIFF metadata
|   |
|   +-- EXIF DateTimeOriginal / DateTimeDigitized / LensModel / UserComment
|       写入阶段：base HEIC 生成时写入。
|       说明：UserComment 只是指针，值为 "TAPDepthHEIC/1; metadata=xmp:tapdepth:Manifest"。
|       代码位置：TAPPhotoFileMetadataCustomizer.swift:33, :57。
|   |
|   +-- GPS metadata
|       写入阶段：有 CLLocation 时写入。
|       说明：不是 TAP 权威数据，权威位置字段在 manifest.payload.location。
|       代码位置：TAPPhotoFileMetadataCustomizer.swift:39。
|
+-- XMP metadata
    |
    +-- tapdepth:Manifest
        写入阶段：base HEIC 生成后，通过 CGImageDestinationCopyImageSource 合并 XMP。
        说明：这是 TAP 自定义 manifest 的权威位置。
        代码位置：TAPDepthHEICWriter.swift:31, :62, :115。
        |
        +-- TAPDepthManifest JSON
            写入阶段：第一次写入 unsigned manifest，后台签名后写入 signed manifest。
            说明：JSON 使用 sortedKeys 和 withoutEscapingSlashes 编码。
            代码位置：TAPDepthManifestEncoding.swift。
```

读取 manifest：

```text
CGImageSourceCreateWithData(originalHEIC)
  |
  +-- CGImageSourceCopyMetadataAtIndex(source, 0, nil)
      |
      +-- CGImageMetadataCopyStringValueWithPath(metadata, nil, "tapdepth:Manifest")
          |
          +-- JSONDecoder.decode(TAPDepthManifest.self)
```

注意：

- 第三方解析器必须读取原始 HEIC resource，不要读缩略图、编辑后副本或 Photos 派生图。
- EXIF UserComment 只告诉解析器 manifest 在哪里，不是 manifest 本体。
- TAP 权威字段只来自 XMP `tapdepth:Manifest`。

## 6. Manifest 总树

下面是当前 v1 manifest 结构。字段下方说明该字段含义和写入阶段。

```text
TAPDepthManifest
|
+-- schema
|   写入阶段：构造 TAPDepthManifest 时自动写入。
|   |
|   +-- id
|   |   含义：manifest schema id，固定为 urn:tapnap:tapcam:depth-manifest:v1。
|   |   写入阶段：TAPDepthManifest.Schema.init。
|   |
|   +-- version
|   |   含义：manifest schema version，当前为 1。
|   |   写入阶段：TAPDepthManifest.Schema.init。
|   |
|   +-- mediaType
|   |   含义：manifest JSON media type，当前为 application/vnd.tapnap.depth-manifest+json;version=1。
|   |   写入阶段：TAPDepthManifest.Schema.init。
|   |
|   +-- xmpNamespaceURI
|   |   含义：XMP namespace URI，当前为 urn:tapnap:tapcam:depth:1.0。
|   |   写入阶段：TAPDepthManifest.Schema.init。
|   |
|   +-- xmpPrefix
|   |   含义：XMP prefix，当前为 tapdepth。
|   |   写入阶段：TAPDepthManifest.Schema.init。
|   |
|   +-- xmpManifestPath
|       含义：XMP path，当前为 tapdepth:Manifest。
|       写入阶段：TAPDepthManifest.Schema.init。
|
+-- payload
|   写入阶段：TAPDepthManifestBuilder.makeManifest 从 AVCapturePhoto、capture context、session plan 构造。
|   说明：payload 是业务元数据，也是 metadata hash 的输入。proofs 不参与 metadata hash。
|   |
|   +-- id
|   |   含义：captureID，UUID 字符串。
|   |   写入阶段：TAPDepthManifestBuilder.makeManifest 生成 UUID。
|   |
|   +-- capturedAt
|   |   含义：拍摄时间，ISO-8601 字符串。
|   |   写入阶段：capture context 创建后，manifest builder 写入。
|   |
|   +-- sessionMode
|   |   含义：拍摄 session 模式。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- pairingMode
|   |   含义：RGB 与 depth 的配对模式。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- alignmentStatus
|   |   含义：RGB-depth 对齐状态。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- sourceAPIs
|   |   含义：记录 photo、depth、camera、location 来源 API。
|   |   写入阶段：固定写入 .avFoundationPhotoDepth。
|   |
|   +-- capture
|   |   含义：AVCapturePhotoOutput 相关输出设置。
|   |   写入阶段：从 AVCapturePhoto.resolvedSettings 和 capture package 写入。
|   |
|   +-- rgbSource
|   |   含义：用户选择或系统解析出的 RGB 来源镜头。
|   |   写入阶段：从 CaptureSelectionContext 和 CaptureSourcePlan 写入。
|   |
|   +-- depthSource
|   |   含义：用户选择或系统解析出的 depth 来源。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- pairing
|   |   含义：配对结果、是否需要 MultiCam、Release 是否允许。
|   |   写入阶段：从 CaptureSelectionContext 和 CaptureSourcePlan 写入。
|   |
|   +-- zoom
|   |   含义：请求 zoom、实际 video zoom、depth safe ranges。
|   |   写入阶段：从 CaptureSourcePlan 写入。
|   |
|   +-- crop
|   |   含义：裁剪模式、normalized crop rect、是否 destructive final crop。
|   |   写入阶段：从 CaptureSourcePlan.cropPolicy 写入。
|   |
|   +-- resolvedSession
|   |   含义：最终使用的 capture device 和 active primary constituent。
|   |   写入阶段：从 CaptureSelectionContext 和 AVCaptureDevice 写入。
|   |
|   +-- selectedDepthCamera
|   |   含义：UI 层所选 depth camera 的展示字段。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- selectedZoom
|   |   含义：UI 层所选 zoom 的展示字段。
|   |   写入阶段：从 CaptureSelectionContext 写入。
|   |
|   +-- photoLens
|   |   含义：照片镜头、焦段标签、35mm 等效焦距、解析后的设备字段。
|   |   写入阶段：从 CaptureSelectionContext、CaptureSourcePlan、AVCaptureDevice 写入。
|   |
|   +-- depthBackend
|   |   含义：legacy depth backend 选择信息。
|   |   写入阶段：从 CaptureSelectionContext 和 AVCaptureDevice 写入。
|   |
|   +-- camera
|   |   含义：AVCaptureDevice、activeFormat、activeDepthFormat、focus 和焦距信息。
|   |   写入阶段：从 AVCaptureDevice 写入。
|   |
|   +-- photo
|   |   含义：照片宽高、orientation、原始 metadata keys。
|   |   写入阶段：从 AVCapturePhoto.resolvedSettings 和 AVCapturePhoto.metadata 写入。
|   |
|   +-- depth
|   |   含义：depth/disparity 类型、尺寸、pixel format、精度、质量、校准数据。
|   |   写入阶段：从 AVDepthData 和 AVCaptureDevice 写入。
|   |
|   +-- alignment
|   |   含义：当前固定为 appleAuxiliaryDepthNative。
|   |   写入阶段：manifest builder 写入。
|   |
|   +-- location
|   |   含义：拍摄地点；没有定位时显式写入 null。
|   |   写入阶段：从 CaptureSourceContext.location 写入。
|   |
|   +-- software
|       含义：app name、bundle identifier、version、build。
|       写入阶段：manifest builder 写入 .current。
|
+-- proofs
    写入阶段：foreground capture 初始为空数组；pending signing 成功后替换为一个 appAttestAssertion proof。
    说明：proofs 不参与 metadata hash。
    |
    +-- [0]
        |
        +-- type
        |   含义：proof 类型，当前必须是 appAttestAssertion。
        |   写入阶段：AppAttestCaptureAssertionSigner.sign。
        |
        +-- algorithm
        |   含义：proof value 算法和 envelope 版本，当前必须是 AppAttestKit.AppAttestAssertionEnvelope.v1。
        |   写入阶段：AppAttestCaptureAssertionSigner.sign。
        |
        +-- keyID
        |   含义：App Attest key id。
        |   写入阶段：从 assertion envelope.keyId 写入。
        |
        +-- createdAt
        |   含义：proof 创建时间；当前等于 contentDigest.capturedAt。
        |   写入阶段：AppAttestCaptureAssertionSigner.sign。
        |
        +-- value
            含义：base64url(canonical JSON(CaptureAssertionProofValue))。
            写入阶段：AppAttestCaptureAssertionSigner.sign。
```

## 7. Proof Value 总树

`manifest.proofs[0].value` base64url 解码后是 JSON：

```text
CaptureAssertionProofValue
|
+-- contentDigest
|   写入阶段：pending processor 从 unsigned HEIC、manifest.payload、AVDepthData 重新计算。
|   代码位置：CaptureContentDigest.make，TAPPendingCaptureProcessor.sign。
|   |
|   +-- schemaID
|   |   含义：固定为 urn:tapnap:tapcam:capture-content-digest:v1。
|   |   验证：必须等于当前支持版本。
|   |
|   +-- manifestSchemaID
|   |   含义：被签名的 manifest schema id。
|   |   验证：必须等于 manifest.schema.id。
|   |
|   +-- captureID
|   |   含义：被签名的 captureID。
|   |   验证：必须等于 manifest.payload.id。
|   |
|   +-- capturedAt
|   |   含义：被签名的拍摄时间。
|   |   验证：必须等于 manifest.payload.capturedAt。
|   |
|   +-- rgb
|   |   含义：primary HEIC image 解码为 RGBA8 后的 SHA-256。
|   |   验证：按第 8 节规则重算。
|   |
|   +-- depth
|   |   含义：AVDepthData 转 DepthFloat32 后的 SHA-256。
|   |   验证：按第 8 节规则重算。
|   |
|   +-- metadata
|       含义：manifest.payload canonical JSON 的 SHA-256。
|       验证：按第 8 节规则重算。
|
+-- assertionEnvelope
    写入阶段：AppAttestCaptureAssertionSigner.sign 调用 AppAttestClient.generateAssertion 返回。
    |
    +-- credentialName
    |   含义：调用方定义的 credential name，照片固定为 photo_keyid。
    |   验证：必须等于服务端照片 credential 策略。
    |
    +-- keyId
    |   含义：Apple App Attest key id。
    |   验证：必须能在服务端 credential store 查到有效公钥。
    |
    +-- challengeId
    |   含义：challenge 记录 id；长期 challenge 模式下可以是稳定 id。
    |   验证：一次性模式查 challenge store；长期模式查服务端静态配置。
    |
    +-- assertionObject
    |   含义：base64url Apple DCAppAttestService.generateAssertion 返回的 raw assertion object。
    |   验证：用 attested public key、clientData、teamID、bundleID 验签。
    |
    +-- requestBinding
        含义：被 assertion 签名的 clientData 输入。
        验证：按第 9 节规则重算和比较。
```

## 8. Content Digest 计算规则

`CaptureContentDigest.canonicalJSONData()` 使用：

```text
JSONEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
```

所有 hash 输出都是：

```text
base64url(SHA256(bytes))
```

### 8.1 RGB digest

代码位置：`CaptureContentDigest.rgbComponent(from:)`。

输入：

```text
original HEIC bytes
```

步骤：

```text
CGImageSourceCreateWithData(heicData)
CGImageSourceCreateImageAtIndex(source, 0)
decode/draw into CGContext
  colorSpace = DeviceRGB
  bitsPerComponent = 8
  bytesPerPixel = 4
  bytesPerRow = width * 4
  bitmapInfo = premultipliedLast + byteOrder32Big
SHA256(all RGBA8 bytes, including every row, no extra row padding)
```

输出 component：

```json
{
  "mediaType": "image/heic-primary-rgba8",
  "width": 4032,
  "height": 3024,
  "algorithm": "SHA-256",
  "value": "<base64url sha256>"
}
```

服务端要求：

- 必须能解码 HEIC primary image。
- 必须使用和客户端等价的 RGBA8 canonicalization。
- 如果服务端库解码色彩管理、alpha premultiplication 或 orientation 规则不同，RGB hash 可能不一致。
- 无法重算 RGB 时，不能声明 `contentVerified`。

### 8.2 Depth digest

代码位置：`CaptureContentDigest.depthComponent(from:)`。

输入：

```text
Apple auxiliary depth/disparity attachment
```

步骤：

```text
TAPDepthHEICReader.depthData(from:)
  |
  +-- first try kCGImageAuxiliaryDataTypeDepth
  |
  +-- fallback kCGImageAuxiliaryDataTypeDisparity

AVDepthData(fromDictionaryRepresentation:)
AVDepthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)

for each row y:
  for each x:
    take Float32.bitPattern
    write UInt32 littleEndian
  SHA256(row canonical bytes)

Do not include CVPixelBuffer row padding.
```

输出 component：

```json
{
  "mediaType": "application/vnd.tapnap.depth-float32",
  "width": 768,
  "height": 576,
  "algorithm": "SHA-256",
  "value": "<base64url sha256>"
}
```

服务端要求：

- 必须能读取 Apple auxiliary depth 或 disparity。
- 必须能转换到 metric DepthFloat32。
- 必须按 little-endian Float32 bit pattern 序列化。
- 无法读取 depth 时，返回 `AUX_DEPTH_MISSING` 或 `DEPTH_CONVERSION_FAILED`。

### 8.3 Metadata digest

代码位置：`CaptureContentDigest.metadataComponent(from:)`。

输入：

```text
manifest.payload
```

步骤：

```text
TAPDepthManifestEncoder.payloadDataExcludingProofs(payload)
  |
  +-- JSONEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  |
  +-- location 缺失时编码为 "location": null

SHA256(payload canonical JSON bytes)
```

输出 component：

```json
{
  "mediaType": "application/vnd.tapnap.depth-manifest.payload+json;version=1",
  "width": null,
  "height": null,
  "algorithm": "SHA-256",
  "value": "<base64url sha256>"
}
```

重要边界：

- `proofs` 不参与 metadata hash。
- EXIF、GPS、TIFF 不参与 metadata hash。
- 只有 XMP manifest 的 `payload` 是 TAP 元数据权威输入。

## 9. Request Binding 规则

签名时构造的 protected request：

```text
method = POST
path = /tapcam/captures/{captureID}/assertion
query = []
body = canonical JSON(contentDigest)
nonce = {captureID}
challenge = backend challenge 或长期 challenge
```

当前签名代码位置：`AppAttestCaptureAssertionSigner.swift:31`。

当前验签代码位置：`AppAttestSignatureVerificationPanel.swift:702`。

验证端必须检查：

```text
binding.method == "POST"
binding.path == "/tapcam/captures/{contentDigest.captureID}/assertion"
binding.query == []
binding.nonce == contentDigest.captureID
binding.bodySHA256 == base64url(SHA256(contentDigest.canonicalJSONData()))
binding.challengeSHA256 == expected challenge SHA-256
```

`requestBinding.canonicalData()` 当前本地验证面板使用：

```text
JSONEncoder.outputFormatting = [.sortedKeys]
JSONEncoder.dateEncodingStrategy = .iso8601
```

这个 canonical JSON 是传给 App Attest assertion verifier 的 `clientData`。

长期 challenge 模式下：

```text
expectedChallengeSHA256 = base64url(SHA256(configuredLongTermChallenge))
```

一次性 challenge 模式下：

```text
challengeRecord = challengeStore[assertionEnvelope.challengeId]
expectedChallengeSHA256 = base64url(SHA256(challengeRecord.rawChallenge))
```

## 10. 签名流程

```text
CameraViewModel.capture(appAttestClient)
|
| foreground capture
| 说明：这里传给 pipeline 的 assertionSigner 是 nil。
| 代码：CameraViewModel+Capture.swift:65
v
CapturePipeline.runSingleCamJob
|
v
EmbeddedPhotoPackager.package(assertionSigner: nil)
|
+-- TAPDepthManifestBuilder.makeManifest
|   生成 unsigned manifest，proofs = []。
|
+-- AVCapturePhoto.fileDataRepresentation(with: TAPPhotoFileMetadataCustomizer)
|   生成 base HEIC，包含 primary image、Apple auxiliary depth、EXIF/GPS/TIFF。
|
+-- TAPDepthHEICWriter.injectingManifest(unsignedManifest, into: baseHEICData)
|   把 unsigned manifest 写入 XMP tapdepth:Manifest。
|
v
PhotoLibraryCaptureArtifactWriter
|
| 当前架构不是直接导出到 Photos，而是先进入 TAP Library pending store。
v
TAPPendingCaptureStore
|
v
TAPPendingCaptureProcessor.processPendingCaptures(appAttestClient)
|
+-- read unsigned HEIC
|
+-- TAPDepthHEICReader.decodedManifest
|   读取 XMP tapdepth:Manifest。
|
+-- TAPDepthHEICReader.depthData
|   读取 Apple depth/disparity auxiliary data。
|
+-- CaptureContentDigest.make
|   计算 rgb、depth、metadata 三个 component hash，并绑定 captureID/capturedAt/schemaID。
|
+-- AppAttestCaptureAssertionSigner.sign
|   |
|   +-- contentDigest.canonicalJSONData()
|   |
|   +-- AppAttestProtectedRequest(
|   |     method: POST,
|   |     path: /tapcam/captures/{captureID}/assertion,
|   |     body: canonical contentDigest JSON,
|   |     nonce: captureID
|   |   )
|   |
|   +-- client.prepareIfNeeded(credentialName: photo_keyid)
|   |
|   +-- client.generateAssertion(credentialName: photo_keyid, request)
|   |   |
|   |   +-- 一次性模式：向服务器请求 assertion challenge。
|   |   |
|   |   +-- 长期模式：使用固定 challenge。
|   |       当前 production HTTP 不改代码时仍会请求 endpoint，但服务端可返回同一个长期 challenge。
|   |
|   +-- CaptureAssertionProofValue(contentDigest, assertionEnvelope)
|   |
|   +-- proof.value = base64url(canonical JSON(CaptureAssertionProofValue))
|
+-- signedManifest = TAPDepthManifest(payload: oldPayload, proofs: [proof])
|
+-- TAPDepthHEICWriter.injectingManifest(signedManifest, into: unsignedData)
|   只替换 XMP manifest。primary image 和 auxiliary depth 尽量通过 ImageIO copy path 保留。
|
v
PhotoLibraryWriter.saveDepthHEIC
|
v
TAPCamDepth Photos Album
```

关键解释：

- foreground 阶段 `assertionSigner` 为 nil 是故意的。
- 真正签名发生在 pending processor，而不是按下快门的同步路径。
- 这样可以让拍摄不被 App Attest 网络、protected data、弱网阻塞。
- unsigned capture 不应自动成为最终可信产物；最终可信产物是 pending signing 后导出的 signed HEIC。

## 11. 服务端验证模式

### 11.1 模式 A：只验证公钥有效性

目标：

```text
验证 App Attest credential 是否真实有效，并把 keyId -> publicKey 存起来。
图片完整性不在这个 API 内验证。
```

适用场景：

- 服务器只负责注册和托管 App Attest 公钥。
- 第三方 verifier 后续拿 `keyId` 查询公钥，自己验 assertion 和图片完整性。

服务端需要实现现有基础接口：

```text
POST /app-attest/challenges
POST /app-attest/attestations
POST /app-attest/credentials/status
```

推荐新增查询接口：

```http
GET /app-attest/credentials/{keyId}
```

响应：

```json
{
  "credentialName": "photo_keyid",
  "keyId": "<base64url key id>",
  "credentialId": "<base64url credential id>",
  "publicKeyX962": "<base64url X9.62 public key>",
  "publicKeySHA256": "<base64url sha256 public key>",
  "teamId": "<Apple Team ID>",
  "bundleId": "<Bundle ID>",
  "environment": "production",
  "status": "active",
  "createdAt": "2026-05-12T00:00:00Z",
  "updatedAt": "2026-05-12T00:00:00Z"
}
```

服务端必须存储：

```text
CredentialRecord
|
+-- credentialName
|   说明：当前照片固定 photo_keyid。
|
+-- keyId
|   说明：App Attest key id，manifest proof 和 assertion envelope 都引用它。
|
+-- credentialId
|   说明：attestation verifier 返回的 credential id。
|
+-- publicKeyX962
|   说明：验证 assertion signature 的公钥。
|
+-- publicKeySHA256
|   说明：用于展示和快速对比。
|
+-- teamId
|   说明：Apple Team ID。
|
+-- bundleId
|   说明：App bundle identifier。
|
+-- environment
|   说明：development 或 production。
|
+-- lastCounter
|   说明：服务端做 strict counter policy 时使用。
|
+-- status
|   说明：active、revoked、disabled。
|
+-- createdAt / updatedAt
    说明：审计字段。
```

模式 A 的验证结论只能是：

```text
keyValid
```

它不能声明：

```text
contentVerified
assertionVerified
fullyVerified
```

因为它没有读取和重算图片内容。

### 11.2 模式 B：服务端验证整张图片完整性

目标：

```text
服务器接收 HEIC，读取 manifest，重算 RGB/depth/metadata hash，验证 requestBinding，查询公钥，验证 App Attest assertion。
```

推荐 API：

```http
POST /tapcam/captures/verify
Content-Type: multipart/form-data

image=@capture.heic
challengeMode=static | oneTime
rawChallengeBase64URL=<optional, if caller supplies challenge>
```

长期 challenge 模式下，`rawChallengeBase64URL` 可以省略，服务端使用配置中的长期 challenge。

一次性 challenge 模式下，服务端从 `assertionEnvelope.challengeId` 查询 challenge record。

推荐响应：

```json
{
  "status": "accepted",
  "verificationLevel": "fullyVerified",
  "challengeMode": "static",
  "captureID": "<manifest.payload.id>",
  "capturedAt": "<manifest.payload.capturedAt>",
  "credentialName": "photo_keyid",
  "keyId": "<assertionEnvelope.keyId>",
  "publicKeySHA256": "<base64url sha256 public key>",
  "hashes": {
    "rgb": "<base64url sha256>",
    "depth": "<base64url sha256>",
    "metadata": "<base64url sha256>",
    "contentDigestBodySHA256": "<base64url sha256>"
  },
  "assertion": {
    "challengeId": "tapcam-photo-v1",
    "counter": 123,
    "counterPolicy": "positive"
  },
  "warnings": [],
  "errors": []
}
```

失败响应：

```json
{
  "status": "rejected",
  "verificationLevel": "failed",
  "captureID": null,
  "errors": [
    {
      "code": "XMP_MANIFEST_MISSING",
      "stage": "manifest",
      "severity": "error",
      "message": "XMP tapdepth:Manifest was not found.",
      "details": {}
    }
  ]
}
```

## 12. 完整验签步骤

服务端模式 B 推荐按这个顺序执行。顺序很重要，因为它让错误原因稳定、可解释。

1. 接收原始 HEIC bytes。
2. 确认输入是原始文件，不是缩略图或编辑后副本。
3. 用 HEIC parser 打开 container。
4. 读取 primary image item。
5. 读取 Apple auxiliary depth 或 disparity attachment。
6. 读取 XMP metadata。
7. 从 XMP path `tapdepth:Manifest` 取 manifest JSON 字符串。
8. JSON decode 为 TAPDepthManifest。
9. 校验 `manifest.schema.id == urn:tapnap:tapcam:depth-manifest:v1`。
10. 找到 `manifest.proofs` 中 `type == appAttestAssertion` 的 proof。
11. 校验 `proof.algorithm == AppAttestKit.AppAttestAssertionEnvelope.v1`。
12. base64url decode `proof.value`。
13. JSON decode `CaptureAssertionProofValue`。
14. 校验 `proof.keyID == assertionEnvelope.keyId`。
15. 校验 `assertionEnvelope.credentialName == photo_keyid`。
16. 从 original HEIC 重算 RGB digest。
17. 从 auxiliary depth/disparity 重算 depth digest。
18. 从 `manifest.payload` 重算 metadata digest。
19. 构造 recomputed `CaptureContentDigest`。
20. 比较 recomputed digest 和 `proofValue.contentDigest` 完全相等。
21. canonical encode recomputed contentDigest。
22. 计算 `base64url(SHA256(canonicalContentDigestJSON))`。
23. 校验 `requestBinding.bodySHA256`。
24. 校验 request method、path、query、nonce。
25. 根据 challengeMode 校验 `requestBinding.challengeSHA256`。
26. canonical encode `requestBinding` 得到 `clientData`。
27. 用 `assertionEnvelope.keyId` 查询 CredentialRecord。
28. 校验 CredentialRecord status、credentialName、teamId、bundleId、environment。
29. base64url decode `assertionEnvelope.assertionObject`。
30. 用 publicKeyX962、clientData、teamId、bundleId 调 App Attest assertion verifier。
31. 根据 counter policy 检查 counter。
32. 返回 verificationLevel 和结构化错误/警告。

## 13. Verification Level

推荐服务端返回以下层级：

| level | 含义 |
| --- | --- |
| `unsigned` | 文件存在 TAP manifest，但没有 appAttestAssertion proof。 |
| `keyValid` | App Attest credential 已验证并且公钥有效，但没有验证图片。 |
| `contentVerified` | RGB、depth、metadata hash 与 proof.contentDigest 匹配。 |
| `bindingVerified` | requestBinding 与 contentDigest、captureID、challenge 匹配。 |
| `assertionVerified` | App Attest assertion signature 验证通过。 |
| `fullyVerified` | content、binding、credential、assertion、challenge policy 都通过。 |
| `failed` | 任一步失败。 |

长期 challenge 模式下，只要服务端明确使用 static challenge policy，仍然可以返回 `fullyVerified`。但响应里必须包含：

```json
{
  "challengeMode": "static",
  "replayProtection": "content-and-counter-only"
}
```

不要把它描述成 one-time challenge replay protection。

## 14. Counter Policy

当前本地验证面板使用：

```text
counterPolicy = positive
```

代码位置：`AppAttestSignatureVerificationPanel.swift:601`。

含义：

- assertion counter 必须是正数。
- 不要求大于服务端已保存的 previous counter。
- 适合公开文件验真，因为旧照片可能在很久以后被第三方验证，验证顺序不可控。

服务端可以支持三种策略：

| policy | 推荐场景 | 风险 |
| --- | --- | --- |
| `positive` | 公开图片验真、离线照片、第三方任意顺序验证。 | 不能用 counter 阻止同一 assertion 重复提交。 |
| `strict` | 登录、支付、一次性业务请求。 | 老照片乱序验证会失败。 |
| `unchecked` | 只做兼容性测试。 | 不建议生产使用。 |

TAP Depth HEIC 图片验证推荐默认：

```text
counterPolicy = positive
```

如果你的服务端要做“每张照片只能提交一次”，建议另加业务去重：

```text
unique key = captureID 或 contentDigestBodySHA256
```

不要把图片验真的 counter policy 改成 strict，除非你明确接受旧照片乱序验证失败。

## 15. ChallengeRecord

一次性 challenge 模式需要存储：

```text
ChallengeRecord
|
+-- challengeId
|   说明：返回给客户端，后续 assertionEnvelope.challengeId 引用。
|
+-- rawChallenge 或 challengeSHA256
|   说明：rawChallenge 用于重算 App Attest clientDataHash；如果只保存 hash，则无法做需要 raw challenge 的 attestation verifier 输入。
|
+-- purpose
|   说明：attestation 或 assertion。
|
+-- credentialName
|   说明：照片 assertion 应为 photo_keyid。
|
+-- associatedKeyId
|   说明：可选，绑定某个 keyId。
|
+-- associatedCaptureID
|   说明：可选，绑定某张 capture。
|
+-- expiresAt
|   说明：过期时间。
|
+-- usedAt
|   说明：成功验证后写入。
|
+-- status
|   说明：issued、used、expired、revoked。
|
+-- createdAt
    说明：审计字段。
```

长期 challenge 模式不需要每张照片创建 ChallengeRecord，但建议保留配置记录：

```text
StaticChallengePolicy
|
+-- challengeId
|   说明：例如 tapcam-photo-v1。
|
+-- rawChallenge
|   说明：服务端配置的长期 challenge bytes。
|
+-- challengeSHA256
|   说明：公开展示时可只展示 hash。
|
+-- validFrom / validTo
|   说明：长期 challenge 也应支持版本轮换。
|
+-- status
    说明：active、deprecated、revoked。
```

## 16. 错误响应模型

推荐统一错误对象：

```json
{
  "code": "REQUEST_BODY_HASH_MISMATCH",
  "stage": "binding",
  "severity": "error",
  "message": "requestBinding.bodySHA256 does not match recomputed contentDigest JSON.",
  "details": {
    "expected": "<base64url>",
    "actual": "<base64url>"
  },
  "upstream": {
    "validationStage": "assertion",
    "errorCode": "ASSERTION_SIGNATURE_INVALID",
    "message": "optional verifier message"
  }
}
```

字段说明：

```text
code
  稳定机器码。第三方 Agent 应优先依赖 code。

stage
  验证阶段。用于 UI 分组和日志索引。

severity
  error 或 warning。

message
  面向开发者的人类可读说明。

details
  可选结构化上下文，避免只拼字符串。

upstream
  可选。AppAttestVerifyKit 或底层 verifier 返回的原始 structured error。
```

推荐 stage：

```text
input
heic
manifest
proof
digest
binding
challenge
credential
attestation
assertion
counter
storage
internal
```

推荐 TAP 错误码：

| code | stage | 含义 |
| --- | --- | --- |
| `INPUT_INVALID` | input | 请求格式、multipart、base64 或参数非法。 |
| `HEIC_READ_FAILED` | heic | HEIC container 无法打开。 |
| `HEIC_ORIGINAL_REQUIRED` | heic | 输入疑似不是 original resource。 |
| `PRIMARY_IMAGE_MISSING` | heic | 没有 primary image item。 |
| `AUX_DEPTH_MISSING` | heic | 没有 depth/disparity auxiliary attachment。 |
| `DEPTH_CONVERSION_FAILED` | heic | depth/disparity 无法转 DepthFloat32。 |
| `XMP_MANIFEST_MISSING` | manifest | XMP `tapdepth:Manifest` 缺失。 |
| `MANIFEST_JSON_INVALID` | manifest | manifest JSON 无法 decode。 |
| `MANIFEST_SCHEMA_UNSUPPORTED` | manifest | schema id 或 version 不支持。 |
| `PROOF_MISSING` | proof | 没有 appAttestAssertion proof。 |
| `PROOF_ALGORITHM_UNSUPPORTED` | proof | proof.algorithm 不支持。 |
| `PROOF_VALUE_BASE64URL_INVALID` | proof | proof.value 不是合法 base64url。 |
| `PROOF_VALUE_JSON_INVALID` | proof | proof.value 解码后不是合法 proof JSON。 |
| `PROOF_KEY_MISMATCH` | proof | proof.keyID 与 assertionEnvelope.keyId 不一致。 |
| `CREDENTIAL_NAME_MISMATCH` | proof | assertionEnvelope.credentialName 不是期望值。 |
| `CONTENT_DIGEST_SCHEMA_UNSUPPORTED` | digest | contentDigest.schemaID 不支持。 |
| `CAPTURE_ID_MISMATCH` | digest | contentDigest.captureID 与 manifest.payload.id 不一致。 |
| `CAPTURED_AT_MISMATCH` | digest | contentDigest.capturedAt 与 manifest.payload.capturedAt 不一致。 |
| `RGB_HASH_MISMATCH` | digest | RGB hash 不匹配。 |
| `DEPTH_HASH_MISMATCH` | digest | depth hash 不匹配。 |
| `METADATA_HASH_MISMATCH` | digest | metadata hash 不匹配。 |
| `CONTENT_DIGEST_MISMATCH` | digest | recomputed digest 与 stored digest 不完全相等。 |
| `REQUEST_BODY_HASH_MISMATCH` | binding | requestBinding.bodySHA256 不匹配。 |
| `REQUEST_METHOD_INVALID` | binding | method 不是 POST。 |
| `REQUEST_PATH_INVALID` | binding | path 不是 `/tapcam/captures/{captureID}/assertion`。 |
| `REQUEST_QUERY_INVALID` | binding | query 不是空数组。 |
| `REQUEST_NONCE_INVALID` | binding | nonce 不是 captureID。 |
| `CHALLENGE_NOT_FOUND` | challenge | 一次性 challengeId 查不到。 |
| `CHALLENGE_PURPOSE_INVALID` | challenge | challenge purpose 不匹配。 |
| `CHALLENGE_EXPIRED` | challenge | challenge 已过期。 |
| `CHALLENGE_ALREADY_USED` | challenge | challenge 已使用。 |
| `CHALLENGE_HASH_MISMATCH` | challenge | challengeSHA256 不匹配。 |
| `KEY_NOT_REGISTERED` | credential | keyId 没有对应 CredentialRecord。 |
| `KEY_REVOKED` | credential | keyId 已撤销或禁用。 |
| `KEY_CREDENTIAL_MISMATCH` | credential | keyId 与 credentialName 不匹配。 |
| `ATTESTATION_INVALID` | attestation | attestation verifier 未通过。 |
| `ASSERTION_OBJECT_INVALID` | assertion | assertionObject CBOR 或结构非法。 |
| `ASSERTION_SIGNATURE_INVALID` | assertion | assertion signature 未通过。 |
| `ASSERTION_COUNTER_INVALID` | counter | counter policy 未通过。 |
| `APP_ID_MISMATCH` | assertion | teamID/bundleID/app id 不匹配。 |
| `VERIFIER_UPSTREAM_ERROR` | attestation/assertion | 底层 verifier 返回结构化错误，服务端只做透传封装。 |
| `INTERNAL_ERROR` | internal | 非预期服务端错误。 |

AppAttestVerifyKit 已有 structured error 字段：

```text
validation_stage
error_code
message
```

服务端封装时应保留为：

```json
{
  "upstream": {
    "validationStage": "<validation_stage>",
    "errorCode": "<error_code>",
    "message": "<message>"
  }
}
```

不要把 upstream error message 当成唯一可解析错误。

## 17. 第三方解析器展示面板建议

解析器只读图片，不需要修改图片。

推荐展示：

```text
File
|
+-- container
|   显示 HEIC 是否能读取、primary image 尺寸、auxiliary depth 是否存在。
|
+-- manifest
|   显示 schema、captureID、capturedAt、payload 全部字段。
|
+-- visual image
|   显示 primary image preview。
|
+-- depth
|   显示 depth width/height、pixel format、depth heatmap preview。
|
+-- hashes
|   显示 stored rgb/depth/metadata hash、recomputed hash、match/mismatch。
|
+-- proof
|   显示 proof.type、algorithm、keyID、createdAt。
|
+-- assertion envelope
|   显示 credentialName、keyId、challengeId、requestBinding、assertionObject size。
|
+-- verification
    显示 challengeMode、credential status、assertion result、verificationLevel、errors。
```

challenge 展示建议：

- 不要假设 HEIC 内包含 raw challenge。
- HEIC 当前只包含 `assertionEnvelope.challengeId` 和 `requestBinding.challengeSHA256`。
- 一次性 challenge 模式下，解析器需要用户或服务器提供 raw challenge。
- 长期 challenge 模式下，解析器可以内置或配置公开的 raw challenge，然后本地重算 hash。

## 18. 服务端实现核对清单

服务端至少需要：

- 能接收 original HEIC bytes。
- 能读取 XMP `tapdepth:Manifest`。
- 能读取 HEIC primary image 并按 RGBA8 canonicalization 计算 hash。
- 能读取 Apple auxiliary depth/disparity 并按 DepthFloat32 little-endian 计算 hash。
- 能按当前 Swift encoder 规则生成 canonical manifest payload JSON 和 contentDigest JSON。
- 能 base64url decode proof.value 和 assertionObject。
- 能按 requestBinding canonical JSON 生成 App Attest clientData。
- 能查询 `keyId -> publicKeyX962`。
- 能调用 App Attest attestation/assertion verifier，或复用 AppAttestVerifyKit 的 Rust verifier。
- 能明确选择 challengeMode：`oneTime` 或 `static`。
- 能返回统一错误码。

服务端不应声称完成验证，如果：

- 只验证了公钥，没有读取图片。
- 只解析了 manifest，没有重算 RGB/depth hash。
- 只验证了 assertion，没有确认 requestBinding.bodySHA256。
- 使用长期 challenge，却把结果描述成一次性 nonce 防重放。

## 19. 最小可行策略

如果当前目标是快速开放第三方验证，推荐第一版按这个策略落地：

```text
credential registration:
  server validates attestation and stores keyId -> publicKeyX962

photo assertion:
  use static long-term challenge "tapcam-photo-v1"
  counterPolicy = positive

verification API:
  POST /tapcam/captures/verify
  server verifies HEIC contentDigest + requestBinding + assertion signature

third-party parser:
  can run content verification locally
  can query server for public key or ask server return full verification result
```

这个策略的安全表述应为：

```text
The file is authentic for this App Attest key and matches the signed RGB/depth/metadata digest.
The verification uses a static challenge, so it is a file authenticity proof, not a one-time request anti-replay proof.
```

中文表述：

```text
该文件由对应 App Attest key 生成 assertion，且文件中的 RGB、深度和 TAP 元数据与被签名 digest 一致。
本验证使用长期 challenge，因此它证明文件真实性和完整性，不证明这次提交是一次性请求。
```
