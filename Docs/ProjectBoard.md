# TAPCam Project Board

- Schema: `1`
- Next Task ID: `TAP-0081`
- Canonical Product Contract: [ProductContract.md](ProductContract.md)
- UI Prototype Contract: [UIPrototypeContract.md](UIPrototypeContract.md)
- Board Steward Session: `019ff4ea-acba-7051-bd0f-3d489f1caadc`
- Last updated: `2026-08-12`

This Markdown file is the task database of record. Task records are permanent;
their IDs are never reused. The Kanban section is a human-readable view derived
from each record's `Status` field.

## 1. Kanban

### Inbox

- `TAP-0005` Choose replacement Simplified Chinese credential-readiness copy
- `TAP-0007` Decide App Store media work after the HTML-first transition
- `TAP-0022` External media import and in-app Verify
- `TAP-0030` Richer App Intents, widget/control, and score-history surfaces
- `TAP-0031` Calibrate score and decide its Release placement
- `TAP-0032` Evaluate Liquid Glass as a new UI proposal
- `TAP-0033` Durable TAP Library filters and reopen behavior
- `TAP-0034` Replace SceneKit with Metal only if evidence requires it
- `TAP-0035` Decide whether a second shutter belongs in the product
- `TAP-0036` Decide whether left/right-handed shutter placement belongs in the product
- `TAP-0037` Decide whether landscape side controls belong in the product
- `TAP-0038` Decide whether advanced per-frame video-depth analysis belongs in the product
- `TAP-0039` Decide whether additional guide types belong in the product

### Todo

- `TAP-0006` Build the repository-owned HTML/Web UI prototype foundation
- `TAP-0008` Enforce explicit-action-only first-install operations
- `TAP-0009` Enforce first-frame camera-interactive readiness
- `TAP-0010` Align Network bounded auto-retry and manual Retry
- `TAP-0011` Make zero-depth TAP Video non-blocking
- `TAP-0012` Align Standard FOV/depth and PRO no-crop behavior
- `TAP-0013` Rebuild lifecycle-correct Locked Camera on the experiment branch
- `TAP-0014` Remove redundant Verify UX for TAPCam-owned captures
- `TAP-0015` Implement fine-grained credential retry optimization
- `TAP-0016` Design and implement TAP Video 3D
- `TAP-0017` Add white-balance UI
- `TAP-0018` Design true camera source switching
- `TAP-0019` Design RAW/ProRAW output contracts
- `TAP-0020` Design 24 MP deferred photo delivery
- `TAP-0021` Maintain a C2PA-compatibility checklist without claiming certification
- `TAP-0023` Implement TAP Video `.tapnap` transport
- `TAP-0024` Implement Sticker sharing
- `TAP-0025` Implement Link sharing
- `TAP-0026` Cancel superseded PhotoKit display requests at the request layer
- `TAP-0027` Define thumbnail retention and purge policy
- `TAP-0028` Migrate legacy exported GPS copies
- `TAP-0029` Isolate Debug fixtures and split oversized test files
- `TAP-0040` Device acceptance: explicit first-install operations
- `TAP-0041` Device acceptance: first camera-interactive readiness
- `TAP-0042` Device acceptance: professional camera control matrix
- `TAP-0043` Device acceptance: Standard FOV/depth and PRO no crop
- `TAP-0044` Device acceptance: Live Photo chain
- `TAP-0045` Device acceptance: TAP Video performance, zero depth, and iCloud
- `TAP-0046` Device acceptance: App Attest production path
- `TAP-0047` Device acceptance: Library permission and deletion semantics
- `TAP-0048` Acceptance: Web prototype to SwiftUI parity
- `TAP-0049` Device acceptance: lifecycle-correct Locked Camera (blocked)

### Doing

- None

### Done

- `TAP-0001` Establish the canonical contract, UI workflow, and Markdown board
- `TAP-0002` Reconcile active documents with the Product Contract
- `TAP-0003` Migrate unique facts, then remove obsolete documents
- `TAP-0004` Normalize TAP Library and Pending Capture Queue terminology
- `TAP-0050` Required versus optional first-install rows
- `TAP-0051` Bounded Network retry policy foundation
- `TAP-0052` PRO Photo and TAP Video Release capability
- `TAP-0053` Standard Basic EV and PRO manual controls
- `TAP-0054` HEIC/JPG Release output formats
- `TAP-0055` No-depth still-photo non-blocking output
- `TAP-0056` Live Photo capture, signing, export, and playback chain
- `TAP-0057` TAP Video core chain and foreground RAW/2D playback
- `TAP-0058` Mixed-media user-facing TAP Library
- `TAP-0059` Photos-style Viewer and bottom capsule
- `TAP-0060` Static-photo native 3D point projection
- `TAP-0061` App-owned, on-demand Share flow
- `TAP-0062` Cross-project Live Photo browser verification contract
- `TAP-0075` Migrate and remove obsolete Startup/Camera design documents
- `TAP-0076` Migrate and remove obsolete Viewer/Queue design documents
- `TAP-0077` Consolidate App Attest documentation
- `TAP-0078` Extract the canonical TAP Video format contract and remove old video plans
- `TAP-0079` Migrate historical evidence and remove AITrace, dated scorecards, and old acceptance snapshots
- `TAP-0080` Migrate Locked Camera experiment guardrails and remove main-tree experiment prose

### Deprecated

- `TAP-0063` First-install page appearance implicitly requests permissions
- `TAP-0064` Video and Live Photo are globally unimplemented
- `TAP-0065` PRO is Photo-only
- `TAP-0066` Standard FOV is preview-only magnification
- `TAP-0067` Tool drawer, vertical Verify/dismiss, detents, and top-level analysis modes
- `TAP-0068` Direct resource preparation followed immediately by system Share
- `TAP-0069` Verify every TAPCam-owned capture during view or Share
- `TAP-0070` Treat the existing Locked Camera POC as a product capability
- `TAP-0071` Discard still photos or TAP Video only because depth is missing
- `TAP-0072` TAP Video AirPlay, PiP, and background playback
- `TAP-0073` Per-frame depth in the current Live Photo MOV contract
- `TAP-0074` Simplified Chinese `Photo Integrity = 照片保真`

## 2. Board Operating Rules

### 2.1 Board session and development sessions

- The product owner may use one long-lived conversation as the **Board Steward
  Session**.
- The Board Steward Session is the only writer that allocates Task IDs, resolves
  duplicates, changes canonical status, and appends board revision history.
- A separate development session normally owns one Task ID. Its first action is
  to read the linked Product Contract section and the complete task record.
- A development session records its session/thread identifier, assignee,
  branch/worktree, implementation, tests, and evidence in its handoff. It does
  not create a competing board or silently broaden its Task.
- At handoff, the development session proposes a status change. The Board
  Steward verifies the completion condition and writes the final transition.
- Multiple research or review Agents may help a development session, but only
  one Board Steward edits this database during a board-maintenance turn.

This workflow is supported by the schema now. It does not create or dispatch
development sessions automatically.

