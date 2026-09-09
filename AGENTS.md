# TAPCam Native App Rules

Read this file, the local README, and only the relevant sections of the
[product contract](../TAPArtifactContracts/ProductContract.md). Inspect the
current call path and tests before editing. Do not read other repositories'
agent guides or the complete backlog as routine preparation.

## Scope and decisions

- The user's explicit request authorizes a bounded fix or cleanup. Routine work
  needs no Task ID, Board Steward, status ceremony, or separate handoff document.
- Read the optional [work notes](../TAPArtifactContracts/ProjectBoard.md) only
  when the request names an item or its unresolved scope is needed. Do not
  resurface expired plans or unrelated known gaps on every run.
- Established product decisions remain settled. In particular, absent depth
  does not block retaining, signing, or exporting valid still photos or TAP
  Video. Keep artifact integrity checks; do not reopen the policy question.
- Clarify only an actually unresolved behavior or scope. Implement the current
  request without expanding into unrelated backlog items.

## Authority and validation

- TAPArtifactContracts owns product requirements, artifact contracts, design
  rationale, and acceptance procedures. Code and tests establish actual behavior.
  Keep implementation navigation and local build commands in this README.
- For an intentional visible design change, follow ProductContract §9: review
  the affected Web prototype and obtain approval of the concrete visual result
  before SwiftUI implementation. A new Task is not a prerequisite.
- Follow ProductContract §2.7 for startup/cold paths. Run focused checks and the
  relevant build/tests; report executed counts and validation limits.
- Device work uses only the relevant section of
  [Acceptance.md](../TAPArtifactContracts/Acceptance.md). Preserve actual human
  acceptance and reset/production permissions; coding work does not require a
  device run merely to update a document.
- Keep docs in their owning location; do not recreate module contracts, per-task
  Markdown files, duplicate task lists, or dated audit reports. Existing commit
  history preserves replaced prose. Do not commit or push unless requested.
