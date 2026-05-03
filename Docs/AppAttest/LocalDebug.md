# Local DEBUG Backend

Source links:

- [LocalDebugAppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/LocalDebugAppAttestBackend.swift)
- [AppAttestRuntimeFactory](../../TAPCamDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift)

## Purpose

`LocalDebugAppAttestBackend` exists for early client development when no server
is available. TAPCamDemo configures it with the fixed challenge string
`TapTapNapNap123123` for both attestation and assertion challenges, and exports
the objects produced by the iOS App Attest APIs.

It does not prove production security. Real validation must happen on a server.

## How It Is Selected

TAPCamDemo selects the backend at launch from build settings expanded into
`Info.plist`:

```text
APP_ATTEST_BACKEND_MODE=localDebug
APP_ATTEST_LOCAL_CHALLENGE=TapTapNapNap123123

APP_ATTEST_BACKEND_MODE=http
APP_ATTEST_BACKEND_URL=https://api.example.com
```

The same mode can be exercised directly in tests with:

```swift
try AppAttestRuntimeFactory.make(
    mode: .localDebug(challenge: "TapTapNapNap123123")
)
```

HTTP mode is selected explicitly with:

```swift
try AppAttestRuntimeFactory.make(
    mode: .http(baseURL: URL(string: "https://api.example.com")!)
)
```

Release settings show only App Attest status. Debug settings also show the
active backend and local debug controls; those debug-only rows use a yellow
background and are compiled out of Release UI. The settings UI no longer changes
backend mode at runtime. In Release builds, localhost-like HTTP backends are
still rejected. While preparation runs, the status row shows a spinner. After
preparation succeeds, the status row shows `Ready` and the details row below it
shows only the App Attest `keyId`. When Help is enabled, the `keyId` explanation
appears inline directly below the status row.

## Exported JSON

The debug export includes:

- `challengeId`
- `challenge`
- `purpose`
- `credentialName`
- `keyId`
- `attestationObject`
- `attestationCertificates`
- `assertionObject`
- `requestBinding`
- `createdAt`

These fields are base64url encoded where they contain binary data.

`attestationObject` is the complete raw CBOR object returned by
`DCAppAttestService.attestKey`. It is the primary artifact another verifier
needs for App Attest registration validation.

`attestationCertificates` is parsed from `attestationObject.attStmt.x5c` when
that field is present. Each certificate includes:

- `index`
- `derBase64`
- `derBase64URL`
- `pem`

The fixed local debug challenge uses the package's debug lifetime. Production
challenges still must be short-lived and one-time-use on the server.

## Direct Attestation Object File Export

The local debug backend exposes the latest raw `attestationObject` directly:

- `latestAttestationObject()`
- `latestAttestationObjectBase64URL()`

The debug settings UI has a separate `Export Attestation CBOR` button. It uses
`latestAttestationObject()` and opens the system file exporter so you can choose
where to save `attestationObject.cbor`.

The saved file is the raw binary CBOR returned by
`DCAppAttestService.attestKey`, not JSON and not base64 text.

## Release Guard

`LocalDebugAppAttestBackend` is available to support explicit Release local QA,
but Release defaults to HTTP configuration. Do not ship Release local debug
mode as a production trust decision.
