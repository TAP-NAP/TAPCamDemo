# Local DEBUG Backend

Source links:

- [LocalDebugAppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/LocalDebugAppAttestBackend.swift)
- [AppAttestRuntimeFactory](../../TAPCamDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../TAPCamDemo/AppAttestDemo/AppAttestDemoView.swift)

## Purpose

`LocalDebugAppAttestBackend` exists for early client development when no server
is available. TAPCamDemo configures it with the fixed challenge string
`TapTapNapNap123123` for both attestation and assertion challenges, and exports
the objects produced by the iOS App Attest APIs.

It does not prove production security. Real validation must happen on a server.

## How It Is Selected

The local debug backend is selected explicitly with:

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

The runtime no longer treats localhost-like URLs as local debug mode. In Release
builds, localhost-like HTTP backends are still rejected.

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

The demo UI has a separate `Save Attestation CBOR` button. It uses
`latestAttestationObject()` and opens the system file exporter so you can choose
where to save `attestationObject.cbor`.

The saved file is the raw binary CBOR returned by
`DCAppAttestService.attestKey`, not JSON and not base64 text.

## Release Guard

The local debug backend is compiled only under `#if DEBUG`, so accidental
Release references fail at compile time.
