# TAP-0046 — Production App Attest And Final Signed-Export Gate

- Status: `Draft — blocked until production scope, matrix, and budget are approved`
- Related Delivery: `TAP-0054`, `TAP-0056`, `TAP-0057`
- Contract: [ProductContract §3.4, §6, §7, and §8](../ProductContract.md),
  [App Attest client contract](../AppAttest/README.md),
  [App Attest backend contract](../AppAttest/BackendContract.md)
- Build/Commit: `OWNER-LIVE: freeze Release/TestFlight build before execution`
- Device/iOS: `OWNER-LIVE: approve a physical supported device before execution`
- Production Backend Window: `OWNER-LIVE: approve operator, account, request budget, and retention before execution`
- Human Confirmation: `Pending`

This procedure validates the production chain in four separate layers:

1. the installed build carries the production entitlement and runtime metadata;
2. the production backend accepts or recognizes the App Attest credential;
3. the device creates an offline capture assertion over the canonical media
   binding; and
4. the exact artifact passes the local fail-closed gate before Photos export,
   then remains valid on original-resource readback.

A backend `valid` response alone is not a verdict about a file. The acceptance
harness must first rebuild the content binding from the received media bytes.
The backend receives only `keyId`, `assertionObject`, and `signingBinding`, not
the original media. This diagnostic verification does not add a user-facing
Verify action for TAPCam-owned captures.

## Preconditions

- **OWNER-LIVE:** authorize use of the production App Attest environment,
  production backend, selected test account or install, exact request/capture
  budget, change window, evidence retention, and cleanup policy.
- A frozen Release or TestFlight `.app` and its signed archive are available.
  Source build settings or an entitlement source file alone are insufficient;
  the installed signed product must be inspectable.
- The approved physical device reports App Attest support. Simulator or a test
  signer cannot satisfy this procedure.
- A production backend operator can correlate a redacted test run and confirm
  challenge/registration or credential reuse, accepted environment/app
  identity, active key status, and capture-signature verification without
  exporting secrets or raw backend bodies.
- The owner chooses one sanctioned credential branch before installation:
  **fresh registration** or **reuse existing ready credential**. Local
  `reset(photo_keyid)` does not delete an Apple private key or backend record,
  so it must not be presented as production cleanup.
- Public-safe device/backend logs and a locally trusted acceptance verifier are
  ready. Logs must not expose full credential names derived from users, key IDs,
  assertion objects, proofs, URLs with private paths, media bytes, or response
  bodies.
- The verifier can rebuild the distinct Still, Live Photo, and TAP Video v1
  content-binding families from exact original bytes before submitting the unchanged
  `/tapcam/capture-signatures/verify` request.
- An owner-reviewed mutation harness can alter a disposable copy outside its
  proof slot without touching a Photos asset or production source artifact.
- Camera and Photos permissions are already available. Media-feature
  acceptance beyond the signing/export boundary remains in `TAP-0044` and
  `TAP-0045`.

## Representative Matrix To Freeze

| Row | Artifact | Required representative boundary | Repetitions | Owner decision |
| --- | --- | --- | --- | --- |
| A1 | HEIC still | `still-photo-manifest:v1` + `still-photo-content-binding:v1` and photo final gate | `OWNER-LIVE` | `OWNER-LIVE` |
| A2 | JPG still | `still-photo-manifest:v1` + `still-photo-content-binding:v1` and photo final gate | `OWNER-LIVE` | `OWNER-LIVE` |
| A3 | Live Photo | Owner-selected HEIC/JPG primary, original paired MOV, `live-photo-manifest:v1` + `live-photo-content-binding:v1` live gate | `OWNER-LIVE` | `OWNER-LIVE` |
| A4 | TAP Video | Owner-selected approved depth/audio state, `video-manifest:v1` + `video-content-binding:v1` file gate and original-video readback | `OWNER-LIVE` | `OWNER-LIVE` |

The four artifact classes are the proposed representative minimum. The owner
must freeze inclusion, repetitions, capture budget, and the exact A3/A4 media
state before the run. A missing decision is Blocked, not an Agent default.

