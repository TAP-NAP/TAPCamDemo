# TAPCam Repository Agent Rules

This root `AGENTS.md` is the mandatory entry point for every Agent working in
this repository. Do not create a competing `agent.md`, private task list, or
second source of product truth.

## 1. Authority And Required Reading

Before giving a substantive design proposal, planning implementation, or
changing files, read in this order:

1. `AGENTS.md` in full.
2. `Docs/ProductContract.md` §1 plus every section relevant to the request.
   Read the whole contract when the change is cross-cutting or changes product
   scope, state machines, claims, non-goals, or terminology.
3. `Docs/ProjectBoard.md` operating rules, then search the complete registry
   across Inbox, Todo, Doing, Done, and Deprecated. Read the complete matching
   Task record and every directly related or blocking Task.
4. `Docs/UIPrototypeContract.md` in full for any user-visible UI, navigation,
   interaction, copy, icon, layout, or presented-state change.
5. The relevant module README and any specialized interface, format, security,
   cross-project, or acceptance contract linked by the Task.
6. The current implementation and tests needed to determine what the product
   actually does. Do not infer current behavior from old prose.

Use this authority order when sources disagree:

```text
ProductContract
    -> approved Task scope and decisions in ProjectBoard
    -> approved UI prototype for visual intent
    -> specialized interface/format/security contract
    -> module README
    -> implementation and tests
    -> acceptance evidence
    -> historical material and Git history
```

Implementation evidence may reveal that a contract is not yet satisfied, but
it does not silently rewrite the contract. Report the mismatch through the
Task. Do not treat dated Acceptance, old PRDs, branch audits, POCs, removed
Sketch pilots, AITrace, or Git history as current product authority.

## 2. Mandatory Iteration Lifecycle

An Agent must not jump directly from a new request to code. Use this sequence:

```text
request
  -> required reading
  -> find/revise one Task
  -> inspect current behavior and conflicts
  -> discuss scope, non-scope, states, and acceptance with the owner
  -> approve Todo scope
  -> for UI: prototype, review, and approval
  -> mark/record Doing and implement
  -> automated/Simulator validation
  -> attended device acceptance when required
  -> documentation-impact check and dev handoff
  -> Board Steward updates history and final status
```

### 2.1 Understand and discuss before implementation

Before implementation, give the product owner a concise, evidence-backed
alignment containing:

- the matching Task ID and current status;
- the relevant Product Contract section;
- current behavior versus requested behavior;
- conflicts, deprecated approaches, dependencies, and evidence gaps;
- proposed in-scope and out-of-scope boundaries;
- states, failure/recovery behavior, and an objective `Done When`;
- the prototype and acceptance work required.

New functionality, changed product behavior, unresolved interactions, or a
request that conflicts with a current contract must be discussed and approved
before implementation begins. A development session may proceed directly only
when it is executing an already-approved Todo whose scope and completion
condition remain unchanged.

If discussion changes product behavior, update the Product Contract and Task
scope before using the new decision as implementation authority.

### 2.2 Find before create

- Every change uses one stable `TAP-xxxx` Task ID.
- Search Task IDs, titles, aliases, Domain, Labels, Match Keys, Contract, Scope,
  and all statuses before proposing a new Task.
- Revise a matching Inbox, Todo, or Doing Task instead of creating a duplicate.
- A Done match becomes a scoped follow-up unless its original `Done When` is no
  longer true, in which case preserve its history and reopen deliberately.
- A Deprecated match must not be restored without an explicit owner decision.
- A genuinely unmatched idea receives the next ID and enters Inbox first.
- Do not implement an Inbox item until its scope is approved and moved to Todo.

### 2.3 Board Steward and development sessions

- The long-lived Board Steward Session owns Task allocation, duplicate
  resolution, canonical status, Kanban synchronization, and append-only
  Revision History.
- A development session normally owns exactly one Task ID. It records its
  Agent/person, session ID, branch/worktree, implementation, validation,
  evidence, documentation impact, and proposed status in its handoff.
- Development sessions do not maintain competing boards or silently broaden
  their Task.
- During multi-Agent work, only the designated Board Steward edits
  `Docs/ProjectBoard.md`; other Agents return structured updates by Task ID.

## 3. UI Prototype Gate

Any change to visible hierarchy, geometry, spacing, copy, icons, navigation,
gestures, controls, or presented states must use the prototype-first workflow in
`Docs/UIPrototypeContract.md`:

1. Record the affected product states and UI scope in the Task.
2. Create or revise the repository-owned HTML/Web prototype.
3. Record the prototype path, Task ID, revision, covered fixtures/states, and
   deliberate native/system-owned differences.
4. Present the prototype for product-owner review.
5. Record explicit approval or requested revisions.
6. Only after approval, implement or revise SwiftUI.
7. Compare the native result with the approved prototype in Simulator and, when
   required, on a physical device.

Sketch or another tool may replace the Web prototype only when the owner chooses
it for that Task; the accepted result must still be synchronized into the
repository-owned prototype record so there is one active visual truth.

