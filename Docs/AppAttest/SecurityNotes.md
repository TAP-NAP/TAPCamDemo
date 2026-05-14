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
The current TAPCamDemo mainline also sends assertion challenges and lets the
client generate assertion envelopes; backend assertion verification is a
server-side rollout step, not a client-side trust shortcut.

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

## Challenge And Replay Protection

Production challenges must come from the backend, be short lived, and be
single-use. The backend must bind each challenge to purpose and credential name.

Assertions bind the challenge to method, path, query, body hash, and optional
nonce so an assertion for one request cannot be replayed as another request.

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