## Reset / Install Procedure

1. **OWNER-LIVE:** approve the production window and artifact/request budget.
   Record the backend operator and stop conditions before any production call.
2. Archive prior evidence. Do not delete backend credentials, Keychain items,
   app data, or Photos assets unless the owner names the exact target and the
   production operator approves the corresponding cleanup procedure.
3. Record commit, build/archive identifier, distribution method, bundle/app
   identifier, device/iOS, and the selected fresh-or-reuse credential branch.
4. Extract the entitlements from the signed `.app` using the approved code-sign
   inspection tool and retain the output. Confirm the evidence belongs to the
   exact binary that will be installed.
5. Have the backend operator prepare redacted correlation for the selected
   account/install and record the pre-run credential state without exposing
   the full key ID or server secrets.
6. Install the frozen build through the approved Release/TestFlight path. Start
   public-safe device and backend logging before credential preparation.
7. If the owner selected fresh registration, use only the approved application
   and backend reset/registration procedure. If reuse was selected, do not
   manufacture a fresh registration merely to make the trace look complete.

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Inspect the entitlements extracted from the installed/frozen signed product. | `com.apple.developer.devicecheck.appattest-environment` is `production`, and the signed product's app identifier matches the production backend expectation. A source-only entitlement value is not accepted as evidence. | Pending | Pending |
| 2 | Inspect the runtime's public-safe configuration summary and the backend target selected by the build. | Release/TestFlight selects `https://www.tapnap.net` with App Attest metadata `.production`; entitlement, runtime metadata, bundle/app identity, and backend environment agree. No development or localhost endpoint is used. | Pending | Pending |
| 3 | **OWNER-LIVE:** enter the camera or use the Release `Photo Integrity` Prepare/Retry action according to the approved branch, then wait for the preparation result. | Fresh branch: the backend issues and atomically consumes an attestation challenge, validates Apple's attestation/app/environment/public key/initial counter, and accepts the credential before local persistence. Reuse branch: the existing ready `photo_keyid` mapping resolves to an active matching production credential. Release UI reaches `Ready` only after its assertion health check; it exposes no backend details or full key ID. | Pending | Pending |
| 4 | Backend operator correlate the preparation trace with the device trace. | Exactly the approved branch occurred. Credential name remains a lookup name, not a user identity or trust claim. The backend, not the client-ready flag, is the trust decision point. | Pending | Pending |
| 5 | For each frozen A1–A4 row, capture one approved test artifact and let the Pending Capture Queue process it. | The record moves through the applicable pending/signing/signed/exporting/exported/readback states without an unsigned fallback or silent trust downgrade. Counts stay within the approved production budget. | Pending | Pending |
| 6 | Audit the proof generated for every artifact before Photos export. | The device uses the registered production key to sign `SHA256(canonical signingBinding JSON)`. `signingBinding` uses operation `tapcam.capture.sign`, the expected capture identity and schema, and `bodySHA256 = SHA256(canonical contentDigest JSON)`. Still uses `still-photo-manifest:v1`/`still-photo-content-binding:v1`, Live Photo uses `live-photo-manifest:v1`/`live-photo-content-binding:v1` with its three signed resources, and TAP Video uses `video-manifest:v1`/`video-content-binding:v1`. Capture signing does not request an online business-request assertion challenge. | Pending | Pending |
| 7 | Observe the final local export gate for A1–A4. | HEIC/JPG pass `validateSignedExportPhoto`; Live Photo passes `validateSignedExportLivePhoto` for the exact primary/MOV pair; TAP Video passes `validateSignedExportVideoFile` for the exact MP4. Each gate recomputes byte binding and checks expected identity/proof before Photos commit. Queue status or a filename never substitutes for validation. | Pending | Pending |
| 8 | Read the saved Photos originals through the approved resource APIs and run the same applicable binding check. | HEIC/JPG originals retain the signed container/proof; Live Photo exposes the bound original `.photo` plus `.pairedVideo`; TAP Video streams its original video resource to disk-backed validation. The recomputed binding still matches, with no compatibility export or re-encoding substituted. | Pending | Pending |
| 9 | In the acceptance verifier, rebuild each content binding locally from the exact readback bytes, compare it with the embedded proof, then submit only the proof's `keyId`, `assertionObject`, and `signingBinding` to the production verification endpoint. | Local file/resource checks pass before the request. The backend confirms that the registered active production key signed the submitted canonical binding and returns the contracted `valid` result. No photo, MOV, MP4, manifest payload, depth data, or recomputed resource hash is uploaded to the endpoint. | Pending | Pending |
| 10 | **OWNER-LIVE:** inspect TAPCam's Release presentation for the captured assets and Share entry. | TAPCam displays persisted protection/verifiability state for its own completed captures and does not trigger a new product Verify operation merely because an item is viewed or shared. The explicit backend calls in step 9 remain acceptance diagnostics. | Pending | Pending |
| 11 | With the owner-reviewed harness, alter one disposable still/Live primary copy outside its proof slot, alter one disposable paired MOV or TAP Video copy, and run local verification before any backend request. | Every altered copy fails local content-binding/final-gate validation. It is not exported and cannot be called verified even if an unchanged embedded assertion would still be cryptographically valid for its original binding. | Pending | Pending |
| 12 | Review request counts, credential state, Photos assets, and retained evidence with the owner and backend operator. | Counts remain within the approved budget; cleanup follows the pre-approved policy; failures and partial traces remain recorded; secrets and private media are not copied into the public Markdown report. | Pending | Pending |