Do not fake system permission dialogs or other system-owned UI. Prototype the
app-owned state before and after the system transition and document the
system-owned boundary.

An urgent runtime or safety fix may bypass visual exploration only when it does
not intentionally change the UI, or when the owner explicitly authorizes the
exception. Any visible divergence must be synchronized back to the prototype
before the Task can close.

## 4. Implementation And Validation

- Implement only the approved Task scope and preserve explicit non-goals.
- Prefer existing module and interface seams over parallel implementations.
- For first-install, empty-cache, first-open, large-Library, iCloud, media, and
  system-presentation work, follow
  [`Docs/ColdPathResponsiveness.md`](Docs/ColdPathResponsiveness.md). A warm
  second run is comparison evidence, never proof that the cold path is safe.
- Add or update tests that protect the contract, not tests that merely spell a
  document or current source structure.
- Validate in proportion to risk: focused tests first, then build/integration,
  Simulator interaction, and physical-device procedure when required.
- Feature delivery and evidence remain separate Tasks. An implementation Task
  may be Done while its DeviceAcceptance Task remains Todo.
- Before a physical-device run, present its prerequisites, reset/install steps,
  numbered actions, expected results, evidence, and pass/fail/blocked rules.
- Simulator or automation does not replace attended owner confirmation.

## 5. Completion Tracking And Required File Updates

Every dev handoff must include a documentation-impact check. Update the files
whose responsibility changed; for every row not updated, record `N/A` and a
short reason.

| Change made or decision reached | Required tracking file |
| --- | --- |
| Task scope, status, assignee, session, dependency, decision, completion, revision, or handoff | `Docs/ProjectBoard.md` through the Board Steward |
| Product behavior, state machine, terminology, capability, future scope, explicit non-goal, experiment status, or claim boundary | `Docs/ProductContract.md` |
| Visual hierarchy, layout, icons, copy placement, interaction, responsive behavior, or simulated UI states | HTML/Web prototype and its repository manifest/revision record |
| The design-to-code workflow or prototype authority itself changes | `Docs/UIPrototypeContract.md` |
| Module ownership, lifecycle, architecture, integration seam, or operational behavior changes | Relevant module `README.md` |
| Public interface, media/file format, security boundary, or cross-project obligation changes | Relevant specialized contract, such as `Docs/TAPVideoFormatContract.md`, `Docs/AppAttest/`, or `Docs/LivePhotoBrowserVerification.md` |
| Testable acceptance procedure, build/device run, evidence, or human verdict changes | Matching `Docs/Acceptance/TAP-xxxx-*.md` and its linked DeviceAcceptance Task |
| Repository-wide Agent workflow changes | Root `AGENTS.md` and the governance Task revision |
| A canonical source replaces old prose | Migrate unique obligations, update inbound links, then delete the obsolete document; Git remains the archive |

A Task is not ready for Done merely because code compiles. Before proposing
Done, confirm:

- approved scope is implemented and out-of-scope behavior was not added;
- required tests and builds passed, with failures or unrun checks recorded;
- prototype approval and parity evidence exist for UI work;
- device acceptance is completed or remains explicitly linked as a separate
  open evidence Task;
- every required documentation update above is complete;
- obsolete sources and links were removed after migration;
- remaining gaps, risks, and follow-up Tasks are explicit.

The development-session handoff must contain:

```md
- Task ID:
- Dev Session:
- Branch/Worktree:
- Build/Commit:
- Contract Sections Read:
- Approved Scope:
- Implemented Scope:
- Prototype Path/Revision/Approval: # or N/A with reason
- Tests And Builds Run:
- Evidence And Acceptance:
- Files Updated:
  - Project Board:
  - Product Contract:
  - UI Prototype/Manifest:
  - UI Prototype Contract:
  - Module README:
  - Specialized Contract:
  - Acceptance Record:
  - AGENTS.md:
- Obsolete Files Removed:
- Remaining Gaps/Risks:
- Follow-up Task IDs:
- Proposed Status:
```

The Board Steward verifies this record against `Done When`, updates the Task's
append-only Revision History, synchronizes the Kanban view, and only then marks
the Task Done.

## 6. Status, Evidence, And History Rules

- `Inbox`: unresolved product decision.
- `Todo`: approved scope, not started.
- `Doing`: assigned and actively being implemented.
- `Done`: objective completion condition and tracking obligations met.
- `Deprecated`: duplicate, superseded, merged, rejected, abandoned, or explicit
  non-goal.

Preserve previous completion, failure, split, merge, replacement, and reopening
facts. History is append-only. Acceptance and historical evidence never
redefine the Product Contract.

## 7. Documentation Retention

- Keep the active document set minimal.
- When a canonical source absorbs an obsolete design, phase plan, or experiment,
  migrate its unique current obligations and executable acceptance procedure,
  update inbound references, and delete the obsolete file.
- Git history is the archive; do not retain duplicate historical prose in the
  active reading path solely for traceability.
- Keep a separate interface, format, security, or cross-project contract only
  while it owns a unique current responsibility.
