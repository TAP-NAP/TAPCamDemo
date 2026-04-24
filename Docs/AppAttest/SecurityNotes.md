# App Attest Security Notes

Source links:

- [DefaultAppAttestClient](../../TAPCamDemo/AppAttestKit/DefaultAppAttestClient.swift)
- [Keychain credential store](../../TAPCamDemo/AppAttestKit/KeychainAppAttestCredentialStore.swift)
- [Error model](../../TAPCamDemo/AppAttestKit/AppAttestError.swift)
- [HTTP release localhost guard](../../TAPCamDemo/AppAttestKit/HTTPAppAttestBackend.swift)

## What The Client Can Trust

The client can call Apple App Attest APIs and generate local key handles,
attestation objects, and assertion objects. It cannot decide that an attestation
is trustworthy by itself.

The backend must validate attestation and assertion results.

## Why Keychain Is Used

The App Attest private key is not stored by this app. Apple keeps it inside the
system-protected key material and gives the app a `keyId` handle.

The Keychain store saves:

```text
subject -> keyId / credentialId / status / environment / createdAt
```

If `keyId` is lost, the app cannot use the previously registered key and must
register a new one. Keychain is used because this metadata is security-sensitive
credential state, not ordinary user preference data.

## Challenge And Replay Protection

Production challenges must come from the backend, be short lived, and be
single-use. The backend must bind each challenge to its purpose and subject.

Assertions bind the challenge to method, path, query, body hash, and optional
nonce so an assertion for one request cannot be replayed as another request.

## Unsupported Devices

`DCAppAttestService.isSupported` can be false. The kit returns
`AppAttestError.unsupportedDevice`; the app and backend must decide whether to
degrade, retry later, or block the action.

## Local Debug Is Not Security

`LocalDebugAppAttestBackend` is for object generation and export only. It does
not replace server validation and cannot appear in Release builds.