The recorded Board Steward Session is the default conversation for requests
such as:

- `列出 Todo / Doing / Inbox` — derive the answer from this file;
- `我想增加……` — search all statuses first, then revise a match or allocate
  the next ID in Inbox;
- `开始 TAP-xxxx` — record the assignee, development session, branch/worktree,
  and move an approved Todo to Doing;
- `修订 / 拆分 / 合并 / 废弃 TAP-xxxx` — preserve the ID history and apply the
  operation in §2.4;
- `验收 TAP-xxxx` — present its executable evidence procedure before any
  physical-device run; and
- `交付 TAP-xxxx` — check its `Done When`, evidence dependency, handoff, and
  human-confirmation boundary before changing status.

### 2.2 Statuses

- `Inbox`: an idea or unresolved product decision.
- `Todo`: approved scope with no active implementation session.
- `Doing`: assigned and actively being implemented.
- `Done`: the recorded `Done When` condition has been met.
- `Deprecated`: duplicate, superseded, merged, rejected, explicitly out of
  scope, or an abandoned design. The record is retained.

```text
Inbox --scope approved--> Todo --dev starts--> Doing --done condition met--> Done
   |                         ^                  |
   +--rejected/duplicate----> Deprecated <-----+--superseded/abandoned

Doing --paused with reason--> Todo
Deprecated --explicit owner decision to revive or replace--> Todo or new Task
```

### 2.3 Find before create

For every new request, the Board Steward must:

1. Read the Product Contract.
2. Search Task ID, title, `Labels`, `Match Keys`, Domain, Contract, Scope, and
   every status, including Done and Deprecated.
3. If a matching Inbox/Todo/Doing Task exists, revise that Task.
4. If a matching Done Task exists, reopen it only when its original completion
   condition is no longer true; otherwise create a scoped follow-up.
5. If a matching Deprecated Task exists, do not revive it silently. Ask whether
   to restore it or create a replacement.
6. If the overlap is partial, split or revise deliberately.
7. Create a new ID in Inbox only when no matching Task exists.
8. Append a Revision History entry and refresh the Kanban view.

### 2.4 Revision operations

- **Revise**: delivery goal remains the same; keep the ID and append history.
- **Split**: create child IDs; deprecate the source record with `Split into`.
- **Merge**: retain the best canonical ID; deprecate other records with
  `Merged into`.
- **Duplicate**: deprecate it with `Duplicate of`.
- **Supersede**: deprecate the old approach and link the replacement.
- **Reopen**: preserve the old completion date and append the new reason.
- **Explicit non-goal**: record it in Product Contract and deprecate any active
  implementation Task.

History is append-only. Do not erase an earlier status, accepted scope, failure,
or completed result to make the current record look cleaner.

### 2.5 Feature delivery and acceptance are separate Tasks

A delivery can be Done while its physical-device acceptance remains Todo. A
`DeviceAcceptance` Task must contain:

```md
- Related Delivery:
- Build/Commit:
- Device/iOS:
- Preconditions:
- Reset/Install Procedure:
- Procedure:
  1. ...
- Expected Results:
  1. ...
- Required Evidence:
- Evidence Location:
- Pass Conditions:
- Fail Conditions:
- Blocked Conditions:
- Human Confirmation: `Pending`
```

Before running a missing physical-device test, the Agent presents the scope and
procedure to the product owner. Only an attended execution followed by explicit
owner acceptance changes `Human Confirmation` to an accepted record and closes
the Task. Simulator automation never substitutes for that confirmation.

### 2.6 Development-session handoff

A development session returns this minimum record to the Board Steward:

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
- Documentation Impact:
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

The Board Steward reconciles that handoff with the existing record. A dev
session does not mark its own Task Done merely because its local patch is
finished. Every documentation-impact row must name the updated file or record
`N/A` with a reason. The Board Steward verifies the handoff against the root
`AGENTS.md` completion matrix before changing canonical status.

## 3. Task Record Schema

Every active Task uses these stable fields:

- `Status`: Kanban state.
- `Kind`: `Feature | Fix | Documentation | Technical | Evidence |
  DeviceAcceptance | Decision | Experiment`.
- `Priority`: `P0 | P1 | P2 | P3`.
- `Domain`: product or engineering domain.
- `Labels`: searchable tags.
- `Contract`: Product Contract section or constraint.
- `Match Keys`: aliases, old names, and likely user vocabulary.
- `Assignee`: person or Agent, if assigned.
- `Dev Session`: task/thread identifier for the development conversation.
- `Branch/Worktree`: delivery location when implementation begins.
- `Scope`: one bounded result.
- `Out of Scope`: explicit guardrail.
- `Done When`: objective completion condition.
- `Related`: parent, child, dependency, evidence, merge, or replacement IDs.
- `Created` / `Updated`.
- `Revision History`: append-only changes with date and reason.

## 4. Detailed Task Registry

### TAP-0002 — Reconcile active documents with the Product Contract

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `Governance`
- Labels: `docs`, `contract`, `stale-current`
- Contract: `ProductContract §1`
- Match Keys: `document conflict, stale roadmap, current docs, constraint cleanup`
- Assignee: `Board Steward with scoped documentation Agents`
- Dev Session: `Current documentation-governance conversation`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Remove or relabel current-document statements that conflict with the
  canonical contract, including onboarding, PRO/Video/Live Photo, Viewer,
  Share/Delete, output, and verification.
- Out of Scope: Rewriting historical bodies or changing product code.
- Done When: Every active document declares its role and no active statement
  contradicts the Product Contract.
- Related: `TAP-0003`, `TAP-0004`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the cross-document product audit.
  - `2026-08-12` Moved to Doing when active document reconciliation began.
  - `2026-08-12` Completed after canonical product/UI/board authority replaced
    conflicting onboarding, Camera, Video, Viewer, Share, and verification prose.

### TAP-0003 — Migrate unique facts, then remove obsolete documents

- Status: `Done`
- Kind: `Documentation`
- Priority: `P1`
- Domain: `Governance`
- Labels: `history`, `aitrace`, `acceptance`, `experiment`, `superseded`, `delete`
- Contract: `ProductContract §1`
- Match Keys: `historical snapshot, branch audit, old phase, POC log, delete old docs`
- Assignee: `Board Steward with scoped documentation Agents`
- Dev Session: `Current documentation-governance conversation`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Produce a per-file retention manifest, migrate any unique current
  constraint, acceptance procedure, or external-interface obligation, then
  delete obsolete AITrace, dated Acceptance, branch audits, old implementation
  phases, Locked experiments, and Sketch pilot materials from the current tree.
- Out of Scope: Deleting a still-authoritative cross-project/format/security
  contract before its responsibility has a durable owner.
- Done When: The current documentation tree contains only the minimal active
  set; deleted history remains recoverable through Git; all retained files have
  a unique declared role.
