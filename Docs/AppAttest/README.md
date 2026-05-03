# TAPCamDemo App Attest

This folder documents TAPCamDemo's App Attest integration. The reusable client
implementation now comes from the upstream
[TAP-NAP/AppAttestKit](https://github.com/TAP-NAP/AppAttestKit) Swift Package.

## Code Boundaries

- [AppAttestKit](https://github.com/TAP-NAP/AppAttestKit/tree/main/Sources/AppAttestKit) contains reusable protocols and core flows.
- [DefaultAppAttestClient](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/DefaultAppAttestClient.swift) owns attestation, assertion, and credential metadata persistence.
- [KeychainAppAttestCredentialStore](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift) stores `credentialName -> keyId` metadata.
- [HTTPAppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/HTTPAppAttestBackend.swift) is the production HTTP backend adapter.
- [LocalDebugAppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/LocalDebugAppAttestBackend.swift) is fixed-challenge object export support for local development.
- [DepthAnalyzerSettingsView](../../TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift) is TAPCamDemo's UI usage example, not reusable core logic.
- [AppAttestRuntime](../../TAPCamDemo/App/AppAttestRuntime.swift) wires TAPCamDemo to the backend selected by build-time `APP_ATTEST_*` configuration.

## Settings UI

Release settings show only the App Attest `Status` row. Debug builds also show
backend, credential, prepare, reset, and export controls, and those debug-only
rows use a yellow background so they are easy to distinguish from Release UI.

When the status is `Not prepared`, tapping that status row asks
`AppAttestRuntimeController` to reset the local credential artifacts and then
run `prepare(credentialName:)` for `photo_keyid`. The status row shows a spinner
while preparation is in progress, then changes to `Ready`. Once ready, the
details row below the status shows only the prepared App Attest `keyId`.

When Help is enabled in Settings, the user-facing `keyId` explanation appears
inline directly below the App Attest `Status` row. It explains that `keyId`
identifies the prepared App Attest key. The app uses that key to generate
request assertions, and the backend uses the `keyId` to find the registered
credential for verification. Assertions are not requested from Apple for each
protected request.

## Boundary Rule

`AppAttestKit` accepts only `credentialName: String` from the caller. It does
not create install IDs, read login state, know user IDs, or choose install/user
strategy. The caller decides what a credential name means.

Apple attests the generated App Attest key. Apple does not attest
`credentialName`.

## When To Call App Attest

The kit never intercepts API requests automatically. The caller decides when to
use it:

- Call `prepare(credentialName:)` when a credential name must register a new App Attest key.
- Call `prepareIfNeeded(credentialName:)` when an existing local credential can be reused.
- Call `generateAssertion(credentialName:request:)` only for selected protected APIs.
- Do not call the kit for APIs that do not need App Attest protection.

## Primary Documents

- [ClientUsage.md](ClientUsage.md): client API and call examples.
- [CredentialNameGuide.md](CredentialNameGuide.md): recommended caller-owned credential names.
- [BackendContract.md](BackendContract.md): HTTP contract and server duties.
- [LocalDebug.md](LocalDebug.md): no-server local debugging and export format.
- [SecurityNotes.md](SecurityNotes.md): safety boundaries and non-goals.
