# TAPCam Native App Rules

Start with README and the affected source/tests. Read the relevant
[product requirements](https://github.com/TAP-NAP/TAPArtifactContracts/blob/main/ProductContract.md) for behavior changes and the
pinned artifact contract for wire-format changes. Building and testing use the
commands in README.

- Work from the requested scope, current source, and relevant tests. Clarify
  unresolved behavior without reopening established decisions.
- Write documentation for a new reader: purpose, concepts, usage, and limits.
  Keep private planning records, internal identifiers, and execution diaries out
  of source and documentation. Keep exact technical revisions where needed.
- Prefer existing seams and deletion of redundant material. Add no dependencies,
  generated infrastructure, or extra documentation without a current need.
- Keep changes and validation proportional; report actual checks and limits.
  Do not commit or push unless the current conversation authorizes it.

- Valid still photos and TAP Video without depth are retained, signed, and
  exported. Preserve artifact integrity checks; depth assessment is a consumer
  responsibility.
- Use the interactive prototype for visible design changes and preserve agreed
  states, interaction, and system-owned presentation boundaries.
- Startup and cold paths follow ProductContract §2.7. A warm run is not evidence
  for a cold path; scalable work requires explicit isolation and bounded updates.
- Real-device acceptance uses the relevant capability procedure and records
  actual observations. Code changes do not imply permission to reset a device,
  delete personal media, or perform production operations.