- Related: `TAP-0002`, `TAP-0070`, `TAP-0075`, `TAP-0076`, `TAP-0077`,
  `TAP-0078`, `TAP-0079`, `TAP-0080`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the document-role decision.
  - `2026-08-12` Revised after the owner chose Git history, rather than the
    current documentation tree, as the archive for superseded material.
  - `2026-08-12` Moved to Doing. Deleted the fully migrated Sketch pilot plans,
    bilingual traceability contracts, state manifest, conflict register, and
    seven design-review images plus their now-orphaned SF Symbol rendering
    helper. Started staged migration of App/Camera, Viewer/Queue, App Attest,
    video-format, and historical evidence documents.
  - `2026-08-12` Completed. Migrated durable facts and executable procedures,
    then removed old PRDs, AITrace, scorecards, dated acceptance, branch audits,
    Sketch pilot assets, and Locked experiment prose. Git remains the archive.

### TAP-0004 — Normalize TAP Library and Pending Capture Queue terminology

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `Library`
- Labels: `terminology`, `tap-library`, `pending-capture-queue`
- Contract: `ProductContract §5.1`
- Match Keys: `TAPLibrary module, private library, album, gallery, pending queue`
- Assignee: `Board Steward with migrate_viewer_queue_docs Agent`
- Dev Session: `/root` and `/root/migrate_viewer_queue_docs`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Use `TAP Library` only for the user-facing mixed-media gallery/Viewer
  and `Pending Capture Queue` for signing/export/retry storage.
- Out of Scope: Renaming the Swift module in the same Task.
- Done When: Product and architecture prose use the two terms consistently and
  explain the legacy module name where relevant.
- Related: `TAP-0058`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the owner terminology decision.
  - `2026-08-12` Completed across Product Contract, documentation entry points,
    Viewer, Camera output/packaging, and the legacy-named queue module README.

### TAP-0005 — Choose replacement Simplified Chinese credential-readiness copy

- Status: `Inbox`
- Kind: `Decision`
- Priority: `P1`
- Domain: `Localization`
- Labels: `copy`, `zh-hans`, `credential`, `claim-boundary`
- Contract: `ProductContract §7`
- Match Keys: `Photo Integrity, 照片保真, 凭证状态, 保护状态`
- Assignee: `Product owner`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Select wording that conveys credential/protection readiness without
  implying visual fidelity or real-world authenticity.
- Out of Scope: Expanding the cryptographic or authenticity claim.
- Done When: The owner approves English/Chinese wording and synchronization
  targets for localization, Web prototype, claims, and acceptance assets.
- Related: `TAP-0074`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created because the old Chinese term was deprecated without a
    replacement decision.

### TAP-0006 — Build the repository-owned HTML/Web UI prototype foundation

- Status: `Todo`
- Kind: `Feature`
- Priority: `P0`
- Domain: `UI Prototype`
- Labels: `html-first`, `web-prototype`, `state-machine`, `visual-contract`
- Contract: `ProductContract §9`; `UIPrototypeContract`
- Match Keys: `HTML UI, web mock, visual editor, prototype, frontend layout`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Create a runnable, versioned Web prototype foundation that can express
  component hierarchy, icon identity, relative layout, and deterministic UI
  states before SwiftUI work.
- Out of Scope: Claiming native camera, permission, depth, performance, or App
  Store evidence.
- Done When: The owner can run the prototype, switch its first documented
  states, inspect component relationships, and approve a recorded revision.
- Related: `TAP-0048`, `TAP-0007`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` HTML/Web was chosen as the default future visual-spec workflow;
    no prototype implementation was started in this governance task.

### TAP-0007 — Decide App Store media work after the HTML-first transition

- Status: `Inbox`
- Kind: `Decision`
- Priority: `P2`
- Domain: `App Store`
- Labels: `app-store`, `media`, `6.9-inch`, `ipad`, `rights`
- Contract: `UIPrototypeContract §7`
- Match Keys: `P3, screenshots, store media, device frame, universal media`
- Assignee: `Product owner`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Decide whether and how to resume 6.9-inch and iPad store media after
  the Web prototype foundation exists.
- Out of Scope: Treating Sketch exports as submit-ready runtime evidence.
- Done When: The owner approves or rejects a scoped Store task with real-media
  and rights requirements.
- Related: `TAP-0006`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Migrated unfinished Sketch P3 from implicit roadmap to Inbox.

### TAP-0008 — Enforce explicit-action-only first-install operations

- Status: `Todo`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Onboarding`
- Labels: `permissions`, `camera`, `photos`, `location`, `microphone`, `network`
- Contract: `ProductContract §2.1`
- Match Keys: `launch prompt, Allow button, automatic permission, clean install`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Ensure each first-install row is the only trigger for its protected or
  network operation; eliminate any pre-action activation.
- Out of Scope: Changing required versus optional classification.
- Done When: Code and focused tests enforce the explicit-action boundary for
  all five rows.
- Related: `TAP-0040`, `TAP-0050`, `TAP-0063`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Expanded from Photos-only to every first-install action.
  - `2026-08-12` Repository audit added early Photo Library observer
    registration and startup poster backfill as explicit implementation paths
    that must be removed or proven inert before the corresponding Allow action.

### TAP-0009 — Enforce first-frame camera-interactive readiness

- Status: `Todo`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Onboarding`
- Labels: `readiness`, `first-frame`, `shutter`, `controls`, `freeze-prevention`
- Contract: `ProductContract §2.4–2.5`
- Match Keys: `Continue, camera ready, interactive, loading gate, page freeze`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Keep first-install readiness active until capture graph, real first
  preview frame, primary controls, shutter, and required haptics are safe; then
  write completion.
- Out of Scope: Blocking on App Attest credential warmup or queue retry.
- Done When: The implementation and tests use the complete readiness definition
  and later permission changes never reopen onboarding.
- Related: `TAP-0041`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Owner clarified that session configuration alone is not ready.
  - `2026-08-12` Repository audit confirmed the current readiness state does
    not yet consume a preview-layer first-frame signal; this remains required
    implementation scope rather than an acceptance-only gap.

### TAP-0010 — Align Network bounded auto-retry and manual Retry

- Status: `Todo`
- Kind: `Fix`
- Priority: `P1`
- Domain: `Onboarding`
- Labels: `network`, `retry`, `timeout`, `manual-action`
- Contract: `ProductContract §2.3`
- Match Keys: `security preflight retry, healthz, foreground retry`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Retry automatically at policy intervals inside one bounded sequence;
  after total timeout, require an explicit user Retry.
- Out of Scope: App Attest credential retry policy.
- Done When: UI, policy, lifecycle behavior, and tests agree on the same retry
  ownership.
- Related: `TAP-0051`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Owner selected bounded automatic attempts followed by manual retry.
  - `2026-08-12` Repository audit identified a refresh path that can restart
    the preflight after denial; implementation must keep that action inside the
    active bounded sequence or a new explicit Retry.

### TAP-0011 — Make zero-depth TAP Video non-blocking

- Status: `Todo`
- Kind: `Fix`
- Priority: `P0`
- Domain: `TAP Video`
- Labels: `zero-depth`, `sign`, `export`, `warning`, `parity`
- Contract: `ProductContract §3.3`
- Match Keys: `sampleCount zero, missing depth video, terminal artifact`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Retain, sign, and export a valid TAP Video with zero depth coverage and
  show a non-blocking warning, matching still-photo policy.
- Out of Scope: Inventing depth samples or claiming 3D readiness.
- Done When: Runtime, queue, manifest, UI, and focused tests no longer treat
  missing depth alone as terminal.
- Related: `TAP-0045`, `TAP-0055`, `TAP-0071`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Resolved the hard conflict in favor of non-blocking output.

### TAP-0012 — Align Standard FOV/depth and PRO no-crop behavior

- Status: `Todo`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Camera`
- Labels: `fov`, `depth`, `standard`, `pro`, `no-crop`
- Contract: `ProductContract §3.1`
- Match Keys: `preview-only zoom, capture FOV, hardware zoom, depth mapping`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Confirm and align each Standard visible FOV with its RGB/depth capture
  plan while keeping PRO fixed and uncropped.
