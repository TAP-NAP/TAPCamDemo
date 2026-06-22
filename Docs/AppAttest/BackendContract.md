# App Attest Backend Contract

Source links:

- [AppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestProtocols.swift)
- [HTTPAppAttestBackend](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/HTTPAppAttestBackend.swift)
- [App Attest request/response models](https://github.com/TAP-NAP/AppAttestKit/blob/main/Sources/AppAttestKit/AppAttestModels.swift)

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
  "credentialName": "install:install-id"
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

The server must bind every challenge to purpose, credential name, expiry, and
one-time use state.

## Attestation Endpoint

`POST /app-attest/attestations`

Request:

```json
{
  "credentialName": "user:user-id",
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
X-App-Attest-Credential-Name
X-App-Attest-Key-Id
X-App-Attest-Challenge-Id
X-App-Attest-Assertion
X-App-Attest-Request-Binding
```

The server verifies the assertion signature with the registered public key,
checks the sign counter, confirms the challenge is valid and unused, confirms
the credential name matches the registered key, and recomputes the request
binding.

## TAPCam Capture Signature Verification

TAPCam photo capture signing is not sent automatically after capture. The proof
is stored in the fixed TAP proof slot inside the HEIC/JPG file so a later
verifier can submit the signature materials to the server:

`POST /tapcam/capture-signatures/verify`

Request:

```json
{
  "keyId": "apple-key-id",
  "assertionObject": "base64url-assertion-object",
  "signingBinding": {
    "bodySHA256": "base64url-sha256-content-digest",
    "captureID": "capture-id",
    "operation": "tapcam.capture.sign",
    "schemaID": "urn:tapnap:tapcam:app-attest-capture-signing:v1"
  }
}
```

Valid response:

```json
{
  "status": "valid",
  "keyId": "canonical-key-id",
  "signingBindingSHA256": "base64url-sha256-signing-binding"
}
```

Invalid semantic verification returns HTTP 200 with `status: "invalid"` and a
machine-readable `reason`. This endpoint verifies that a registered active
`keyId` signed the submitted `signingBinding`; it does not upload or re-hash
the original HEIC/JPG file, RGB image, depth data, or `contentDigest`.

Before calling this endpoint, the verifier must rebuild the TAP content binding
locally from the original file bytes by excluding the fixed proof slot and
hashing canonical `manifest.payload` JSON. This mirrors C2PA-style hard binding:
the backend verifies the App Attest signature over the binding, while the
client or browser-side verifier proves that the binding still matches the file
it received.
