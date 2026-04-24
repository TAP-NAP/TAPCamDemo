# App Attest Client Usage

Source links:

- [AppAttestSubject](../../TAPCamDemo/AppAttestKit/AppAttestSubject.swift)
- [AppAttestClient protocol](../../TAPCamDemo/AppAttestKit/AppAttestProtocols.swift)
- [DefaultAppAttestClient](../../TAPCamDemo/AppAttestKit/DefaultAppAttestClient.swift)
- [AppAttestProtectedRequest and AppAttestAssertionEnvelope](../../TAPCamDemo/AppAttestKit/AppAttestModels.swift)
- [TAPCamDemo view model example](../../TAPCamDemo/AppAttestDemo/AppAttestDemoViewModel.swift)

## Create Subjects

```swift
let installSubject = AppAttestSubject(type: "install", id: callerManagedInstallId)
let userSubject = AppAttestSubject(type: "user", id: callerManagedUserId)
let tenantSubject = AppAttestSubject(type: "tenantUser", id: "\(tenantId):\(userId)")
```

`AppAttestSubject` is a backend-defined credential scope, not something Apple
attests. The kit does not create install IDs, read login state, know user IDs,
or choose a strategy. Callers decide what `type` and `id` mean before calling
AppAttestKit.

## Register A Key

```swift
let credential = try await appAttest.prepare(subject: installSubject)
```

`prepare(subject:)` always creates and asks Apple to attest a new App Attest
key. The subject is sent to the backend so the backend can store that verified
key under the caller-defined scope. The key is saved locally only after the
backend accepts the attestation.

## Register Only If Needed

```swift
let credential = try await appAttest.prepareIfNeeded(subject: userSubject)
```

`prepareIfNeeded(subject:)` reuses a ready local credential. If no local
credential exists, it runs the full attestation flow.

## Generate Assertion For A Selected API

```swift
let request = AppAttestProtectedRequest(
    method: "POST",
    path: "/api/payment/confirm",
    body: paymentBodyData
)

let envelope = try await appAttest.generateAssertion(
    subject: userSubject,
    request: request
)

var urlRequest = URLRequest(url: paymentURL)
try envelope.applyHeaders(to: &urlRequest)
```

No request is protected unless the caller explicitly calls
`generateAssertion(subject:request:)` and applies the returned envelope.

## Reset One Subject

```swift
try await appAttest.reset(subject: tenantSubject)
```

Reset deletes local credential metadata for that subject only. It does not reset
other caller-defined subjects.
