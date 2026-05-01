# Credential Name Guide

Source links:

- [AppAttestClient protocol](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestProtocols.swift)
- [Keychain credential store](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift)
- [TAPCamDemo demo view model](../../TAPCamDemo/AppAttestDemo/AppAttestDemoViewModel.swift)

## What It Is

`credentialName` is a caller-defined string that names one App Attest
credential. AppAttestKit only uses it as a lookup key for stored metadata:

```text
credentialName -> keyId / credentialId / status / environment / timestamps
```

It is not an Apple App Attest claim. It is not a user model. It is not generated
by the kit.

## Recommended Patterns

Anonymous or pre-login apps:

```swift
let credentialName = "install:\(callerManagedInstallId)"
```

Login-required apps:

```swift
let credentialName = "user:\(callerManagedUserId)"
```

Two-stage apps:

```swift
let anonymousCredentialName = "install:\(callerManagedInstallId)"
let accountCredentialName = "user:\(callerManagedUserId)"
```

Multi-tenant apps:

```swift
let credentialName = "tenant:\(tenantId):user:\(userId)"
```

## Caller Responsibilities

- Generate and persist install IDs outside AppAttestKit if the app needs install-level credentials.
- Pass account/user IDs only after the app knows the authenticated user.
- Keep the naming scheme stable. Changing the string means using a different credential.
- Prefer opaque backend IDs or hashed stable IDs instead of raw PII such as email addresses.

## Kit Responsibilities

- Store and retrieve the App Attest `keyId` for the given credential name.
- Run attestation and assertion flows.
- Never decide which credential name a business operation should use.
