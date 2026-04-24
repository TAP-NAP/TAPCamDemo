# TAPCamDemo App Attest

This folder documents the reusable App Attest implementation used by TAPCamDemo.
Links point to the source files so they can be opened directly from Xcode or a
Git browser.

## Code Boundaries

- [AppAttestKit](../../TAPCamDemo/AppAttestKit/AppAttestProtocols.swift) contains reusable protocols and core flows.
- [DefaultAppAttestClient](../../TAPCamDemo/AppAttestKit/DefaultAppAttestClient.swift) owns the App Attest attestation and assertion orchestration.
- [HTTPAppAttestBackend](../../TAPCamDemo/AppAttestKit/HTTPAppAttestBackend.swift) is the production HTTP backend adapter.
- [LocalDebugAppAttestBackend](../../TAPCamDemo/AppAttestKit/LocalDebugAppAttestBackend.swift) is DEBUG-only local challenge and export support.
- [AppAttestDemo](../../TAPCamDemo/AppAttestDemo/AppAttestDemoView.swift) is TAPCamDemo's UI usage example, not reusable core logic.
- [AppAttestRuntime](../../TAPCamDemo/App/AppAttestRuntime.swift) wires TAPCamDemo to a backend and client.

## When To Call App Attest

The kit never intercepts API requests automatically. The caller decides when to
use it:

- Call `prepare(subject:)` when a subject must register a new App Attest key.
- Call `prepareIfNeeded(subject:)` when an existing local credential can be reused.
- Call `generateAssertion(subject:request:)` only for selected protected APIs.
- Do not call the kit for APIs that do not need App Attest protection.

The caller also owns the credential scope model. The kit only accepts
`AppAttestSubject(type:id:)` as a backend-defined storage and challenge-binding
scope. Apple does not attest this subject; Apple attests the generated App
Attest key.

## Primary Documents

- [ClientUsage.md](ClientUsage.md): client API and call examples.
- [BackendContract.md](BackendContract.md): HTTP contract and server duties.
- [LocalDebug.md](LocalDebug.md): no-server local debugging and export format.
- [SecurityNotes.md](SecurityNotes.md): safety boundaries and non-goals.