- Out of Scope: New source switching, PRO multi-focal zoom, or fusion.
- Done When: Code, output facts, UI labels, and active docs express one behavior.
- Related: `TAP-0043`, `TAP-0066`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Replaced the earlier preview-only Standard assumption.

### TAP-0013 — Rebuild lifecycle-correct Locked Camera on the experiment branch

- Status: `Todo`
- Kind: `Experiment`
- Priority: `P0`
- Domain: `Locked Camera`
- Labels: `locked-camera`, `lifecycle`, `first-frame`, `freeze`, `experiment-branch`
- Contract: `ProductContract §4`
- Match Keys: `lock screen camera, black screen, secure capture, POC, E-series`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Dedicated experiment branch; record when assigned`
- Scope: Build a lifecycle-correct experimental version covering launch,
  first frame, capture, suspension, exit, and relaunch without the known freeze.
- Out of Scope: Production promotion, extension-side App Attest/Photos/network,
  reusing an old experiment as current implementation, private or undocumented
  APIs, treating direct-open as an import-completion signal, or suppressing the
  normal Pending Capture Queue to hide a lifecycle fault.
- Done When: The experimental implementation reaches its defined lifecycle
  checkpoints; camera configuration is committed before `startRunning`;
  containing-app import uses app-level `sessionContentUpdates`; and the build is
  ready for `TAP-0049` attended acceptance.
- Related: `TAP-0003`, `TAP-0049`, `TAP-0070`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Reframed all existing Locked work as historical experiment input.
  - `2026-08-12` Migrated durable experiment guardrails from the E-series:
    public APIs only, commit-before-start, app-level session-content import, and
    no direct-open or queue-suppression shortcut.

### TAP-0014 — Remove redundant Verify UX for TAPCam-owned captures

- Status: `Todo`
- Kind: `Feature`
- Priority: `P0`
- Domain: `Credential UX`
- Labels: `verify`, `attestation`, `owned-capture`, `share-status`
- Contract: `ProductContract §6`
- Match Keys: `Verify button, WiFi button, verify on share, credential status`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: For TAPCam-owned attested captures, present persisted credential and
  verifiability state without a standalone or Share-time Verify action.
- Out of Scope: External media verification.
- Done When: Product UI and docs contain no redundant active Verify workflow for
  owned captures and preserve accurate state language.
- Related: `TAP-0022`, `TAP-0069`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Owner limited true Verify to possible future external imports.

### TAP-0015 — Implement fine-grained credential retry optimization

- Status: `Todo`
- Kind: `Technical`
- Priority: `P2`
- Domain: `Pending Capture Queue`
- Labels: `credential`, `retry-window`, `cooldown`, `pause`, `migration`
- Contract: `ProductContract §6`
- Match Keys: `nextAttemptAt, retry budget, credential stage, assertion stage`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Separate credential/assertion/export retry stages and add bounded
  cooldown/window/pause state with migration.
- Out of Scope: Treating this technical optimization as a missing core feature.
- Done When: The approved state model, persistence migration, scheduling, UI
  boundary, and tests are implemented.
- Related: `ProductContract §6`, `TAPCamDemo/TAPLibrary/README.md`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Classified as future technical optimization.
  - `2026-08-12` Migrated the current coarse model to the Pending Capture Queue
    module README and retired the superseded standalone design document.

### TAP-0016 — Design and implement TAP Video 3D

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `TAP Video`
- Labels: `video-3d`, `depth-timeline`, `playback`, `performance`
- Contract: `ProductContract §3.3`; `§5.2`
- Match Keys: `Video 3D, Coming Soon, point cloud playback`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define depth time mapping, rendering, interaction, failure, and
  performance contracts before enabling Video 3D.
- Out of Scope: Reusing static-photo 3D as if it were synchronized video 3D.
- Done When: Product contract extension, approved prototype, implementation,
  tests, and required acceptance are complete.
- Related: `TAP-0045`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Migrated from undifferentiated Coming Soon to a real Task.

### TAP-0017 — Add white-balance UI

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `Camera`
- Labels: `white-balance`, `pro-controls`, `ui`
- Contract: `ProductContract §3.1`
- Match Keys: `WB, temperature, tint, manual white balance`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Add white-balance controls through existing capability, intent, and
  runtime boundaries.
- Out of Scope: Adjustable physical aperture.
- Done When: Product decision, prototype, runtime behavior, and validation are complete.
- Related: `TAP-0053`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Confirmed as true future camera work.

### TAP-0018 — Design true camera source switching

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `Camera`
- Labels: `source-switching`, `depth`, `capability`, `manual-controls`
- Contract: `ProductContract §3.1`
- Match Keys: `camera source, lens switching, Triple, Wide, Tele, LiDAR`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define source selection, depth pairing, control availability, output
  facts, transitions, and validation for true source switching.
- Out of Scope: Calling preview magnification source switching or auto fusion.
- Done When: A separately approved contract and implementation meet their evidence gate.
- Related: `TAP-0012`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Kept as future work distinct from current FOV behavior.

### TAP-0019 — Design RAW/ProRAW output contracts

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `Output`
- Labels: `raw`, `proraw`, `manifest`, `signing`, `reader`
- Contract: `ProductContract §3.4`
- Match Keys: `RAW output, DNG, Apple ProRAW`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define profile, resources, manifest, signing, export, reader, and
  validation contracts for RAW/ProRAW.
- Out of Scope: Mutating current HEIC/JPG profiles into a fallback.
- Done When: The new reviewed contract and end-to-end implementation are accepted.
- Related: `TAP-0054`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Confirmed as future output work.

### TAP-0020 — Design 24 MP deferred photo delivery

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `Output`
- Labels: `24mp`, `deferred-delivery`, `photo-output`
- Contract: `ProductContract §3.4`
- Match Keys: `24 MP, deferred photo, max dimensions`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Create an explicit 24 MP delivery and provenance contract.
- Out of Scope: Reinterpreting current quality tuning as 24 MP support.
- Done When: Profile, runtime, storage, signing, reading, and device acceptance are complete.
- Related: `TAP-0054`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Confirmed as future output work.

### TAP-0021 — Maintain a C2PA-compatibility checklist without claiming certification

- Status: `Todo`
- Kind: `Technical`
- Priority: `P2`
- Domain: `Provenance`
- Labels: `c2pa`, `compatibility`, `resource-model`, `claims`
- Contract: `ProductContract §3.4`; `§7`
- Match Keys: `C2PA support, credential standard, certification`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define design checks that keep new resources and signing boundaries
  compatible with possible future C2PA integration.
- Out of Scope: Claiming current compliance, certification, or authority.
- Done When: The checklist is linked from relevant output/provenance designs and
  used by future Tasks.
- Related: `TAP-0062`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Separated compatibility guardrails from an unsupported capability claim.

### TAP-0022 — External media import and in-app Verify

- Status: `Inbox`
- Kind: `Decision`
- Priority: `P3`
- Domain: `Verification`
- Labels: `external-import`, `verify`, `unowned-media`
- Contract: `ProductContract §6`
- Match Keys: `import photo, external asset, verify workflow`
- Assignee: `Product owner`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Decide whether TAPCam should import external media and run a true Verify flow.
- Out of Scope: Reintroducing Verify for TAPCam-owned attested captures.
- Done When: Owner accepts or rejects a bounded external-import product contract.
- Related: `TAP-0014`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created as the only current rationale for a future in-app Verify action.

### TAP-0023 — Implement TAP Video `.tapnap` transport

- Status: `Todo`
- Kind: `Feature`
- Priority: `P2`
- Domain: `Share`
- Labels: `tapnap`, `video`, `package`, `share`
- Contract: `ProductContract §5.3`
- Match Keys: `Video TAPNAP, video package, Coming Soon`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define and implement a real TAP Video package contract.
- Out of Scope: Disguising an original MP4 as the still/live package.
- Done When: Format, generation lifecycle, validation, UI, and tests are complete.
- Related: `TAP-0061`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Migrated from Coming Soon to an explicit Task.

### TAP-0024 — Implement Sticker sharing

- Status: `Todo`
- Kind: `Feature`
- Priority: `P3`
- Domain: `Share`
- Labels: `sticker`, `share`
- Contract: `ProductContract §5.3`
- Match Keys: `Sticker, Coming Soon`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define supported media, rendering, privacy, and lifecycle for Sticker share.
- Out of Scope: Placeholder-only activation.
- Done When: Contract, UI, implementation, and validation are complete.
- Related: `TAP-0061`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Migrated from Coming Soon.

### TAP-0025 — Implement Link sharing

- Status: `Todo`
- Kind: `Feature`
- Priority: `P3`
- Domain: `Share`
- Labels: `link`, `share`, `backend`
- Contract: `ProductContract §5.3`
- Match Keys: `Link, Coming Soon, share URL`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define ownership, privacy, expiry, backend, and UX for Link share.
- Out of Scope: Exposing a nonfunctional URL row.
- Done When: Approved contract, implementation, and operational acceptance are complete.
- Related: `TAP-0061`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Migrated from Coming Soon.

### TAP-0026 — Cancel superseded PhotoKit display requests at the request layer

- Status: `Todo`
- Kind: `Technical`
- Priority: `P2`
- Domain: `Viewer`
- Labels: `photokit`, `cancellation`, `carousel`, `resource-request`
- Contract: `ProductContract §5.2`
- Match Keys: `display request ID, Swift Task cancel, image request cancellation`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Cancel stale underlying PhotoKit requests when carousel/display work is superseded.
- Out of Scope: Redesigning Viewer navigation.
- Done When: Request ownership, cancellation, races, and tests are explicit.
- Related: `TAP-0059`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Imported as technical debt, not a missing product feature.

### TAP-0027 — Define thumbnail retention and purge policy

- Status: `Todo`
- Kind: `Technical`
- Priority: `P2`
- Domain: `Library`
- Labels: `thumbnail`, `privacy`, `cache`, `retention`
- Contract: `ProductContract §5`
- Match Keys: `thumbnail cache, derived private photo, purge`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Specify retention, invalidation, purge triggers, and protected storage for thumbnails.
- Out of Scope: Removing user-visible Library thumbnails.
- Done When: Policy, implementation, migration if required, and tests are complete.
- Related: `TAP-0058`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Imported from privacy evidence gaps.

### TAP-0028 — Migrate legacy exported GPS copies

- Status: `Todo`
- Kind: `Technical`
- Priority: `P2`
- Domain: `Pending Capture Queue`
- Labels: `gps`, `privacy`, `migration`, `exported-record`
- Contract: `ProductContract §1`
- Match Keys: `persisted location, exported bundle GPS, precise location cleanup`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Remove redundant precise location retained by legacy exported records.
- Out of Scope: Removing location needed before a pending Photos export completes.
- Done When: Migration is idempotent, protected-data safe, and tested.
- Related: `TAP-0027`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Imported from the scorecard as technical debt.

### TAP-0029 — Isolate Debug fixtures and split oversized test files

- Status: `Todo`
- Kind: `Technical`
- Priority: `P3`
- Domain: `Tests`
- Labels: `debug-fixture`, `test-organization`, `support-target`
- Contract: `ProductContract §1`
- Match Keys: `fixture target, huge test file, test debt`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Move Debug fixtures toward a support boundary and split oversized tests
  without changing product behavior.
- Out of Scope: Claiming new feature coverage solely from file reorganization.
- Done When: Approved structural boundaries and existing behavior tests pass.
- Related: `None`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Combined closely related test-only debt during board bootstrap.
  - `2026-08-12` Historical R1–R4 production splits and most source-spelling
    assertions were already completed; remaining scope is only Debug support
    isolation and oversized test-suite organization.

### TAP-0075 — Migrate and remove obsolete Startup/Camera design documents

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `App / Camera`
- Labels: `migration`, `startup`, `camera`, `pro`, `focus`, `delete-old-docs`
- Contract: `ProductContract §2–3`
- Match Keys: `FirstLaunch, CameraControlsDesign, device limits, PRO plan, focus EV, Pro Video plan`
- Assignee: `migrate_startup_camera_docs Agent`
- Dev Session: `/root/migrate_startup_camera_docs`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Migrate unique current implementation ownership and acceptance hooks
  from the obsolete Startup and Camera design documents into App/Camera module
  READMEs and acceptance Tasks, then remove the obsolete sources.
- Out of Scope: Changing product behavior, tests, or Swift code.
- Done When: Module READMEs contain the unique current facts, links and source
  dependencies are updated, and the obsolete design files are deleted.
- Related: `TAP-0002`, `TAP-0003`, `TAP-0040`–`TAP-0043`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Split from the staged documentation-retention work and assigned.
  - `2026-08-12` Completed. Migrated setup and Camera implementation ownership
    into App/UI/Planning/Runtime READMEs, captured attended procedures in
    `TAP-0040/41/42/43/45`, removed prose-dependent tests, and deleted the
    obsolete Startup/Camera/Future/scorecard documents.

### TAP-0076 — Migrate and remove obsolete Viewer/Queue design documents

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `Viewer / Pending Capture Queue`
- Labels: `migration`, `viewer`, `share`, `delete`, `credential-retry`, `terminology`
- Contract: `ProductContract §5–6`
- Match Keys: `DepthAnalysisViewerRedesign, CredentialSigningRetryDesign, TAP Library queue`
- Assignee: `migrate_viewer_queue_docs Agent`
- Dev Session: `/root/migrate_viewer_queue_docs`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Migrate unique current Viewer/Share/Delete and coarse queue behavior
  into module READMEs, remove deprecated Verify/drawer language, normalize terms,
  and remove the obsolete design sources.
- Out of Scope: Implementing the future fine-grained retry model.
- Done When: Module READMEs own the current facts, links are updated, and the two
  obsolete design files are deleted.
- Related: `TAP-0004`, `TAP-0014`, `TAP-0015`, `TAP-0059`, `TAP-0061`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Split from the staged documentation-retention work and assigned.
  - `2026-08-12` Completed. Migrated current Viewer, Share, Delete, terminology,
    coarse queue retry, and missing-depth obligations into module READMEs;
    removed both superseded standalone design documents and repaired links.

### TAP-0077 — Consolidate App Attest documentation

- Status: `Done`
- Kind: `Documentation`
- Priority: `P1`
- Domain: `App Attest`
- Labels: `migration`, `security`, `backend-contract`, `delete-old-docs`
- Contract: `ProductContract §3.4`; `§6–7`
- Match Keys: `ClientUsage, CredentialNameGuide, SecurityNotes, App Attest docs`
- Assignee: `consolidate_appattest_docs Agent`
- Dev Session: `/root/consolidate_appattest_docs`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Consolidate TAPCam-specific client, naming, privacy, trust, replay, and
  backend boundaries into `AppAttest/README.md` and `BackendContract.md`, then
  delete the three redundant helper documents.
- Out of Scope: Changing the API or backend implementation.
- Done When: The two retained contracts own all unique obligations, old links are
  fixed, and the redundant documents are deleted.
- Related: `TAP-0003`, `TAP-0021`, `TAP-0046`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Split from the staged documentation-retention work and assigned.
  - `2026-08-12` Completed. Consolidated client/naming/privacy rules into the
    App Attest README, consolidated server trust/replay/file-binding duties into
    the Backend Contract, deleted three redundant helper documents, and passed
    link and whitespace validation.

### TAP-0078 — Extract the canonical TAP Video format contract and remove old video plans

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `TAP Video`
- Labels: `format-contract`, `klv`, `manifest`, `proof-slot`, `migration`
- Contract: `ProductContract §3.3`
- Match Keys: `DepthVideoRecordingDesign, TAPVideoLibraryPRD, video format, content binding`
- Assignee: `extract_video_format_contract Agent`
- Dev Session: `/root/extract_video_format_contract`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Create a compact TAP Video container/KLV/manifest/proof/content-binding
  contract, migrate current code ownership to module READMEs, and delete the old
  design/PRD phase documents.
- Out of Scope: Changing the format or implementing Video 3D.
- Done When: Format vectors and code depend on the compact current contract and
  old plans are removed without losing cross-implementation obligations.
- Related: `TAP-0011`, `TAP-0016`, `TAP-0045`, `TAP-0057`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the document-retention manifest.
  - `2026-08-12` Completed. Added `TAPVideoFormatContract.md` for current MP4,
    KLV, manifest, registration, proof-slot, content-binding, queue/readback,
    playback, zero-depth, compatibility, and evidence boundaries; removed the
    three superseded video design/audit documents.

### TAP-0079 — Migrate historical evidence and remove AITrace, scorecards, and old acceptance snapshots

- Status: `Done`
- Kind: `Documentation`
- Priority: `P1`
- Domain: `Governance / Acceptance`
- Labels: `aitrace`, `scorecard`, `acceptance`, `git-history`, `delete-old-docs`
- Contract: `ProductContract §1`; `§8`
- Match Keys: `AITrace, ProjectScorecard, branch audit, dated acceptance`
- Assignee: `Board Steward with historical_evidence_migration_audit Agent`
- Dev Session: `/root` and `/root/historical_evidence_migration_audit`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Move executable procedures and unresolved work into DeviceAcceptance or
  technical Tasks, update direct test/doc dependencies, then remove historical
  snapshots from the current tree.
- Out of Scope: Deleting evidence before its reusable procedure or obligation is captured.
- Done When: Current tests/docs no longer depend on historical prose, required
  procedures live in Task-linked acceptance records, and Git is the sole archive.
- Related: `TAP-0003`, `TAP-0029`, `TAP-0040`–`TAP-0048`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the document-retention manifest.
  - `2026-08-12` Moved to Doing after per-file Task/evidence mapping completed;
    removed prose-spelling tests that made historical documents active inputs.
  - `2026-08-12` Completed. Kept minimal prior evidence in Task history, added
    ten executable acceptance drafts, removed dated evidence/AITrace/scorecard
    bodies, and left Git as the sole historical archive.

### TAP-0080 — Migrate Locked Camera guardrails and remove main-tree experiment prose

- Status: `Done`
- Kind: `Documentation`
- Priority: `P1`
- Domain: `Locked Camera`
- Labels: `locked-camera`, `experiment`, `lifecycle`, `migration`, `delete-old-docs`
- Contract: `ProductContract §4`
- Match Keys: `LockedCameraCapturePOC, API Notes, E-series, black screen`
- Assignee: `Board Steward with write_library_ui_locked_acceptance Agent`
- Dev Session: `/root` and `/root/write_library_ui_locked_acceptance`
- Branch/Worktree: `codex/sketch-ui-pilot-checkpoint-1`
- Scope: Move public-API prohibitions, lifecycle completion criteria, and
  attended procedure into `TAP-0013`/`TAP-0049`, then remove the old POC and API
  experiment narratives from the main documentation tree.
- Out of Scope: Deleting experiment-branch code or promoting it to production.
- Done When: The board fully specifies the next experiment and acceptance while
  the main tree contains no competing “current” Locked experiment narrative.
- Related: `TAP-0013`, `TAP-0049`, `TAP-0070`
- Created: `2026-08-12`
- Updated: `2026-08-12`
- Revision History:
  - `2026-08-12` Created from the document-retention manifest.
  - `2026-08-12` Moved to Doing; technical guardrails were migrated into
    `TAP-0013` and the attended lifecycle procedure is being written.
  - `2026-08-12` Completed. Added the blocked, owner-attended `TAP-0049`
    procedure, retained only public-API/lifecycle guardrails in the Task, and
    removed the POC, API notes, and E-series trace from the current tree.

## 5. Inbox Decision Registry

The following records deliberately remain compact until the owner decides
whether they belong in Todo. They still have stable IDs and participate in
duplicate matching.

| ID | Kind | Priority | Domain | Labels / Match Keys | Decision needed | Created | History |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `TAP-0030` | Decision | P3 | App Intents | `widget, control, richer score history` | Whether to extend the completed minimal App Intents surface | 2026-08-12 | Bootstrapped from broad future text |
| `TAP-0031` | Decision | P2 | Scoring | `score calibration, Release placement` | Whether and where calibrated scores belong in Release UI | 2026-08-12 | Separated existing local score from future product placement |
| `TAP-0032` | Decision | P3 | UI | `Liquid Glass, iOS 26` | Whether to propose a new Liquid Glass design through HTML-first workflow | 2026-08-12 | Not inherited as automatic Todo |
| `TAP-0033` | Decision | P3 | Library | `durable filters, reopen detail` | Whether durable filters/reopen behavior is a product priority | 2026-08-12 | Migrated from vague future text |
| `TAP-0034` | Decision | P3 | Rendering | `Metal, SceneKit replacement` | Activate only if performance or capability evidence justifies it | 2026-08-12 | Classified as conditional technical option |
| `TAP-0035` | Decision | P3 | Camera UI | `second shutter` | Todo or explicit non-goal | 2026-08-12 | Old document said only “not this pass” |
| `TAP-0036` | Decision | P3 | Camera UI | `left handed, right handed, shutter position` | Todo or explicit non-goal | 2026-08-12 | Old document said only “not this pass” |
| `TAP-0037` | Decision | P3 | Camera UI | `landscape, side controls` | Todo or explicit non-goal | 2026-08-12 | Old document said only “not this pass” |
| `TAP-0038` | Decision | P3 | TAP Video | `scrub, per-frame analysis, plane analysis` | Whether advanced video-depth analysis is in product scope | 2026-08-12 | Deferred text is not treated as approval |
| `TAP-0039` | Decision | P3 | Camera UI | `new guide types` | Whether any additional guide has a real product requirement | 2026-08-12 | Prevents an open-ended guide Todo |

## 6. Device And Visual Acceptance Registry

These Tasks must be expanded with the template in §2.5 and confirmed with the
owner before execution.

| ID | Status | Priority | Related delivery | Scope | Procedure | Dev Session | Human Confirmation | History |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `TAP-0040` | Todo | P0 | `TAP-0008` | Clean install: every setup operation starts only after its corresponding button | [Procedure](Acceptance/TAP-0040-first-install-operations.md) | Unassigned | Pending | Created 2026-08-12 from permission regression; executable draft added 2026-08-12 |
| `TAP-0041` | Todo | P0 | `TAP-0009` | Continue: real first frame, safe shutter/controls, no early-entry freeze | [Procedure](Acceptance/TAP-0041-camera-readiness.md) | Unassigned | Pending | Created 2026-08-12 from readiness decision; executable draft added 2026-08-12 |
| `TAP-0042` | Todo | P1 | `TAP-0053` | EV direction, ISO/S clamp, AF→MF, focus assist, front gating, transitions, device matrix | [Procedure](Acceptance/TAP-0042-pro-controls.md) | Unassigned | Pending | Migrated from camera evidence gaps; executable draft added 2026-08-12 |
| `TAP-0043` | Todo | P0 | `TAP-0012` | Standard RGB/depth per FOV and PRO fixed uncropped output | [Procedure](Acceptance/TAP-0043-fov-depth-pro-no-crop.md) | Unassigned | Pending | Created 2026-08-12 from FOV conflict; executable draft added 2026-08-12 |
| `TAP-0044` | Todo | P1 | `TAP-0056` | Live Photo capture, paired MOV, signing, Photos readback, audio and playback | [Procedure](Acceptance/TAP-0044-live-photo-chain.md) | Unassigned | Pending | Migrated from Live Photo evidence gaps; executable draft added 2026-08-12 |
| `TAP-0045` | Todo | P0 | `TAP-0011`, `TAP-0057` | Device codec/drop/RSS/thermal/registration, iCloud-only, broad formats, zero-depth path | [Procedure](Acceptance/TAP-0045-tap-video-device.md) | Unassigned | Pending | Consolidated TAP Video device gaps; executable draft added 2026-08-12 |
| `TAP-0046` | Todo | P1 | `TAP-0056`, `TAP-0057` | Entitlement, production backend, assertion and final signed-export gate | [Procedure](Acceptance/TAP-0046-app-attest-production.md) | Unassigned | Pending | Migrated from App Attest evidence gaps; executable draft added 2026-08-12 |
| `TAP-0047` | Todo | P1 | `TAP-0058`, `TAP-0059` | Limited access, Photos system delete, pending confirm, adjacency, empty close | [Procedure](Acceptance/TAP-0047-library-permission-delete.md) | Unassigned | Pending | Created from Library contract audit; executable draft added 2026-08-12 |
| `TAP-0048` | Todo | P0 | `TAP-0006` | Approved Web states versus SwiftUI geometry, icons, layout, navigation and state presentation | [Procedure](Acceptance/TAP-0048-web-swiftui-parity.md) | Unassigned | Pending | Created for HTML-first workflow; executable draft added 2026-08-12 |
| `TAP-0049` | Todo | P0 | `TAP-0013` | Locked launch/first-frame/soak/capture/suspend/exit/relaunch | [Blocked Procedure](Acceptance/TAP-0049-locked-camera-lifecycle.md) | Unassigned | Pending | Executable draft added 2026-08-12; cannot run until lifecycle-correct experiment is ready |

## 7. Completed Task Registry

These records bootstrap known completed work. Their historical completion does
not replace the Product Contract, and linked device evidence may remain open.

| ID | Domain | Completed scope | Related evidence | Completed/recorded | Revision History |
| --- | --- | --- | --- | --- | --- |
| `TAP-0001` | Governance | Canonical Product Contract, UI workflow, Markdown board schema, initial inventory, and Agent rules established | N/A | 2026-08-12 | Created and completed in the board-bootstrap task; revised root Agent lifecycle on 2026-08-12 to require ordered reading, pre-implementation discussion, prototype-first UI, validation, documentation-impact tracking, and Board Steward closure |
| `TAP-0050` | Onboarding | Network/Camera/Photos required; Location/Microphone optional | `TAP-0040` | Before board bootstrap; recorded 2026-08-12 | Imported from current policy |
| `TAP-0051` | Onboarding | Bounded wall-clock Network retry foundation and pure policy boundary | `TAP-0040` | Before board bootstrap; recorded 2026-08-12 | Final post-timeout UX remains `TAP-0010` |
| `TAP-0052` | Camera | PRO is a Release Photo and TAP Video capability | `TAP-0042`, `TAP-0045` | Before board bootstrap; recorded 2026-08-12 | Supersedes Photo-only/Debug-only history |
| `TAP-0053` | Camera | Standard Basic EV; PRO EV/ISO/S/AF-MF/focus assist; read-only ƒ | `TAP-0042` | Before board bootstrap; recorded 2026-08-12 | A 2026-07-01 attended run reported controls accepted, but lacked today's build/reset/numbered procedure; `TAP-0042` remains open |
| `TAP-0054` | Output | Release HEIC/JPG Output Format | `TAP-0044`, `TAP-0046` | Before board bootstrap; recorded 2026-08-12 | Historical iPhone 15 Pro HEIC/JPG originals retained 4032x3024 RGB, auxiliary depth, manifest, and test-shaped proof; production App Attest remains `TAP-0046` |
| `TAP-0055` | Photo | Missing depth does not block still save/sign/export | Device output evidence remains linked through relevant acceptance | Before board bootstrap; recorded 2026-08-12 | Current non-blocking policy retained |
| `TAP-0056` | Live Photo | Paired MOV capture, signing, export, playback, and versioned app-side contract | `TAP-0044`, `TAP-0046` | Before board bootstrap; recorded 2026-08-12 | Historical v2/v3 primary-photo/paired-MOV suites passed; device and production-backend acceptance remain `TAP-0044/46` |
| `TAP-0057` | TAP Video | RGB/optional audio/KLV depth, manifest/proof, queue/export/readback, poster, foreground RAW/2D | `TAP-0045`, `TAP-0046` | Before board bootstrap; recorded 2026-08-12 | Historical R1–R4/golden gates and iPhone 15 Pro foreground evidence passed; performance, iCloud, zero-depth, and production backend remain `TAP-0045`, `TAP-0011`, `TAP-0046` |
| `TAP-0058` | Library | User-facing mixed-media TAP Library and canonical item order | `TAP-0047` | Before board bootstrap; recorded 2026-08-12 | Historical focused tests covered fresh top-start, clicked-item return, cached snapshots, and queue priority; real Photos/large-library behavior remains `TAP-0047` |
| `TAP-0059` | Viewer | Horizontal mixed-media paging, stable bottom toolbar and RAW/2D/3D capsule | `TAP-0047`, `TAP-0048` | Before board bootstrap; recorded 2026-08-12 | Replaces old drawer/vertical design |
| `TAP-0060` | 3D | Eligible static-photo native SceneKit point projection | `TAP-0048` | Before board bootstrap; recorded 2026-08-12 | Historical Simulator projection/interaction evidence does not expand the point-projection claim; visual/device parity remains `TAP-0048` |
| `TAP-0061` | Share | App-owned format selection and per-choice on-demand temporary payload lifecycle | `TAP-0047` | Before board bootstrap; recorded 2026-08-12 | Old direct-share design superseded |
| `TAP-0062` | Verification | Cross-project Live Photo browser verification contract documented | External project owns implementation evidence | Before board bootstrap; recorded 2026-08-12 | Contract completion does not claim browser delivery in this repo |

## 8. Deprecated Task And Design Registry

| ID | Domain | Deprecated item | Reason / replacement | Recorded | Revision History |
| --- | --- | --- | --- | --- | --- |
| `TAP-0063` | Onboarding | Page appearance, refresh, foregrounding, or background work implicitly starts setup operations | Explicit row action owns each operation; replaced by `TAP-0008` | 2026-08-12 | Expanded from Photos-only regression to all setup rows |
| `TAP-0064` | Camera docs | “Complete Video and Live Photo are unimplemented” | Current capabilities are `TAP-0056` and `TAP-0057` | 2026-08-12 | Preserve only as historical status |
| `TAP-0065` | PRO | `Photo-Only v1` | PRO supports Photo and TAP Video; see `TAP-0052` | 2026-08-12 | Deprecated product matrix |
| `TAP-0066` | Camera | Standard visible FOV is preview-only magnification | Owner requires corresponding RGB/depth capture plan; see `TAP-0012` | 2026-08-12 | Latest product decision supersedes prior preview-only note |
| `TAP-0067` | Viewer | Tool drawer, vertical Verify/dismiss, detents, top-level Heatmap/Overlay/Mask modes | Replaced by horizontal Viewer and bottom capsule `TAP-0059` | 2026-08-12 | Must not return to Todo automatically |
| `TAP-0068` | Share | Prepare resources immediately and open system Share directly | Replaced by on-demand app-owned selection `TAP-0061` | 2026-08-12 | Historical flow only |
| `TAP-0069` | Verification | Verify every TAPCam-owned capture when viewed/shared or expose standalone Verify | Persisted credential/verifiability state replaces it; see `TAP-0014` | 2026-08-12 | A prior panel passed privacy/presentation tests, but active Verify for owned captures is now deprecated; keep only public-safe state display |
| `TAP-0070` | Locked Camera | Existing POC/E-series represents current product capability | Historical experiments only; replacement experiment `TAP-0013` | 2026-08-12 | E-series exposed start-ordering and recurring direct-open lifecycle freezes; none satisfies `TAP-0013/49` |
| `TAP-0071` | Photo/Video | Missing depth alone discards or terminally fails an otherwise valid artifact | Non-blocking truth-preserving output; video fix `TAP-0011` | 2026-08-12 | Unified still/video policy |
| `TAP-0072` | TAP Video | AirPlay, PiP, and background playback | Explicitly outside product scope | 2026-08-12 | Must not remain in Todo |
| `TAP-0073` | Live Photo | Per-frame depth in the current paired MOV | Depth belongs to primary still; new format required for any future video-depth product | 2026-08-12 | Explicit non-goal |
| `TAP-0074` | Localization | `Photo Integrity = 照片保真` | Implies unsupported visual/authenticity meaning; replacement decision `TAP-0005` | 2026-08-12 | Old copy must not propagate to new prototypes |

## 9. Board Revision Log

- `2026-08-12` Schema 1 created. Imported the product audit, owner decisions,
  current capabilities, true future work, evidence gaps, conditional Inbox
  ideas, and deprecated designs.
- `2026-08-12` Established Markdown as the task database, one long-lived Board
  Steward Session as the canonical writer, and one Task ID per development
  session as the default collaboration model.
- `2026-08-12` Designated this board-bootstrap conversation as the Board
  Steward Session and added user command and development-handoff protocols.
- `2026-08-12` Completed `TAP-0076`; moved Viewer/Queue current facts into
  module-owned READMEs and deleted the two superseded design sources.
- `2026-08-12` Added executable attended-device drafts for `TAP-0040`,
  `TAP-0041`, `TAP-0042`, `TAP-0043`, and `TAP-0045`; unresolved matrices and
  numeric budgets remain owner-confirmed Blocked inputs rather than invented
  acceptance criteria.
- `2026-08-12` Completed `TAP-0075` after module and acceptance migration;
  removed the obsolete Startup, Camera-design, Future-spec, and scorecard prose.
- `2026-08-12` Completed the documentation-consolidation umbrella and its
  historical/Locked/terminology children. Ten attended acceptance drafts now
  hold the device procedures; old bodies are recoverable only through Git.
- `2026-08-12` Revised completed governance Task `TAP-0001`. Root `AGENTS.md`
  now defines the mandatory read-discuss-prototype-implement-validate-track
  lifecycle, and the development handoff records exactly which canonical,
  prototype, module, specialized, acceptance, and governance files changed or
  are explicitly not applicable. `UIPrototypeContract.md` now permits a
  prototype-first exception only for a non-visual urgent runtime/safety fix or
  explicit owner authorization, with synchronization required before closure.
