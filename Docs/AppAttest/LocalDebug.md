# Local DEBUG Backend

Source links:

- [LocalDebugAppAttestBackend](../../TAPCamDemo/AppAttestKit/LocalDebugAppAttestBackend.swift)
- [AppAttestRuntimeFactory](../../TAPCamDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../TAPCamDemo/AppAttestDemo/AppAttestDemoView.swift)

## Purpose

`LocalDebugAppAttestBackend` exists for early client development when no server
is available. It generates local challenges and exports the objects produced by
the iOS App Attest APIs.

It does not prove production security. Real validation must happen on a server.

## How It Is Selected

In DEBUG builds, `AppAttestRuntimeFactory` treats localhost-like backend URLs as
local debug mode:

```swift
http://localhost:8080
http://127.0.0.1:8080
http://*.local
```

In Release builds, localhost-like HTTP backends are rejected.

## Exported JSON

The debug export includes:

- `challengeId`
- `challenge`
- `purpose`
- `subject`
- `keyId`
- `attestationObject`
- `attestationCertificates`
- `assertionObject`
- `requestBinding`
- `createdAt`
- `expiresAt`

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

`expiresAt` belongs to the locally generated challenge. It is intentionally
short-lived and is not the certificate expiration date.

## Direct Attestation Object File Export

The local backend also exposes the latest raw `attestationObject` directly:

- `latestAttestationObject()`
- `latestAttestationObjectBase64URL()`

The demo UI has a separate `Save Attestation CBOR` button. It uses
`latestAttestationObject()` and opens the system file exporter so you can choose
where to save `attestationObject.cbor`.

The saved file is the raw binary CBOR returned by
`DCAppAttestService.attestKey`, not JSON and not base64 text.

## Release Guard

The local backend is compiled only under `#if DEBUG`. Release builds get an
unavailable shell with the same name so accidental references fail at compile
time.
