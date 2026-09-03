# TAPCam Repository Agent Rules

This file is the mandatory entry for work in this repository. Do not create a
second task list, agent guide, or source of product truth.

## 1. Read and authority

Before proposing or changing anything:

1. Read this file and the relevant sections of
   [ProductContract.md](Docs/ProductContract.md); read it all for cross-cutting
   scope, state-machine, terminology, claim, or non-goal changes.
2. Read [ProjectBoard.md](../TAPCamKanban/ProjectBoard.md) section 2, search
   every active and closed ID, and read the complete matching Task and blockers.
3. For visible UI, also read ProductContract section 9, the sibling
   [TAPCamPrototype rules](../TAPCamPrototype/AGENTS.md), root README, and
   Prototype/manifest.json.
4. Read the linked acceptance procedure, App Attest backend contract, shared
   artifact contract, or Planes note when that boundary is affected.
5. Inspect current implementation and tests. Old prose and Git history are not
   evidence of current behavior.

Authority order is ProductContract -> approved Task -> approved prototype ->
TAPArtifactContracts or App Attest BackendContract for its named boundary ->
implementation/tests -> acceptance evidence -> Git history. Code may reveal a
contract gap but cannot silently redefine the contract.

## 2. One Task, then implementation

Product, code, or documentation changes use one stable TAP-xxxx Task.
Mechanical commit/push of already approved work does not need a new Task.
Follow the Board's find-before-create and status rules: revise an active match;
use a scoped follow-up for completed work unless its original Done When is
false; never revive Deprecated work without owner approval.

Before implementing new or changed behavior, align with the owner on current
versus requested behavior, scope/non-scope, states, failure/recovery, objective
Done When, dependencies, prototype work, and acceptance. Update the Task and
ProductContract first when the decision changes product behavior. An already
approved Todo with unchanged scope may proceed directly.

Only the Board Steward edits the sibling Board. A development session normally
owns one Task and must not broaden it. During multi-Agent work, all other Agents
return a structured handoff to the Steward.

## 3. Visible UI is prototype-first

For hierarchy, geometry, spacing, copy, icons, navigation, gestures, controls,
or presented states:

1. Record affected states and scope in the Task.
2. Revise the sibling HTML/Web prototype and manifest.
3. Record revision, fixtures, deliberate native/system differences, and get
   explicit owner approval.
4. Only then implement SwiftUI and compare it in Simulator and, when required,
   on device.

Do not fake system-owned UI. An urgent non-visual runtime or safety fix may skip
exploration; any visible divergence must be synchronized back before closure.
TAPCamDemo owns behavior/native acceptance, TAPCamPrototype owns visual truth,
and TAPCamKanban owns status.

## 4. Implementation and validation

- Implement only approved scope and prefer existing seams.
- For cold/first-open/large-Library/iCloud/system-presentation paths, enforce
  [ProductContract section 2.7](Docs/ProductContract.md#27-startup-milestones-and-cold-path-execution);
  a warm rerun is never cold-path proof.
- Test contracts, not document structure. Run focused checks, then the relevant
  build/integration, Simulator, and device procedure in proportion to risk.
- Feature delivery and attended acceptance remain separate Tasks. Automation
  never substitutes for required owner confirmation.
- Before device work, state prerequisites, reset/install steps, numbered
  actions, expected results, retained evidence, and pass/fail/blocked rules.

## 5. Documentation and completion

Update only the owner whose responsibility changed:

| Change | Owner |
| --- | --- |
| Task scope/status/dependencies/history | sibling ProjectBoard through the Steward |
| Product behavior/state/terms/claims/non-goals | ProductContract |
| Visual state/workflow | Prototype + manifest; ProductContract section 9 for workflow |
| Module ownership/entry points | root README |
| Shared wire/container/signing format | TAPArtifactContracts |
| App Attest server trust/replay/HTTP | Docs/AppAttest/BackendContract.md |
| Executable or attended acceptance | matching Docs/Acceptance/TAP-xxxx file |
| Repository workflow | this file |

A Task is ready for Done only when approved scope, required checks, prototype
approval/parity, acceptance separation, documentation impact, obsolete-link
removal, and remaining gaps have all been reconciled.

The handoff must identify the Task, session, branch/worktree, build/commit,
contract sections, approved and implemented scope, prototype approval or N/A,
checks and evidence, updated authorities and N/A reasons, obsolete files,
remaining risks/follow-ups, and proposed status.

The Board Steward verifies Done When, synchronizes the Kanban, and alone records
final status.

## 6. Retention

Keep the active set minimal. Migrate unique current obligations and executable
acceptance, update inbound links, then delete obsolete plans, indexes, module
narration, and evidence prose. Git is the archive. Retain a separate interface,
format, security, or cross-project contract only while it owns a unique current
responsibility.
