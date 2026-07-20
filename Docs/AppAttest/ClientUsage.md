# App Attest Client Usage

Source links:

- [AppAttestClient protocol](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestProtocols.swift)
- [DefaultAppAttestClient](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/DefaultAppAttestClient.swift)
- [AppAttestProtectedRequest and AppAttestAssertionEnvelope](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestModels.swift)
- [TAPCamDemo runtime configuration](../../TAPCamDemo/App/AppAttestRuntime.swift)
- [TAPCamDemo capture assertion signer](../../TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift)

## Choose A Credential Name

```swift
let installCredentialName = "install:\(callerManagedInstallId)"
let userCredentialName = "user:\(callerManagedUserId)"
let tenantCredentialName = "tenant:\(tenantId):user:\(userId)"
```

`credentialName` is a caller-owned name for one App Attest credential. The kit
does not know whether it represents an install, user, tenant, or session. See
[CredentialNameGuide.md](CredentialNameGuide.md) for recommended patterns.

Caller responsibility: if a credential name contains user, tenant, install, or
session identity, treat it as sensitive in logs even when the credential name is
not itself a trust claim.

## Register A Key

```swift
let credential = try await appAttest.prepare(
    credentialName: installCredentialName
)
```

`prepare(credentialName:)` always creates a new App Attest key, asks Apple to
attest the public key, sends the attestation object to the backend, and saves
`credentialName -> keyId` only after the backend accepts registration.

## Register Only If Needed

```swift
let credential = try await appAttest.prepareIfNeeded(
    credentialName: userCredentialName
)
```

`prepareIfNeeded(credentialName:)` reuses a ready local credential. If no local
credential exists, it runs the full attestation flow.

## Generate Assertion For A Selected API

```swift
let request = AppAttestProtectedRequest(
    method: "POST",
    path: "/api/payment/confirm",
    body: paymentBodyData
)

let envelope = try await appAttest.generateAssertion(
    credentialName: userCredentialName,
    request: request
)

var urlRequest = URLRequest(url: paymentURL)
try envelope.applyHeaders(to: &urlRequest)
```

No request is protected unless the caller explicitly calls
`generateAssertion(credentialName:request:)` and applies the returned envelope.

## TAPCam Photo Capture Signatures

TAPCam photo capture signing is intentionally not modeled as a protected online
API request. The pending capture processor still calls
`prepareIfNeeded(credentialName:)` for `photo_keyid`, but it does not call
`generateAssertion(credentialName:request:)` because that API requests an
assertion challenge from the backend.

For a HEIC or JPG TAP depth photo, the app builds a `signingBinding` from the
canonical `contentDigest`, signs `SHA256(canonical signingBinding JSON)`
directly with `DCAppAttestService.generateAssertion`, and stores the resulting
`keyId`, `assertionObject`, `signingBinding`, and `contentDigest` in the fixed
TAP proof slot. The embedded manifest keeps `proofs: []`; proof bytes are not
part of the signed manifest payload.

The `contentDigest` is a C2PA-aligned content binding: it hashes the format
native photo bytes after excluding the fixed proof slot, plus canonical
`manifest.payload` JSON. It does not hash CoreGraphics-decoded RGB pixels or
`AVDepthData` converted to Float32. A verifier that later receives the photo can
first rebuild that binding locally, then call
`/tapcam/capture-signatures/verify` with `keyId`, `assertionObject`, and
`signingBinding`.

## Reset One Credential

```swift
try await appAttest.reset(credentialName: tenantCredentialName)
```

Reset deletes local credential metadata for that credential name only. It does
not reset other caller-defined credential names.

## TAPCamDemo Settings Mapping

- Release shows only App Attest `Status`.
- Debug shows the backend, credential name, prepare, and reset rows. These
  debug-only rows use a yellow background.
- `Prepare Credential` calls `prepare(credentialName:)`.
- `Reset Local Credential` calls `reset(credentialName:)` and clears the local
  `photo_keyid` health token metadata.
- Tapping `Not prepared` on the status row runs reset and then
  `prepare(credentialName:)`. The status row shows a spinner while this is
  running, then shows `Ready`.
- After preparation succeeds, the settings detail row shows only a redacted App
  Attest key ID summary; credential name and the full `keyId` stay out of the
  Release status details and accessibility labels.
- Enabling Help in Settings shows the `keyId` explanation inline below the App
  Attest `Status` row.

## TAPCamDemo Backend Configuration

TAPCamDemo reads only `APP_ATTEST_BACKEND_URL`.

- Debug: `https://dev.tapnap.net`
- Release/TestFlight: `https://www.tapnap.net`

The value must be an HTTPS base URL. Do not include `/healthz`, App Attest
endpoint paths, a bare IP address, localhost, or cleartext HTTP.

The first-launch warmup stores a local health token that binds the bundle id,
version/build, backend URL, App Attest environment, and `photo_keyid`
credential name. If any of those inputs change, the app resets the local
`photo_keyid` metadata and calls `prepare(credentialName:)` so the current
server receives a fresh registration. If the token still matches, the app may
reuse the local credential through `prepareIfNeeded(credentialName:)`.
