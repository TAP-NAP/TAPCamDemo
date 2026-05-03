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

## Reset One Credential

```swift
try await appAttest.reset(credentialName: tenantCredentialName)
```

Reset deletes local credential metadata for that credential name only. It does
not reset other caller-defined credential names.

## Demo Button Mapping

- `Credential name`: the caller-defined name used to find a saved `keyId`.
- `Ensure Attested`: calls `prepareIfNeeded(credentialName:)`.
- `Force New Attestation`: calls `prepare(credentialName:)`.
- `Check Credential`: calls `status(credentialName:)`.
- `Generate Assertion`: calls `generateAssertion(credentialName:request:)` for the method/path/body shown in the form.
- `Save Attestation CBOR`: exports the raw `attestationObject` returned by Apple.
