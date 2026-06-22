# App Attest Security Notes

Source links:

- [DefaultAppAttestClient](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/DefaultAppAttestClient.swift)
- [Keychain credential store](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift)
- [Error model](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestError.swift)
- [HTTP backend adapter](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/HTTPAppAttestBackend.swift)

## What The Client Can Trust

The client can call Apple App Attest APIs and generate local key handles,
attestation objects, and assertion objects. It cannot decide that an attestation
is trustworthy by itself.

The backend must validate attestation results before accepting registration.
TAPCam photo capture signing uses the registered `photo_keyid` key to sign a
capture `signingBinding` and stores the resulting assertion in the TAP photo
proof.
The client still does not get to decide that the assertion is trustworthy; a
verifier must check the signature with the registered backend credential.

The app also revalidates the final signed HEIC or JPG before Photos export.
That check does not prove server trust, but it does ensure the exported file
still contains the expected container, manifest id, App Attest proof envelope,
digest binding, and auxiliary depth.

## Why Keychain Stores keyId

The App Attest private key is not stored by this app. Apple keeps it inside
system-protected key material and gives the app a `keyId` handle.

The Keychain store saves:

```text
credentialName -> keyId / credentialId / status / environment / createdAt / updatedAt
```

`keyId` is required later by `DCAppAttestService.generateAssertion`. If it is
lost after app restart, the app cannot use the previously registered key and
must run attestation again. That would create unnecessary backend credential
records and makes each app duplicate the same credential lifecycle code.

Keychain stores only credential metadata. It does not store the App Attest
private key.

## Credential Names Are Not Trust Claims

`credentialName` is caller-defined. The kit does not know whether it contains an
install ID, user ID, tenant ID, or session ID. Prefer opaque backend IDs or
hashed stable IDs instead of raw PII.

The backend must decide whether a given credential name is allowed for the
current authenticated account or business action.

Credential names and key ids are diagnostic-sensitive even when they are not
trust claims. TAPCamDemo's current `photo_keyid` is fixed and non-PII, but any
future credential name that contains user, tenant, install, or session identity
must remain private in logs. Public error summaries should use
`TAPDiagnostics.describe` rather than raw localized errors, URLs, or backend
payloads.

The same boundary applies to user-visible text. Settings must use
`AppAttestCredentialPresentation` for generic failure status and redacted key ID
summaries and `AppAttestRuntime.backendPublicSummary` for backend status; full
key IDs, localized errors, failing URLs, paths, backend URLs, backend text, and
raw diagnostic payloads should not appear in visible text or accessibility
labels.

## Challenge And Replay Protection

Production challenges must come from the backend, be short lived, and be
single-use for attestation and online protected request flows. The backend must
bind each challenge to purpose and credential name.

Online request assertions bind the challenge to method, path, query, body hash,
and optional nonce so an assertion for one request cannot be replayed as
another request.

TAPCam photo capture signing does not use an assertion challenge because the
business claim is offline file signing, not server freshness. Its assertion
binds `schemaID`, `operation`, `captureID`, and `bodySHA256` through the
canonical `signingBinding`.

## Unsupported Devices

`DCAppAttestService.isSupported` can be false. The kit returns
`AppAttestError.unsupportedDevice`; the app and backend must decide whether to
degrade, retry later, or block the action.

## Server Backend Only

TAPCamDemo only connects to HTTPS App Attest server base URLs. Debug builds use
the development server and development App Attest metadata; Release and
TestFlight builds use the production server and production metadata. Local
debug backends, bare IP URLs, localhost URLs, cleartext HTTP, and endpoint paths
are not supported runtime configuration.