## Required Evidence

- Frozen commit/build/archive, installed-product identity, distribution method,
  device/iOS, owner-approved production window, request/capture budget, and
  fresh-or-reuse decision.
- Entitlement extraction from the exact signed product plus public-safe runtime
  environment/backend summary.
- Redacted device/backend correlation for credential preparation, accepted app
  identity/environment, active credential status, and the Release readiness
  result. Store raw production logs only in the approved restricted location.
- A1–A4 matrix with queue state timeline, manifest/content-binding schema,
  expected capture/package identity, proof-slot count, final-gate outcome,
  Photos original-resource inventory, and readback outcome.
- Local binding-reconstruction report and redacted production verification
  response for every representative artifact. The report must show that local
  validation preceded the backend request.
- Mutation-test input hashes and rejection stages for the disposable copies;
  do not retain mutated copies in Photos.
- Public-safe request-count and cleanup report. Full key IDs, assertion
  objects, proof bodies, backend response bodies, raw private URLs, and private
  media do not belong in the Markdown record.
- **OWNER-LIVE:** written acceptance of the production environment alignment,
  Release readiness presentation, four-row result, negative mutation behavior,
  and cleanup report.

## Verdict Conditions

- **Pass:** the exact installed product carries the production entitlement and
  selects matching production runtime/backend metadata; the approved fresh or
  reuse credential branch is accepted by the backend; every frozen HEIC, JPG,
  Live Photo, and TAP Video row contains a real production App Attest capture
  assertion, passes the correct pre-export and Photos-readback binding gates,
  and receives backend `valid` only after local reconstruction; altered copies
  fail locally; budgets and privacy rules hold; and the owner accepts.
- **Fail:** development/production identity mismatch; client-only readiness is
  treated as backend trust; attestation/credential rejection; a missing,
  wrong-key, wrong-identity, or wrong-binding assertion; unsigned fallback;
  Photos export before the applicable final gate; readback mismatch; media
  uploaded to the signature endpoint; backend `valid` used despite a local
  media mismatch; mutation accepted; secret leakage; or any unrecorded
  representative-row failure.
- **Blocked:** production authorization, operator, account/install choice,
  request/capture budget, frozen build, signed entitlement evidence, supported
  physical device, backend observability, exact-resource readback, local
  verifier, mutation harness, safe evidence storage, or owner attendance is
  missing. Development App Attest, Simulator, test-signature fixtures, and
  source inspection alone cannot close this Task.

## Human Confirmation

`Pending — OWNER-LIVE must approve the production run and accept its retained result.`
