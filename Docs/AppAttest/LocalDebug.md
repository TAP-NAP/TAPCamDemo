# Mock DEBUG Backend

Source links:

- [MockDebugAppAttestBackend](../../TAPCamDemo/AppAttestKit/MockDebugAppAttestBackend.swift)
- [AppAttestRuntimeFactory](../../TAPCamDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../TAPCamDemo/AppAttestDemo/AppAttestDemoView.swift)

## Purpose

`MockDebugAppAttestBackend` exists for early client development when no server
is available. It uses the fixed challenge string `nearbycommunity` and exports
the objects produced by the iOS App Attest APIs.

It does not prove production security. Real validation must happen on a server.

## How It Is Selected

The mock backend is selected explicitly with:

```swift
try AppAttestRuntimeFactory.make(mode: .mockDebug)
```

HTTP mode is selected explicitly with:

```swift
try AppAttestRuntimeFactory.make(
    mode: .http(baseURL: URL(string: "https://api.example.com")!)
)
```

The runtime no longer treats localhost-like URLs as mock mode. In Release
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

The fixed mock challenge has no expiration date. Production challenges still
must be short-lived and one-time-use on the server.

## Direct Attestation Object File Export

The mock backend exposes the latest raw `attestationObject` directly:

- `latestAttestationObject()`
- `latestAttestationObjectBase64URL()`

The demo UI has a separate `Save Attestation CBOR` button. It uses
`latestAttestationObject()` and opens the system file exporter so you can choose
where to save `attestationObject.cbor`.

The saved file is the raw binary CBOR returned by
`DCAppAttestService.attestKey`, not JSON and not base64 text.

## Release Guard

The mock backend is compiled only under `#if DEBUG`. Release builds get an
unavailable shell with the same name so accidental references fail at compile
time.
