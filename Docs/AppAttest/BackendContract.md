# App Attest Backend Contract

Source links:

- [AppAttestBackend](../../TAPCamDemo/AppAttestKit/AppAttestProtocols.swift)
- [HTTPAppAttestBackend](../../TAPCamDemo/AppAttestKit/HTTPAppAttestBackend.swift)
- [App Attest request/response models](../../TAPCamDemo/AppAttestKit/AppAttestModels.swift)

## Backend Boundary

All server communication goes through `AppAttestBackend`:

```swift
func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge
func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult
func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus
func recordAssertionResult(_ record: AppAttestAssertionRecord) async
```

`ChallengeProvider` is intentionally not a separate abstraction because
challenge generation, attestation registration, credential status, and assertion
audit data all belong to the same backend trust boundary.

## Challenge Endpoint

`POST /app-attest/challenges`

Request:

```json
{
  "purpose": "attestation",
  "subjectType": "install",
  "subjectId": "install-id"
}
```

Response:

```json
{
  "challengeId": "server-challenge-id",
  "challenge": "base64url-random-bytes",
  "expiresAt": "2026-04-24T13:00:00Z"
}
```

The server must bind every challenge to purpose, subject, expiry, and one-time
use state.

## Attestation Endpoint

`POST /app-attest/attestations`

Request:

```json
{
  "subjectType": "user",
  "subjectId": "user-id",
  "keyId": "apple-key-id",
  "challengeId": "server-challenge-id",
  "attestationObject": "base64url-attestation-object"
}
```

Response:

```json
{
  "credentialId": "server-credential-id",
  "status": "accepted"
}
```

The server validates the Apple attestation object, app identifier, environment,
challenge, public key, and initial sign counter before returning `accepted`.

## Protected Business Requests

The caller applies assertion metadata only to APIs that need App Attest:

```text
X-App-Attest-Subject-Type
X-App-Attest-Subject-Id
X-App-Attest-Key-Id
X-App-Attest-Challenge-Id
X-App-Attest-Assertion
X-App-Attest-Request-Binding
```

The server verifies the assertion signature with the registered public key,
checks the sign counter, confirms the challenge is valid and unused, and
recomputes the request binding.
