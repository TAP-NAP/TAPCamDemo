# TAPCam Project Board

- Schema: `1`
- Next Task ID: `TAP-0085`
- Canonical Product Contract: [ProductContract.md](ProductContract.md)
- UI Prototype Contract: [UIPrototypeContract.md](UIPrototypeContract.md)
- Board Steward Session: `019ff4ea-acba-7051-bd0f-3d489f1caadc`
- Last updated: `2026-08-14`

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
- `TAP-0084` Design a Library-to-Viewer zoom transition with stable top chrome

### Todo

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

- `TAP-0081` Unify TAP Share selection and preparation into an anchored handoff
- `TAP-0082` Device acceptance: TAP Share anchored handoff and anti-flash progress
- `TAP-0083` Eliminate cold-path UI starvation and codify responsiveness guardrails

### Done

- `TAP-0001` Establish the canonical contract, UI workflow, and Markdown board
- `TAP-0002` Reconcile active documents with the Product Contract
- `TAP-0003` Migrate unique facts, then remove obsolete documents
- `TAP-0004` Normalize TAP Library and Pending Capture Queue terminology
- `TAP-0006` Build the repository-owned HTML/Web UI prototype foundation
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

- Status: `Done`
- Kind: `Feature`
- Priority: `P0`
- Domain: `UI Prototype`
- Labels: `html-first`, `web-prototype`, `state-machine`, `visual-contract`
- Contract: `ProductContract §9`; `UIPrototypeContract`
- Match Keys: `HTML UI, web mock, visual editor, prototype, frontend layout`
- Assignee: `prototype_contract_audit Agent`
- Dev Session: `/root/prototype_contract_audit`
- Branch/Worktree: `Current main working tree; baseline main@a4cf808`
- Scope: Create a lightweight, versioned, repository-owned interactive
  prototype foundation served as static HTML/CSS/JavaScript, with no backend or
  heavyweight mobile-Web runtime. The current milestone supplies one clear,
  extensible entry point plus the first vertical TAP Share slice for `TAP-0081`:
  the selected format-selection and preparation references, deterministic
  state switching, and the 50 ms delayed-reveal / 400 ms minimum-visible
  progress policy. Later first-install, Viewfinder, and other product slices
  extend this entry point only through their own Tasks after reading their
  applicable contracts.
- Out of Scope: A backend, production hosting, a general-purpose mobile runtime
  or component framework, implementing unrelated product screens inside this
  milestone, and claiming native camera, permission, depth, performance, or App
  Store evidence.
- Done When: The owner can serve the lightweight prototype statically, enter
  the TAP Share slice through the documented extensible entry point, switch its
  documented states, inspect component relationships and manifest traceability,
  and explicitly approve the exact recorded Share revision. This Task must not
  move to Done merely because files render, because a heavier scaffold was
  started, or because generated image references were previously accepted;
  exact repository revision approval is required. Later product slices are
  separate Task work and do not keep this foundation milestone open.
- Current Milestone Revision: `TAP-0081-r2-candidate` (final updated revision;
  owner approved on `2026-08-13`)
- Prototype Path: `Prototype/index.html`
- Manifest / QA: `Prototype/manifest.json`; `Prototype/design-qa.md`
- Approval: `ownerApproved`. The product owner approved exact base revision
  `TAP-0081-r1` on `2026-08-12` with “我觉得 web 模拟流程是合理的 请开始实现”. On
  `2026-08-13`, after reviewing the final updated
  `TAP-0081-r2-candidate`, the owner explicitly confirmed “已确认没有问题 请继续实施
  Swift UI”. The full current revision—including its resource/local-integrity
  states and refined toolbar treatment—is therefore the current SwiftUI visual
  authority. Share and Delete use the prototype's custom vector glyphs in 20pt
  icon boxes, each glyph is optically concentric inside a 42pt circular
  background matching the top-left Back control, and the centered
  `RAW / 2D / 3D` capsule keeps its compact intrinsic width rather than filling
  the space between the outer controls. This approval authorizes native
  implementation; it does not by itself complete TAP-0006 or TAP-0081.
- Milestone Evidence: The heavyweight React/Vite mobile runtime was removed and
  replaced by static `index.html`, `prototype.css`, and `prototype.js` plus a
  documented `Prototype/README.md` entry point. `node
  Prototype/prototype.test.mjs` passes. The browser review exercised selector,
  Slow, Threshold, Cancel, Failure, Retry availability, system-dismissal
  return, media matrix, and credential matrix with no reported console error.
  The 120 ms threshold fixture recorded progress reveal at 51 ms and the system
  boundary at 452 ms; captures are
  `Prototype/evidence/TAP-0081-r1-selection-full.png` and
  `Prototype/evidence/TAP-0081-r1-preparing-full.png`.
- Documentation Sync: `Docs/ProductContract.md §5.3/§9` records the anchored
  Share handoff and incremental prototype slices; `Docs/UIPrototypeContract.md`
  records lightweight, statically served vertical-slice growth; `README.md`,
  `Docs/README.md`, and `Prototype/README.md` expose the review entry point and
  evidence boundary.
- Related: `TAP-0048`, `TAP-0007`, `TAP-0081`
- Created: `2026-08-12`
- Updated: `2026-08-13`
- Revision History:
  - `2026-08-12` HTML/Web was chosen as the default future visual-spec workflow;
    no prototype implementation was started in this governance task.
  - `2026-08-12` Linked as the prototype-foundation dependency for `TAP-0081`.
    The generated Share references are review evidence only, so native
    `TAP-0081` visual implementation remains gated on a runnable repository Web
    revision and owner approval.
  - `2026-08-12` Assigned to `/root/prototype_contract_audit` and moved Todo ->
    Doing on the shared `main@a4cf808` baseline. The bounded delivery is the
    repository-owned mobile Web foundation plus its first TAP Share fixture
    revision and manifest. Owner approval must cite the exact revision before
    this Task can become Done or authorize the native `TAP-0081` visual change.
  - `2026-08-12` Owner clarified that `TAP-0006` remains active and Doing; no
    Partial status, pause, split, deprecation, or global prototype-process
    cancellation applies. The implementation direction changed from a
    heavyweight mobile-Web runtime to a lightweight, statically served
    HTML/CSS/JavaScript foundation. This milestone delivers the extensible
    entry point and first TAP Share vertical slice. Its staged progress is
    preserved in this Revision History; first-install, Viewfinder, and later
    slices belong to their own contract-scoped Tasks. The Task remains not Done
    until the owner approves the exact lightweight Share revision.
  - `2026-08-12` Prototype handoff recorded for exact revision `TAP-0081-r1` at
    `Prototype/index.html`, with manifest, design QA, static-contract test,
    browser-path exercise, 51 ms reveal / 452 ms boundary timing evidence, and
    two repository captures. The heavyweight React/Vite runtime was removed;
    the lightweight static foundation and Share slice are ready for owner
    review. Manifest approval remains `pendingOwnerReview`, so this Task stays
    Doing and is not approved or Done.
  - `2026-08-12` Owner explicitly approved exact repository revision
    `TAP-0081-r1` (“我觉得 web 模拟流程是合理的 请开始实现”). The Share-slice
    prototype gate is satisfied and native `TAP-0081` implementation is
    authorized. `TAP-0006` remains Doing until its milestone handoff and
    documentation obligations are reconciled; prototype approval alone is not
    a Done transition. The manifest still requires a separate authorized
    synchronization from `pendingOwnerReview` to the recorded Board decision.
  - `2026-08-13` Recorded the owner's component-scoped visual approval of the
    current Share prototype's Viewer toolbar treatment: native Share/Delete
    icon identities, their circular backgrounds, and optical concentricity.
    This extends the existing `TAP-0081-r1` visual authority for the bounded
    native parity change and does not convert the complete
    `TAP-0081-r2-candidate` from `pendingOwnerReview` to approved. `TAP-0006`
    remains Doing; the prototype/manifest synchronization and milestone
    completion review remain open.
  - `2026-08-13` Owner refined that component decision. The current toolbar
    authority is the prototype's custom Share/Delete vectors in 20pt boxes,
    optically centered in 42pt circles equal to the top-left Back button, with
    a compact, intrinsically sized center mode capsule. The interim 54px outer
    controls, 25px bottom / 18px gap geometry, and flexible fill center column
    are superseded implementation history rather than visual authority.
    TAP-0006 remains Doing while the prototype manifest/QA synchronization is
    completed; this does not approve the rest of the r2 candidate.
  - `2026-08-13` Owner subsequently approved the complete final updated
    `TAP-0081-r2-candidate` with “已确认没有问题 请继续实施 Swift UI”. This
    supersedes the interim component-only approval boundary: the exact current
    prototype, including 42pt Back-matched circles, concentric 20pt custom
    vectors, shared Share progress-ring center, compact non-flex-fill mode
    capsule, and all recorded r2 resource/local-integrity states, is now the
    visual authority for `/root` SwiftUI implementation. TAP-0006 remains Doing
    pending manifest/QA synchronization and handoff reconciliation; no Done
    transition is inferred.
  - `2026-08-13` Final closure audit completed after prototype commit
    `70e8b60d4e20486a6d4847d726b393a50e22c7ba` and governance synchronization
    commit `456e30790bdae0b227ae99433e604d0c87f6dfb1`. The lightweight static
    entry point, TAP Share vertical slice, deterministic states, 50/400 timing,
    manifest and design-QA traceability, exact-revision owner approval, static
    contract test, browser-path evidence, and required documentation now satisfy
    the recorded Done When. The owner explicitly confirmed “同意 06 关闭 并提交且
    推送相关代码”. Moved TAP-0006 Doing -> Done. First-install, Viewfinder, and
    every later prototype slice remain independently scoped by their own Tasks;
    extending the shared foundation through those Tasks does not reopen
    TAP-0006.

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
- Labels: `readiness`, `first-frame`, `shutter`, `controls`, `freeze-prevention`,
  `resource-initialization`, `library-catalog`, `cold-install`, `reinstall`,
  `app-update`, `versioned-marker`, `prototype-first`
- Contract: `ProductContract §2.4–2.5` (resource-initialization extension
  synchronized on `2026-08-13`)
- Match Keys: `Continue, camera ready, interactive, loading gate, page freeze,
  resource initialization, please wait, first Library snapshot, first launch,
  reinstall, app update, versioned completion marker, repeated launch,
  首次安装, 重新安装, 应用更新, 资源初始化, 请稍候`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Show one app-owned Resource Initialization / Please Wait state on the
  first launch after a fresh install, reinstall, and every app update. On fresh
  install/reinstall it follows the required first-install rows and Continue;
  after an update it runs before exposing the interactive camera even when the
  ordinary setup-completion marker already exists. Keep that state until both
  readiness groups complete: (a) capture graph, real first preview frame,
  primary controls, shutter, and required haptics are safe; and (b) the first
  usable TAP Library catalog metadata snapshot is available. A successful empty
  catalog is usable; the gate owns catalog identity/order metadata only, not
  media bytes or visual decoding. This two-group gate is an invariant, not a
  best-effort operation: persist its versioned completion marker and enter the
  interactive camera only after both groups succeed. The only product-visible
  transition is `Resource Initialization -> interactive camera`.
- Trigger / Versioned Completion Marker: Resource Initialization has its own
  persisted marker, distinct from setup/permission completion. The marker must
  identify the current installed app update and initialization-schema
  generation. An absent marker (fresh install/reinstall), a marker from another
  installed update, or a schema-generation mismatch triggers the gate. Write
  the current marker atomically only after both readiness groups succeed; an
  interrupted or abnormally incomplete run must leave it absent/stale so the
  next launch remains in the gate. An ordinary repeated launch whose marker
  exactly matches the current update/generation skips this cold resource setup
  and does not show Resource Initialization again.
- Current Behavior / Conflict: Product Contract §2.4–2.5, exact owner-approved
  Web revision `TAP-0009-r1-candidate`, and its manifest/design-QA
  `ownerApproved` metadata are synchronized. The approved state machine now
  includes the first usable TAP Library catalog checkpoint and the separate
  update-versioned completion marker, and remains independent of Share. Native
  implementation and its focused validation/device evidence are the remaining
  delivery work.
- Failure / Recovery: There is no product Retry, Failed, timeout, skip, or
  degraded-continuation state for this gate. Resource Initialization remains
  visible until both readiness groups succeed. Any abnormal noncompletion is a
  malignant implementation/lifecycle bug, not a supported product branch; it
  must remain attributable through bounded developer diagnostics that identify
  which readiness group and checkpoint did not complete, without exposing a
  recovery decision in the user interface or entering a partially ready camera.
- Out of Scope: Blocking on iCloud originals, complete original-resource
  downloads, all thumbnail decoding, local proof/hash work, ZIP/package work,
  system activity-controller prewarm, App Attest/network warmup, Pending Capture
  Queue retries or batch completion, or silently treating a warm second launch
  as first-install/update readiness evidence. The marker is not a Share-
  readiness, signature, verification, payload, cache, or package-prewarm marker;
  this gate must not open or prepare TAP Share, hash a Share payload, build ZIP/
  `.tapnap`, or initialize system Share UI.
- Prototype Gate: `Satisfied for TAP-0009-r1-candidate`. Repository path:
  `Prototype/index.html`; fixture:
  `Prototype/states/first-install-resource-initialization.json`; QA:
  `Prototype/design-qa.md`; manifest: `Prototype/manifest.json`. The exact
  approved revision distinguishes first launch after fresh install/reinstall,
  first launch after app update, and an ordinary repeated launch that bypasses
  the completed current generation. It covers both readiness completion orders,
  the stable Resource Initialization state, successful camera handoff, and the
  deliberate absence of Retry, Failed, timeout, skip, or degraded states. The
  owner explicitly approved it on `2026-08-13` with “原型我检查了 没有问题”.
  Commit `70e8b60d4e20486a6d4847d726b393a50e22c7ba` synchronizes the manifest
  boundary and design QA to `ownerApproved`, including the approval date,
  statement, fixture, and evidence link. This clears the visual gate for this
  exact revision only; approval does not imply native implementation,
  validation, acceptance, or Done. TAP-0006
  supplies the foundation but does not absorb this later vertical slice.
- Done When: Product Contract §2.4–2.5, the exact approved first-launch/update
  prototype, SwiftUI implementation, and focused tests use the same two-group
  readiness invariant; no prohibited work blocks the gate; no timeout/Retry/Failed/skip/
  degraded UI or early camera transition exists; developer diagnostics can
  attribute abnormal noncompletion to the last incomplete readiness checkpoint;
  marker-absent, update-mismatch, schema-mismatch, successful atomic write,
  interruption, and current-marker repeated-launch bypass semantics are
  deterministic; the marker carries no Share/prewarm meaning; later permission
  changes never reopen onboarding; and the fixed build is ready for TAP-0041
  attended acceptance.
- Related: `TAP-0006`, `TAP-0041`, `TAP-0047`, `TAP-0083`
- Created: `2026-08-12`
- Updated: `2026-08-13`
- Revision History:
  - `2026-08-12` Owner clarified that session configuration alone is not ready.
  - `2026-08-12` Repository audit confirmed the current readiness state does
    not yet consume a preview-layer first-frame signal; this remains required
    implementation scope rather than an acceptance-only gap.
  - `2026-08-13` Owner approved extending the post-Continue wait before the
    first interactive camera to cover existing camera readiness plus the first
    usable TAP Library catalog metadata snapshot. Reused TAP-0009 because this
    is the same first-entry freeze-prevention state machine; it is not TAP-0081
    Share scope and no duplicate Task was allocated. Recorded strict non-blocking
    exclusions for iCloud originals, all thumbnails, proof/hash/ZIP work,
    system-activity prewarm, App Attest/network, and queue batches. Because this
    is a visible state-machine change not yet present in Product Contract §2.4,
    TAP-0009 remains Todo behind contract reconciliation, an exact first-install
    Web prototype revision, owner-approved timeout/Retry/degraded behavior, and
    normal implementation/validation gates. No Done or Doing transition was
    inferred.
  - `2026-08-13` Owner corrected the recovery model before implementation. The
    camera-plus-first-usable-Library-snapshot gate is a required invariant, not
    a bounded best-effort operation. The current product state remains Resource
    Initialization until both groups succeed, then enters the interactive
    camera; Retry, Failed, timeout, skip, and degraded-continuation UI are not
    product states. Abnormal noncompletion is a malignant bug attributable only
    through bounded developer diagnostics. This supersedes the immediately
    preceding timeout/Retry/degraded candidate without erasing its history.
    TAP-0009 remains Todo until Product Contract synchronization, exact Web
    prototype approval, implementation, validation, and TAP-0041 evidence.
  - `2026-08-13` Owner clarified the trigger and persistence boundary. Resource
    Initialization appears on the first launch after fresh install, reinstall,
    and every app update so cold setup cannot leak into later interactive
    elements. It owns a separate current-update/initialization-generation
    completion marker, written only after both invariant groups succeed; an
    interrupted run remains pending, while ordinary repeated launches with the
    current marker bypass the state. The marker does not represent permissions,
    Share readiness, signature/verification, or package cache state, and the
    gate must not prewarm Share, hash/ZIP/`.tapnap`, or system activity UI.
    TAP-0009 remains Todo behind Product Contract synchronization and explicit
    owner approval of the exact install/update/repeated-launch Web fixtures.
  - `2026-08-13` Owner explicitly approved exact current Web revision
    `TAP-0009-r1-candidate` with “原型我检查了 没有问题”. Recorded
    `Prototype/index.html`, its first-install resource-initialization fixture,
    manifest, and design QA as the approved visual authority for the invariant,
    versioned trigger/bypass fixtures, both readiness completion orders, and
    successful camera handoff with no public failure branch. The prototype gate
    is cleared for this revision; commit `70e8b60` now carries synchronized
    `ownerApproved` manifest/QA metadata. Native SwiftUI work has not started, so TAP-0009
    remains Todo and no implementation, evidence, or Done transition is
    inferred. TAP-0081 and TAP-0082 remain Doing for their independent Share
    regression and fresh-install device acceptance.
  - `2026-08-13` Prototype source commit
    `70e8b60d4e20486a6d4847d726b393a50e22c7ba` formally synchronized
    `Prototype/manifest.json` and `Prototype/design-qa.md` to `ownerApproved`
    for exact `TAP-0009-r1-candidate`, including the approval date, owner
    statement, fixture, and QA evidence. This closes the previously recorded
    metadata-sync remainder without changing scope or implementation status.
    TAP-0009 remains Todo pending native implementation and TAP-0041 evidence.

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

### TAP-0081 — Unify TAP Share selection and preparation into an anchored handoff

- Status: `Doing`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Share / Viewer`
- Labels: `share`, `tapnap`, `popover`, `progress`, `anti-flash`, `system-activity`,
  `photo`, `live-photo`, `video`, `icloud`, `local-integrity`,
  `prototype-first`, `icon-parity`, `optical-centering`, `cold-start`,
  `first-share`, `activity-lifecycle`, `launch-services`, `file-url-handoff`,
  `system-consumer-lifetime`
- Contract: `ProductContract §5.3`; `§6`; `§9`; `UIPrototypeContract §2–5`;
  `TAPVideoFormatContract §7`
- Match Keys: `custom share page, app-owned share panel, system share, share
  twice, single share page, AirDrop, other apps, TAPNAP progress, 50 ms, 400 ms,
  flicker, flash, anchored menu, iCloud original, local content binding,
  pending record missing, Needs Retry, 分享两次, 系统分享, 防闪烁,
  等待进度, 本地完整性, toolbar icon, circular background, concentric,
  compact mode capsule, 42pt control, 20pt vector, 图标背景, 同心,
  紧凑模式胶囊, cold install, first Share hang, no loading surface,
  activity sheet onDismiss, stale attachment lease, LaunchServices -10814,
  system-native file URL, ordinary image share, premature source cleanup`
- Assignee: `/root`
- Dev Session: `/root`
- Branch/Worktree: `codex/tap-share-system-handoff-recovery; baseline
  main@8aefd8d`
- Scope: Replace the separate app-owned modal format sheet with one stable,
  lightweight app-owned presentation anchored to the Viewer's bottom Share
  action. During ordinary browsing, the Viewer may fetch and retain the complete
  original resource set from local Photos or iCloud for viewing and playback;
  this is not Share-package prewarming. Share is unavailable until that set is
  ready: the original still for Photo, original still plus paired MOV for Live
  Photo, and the complete original file for TAP Video. Opening the anchored
  surface then evaluates the actual ready resource with the app's local
  embedded-proof/content-binding byte-integrity gate. It must not call the TAP backend or
  run App Attest assertion/credential Verify. Share-specific copying, TAPNAP
  packaging, or other payload generation still begins only after format
  selection, and the system activity controller appears only after the selected
  payload is ready. Photo, Live Photo, and TAP Video use the same presentation
  and lifecycle while retaining their existing capability matrix. Synchronize
  the Viewer toolbar with the refined approved prototype treatment: Share and
  Delete use the prototype's custom vector glyphs in 20pt boxes, optically
  centered in 42pt circular backgrounds matching the top-left Back button.
  The middle `RAW / 2D / 3D` mode capsule remains compact and centered at its
  intrinsic approved width; it must not flex-fill the remaining toolbar space.
  The Share preparation ring must use the same 42pt control center without
  moving or resizing the 20pt vector when progress appears.
- States: Resource readiness precedes credential presentation. While an
  original resource is absent or downloading from iCloud, the Viewer owns the
  loading state and keeps Share disabled; this is not a fourth credential
  state. Once ready, the anchored surface may use a text-free resolving
  skeleton and then exposes only `verified / retry pending / failed`.
  `verified` means the actual resource passed the local embedded-proof and
  content-binding byte comparison. `retry pending` (product copy: Needs Retry) may
  come only from an unsigned app-private Pending Capture Queue item in
  `pending / signing / waiting network / retryable failure`; it must not be
  inferred for a Photos/iCloud asset. `failed` covers local proof/binding or
  resource-set mismatch and terminal queue failure. A missing Pending Capture
  Queue record for a Photos/iCloud asset is not itself failure evidence; the
  ready media determines the result. Idle format selection, the hidden
  fast-preparation grace period, visible preparing progress, completed handoff,
  cancellation, and recoverable preparation failure remain part of the same
  state machine. Work completed within 50 ms never inserts progress UI. Work
  still running after 50 ms reveals progress, and once revealed it remains
  visible for at least 400 ms. Progress is monotonic; early completion shows
  100% until the minimum duration elapses, then hands directly to the system
  controller without an intermediate blank frame, Viewer rebuild, or
  full-screen flash. Destination selection, transfer progress, completion, and
  dismissal remain system-owned once the activity controller is presented;
  TAPCam does not install a destination-completion callback to proactively
  close that controller.
- Failure / Recovery: Cancel stops the active preparation and removes its
  per-attempt temporary directory when no system handoff owns that source. A
  public-safe preparation failure remains in the anchored surface and offers
  Retry for the same option. Dismissing the app-owned surface cleans an
  unhanded attempt. Once a source has been handed to the system activity
  controller, user/system dismissal, representable dismantle, or the bounded
  never-appeared recovery ends coordinator/presentation state but is not an
  independent signal that a destination has finished reading the URL and must
  not delete the source. The activity
  controller strongly owns the artifact; controller deinitialization performs
  explicit, attempt-scoped, idempotent cleanup after that final owner releases
  it, while artifact-lease deinitialization remains an abnormal-path fallback.
  Credential refresh may invalidate an option but must not delete an attachment
  still owned by a system consumer. Local integrity failure disables the TAPNAP
  package option but preserves the applicable ordinary image/video share option
  with an explicit warning that verifiability is not guaranteed. iCloud
  unavailability or resource eviction remains resource-unavailable state and
  must not be rewritten as a credential failure.
- Out of Scope: Changing the TAPNAP package format or trust claim; contacting
  the TAP verification backend; re-running App Attest assertion/credential
  Verify; treating the approved local content-binding gate as a new backend
  verdict; pre-generating, background-prewarming, or persistently caching share
  artifacts; customizing or imitating the system activity controller; adding
  TAP Video `.tapnap`, Sticker, Link, upload, membership, billing, external
  Verify, or TAPCamVerifier behavior.
- Pre-Implementation Baseline: Before this Task, `DepthAnalysisShareSheet`
  presented a separate `NavigationStack` modal and then nested
  `VerificationExportActivityView` as the system sheet. Its progress policy was
  50 ms reveal plus 200 ms minimum visibility, with progress in a sheet footer
  rather than the approved Share-anchored state. This remains historical
  comparison evidence, not a description of the current implementation.
- Current Implementation Evidence: The native Share implementation is split
  across `DepthAnalysisShareCoordinator`, `DepthAnalysisSharePopover`, and the
  stable `DepthViewerShareControl` leaf shared by Photo, Live Photo, and TAP
  Video. The control anchors one app-owned popover to the Viewer Share action;
  coordinator-owned selection/preparation/failure state stays outside the
  Viewer, pager, and playback session; the later system activity controller is
  a sibling presentation rather than a nested app-owned modal flow. The active
  policy is 50 ms delayed reveal plus 400 ms minimum visibility with monotonic
  visible progress. `SharePopoverDismissalObserver` provides an explicit UIKit
  `viewDidDisappear` completion signal so interactive popover dismissal runs
  coordinator-state cleanup instead of relying only on a SwiftUI binding write.
  `TAPNAPShareArtifact` carries a shared, reference-counted temporary-directory
  lease. The current recovery makes `TAPObservedActivityViewController` the
  strong final owner of a handed-off artifact: user/system dismissal,
  representable dismantle, and never-appeared recovery only release app-owned
  state, while
  controller deinitialization explicitly performs idempotent cleanup and the
  artifact lease supplies an abnormal-path fallback. The previous
  `DepthAnalysisShareSheet.swift` implementation has been removed. Photo and
  Live Photo now publish a complete original-photo lease, including the paired
  MOV required by Live Photo, before depth analysis finishes; TAP Video owns an
  equivalent complete-original lease independent of player/first-frame
  readiness. Share remains unavailable until the media-kind-specific owner has
  that complete set. Opening Share freezes the exact lease, validates its
  capture/asset/media-kind identity, and passes the same lease to later
  on-demand copying or packaging. Local mismatch disables TAPNAP but retains
  the applicable direct image/video action with the required warning. Exact
  pending-capture notifications are deduplicated and cannot promote unrelated,
  stale, or already-frozen resources.
- Superseded Historical Cold-Path Regression / Remediation Evidence: After the
  earlier
  device run, the owner reported that the first Share attempt after install
  could leave the Viewer apparently frozen before the anchored selector became
  visible, and that a later `.tapnap` handoff could wait for the system activity
  controller without any visible loading state. Re-entering the app was fast,
  so the warm run does not close the regression. Supplied logs also contain
  LaunchServices/FileProvider failures for the custom `.tapnap` URL, including
  `NSOSStatusErrorDomain -10814`. This behavior violates the existing stable,
  no-blank handoff and cleanup conditions and therefore remained TAP-0081 scope,
  not a duplicate Task. The historical `bf20b52` remediation required:
  1. publish the existing app-owned selector/progress acknowledgment before any
     scalable local-integrity or payload work can starve the main run loop;
  2. export `.tapnap` as its declared custom type with explicit public data,
     content, and ZIP conformances and hand the activity controller a provider
     carrying that type instead of relying on a bare URL inference;
  3. keep the existing Share progress center visibly stable through activity-
     controller construction/presentation, with no bare-Viewer gap; and
  4. close completion, cancellation, binding dismissal, UIKit dismissal,
     presenter disappearance, initialization failure, and stale-callback paths
     with attempt-scoped, idempotent temporary-artifact cleanup. In particular,
     SwiftUI sheet `onDismiss` and the activity completion callback must be
     safe in either order and must not release a newer attempt.
  Commit `bf20b52452512aefe745624bd9f80c09355abae5` implements this
  non-visual runtime/lifecycle repair using the already approved
  selector and progress states; it does not authorize package prewarming,
  persistent Share caches, private LaunchServices entitlements, document-import
  registration, or a new system-activity imitation. Cross-cutting Library,
  thumbnail, geometry, and TAP Video progress backpressure work is tracked by
  `TAP-0083` rather than silently widening this Share Task. The fixed build was
  installed and launched on the recorded iPhone 15 Pro, and the owner accepted
  TAP-0081/TAP-0082 for closure on `2026-08-13`. This entire provider/no-bare-
  URL direction is superseded history after the later cross-format device
  failure; it has no continuing implementation or acceptance authority.
- Closed Native Visual Parity Gap: Before the final toolbar revision, the owner
  reported that the native glyphs were not visually concentric with their
  circular backgrounds. The revised implementation was delivered in the fixed
  build and the owner accepted the post-change result when directing TAP-0081
  and TAP-0082 to be closed.
  The refined prototype treatment is now the approved bounded direction.
  `/root` must use the custom prototype Share/Delete vectors in 20pt boxes,
  optically center them in 42pt circular controls equal to the Back button,
  keep the center mode capsule compact instead of flex-fill, and retain that
  exact center for the Share progress ring. The interim 54px outer-control,
  25px bottom, 18px gap, and flexible-center geometry is superseded and must not
  be propagated. At the owner's direction, final post-change inspection is on
  the connected physical device rather than Simulator; one attended comparison
  across Photo, Live Photo, and TAP Video was included in that final owner
  acceptance; this gap is closed.
- TAP Video Pending-Queue Atomicity / Tradeoff: Signing now freezes the durable
  unsigned TAP Video into an on-demand, independent-inode working generation;
  proof filling and local validation occur only on that generation. After it is
  complete, a same-directory `RENAME_SWAP` exchanges it with the durable media
  while retaining the complete prior inode for rollback. The signed record is
  encoded, file-protected, validated, synchronized, and fault-injected at a
  private sibling path before one final replacing rename; if record preparation
  fails, the media swap is reversed, while a successful record rename is the
  last throwable commit point. This prevents Viewer/Share from observing a
  partially rewritten proof slot and is not Share prewarming or a persistent
  cache. It does, however, require transient space for another complete video
  generation and additional clone/copy, synchronization, and rename I/O. The
  owner must explicitly accept that implementation tradeoff during the TAP-0081
  audit.
- Security / Claim Boundary: The local gate recomputes the digest and signing
  binding embedded beside the App Attest assertion and compares them with the
  exact frozen bytes. It does not cryptographically verify the assertion object
  with the registered App Attest public key and does not independently prove
  assertion authenticity or establish a new backend credential verdict. The
  public `Verified` label in this owned-capture Share flow therefore records
  local byte/content-binding integrity within Product Contract §6, not a new
  backend/App Attest Verify result.
- Closed Scope-Revision Gap: The `2026-08-13` post-revision inspection recorded
  a historical gap: certification was queue-record-only, an absent exported
  record mapped to `failed`, and Viewer Share readiness did not own the complete
  original resource. The current shared-tree patch closes that implementation
  gap with Photo/Live Photo/TAP Video complete-original owners and leases,
  exact-identity local validators, queue-only Needs Retry, exported-record
  absence tolerance, and mismatch degradation. Focused tests cover the revised
  state/identity/notification/resource boundaries. This closes the source gap;
  it did not itself satisfy prototype approval or any frozen-build, Simulator,
  owner-audit, or physical-device evidence gate at that time. The owner has
  since approved the final updated r2 prototype and accepted frozen build
  `bf20b52`; those native/evidence gates are now closed.
- Implementation Handoff State: `Accepted and closed by the product owner on
  2026-08-13 for frozen commit bf20b52452512aefe745624bd9f80c09355abae5.`
  The revised native implementation and its module/contract synchronization
  were handed off and accepted.
  One unified run of nine focused XCTest groups passed for the Share
  state/identity/notification matrix, complete Photo/Live resource ownership,
  TAPNAP and TAP Video artifact builders, streaming/cancellation, playback
  policy, presentation, localization, and video signed-original notification
  claim; the xcresult reports 268 tests and a succeeded Test action. The stale
  source-shape assertion was corrected before that final run. A generic iOS
  Simulator Release build also succeeded. The focused Simulator UI test
  `TAPVideoPlaybackFixtureUITests.testShareOpensAnchoredSelectorBeforePlayerReadinessAndKeepsChromeStable`
  passed with one test and zero failures: after the complete video original was
  ready but before player readiness, Share became actionable, presented the
  native anchored popover, and kept all six Viewer-control frames plus RAW
  selection stable. No frozen commit or completed full Web/SwiftUI Simulator
  parity matrix was supplied for the earlier revision. For the final toolbar
  revision, the owner explicitly directed physical-device delivery and skipped
  Simulator, so no post-change Simulator evidence is claimed or awaited.
  The final updated `TAP-0081-r2-candidate` is owner-approved. The final
  post-change Simulator run was intentionally skipped at
  the owner's direction in favor of delivery to the connected physical device.
  The app built, installed, and launched there successfully. A narrow navigation/
  safe-area regression found after that delivery has since been fixed with the
  owner-approved interpretation and redelivered to the same device. The later
  cold-path remediation is frozen in `bf20b52`; when directing TAP-0081 and
  TAP-0082 closure, the owner explicitly accepted the implementation/process
  handoff and the documented TAP Video transient disk/I/O tradeoff.
- Build / Commit: `Frozen commit bf20b52452512aefe745624bd9f80c09355abae5
  (bf20b52, Fix cold share handoff and media loading). Nine-group focused test
  action TEST SUCCEEDED at
  /tmp/TAPCamDemo-TAP0081-final-tests/Logs/Test/Test-TAPCamDemo-2026.08.13_03-08-56-+0800.xcresult
  (268 tests). Generic iOS Simulator Release BUILD SUCCEEDED with DerivedData at
  /private/tmp/TAPCamDemo-TAP0081-final-release. Focused Simulator UI test TEST
  EXECUTE SUCCEEDED (1 test, 0 failures) at
  /tmp/TAPCamDemo-TAP0081-final-tests/Logs/Test/Test-TAPCamDemo-2026.08.13_03-12-48-+0800.xcresult.
  After the final approved toolbar revision, an iphoneos Debug build succeeded
  with Automatic Development signing using Apple Development: Jinbo Li, team
  UD3269PSCB. Device artifact:
  /private/tmp/TAPCamDemo-TAP0081-device/Build/Products/Debug-iphoneos/TAPCamDemo.app.
  That app installed and launched successfully as TAP-NAP.TAPCamDemo on the
  connected iPhone 15 Pro (iPhone16,1), iOS 26.6, CoreDevice
  8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7. The post-change Simulator run was
  intentionally skipped per owner instruction; the earlier Simulator evidence
  above predates the final toolbar revision. Human post-change visual/flow
  verdict Pending. After the narrow navigation/safe-area regression fix, `git
  diff --check` and `node Prototype/prototype.test.mjs` passed; the Debug device
  build, install, and launch then succeeded again on the same identified iPhone
  15 Pro / iOS 26.6. Simulator remained intentionally skipped per owner
  instruction. Commit bf20b52 was subsequently built for iphoneos, installed,
  and launched on the same recorded iPhone 15 Pro / iOS 26.6. The product owner
  explicitly accepted the fixed result and directed TAP-0081/TAP-0082 closure.`
- Prototype Path/Revision/Approval: `Prototype/index.html`; approved geometry
  and anchored-handoff base `TAP-0081-r1`; current incremental visual revision
  `TAP-0081-r2-candidate`; manifest `Prototype/manifest.json`; QA
  `Prototype/design-qa.md`. The owner approved exact base revision
  `TAP-0081-r1` on `2026-08-12` and approved the incremental local-integrity
  behavior on `2026-08-13`. After the final 42pt/20pt/compact toolbar update,
  the owner explicitly approved the exact current candidate with “已确认没有问题
  请继续实施 Swift UI”; its Board approval state is now `ownerApproved`.
  Prototype source commit `70e8b60d4e20486a6d4847d726b393a50e22c7ba`
  synchronizes `Prototype/manifest.json` and `Prototype/design-qa.md` to that
  exact `TAP-0081-r2-candidate` approval. The
  owner selected the anchored format reference
  `exec-23c261dc-836c-4ffb-8bb0-492a01ab9816.png`, approved the preparation
  reference `exec-5f02b050-0547-4bd2-aed2-7243a9da1c5e.png`, and explicitly
  approved the 50 ms reveal / 400 ms minimum-visible policy in the development
  conversation. Those generated images are review evidence, not the canonical
  prototype. The repository-owned final updated r2 revision—not the generated
  images—is the approved authority. Its refined toolbar uses custom Share/Delete
  vectors in 20pt boxes, 42pt circular backgrounds matching Back, optically
  concentric vector/background/progress-ring centers, and a compact
  intrinsic-width center mode capsule. `/root` is authorized to implement the
  full approved revision in SwiftUI.
- Prototype Evidence: `node Prototype/prototype.test.mjs` passes; browser review
  exercised selection, slow/threshold preparation, Cancel, Failure, Retry,
  system-dismissal return, media variants, and credential variants. The 120 ms
  threshold fixture observed reveal at 51 ms and system-boundary handoff at
  452 ms. Review captures are
  `Prototype/evidence/TAP-0081-r1-selection-full.png` and
  `Prototype/evidence/TAP-0081-r1-preparing-full.png`. The r2 candidate adds
  repository captures for resource loading, text-free local-integrity resolving,
  and failed-integrity degradation, together with combined comparison images
  listed in `Prototype/manifest.json`. These establish Web visual/state QA only,
  while the owner's explicit statement establishes exact visual approval. They
  do not establish native timing, cryptographic assertion authenticity, or
  physical-device acceptance.
- Prototype Impact: Approved `TAP-0081-r1` remains the anchored
  selection/preparation authority except for the toolbar geometry explicitly
  superseded by the owner's refined 42pt/20pt/compact-capsule decision.
  `TAP-0081-r2-candidate` now covers the
  previously missing Share-disabled original loading/unavailability states,
  text-free local-integrity resolution, queue-only Needs Retry, and Failed
  package-disabled/warned-direct-media degradation for Photo, Live Photo, and
  TAP Video. Exact r2 visual approval and the owner's native result acceptance
  are complete. The approved
  current revision requires 42pt Back-matched outer circles, custom vectors in
  concentric 20pt boxes, a shared Share progress-ring center, and a compact
  non-flex-fill mode capsule. SwiftUI and the prototype manifest/QA carry this
  authority. The interim 54/25/18/flexible geometry has no continuing authority.
- Implementation Gate: `TAP-0006` supplies the repository-owned prototype
  foundation. Exact Share revision `TAP-0081-r1` received owner approval on
  `2026-08-12`; the prototype gate is satisfied and SwiftUI implementation is
  authorized. The owner subsequently approved the local-integrity behavior and
  directed implementation to continue. Native implementation and focused-test
  handoff plus a generic-Simulator Release build are recorded above. The owner
  has now approved the exact final updated r2 prototype and explicitly directed
  `/root` to continue SwiftUI implementation. The resulting
  native build was delivered to the connected physical device at the owner's
  direction; post-change Simulator comparison was intentionally skipped. The
  owner-approved narrow regression fix removed `CameraView`'s forced outer
  navigation-bar visibility, gates `DepthAlbumPickerView` navigation-bar
  visibility with `isViewerPresented`, and changes fallback bottom padding from
  20 to the prototype-matched 25. Diff check, prototype static tests, and the
  repeated Debug device build/install/launch passed. Commit `bf20b52` freezes
  the final cold-share remediation; its device delivery and owner verdict are
  recorded under TAP-0082. Handoff review is accepted and this Task is Done.
- Documentation Impact: `Docs/ProductContract.md §5.3/§6`,
  `TAPCamDemo/DepthAnalysis/README.md`,
  `TAPCamDemo/DepthAnalysis/Playback/PLAYBACK.md`, the r2 candidate Web
  prototype/manifest/QA, and
  `Docs/Acceptance/TAP-0048-web-swiftui-parity.md` are synchronized with the
  revised implementation boundary. `Docs/UIPrototypeContract.md` needs no
  behavior-specific change because the prototype-first authority model is
  unchanged. `Docs/TAPVideoFormatContract.md §7` is synchronized with the
  independent-inode working generation, atomic media/record commit, rollback,
  and transient-resource boundary; the TAPNAP transport format did not change.
  The owner chose the detailed TAP-0082 Board record as the final acceptance
  record for `bf20b52`; no separate
  `Docs/Acceptance/TAP-0082-share-handoff.md` artifact was supplied. Frozen
  commit, device/iOS identity, install/launch, and explicit human acceptance are
  reconciled below. Root `AGENTS.md` and
  `Docs/ColdPathResponsiveness.md` now own the later repository-wide cold-path
  workflow introduced through TAP-0083.
  Obsolete native source removed:
  `TAPCamDemo/DepthAnalysis/DepthAnalysisShareSheet.swift`.
- Current Cold-Path Governance Impact: The earlier `AGENTS.md` N/A statement is
  preserved as history for that handoff. The owner's later requirement for a
  durable cold-path implementation standard is new cross-cutting scope owned by
  `TAP-0083`; TAP-0081 consumes that standard for its first-visible-response,
  progress-backpressure, observability, and presentation-lifecycle gates.
- Done When: A repository-owned prototype and manifest cover Photo, Live Photo,
  and TAP Video fixtures plus resource-not-ready Share disabling, local
  integrity resolving/result states, the failed-integrity ordinary-media
  warning/package-disabled degradation, credential selection, hidden-fast,
  visible progress, 100%-handoff, Cancel, failure, and Retry states; the owner
  approves that revision; SwiftUI matches it without the separate app-owned
  modal format sheet; complete original readiness gates Share for every media
  kind; Photos/iCloud certification comes from local validation of the actual
  ready resource rather than Pending Capture Queue record presence; Needs Retry
  remains queue-only; no Share path calls backend/App Attest Verify; and the
  exact locally validated resource stays bound to the later payload attempt.
  The resource/status matrix, local pass/mismatch, missing exported record,
  iCloud loading/unavailability, package-disable/media-warning behavior, 50/400
  timing policy, monotonic progress, cancellation, cleanup, stale-callback, and
  ready-only system-presentation boundaries have focused tests. The custom UTI
  declares public data/content/ZIP conformances; the system handoff carries its
  explicit type; activity completion and sheet/UIKit dismissal are tested in
  either order with stale-attempt protection and idempotent cleanup; and a cold
  first Share publishes an app-owned visible response before scalable work,
  with structured milestones through system-controller appearance/dismissal.
  An attended
  post-change device inspection confirms the custom Share/Delete vectors remain optically centered
  in their 20pt boxes and 42pt Back-matched circular controls, the Share
  progress ring uses the same center, and the compact intrinsic-width mode
  capsule does not flex-fill or move the stable toolbar across Photo, Live
  Photo, and TAP Video;
  interaction and a Release build pass; Product Contract, module README,
  prototype manifest, and acceptance impact are synchronized; and the owner
  completes the requested implementation/process audit, explicitly accepts the
  transient TAP Video disk/I/O tradeoff, and accepts the development handoff.
  Physical-device system-share/iCloud evidence may remain open under `TAP-0082`
  and does not silently become Simulator evidence.
- Completion Audit: `Satisfied and owner-accepted for bf20b52 on 2026-08-13.`
  Approved Web states, native implementation, focused tests, Release build,
  custom UTI/provider lifecycle, cold-share remediation, module/contract sync,
  fixed device delivery, transient TAP Video tradeoff, implementation/process
  audit, and development handoff are reconciled. TAP-0082 records the attended
  verdict. The newly observed Library-grid-to-Viewer navigation motion belongs
  to TAP-0084 and does not reopen Share or Viewer paging. This completion audit
  is retained as historical evidence for `bf20b52`; the 2026-08-14 transport
  regression below invalidates it as proof of the current typed handoff.
- Reopened Transport Regression: The owner deliberately reopened TAP-0081 after
  a current real-device run on `main@fe0d308`: choosing Save to Files caused the
  system file selector to crash, AirDrop remained waiting without a received
  artifact, and the supplied attachment repeatedly reports `Could not load
  representation public.zip-archive from the item provider for opening in
  place`. The current typed item-provider path therefore does not satisfy the
  original handoff Done evidence. The historical Done transition and attended
  `bf20b52` verdict remain recorded, but they cannot close this regression.
- Failed Copy-Backed Candidate Evidence: Candidate `35745be` changed the
  provider to copy-backed delivery and passed its compile/provider-load checks,
  but the owner's physical-device run did not succeed. AirDrop still remained
  at “未找到用户” without a received artifact, and the same system-share failure
  plus repeated LaunchServices `NSOSStatusErrorDomain Code=-54` diagnostics
  occurred when sharing an ordinary image directly. Because ordinary media and
  `.tapnap` fail at the same boundary, the current evidence rejects the earlier
  package/custom-UTI-specific explanation and points to their shared manual
  `UIActivityItemsConfiguration` / `NSItemProvider` handoff or source lifetime.
  The logs do not authorize a private LaunchServices entitlement.
- Reopened Approved Scope: Do not create a rollback commit for the already
  pushed candidate. On `codex/tap-share-system-handoff-recovery`, restore the
  pre-`bf20b52` system-native file-URL activity-item handoff for every current
  Share artifact kind, including ordinary media and `.tapnap`, while preserving
  the anchored app-owned selector, 50/400 progress policy, one system activity
  controller, exact-attempt coordinator, and artifact lease. Keep the TAPNAP
  package format and declared UTI unchanged; the former reopened requirement
  that prohibited a bare file-URL handoff is superseded by this owner-approved
  recovery and has no continuing acceptance authority. A handed-off source must
  remain readable for the activity controller's lifetime. The controller
  strongly retains the artifact and explicitly performs attempt-scoped,
  idempotent cleanup on deinitialization; user/system dismissal,
  representable dismantle, or bounded never-appeared recovery only release
  coordinator/presentation state and are not deletion signals. Artifact-lease
  deinitialization is an abnormal-path fallback. Explicit immediate cleanup
  remains valid only for an artifact never handed to the system, such as
  cancelled/stale preparation or a discarded pending handoff. TAPCam must not
  install or depend on `completionWithItemsHandler` to proactively close the
  system controller. Add focused coverage for activity items,
  ordinary-media/`.tapnap` parity, exact-attempt release ordering, and premature
  dismissal/dismantle. Bind every system sheet to one immutable presentation
  UUID. Binding, user/system dismissal, appearance, dismantle, and
  never-appeared recovery callbacks must carry that expected artifact ID so a
  delayed callback from attempt A cannot release attempt B. Every
  `TAPShareActivityPresentation` initializer transfers artifact ownership to
  its controller. Do not add private LaunchServices
  entitlements, document-import registration, package prewarming, or a
  persistent Share cache. This is
  a non-visual transport/lifetime repair: app-owned Share states, UI copy/text,
  geometry, icons, interaction, and the approved Web prototype do not change.
- Failed Candidate Implementation Handoff: Candidate `35745be`
  registers each app-private per-attempt temporary file with default copy-backed
  `fileOptions: []` instead of `[.openInPlace]`. It remains one typed provider
  with the custom TAPNAP UTI first and `public.zip-archive` as its fallback; no
  bare URL is added. Focused tests now call both `loadFileRepresentation` and
  `loadInPlaceFileRepresentation`, compare the consumer-visible bytes, require
  `isInPlace == false`, verify `suggestedName`, and prove the captured artifact
  lease keeps the source directory alive through provider loading. Cleanup now
  publishes the low-cardinality success milestone
  `tap_share_temp_cleanup_finished` without media paths or identifiers.
  `TAPCamDemo/DepthAnalysis/README.md` and
  `Docs/Acceptance/TAP-0082-share-handoff.md` are synchronized to the same
  copy-backed provider, lease, cleanup, and device-retest contract. This is now
  failed-candidate history rather than current implementation authority.
- Failed Candidate Validation: `git diff --check` passed. Generic iOS Simulator
  `build-for-testing` compiled successfully without launching Simulator, and
  generic iphoneos `build-for-testing` completed with exit code 0. An audit run
  exercised the new provider tests twice and those provider tests passed both
  times. The containing suite nevertheless failed in those runs only because a
  source-shape assertion still expected the README's old wording; the README
  assertion source is now repaired, but that entire suite has not been rerun,
  so no current full-suite pass is claimed. That implementation is frozen as
  candidate commit `35745be` (`Fix TAPNAP system share transport`), and its
  signed iPhone build succeeded, but its subsequent physical-device transport
  result failed and therefore those automated checks do not satisfy TAP-0081.
- Current Recovery Implementation State: The recovery represented by this Board
  revision is being frozen on `codex/tap-share-system-handoff-recovery` by the
  self-referential checkpoint commit titled
  `Checkpoint working Share transport before lifecycle repair`. The commit
  containing this record supplies its own Git identity; this record does not
  predeclare a hash. The checkpoint passes
  `[artifact.fileURL]` directly to `UIActivityViewController` for package,
  image, and video artifacts and removes the shared manual
  `UIActivityItemsConfiguration` / `NSItemProvider` path. The observed activity
  controller strongly retains the artifact; its deinitialization explicitly
  performs idempotent directory cleanup, while user/system dismissal,
  representable dismantle, and never-appeared recovery release only app state.
  The system sheet remains item-scoped by presentation UUID, and applicable
  lifecycle callbacks carry `expectedArtifactID` so a stale callback from
  attempt A cannot release attempt B. The unused proactive-completion path has
  been removed: production no longer installs `completionWithItemsHandler` and
  no longer carries `onFinished`, `activityFinishTask`,
  `activitySheetHasDismissed`, `finishActivityPresentation`, or post-handoff
  minimum-visibility machinery. `TAPShareActivityPresentation` initialization
  still transfers artifact ownership to the controller. There is no persistent
  Share payload cache or prewarm: each artifact exists only in one per-attempt
  OS temporary directory. Controller release is the intended normal cleanup
  boundary and the shared lease is an abnormal-path fallback; a process
  `SIGKILL` or exhausted removal retries may leave OS-temporary residue, which
  is a cleanup risk rather
  than an app cache. Product Contract §5.3, the DepthAnalysis README, and the
  TAP-0082 acceptance record are synchronized to this ownership contract.
  Generic iphoneos `build-for-testing` passed after the dead-code cleanup. The
  revised tests compiled as part of that build but were not executed, so no test
  pass is claimed. The owner then replied “验收通过” to the immediately
  preceding four-path matrix, explicitly accepting ordinary image and `.tapnap`
  through both Save to Files and AirDrop with every saved/received artifact
  openable. No filename, hash, receiving-device identity, or final lifecycle-
  fixed build identity is inferred from that verdict. `/root` performed no
  device operation. This checkpoint freezes the successful direct-file-URL
  transport path only; TAP-0081 remains Doing until its focused tests execute
  successfully and the open teardown/progress lifecycle defects are repaired
  and evidenced.
- Current Console-Warning And Lifecycle Audit: After the successful four-path
  device verdict, the owner supplied Share console samples containing
  `NSOSStatusErrorDomain -10814`, CKShare/SWY option-loading, FileProvider,
  LaunchServices `Code=-54`, persona-service, and `System gesture gate timed
  out` diagnostics. Read-only source inspection confirms that current
  production creates one `UIActivityViewController` with the materialized file
  URL; no shared manual `NSItemProvider` / `UIActivityItemsConfiguration`,
  `[.openInPlace]`, or destination-completion callback remains. `-10814` is
  `kLSApplicationNotFoundErr` from the system's default-handler probe for the
  custom file URL; the CKShare/SWY, FileProvider, `Code=-54`, and persona lines
  are system Share-extension/capability probes, not evidence that TAPCam's
  successful file handoff failed and not authority for a private entitlement or
  document-handler registration. Both `.tapnap` and ordinary-image sequences
  place those URL probes after `tap_share_activity_controller_created` but
  before coordinator `tap_share_activity_handoff_started`. During this interval
  the coordinator still treats the presentation as pending, while
  `discardPendingHandoff()` explicitly deletes the artifact; controller
  construction has therefore started system URL consumption before the current
  source-lifetime state machine declares handoff. This is an open race even
  though both attended transport paths passed. The later detailed sequence also
  establishes an open teardown evidence gap: the `.tapnap` attempt logged
  `tap_share_activity_sheet_dismissed`, and a new image attempt began without an
  intervening `tap_share_activity_controller_dismantled` or terminal
  `tap_share_temp_cleanup_finished scope=artifactLease`. The observed
  `scope=tapnapResources` / `scope=imageResources` milestones cover preparation
  inputs, not the activity artifact's terminal lease. In the same `.tapnap`
  attempt, `tap_share_activity_controller_created` reported `under50ms`, but
  `tap_share_activity_wait_feedback_revealed` then reported `over50ms` with
  `phase=controllerConstruction`; therefore prompt controller release and the
  current progress-phase attribution are not accepted. This does not reopen the
  successful transport verdict, but it keeps lifecycle and progress sequencing
  inside TAP-0081. Mechanical cleanup removed the now-unused
  `UTType.tapnapCapturePackage` helper and repaired the stale
  `activityPresentationBinding` source-shape assertion. Generic iphoneos
  `build-for-testing` completed with exit code 0 after that cleanup; no new
  device or Simulator run is claimed by `/root`.
- Reopened Done When: A fixed build uses the system-native file-URL activity
  handoff for both ordinary media and `.tapnap`; focused tests protect the
  activity-item matrix, exact-attempt ownership, controller-last-owner cleanup,
  stale-A/new-B dismissal/teardown boundary, and the separation between
  coordinator-state termination and source cleanup; once controller
  construction can start system URL probing, pending cancellation/discard
  cannot delete that source; controller-construction feedback uses an accurate
  phase and timing boundary; no proactive destination-
  completion callback, private LaunchServices entitlement, persistent Share
  payload cache, or Share prewarm is introduced; and TAP-0082
  records successful physical-device Save to Files plus AirDrop receipt for the
  representative ordinary-media and `.tapnap` paths.
  The current evidence record is
  [TAP-0082 Share handoff](Acceptance/TAP-0082-share-handoff.md).
- Related: Follow-up to `TAP-0061`; contrasts with deprecated `TAP-0068`;
  prototype dependency `TAP-0006`; parity evidence `TAP-0048`; attended evidence
  `TAP-0082` and its current
  [acceptance record](Acceptance/TAP-0082-share-handoff.md); cold-path
  implementation standard `TAP-0083`; credential wording
  boundary `TAP-0014`; independent Library-to-Viewer visual follow-up
  `TAP-0084`; future capabilities
  `TAP-0023`, `TAP-0024`, `TAP-0025`
- Created: `2026-08-12`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-12` Created in Inbox after a full Inbox/Todo/Doing/Done/Deprecated
    search. `TAP-0061` remains correctly Done because its original app-owned,
    on-demand selection and temporary-payload condition still holds; this
    request changes its presentation and handoff details, so it is a scoped
    follow-up rather than a reopen. Deprecated `TAP-0068` was not revived
    because the new flow still waits for explicit format selection before
    preparing a payload.
  - `2026-08-12` Scope approved by the owner and moved Inbox -> Todo. Approval
    fixed the anchored selection/preparation direction, one subsequent
    system-owned activity presentation, 50 ms delayed reveal, 400 ms minimum
    visible duration, stable Viewer identity, and explicit non-goals above.
  - `2026-08-12` Assigned to development session `/root` and moved Todo ->
    Doing on baseline `main@a4cf808`. Work starts at the Web-prototype gate;
    native implementation must wait for the recorded prototype approval, and
    this Task must not move to Done before the owner's requested audit.
  - `2026-08-12` Prototype gate synchronized with the owner's clarified
    `TAP-0006` milestone: the required authority is the exact lightweight,
    statically served TAP Share revision and manifest, not a heavyweight mobile
    runtime. Native implementation may begin only after the owner approves that
    exact revision; the owner-audit blocker against Done remains unchanged.
  - `2026-08-12` Exact prototype revision `TAP-0081-r1` handed off for owner
    review at `Prototype/index.html`, with manifest, design QA, passing static
    contract test, exercised browser paths, timing observations, and repository
    captures recorded above. Documentation was synchronized across Product
    Contract §5.3/§9, the incremental-slice UI Prototype Contract, and root/Docs
    prototype discovery. Approval remains `pendingOwnerReview`; no native
    implementation authorization, approval, or Done transition is inferred.
  - `2026-08-12` Owner explicitly approved exact Web revision `TAP-0081-r1`
    (“我觉得 web 模拟流程是合理的 请开始实现”). The prototype gate is now
    satisfied and native implementation is authorized. The Task remains Doing:
    implementation, automated/Simulator validation, documentation-impact
    reconciliation, development handoff, and the owner's requested final audit
    are not yet complete. Manifest approval synchronization remains pending an
    authorized non-Board edit and does not negate the canonical Board decision.
  - `2026-08-12` Native implementation handoff recorded without a Done
    transition. Reclassified the old separate modal and 50/200 footer behavior
    as the pre-implementation baseline, and recorded the current split
    coordinator / anchored popover / stable toolbar control architecture,
    50/400 anti-flash policy, explicit UIKit dismissal observer, sibling system
    activity presentation, and shared reference-counted temporary-artifact
    lease. The implementation is ready for completion review, but owner audit
    and all remaining Done When evidence are still required; Status remains
    Doing.
  - `2026-08-13` Owner-approved scope revision recorded while retaining Doing.
    Normal Viewer browsing may fetch the complete original resource from local
    Photos/iCloud, and Share remains unavailable until that media-kind-specific
    set is ready. Opening the anchored surface then performs only local
    content-binding/signature-integrity checks over the actual resource; it
    never contacts the TAP backend or re-runs App Attest Verify. Needs Retry is
    restricted to the app-private unsigned signing queue, and missing exported
    queue state must not make a Photos/iCloud asset Failed. A local mismatch
    disables TAPNAP but preserves ordinary image/video sharing with an explicit
    unverifiability warning. Package pre-generation, background prewarming, and
    persistent caches remain prohibited. Current source inspection and the
    uncovered prototype states were recorded as open gaps, and the owner then
    directed implementation to continue; no Done or owner-audit acceptance was
    inferred.
  - `2026-08-13` Revised implementation handoff recorded without a Done
    transition. The shared tree now closes the earlier record-only/readiness gap
    with complete-original owners and exact frozen leases for Photo, Live Photo,
    and TAP Video; identity-bound local byte/content-binding validation; missing
    exported-record tolerance; queue-only Needs Retry; mismatch package-disable
    and warned direct-media degradation; precise notification deduplication; and
    the existing 50/400 anchored handoff/cleanup lifecycle. Focused Share,
    Photo/Live resource, TAPNAP/TAP Video artifact, streaming/cancellation,
    playback, presentation, localization, and video notification-claim tests
    passed. The local gate compares current bytes with the embedded digest and
    signing binding but does not cryptographically verify App Attest assertion
    authenticity or produce a new backend verdict. Exact visual revision
    `TAP-0081-r2-candidate` remains `pendingOwnerReview`; the frozen commit,
    final Release build, Simulator interaction/parity record, owner audit, and
    attended `TAP-0082` evidence remain open. Status remains Doing.
  - `2026-08-13` Final automated handoff evidence appended without changing
    status. One unified run of nine focused XCTest groups reports TEST SUCCEEDED
    for 268 tests at
    `/tmp/TAPCamDemo-TAP0081-final-tests/Logs/Test/Test-TAPCamDemo-2026.08.13_03-08-56-+0800.xcresult`,
    and the generic iOS Simulator Release build reports BUILD SUCCEEDED with
    DerivedData at `/private/tmp/TAPCamDemo-TAP0081-final-release`. The handoff
    also records the pending TAP Video signing invariant: an independent-inode
    working generation, same-directory `RENAME_SWAP`, preprotected/synchronized
    temporary record, final atomic replacing rename, and rollback to the prior
    media generation on record-preparation failure. `TAPVideoFormatContract §7`
    is synchronized. This safety boundary adds transient duplicate-video disk
    space and clone/copy/synchronization I/O and therefore remains an explicit
    owner-audit acceptance item. The exact r2 prototype, frozen commit,
    Simulator interaction/parity, owner audit, and TAP-0082 attended evidence
    remain Pending; TAP-0081 remains Doing.
  - `2026-08-13` Appended focused native-interaction evidence without a Done
    transition. Simulator UI test
    `TAPVideoPlaybackFixtureUITests.testShareOpensAnchoredSelectorBeforePlayerReadinessAndKeepsChromeStable`
    reports TEST EXECUTE SUCCEEDED with one test and zero failures at
    `/tmp/TAPCamDemo-TAP0081-final-tests/Logs/Test/Test-TAPCamDemo-2026.08.13_03-12-48-+0800.xcresult`.
    It demonstrates that once the complete TAP Video original is ready, Share
    is actionable before player readiness, presents the native anchored
    popover, and preserves all six Viewer-control frames plus RAW selection.
    This is one focused Simulator path, not the full Web/SwiftUI parity matrix,
    owner audit, or attended device evidence. TAP-0081 remains Doing, the exact
    r2 candidate remains pending owner review, and TAP-0082 remains Todo.
  - `2026-08-13` Owner reported that a physical-device Share run passed and
    requested one final prototype-parity correction: the current native toolbar
    glyphs and circular backgrounds are not visually concentric, while the
    prototype treatment is preferred. This is a bounded revision of the active
    TAP-0081 delivery rather than a new Task. The owner approved the prototype's
    Share/Delete icon identities, circular control geometry, and optical
    concentricity as implementation authority for `/root`, including keeping
    the Share progress ring on the same center. The complete
    `TAP-0081-r2-candidate` remains pending exact review, and the revised native
    result still requires Simulator parity plus owner audit; status remains
    Doing.
  - `2026-08-13` Owner refined the bounded toolbar authority before parity
    implementation completed: Share/Delete now use the prototype's custom
    vectors in 20pt boxes; their circular backgrounds are 42pt to match the
    top-left Back button; vector, circle, and Share progress ring share one
    optical center; and the middle mode capsule remains compact rather than
    flex-filling the toolbar. This supersedes the interim 54px control, 25px
    bottom, 18px gap, and flexible-center geometry without erasing that history.
    TAP-0081 remains Doing pending native implementation, Simulator comparison,
    prototype/manifest synchronization, and owner audit.
  - `2026-08-13` Owner explicitly approved the final updated repository Web
    prototype with “已确认没有问题 请继续实施 Swift UI”. Exact
    `TAP-0081-r2-candidate` approval is therefore complete and `/root` is
    authorized to implement the full current visual revision, including the
    recorded resource/local-integrity states and refined 42pt outer controls,
    20pt custom vectors, shared progress-ring center, and compact mode capsule.
    This supersedes the interim component-only approval boundary without erasing
    its history. Native parity, tests/build, final owner audit, and post-build
    TAP-0082 device inspection remain open; TAP-0081 remains Doing.
  - `2026-08-13` Appended final-revision device delivery evidence without a Done
    transition. The Debug iphoneos build succeeded with Automatic Development
    signing (`Apple Development: Jinbo Li`, team `UD3269PSCB`) and produced
    `/private/tmp/TAPCamDemo-TAP0081-device/Build/Products/Debug-iphoneos/TAPCamDemo.app`.
    It installed and launched successfully as `TAP-NAP.TAPCamDemo` on the
    connected iPhone 15 Pro (`iPhone16,1`), iOS 26.6, CoreDevice
    `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`. Per the owner's instruction, the
    post-change Simulator run was intentionally skipped; prior Simulator
    evidence remains historical evidence for the earlier revision. The human
    post-change visual/flow verdict is Pending, so TAP-0081 remains Doing.
  - `2026-08-13` Appended the owner-approved narrow regression fix and repeat
    device delivery without a Done transition. The production change is three
    lines: remove `CameraView`'s outer forced navigation-bar visibility; gate
    `DepthAlbumPickerView` navigation-bar visibility by `isViewerPresented`;
    and change fallback bottom padding from 20 to the prototype-matched 25.
    `git diff --check` and `node Prototype/prototype.test.mjs` passed. The Debug
    iphoneos build, install, and launch then succeeded again on the same iPhone
    15 Pro (`iPhone16,1`), iOS 26.6. Simulator remained intentionally skipped
    per owner instruction. Human visual/flow verdict remains Pending, so
    TAP-0081 stays Doing.
  - `2026-08-13` Recorded a later cold-first-Share regression and retained
    Doing. After install, the owner's first Share tap could wait before the
    anchored app surface appeared; selecting `.tapnap` could then wait for the
    system activity controller with no visible handoff feedback, while a warm
    re-entry was fast. Supplied logs include custom-type LaunchServices and
    FileProvider failures, including `NSOSStatusErrorDomain -10814`. This is a
    failure of TAP-0081's existing stable/no-blank/lifecycle condition, not a
    new Share feature or a reason to revive deprecated direct Share. The owner
    authorized remediation: explicit public UTI conformances and typed item
    provider; visible handoff feedback through controller presentation; and
    attempt-scoped, idempotent cleanup across completion, cancellation,
    SwiftUI `onDismiss`, UIKit dismissal, initialization failure, and stale
    callback orderings. The prior delivered build no longer supplies acceptance
    for this regression. Cross-cutting main-thread starvation and progress
    backpressure are separated into TAP-0083. TAP-0081 remains Doing and its
    next fixed build requires a cold first-attempt recheck under TAP-0082.
  - `2026-08-13` Closure audit completed for frozen commit
    `bf20b52452512aefe745624bd9f80c09355abae5` after its iphoneos build was
    installed and launched on the recorded iPhone 15 Pro / iOS 26.6. The owner
    explicitly directed “先把 8182 先给验收掉”, accepting the fixed native
    Share result, implementation/process handoff, approved prototype parity,
    cold-handoff remediation, and documented transient TAP Video disk/I/O
    tradeoff. TAP-0082 supplies the attended verdict. Moved TAP-0081 Doing ->
    Done. The newly observed Library grid-to-Viewer horizontal title/Back motion
    is separated into TAP-0084; it is not a Share regression and does not reopen
    TAP-0081 or mixed-media Viewer paging.
  - `2026-08-13` Prototype source commit
    `70e8b60d4e20486a6d4847d726b393a50e22c7ba` formally synchronized
    `Prototype/manifest.json` and `Prototype/design-qa.md` to `ownerApproved`
    for exact `TAP-0081-r2-candidate`, including the approval date, owner
    statement, fixture, and QA evidence. This is post-closure evidence
    synchronization only; TAP-0081 remains Done.
  - `2026-08-14` The owner deliberately reopened TAP-0081 through the historical
    sequence Done -> Todo -> Doing on baseline `main@fe0d308`. A current
    real-device run made Save to Files crash its selector and left AirDrop
    waiting, while the supplied log repeatedly states `Could not load
    representation public.zip-archive from the item provider for opening in
    place`. The old `bf20b52` Done and acceptance facts remain append-only
    history, but no longer prove the current typed handoff. Approved remediation
    is limited to a copy-backed typed `NSItemProvider`, provider load and
    temporary-artifact lifetime tests, and the linked TAP-0082 device recheck;
    no UI copy/text, state, prototype, or unrelated Task scope changes. Assigned
    to `/root`; final status is Doing.
  - `2026-08-14` Appended the current `/root` implementation handoff without a
    lifecycle transition. Production changes the app-private temporary-file
    provider from `[.openInPlace]` to copy-backed `[]`, while preserving custom
    UTI first, ZIP fallback, one typed provider, and no bare URL. New tests load
    both provider APIs, verify copied bytes, `isInPlace == false`, suggested
    name, and source-lease lifetime; cleanup gains the low-cardinality
    `tap_share_temp_cleanup_finished` milestone. The DepthAnalysis README and
    TAP-0082 acceptance record are synchronized, and this non-visual repair
    changes no Share UI copy/text, state, geometry, icons, interaction, or Web
    prototype. `git diff --check`, generic Simulator build-for-testing without
    launching Simulator, and generic iphoneos build-for-testing passed. The new
    provider tests passed in two audit runs, but the containing suite then
    failed only on its stale README wording assertion; that source assertion is
    repaired and the full suite has not been rerun. The iPhone 15 Pro currently
    reports CoreDevice unavailable, no fixed build is installed, and TAP-0082
    Save to Files/AirDrop owner retest remains Pending. TAP-0081 stays Doing.
  - `2026-08-14` Froze the current implementation candidate as commit `35745be`
    (`Fix TAPNAP system share transport`) and recorded a successful signed
    iPhone build without claiming device delivery. The automated install stalled
    while Xcode/LLDB held the previous app process; LLDB's expected `SIGKILL`
    occurred during replacement and is not treated as an app crash or acceptance
    result. After the owner said “你先不要帮我进行调试之类的操作，我自己安装。到
    时候我会把 Xcode 的 console log 给你。”, `/root` cancelled the one active
    `devicectl` install and stopped all further device install/debug/launch work.
    The owner will self-install and return console logs. No fixed-build install,
    launch, Files/AirDrop result, or owner verdict is claimed; TAP-0081 remains
    Doing.
  - `2026-08-14` The owner's self-managed physical-device run rejected
    candidate `35745be`: AirDrop remained at “未找到用户” without a received
    artifact, and an ordinary-image Share attempt exhibited the same failure
    and repeated LaunchServices `Code=-54` diagnostics as `.tapnap`. This
    cross-format result falsifies the current custom-UTI/package-only diagnosis;
    the copy-backed provider candidate is not accepted even though it compiled
    and its provider tests passed. TAP-0081 remains Doing.
  - `2026-08-14` The owner declined a separate rollback commit with “这条就算了
    直接开始改吧” and approved direct recovery on the unpushed
    `codex/tap-share-system-handoff-recovery` branch. Current scope restores the
    pre-`bf20b52` system-native file-URL activity-item handoff for ordinary
    media and `.tapnap`, preserves the anchored UI/progress/exact-attempt lease,
    and forbids deleting a handed-off source before the system consumer reaches
    its terminal boundary. The prior “no bare URL” requirement is explicitly
    superseded for this recovery; private LaunchServices entitlements remain
    prohibited. No recovery implementation, tests, or device pass is inferred;
    TAP-0081 remains Doing and TAP-0082 supplies the later attended verdict.
  - `2026-08-14` Appended the uncommitted recovery implementation handoff without
    changing status. Package, image, and video now all hand
    `[artifact.fileURL]` directly to one `UIActivityViewController`; the shared
    manual `UIActivityItemsConfiguration` / `NSItemProvider` transport is
    removed. `TAPObservedActivityViewController` strongly retains the handed-
    off artifact and explicitly cleans its directory on controller
    deinitialization; completion, SwiftUI dismissal, and representable
    dismantling release coordinator state only, while the artifact lease remains
    an abnormal cleanup fallback. Product Contract §5.3, the DepthAnalysis
    README, and `Docs/Acceptance/TAP-0082-share-handoff.md` are synchronized to
    this controller-last-owner contract. Generic iphoneos `build-for-testing`
    passed and compiled the revised tests, but those tests were not run. Nothing
    is committed or pushed, no device operation or acceptance is claimed,
    TAP-0081 remains Doing, and TAP-0082 remains Todo.
  - `2026-08-14` Recorded the owner's completion-state decision and the
    subsequent exact-attempt hardening. After AirDrop or Save to Files activity
    completion, TAPCam ends its app-owned Share presentation and returns to the
    stable Viewer; destination UI remains system-owned and the TAP Share popover
    does not reopen. The system sheet now uses an item-scoped presenter keyed by
    presentation UUID; binding, `onDismiss`, appearance, completion, and
    dismantle all carry `expectedArtifactID`, so stale attempt-A callbacks
    cannot dismiss attempt B. Controller callbacks capture the UUID rather than
    the presentation object to avoid a retain cycle, and every presentation
    initializer transfers artifact ownership to its controller. Generic
    iphoneos `build-for-testing` passed after these changes and compiled the
    revised tests, but the tests were not run. No device operation, commit,
    push, or owner acceptance is claimed. TAP-0081 remains Doing and TAP-0082
    remains Todo.
  - `2026-08-14` Superseded that completion-callback direction at the owner's
    instruction: “分享完成之后自动关闭”的功能没有实现，我们就先取消，并清理掉之前与该功能相关的代码。
    TAPCam must not install or depend on `completionWithItemsHandler` to
    proactively close the system activity controller. Removed the unused
    `onFinished`, completion handler, `activityFinishTask`,
    `activitySheetHasDismissed`, `finishActivityPresentation`, and post-handoff
    minimum-visibility machinery while preserving direct file-URL handoff,
    controller-owned artifacts, and expected-artifact-ID guards for dismissal,
    dismantle, and never-appeared recovery. The cache audit found no persistent
    Share payload cache or prewarm: outputs live only in per-attempt OS
    temporary directories, normally removed on controller release with lease
    deinitialization as a fallback. `SIGKILL` or exhausted removal retries may
    leave OS-temporary residue, which is a cleanup risk rather than a cache.
    Generic iphoneos `build-for-testing` passed after this cleanup and compiled
    the revised tests, but tests were not run. No Codex device operation,
    commit, or push is claimed; TAP-0081 remains Doing.
  - `2026-08-14` Recorded the owner's explicit reply “验收通过” to the
    immediately preceding four-item transport matrix. This confirms Pass for
    ordinary image Save to Files, ordinary image AirDrop, `.tapnap` Save to
    Files, and `.tapnap` AirDrop, including openability of every saved or
    received artifact. It does not invent filenames, hashes, logs, a receiving
    device, a recovery commit, or a final build identity. The attended
    transport gate is satisfied, but the accepted recovery is still
    uncommitted/unpushed and its focused tests were compiled rather than run;
    TAP-0081 therefore remains Doing.
  - `2026-08-14` Classified the owner's post-Pass Share console sample without
    reopening the successful transport verdict. Current production has one
    direct file-URL `UIActivityViewController` and no residual manual provider,
    open-in-place option, or destination-completion callback. LaunchServices
    `-10814` is the custom URL's default-handler lookup returning
    `kLSApplicationNotFoundErr`; CKShare/SWY, FileProvider, LaunchServices
    `Code=-54`, and persona diagnostics are system probe noise rather than an
    app transport failure or a reason to add private entitlement/document-
    handler code. `System gesture gate timed out` remains an observation unless
    it accompanies a reproducible visible stall, in which case the existing
    payload-ready/controller-created/handoff-started milestones must be
    correlated first. Removed the unused TAPNAP `UTType` helper and repaired a
    stale presentation-binding source assertion; generic iphoneos
    `build-for-testing` exited 0. No device/Simulator run, commit, push, or
    status transition is claimed; TAP-0081 remains Doing.
  - `2026-08-14` Board Steward checkpoint reconciliation: the owner-accepted
    ordinary-image and `.tapnap` Save to Files/AirDrop path is frozen by the
    commit containing this record under the self-referential subject
    `Checkpoint working Share transport before lifecycle repair`; no guessed
    hash is written. The detailed sequence preserves the transport Pass but
    leaves lifecycle open. For both `.tapnap` and image, system URL probing
    starts after controller construction but before coordinator handoff, while
    `discardPendingHandoff()` can still delete that artifact. After the
    `.tapnap` sheet logged dismissal, the next image Share also began before any
    controller-dismantled or `artifactLease` terminal-cleanup milestone
    appeared. Finally, the same attempt logged controller construction as
    `under50ms` before revealing `over50ms` feedback attributed to
    `controllerConstruction`. Pending-handoff source ownership, prompt teardown,
    and progress-phase attribution are therefore not accepted by this
    checkpoint. TAP-0081 remains Doing; the next implementation may repair
    these lifecycle defects without weakening the successful direct-file-URL
    transport path.

### TAP-0082 — Device acceptance: TAP Share anchored handoff and anti-flash progress

- Status: `Doing`
- Kind: `DeviceAcceptance`
- Priority: `P0`
- Domain: `Share / Viewer`
- Labels: `device-acceptance`, `share`, `airdrop`, `activity-controller`,
  `progress`, `anti-flash`, `photo`, `live-photo`, `video`, `icloud`,
  `local-integrity`, `human-confirmation`, `cold-install`, `first-share`,
  `main-runloop`, `file-url-handoff`, `system-consumer-lifetime`
- Contract: `ProductContract §5.3`; `§8`; `§9`; `UIPrototypeContract §5`
- Match Keys: `share visual audit, AirDrop, share to app, progress flash, 50 ms,
  400 ms, one system share, physical device, iCloud original download,
  local integrity mismatch, cold first Share, clean install, empty cache,
  no loading feedback, 真机分享, 人工验收, 首次安装卡住`
- Assignee: `Product owner for attended verdict; Codex /root for evidence and revised-build reconciliation`
- Dev Session: `Product-owner attended run reported; /root evidence and revised-build reconciliation`
- Branch/Worktree: `N/A; evidence Task consumes a fixed TAP-0081 build`
- Related Delivery: `TAP-0081`
- Acceptance Record:
  [TAP-0082 Share handoff](Acceptance/TAP-0082-share-handoff.md)
- Historical Build/Commit (`bf20b52`): `Frozen commit bf20b52452512aefe745624bd9f80c09355abae5
  (bf20b52, Fix cold share handoff and media loading). Its iphoneos build was
  installed and launched successfully as TAP-NAP.TAPCamDemo on the recorded
  device. Earlier delivered artifacts remain superseded historical evidence.`
- Current Reopen Build/Install: `Implementation candidate 35745be (Fix TAPNAP
  system share transport) is frozen and its signed iPhone build succeeded, but
  the owner's physical-device Share run rejected it: AirDrop displayed
  “未找到用户” without a received artifact, and ordinary-image sharing showed the
  same system failure and LaunchServices Code=-54 diagnostics. The active
  direct-file-URL recovery on codex/tap-share-system-handoff-recovery is being
  frozen by the commit containing this record under the self-referential
  subject “Checkpoint working Share transport before lifecycle repair”; no
  guessed hash is recorded. Generic iphoneos build-for-testing passed after
  proactive-completion dead-code removal and compiled the revised tests, but
  those tests were not run. The owner replied “验收通过” to the immediately
  preceding explicit four-path matrix: ordinary image and `.tapnap` each passed
  Save to Files and AirDrop, and every saved/received artifact opens. This
  checkpoint is a transport baseline, not a lifecycle-fixed build identity.
  The owner controls device execution; /root must not
  perform device debugging, installation, or launch unless that instruction
  changes.`
- Historical Device/iOS (`bf20b52`): `Connected iPhone 15 Pro; model identifier iPhone16,1; iOS 26.6;
  CoreDevice 8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7.`
- Scope: On a physical device, verify the approved anchored app-owned Share
  selection/preparation presentation and its direct handoff to the single
  system activity controller for representative still photo, Live Photo, and
  TAP Video paths. Exercise AirDrop and at least one compatible third-party
  destination when available, fast and deliberately slow preparation, Cancel,
  Retry, system dismissal, repeated Share attempts, complete-original readiness
  after iCloud download, and local-integrity pass/mismatch degradation. After
  the approved TAP-0081 toolbar revision, inspect the native Share/Delete glyphs,
  42pt circular backgrounds, 20pt vector boxes, compact middle mode capsule,
  and Share progress ring on the fixed device build. Confirm their refined
  optical relationship without shifting or stretching the toolbar. The re-run
  must begin from a true cold evidence condition (fresh install or an
  explicitly equivalent cleared app-container/cache state), exercise the first
  Library/Viewer/Share path before any warm-up, and distinguish the app-owned
  surface becoming visible from payload preparation and system-controller
  presentation. After the system activity controller appears, destination
  selection, completion, and dismissal remain system-owned; confirm TAPCam does
  not install a destination-completion callback to proactively close it. A
  subsequent warm run is comparison evidence only.
- Out of Scope: Restyling system-owned UI; proving the cryptographic validity of
  package contents; implementing future Video `.tapnap`, Sticker, Link, upload,
  or membership features; treating Simulator screenshots as device evidence.
- Preconditions: Owner-approved repository Web prototype revision; fixed
  TAP-0081 build/commit; representative signed still, signed Live Photo, video,
  retry-pending and failed fixtures; at least one Photos/iCloud resource evicted
  from local storage plus valid and locally mismatched controlled fixtures; a
  reachable AirDrop peer and a compatible receiving app where those
  destinations are part of the run; and instrumentation that can correlate,
  without media IDs or paths, Share tap, app-owned surface visible, local-
  integrity start/end, payload ready, activity-controller constructed,
  appeared, coordinator dismissal/teardown state ended, controller final release, and
  temporary-attempt cleanup as distinct milestones, with every callback
  attributable to one immutable presentation/artifact ID. User/system
  dismissal, dismantle, and never-appeared recovery must not be presented as
  proof of source cleanup.
- Reset/Install Procedure: `The fixed bf20b52 iphoneos build was installed and
  launched on the recorded iPhone. A separate narrated reset transcript was not
  supplied. After completing the attended check, the product owner explicitly
  accepted TAP-0081/TAP-0082 and directed their closure; this Board record is
  the accepted evidence record for that owner decision.`
- Procedure:
  1. From the confirmed cold reset, enter TAP Library for the first time, open a
     ready representative item, and tap Share before any warm-up. Confirm an
     app-owned visible acknowledgment is committed before local integrity,
     payload work, or system-controller initialization can occupy the path;
     correlate every milestone in the structured log.
  2. Open an iCloud-only representative item; confirm Viewer loading may fetch
     the complete original while Share remains unavailable, then becomes
     available only after the full media-kind-specific resource set is ready.
  3. Open each ready representative Viewer item and invoke Share once; confirm
     the status comes from local validation of the actual media and no TAP
     backend/App Attest Verify request occurs, including when no exported queue
     record exists.
  4. Confirm one anchored app-owned selector appears without rebuilding the
     media, pager, toolbar, or chrome. Confirm Share/Delete use the approved
     custom prototype vectors in 20pt boxes; each is optically concentric in a
     42pt circle equal to Back; the Share progress ring uses that same center;
     and the middle mode capsule stays compact rather than flex-filling.
  5. Select a payload that completes within 50 ms and confirm no progress
     surface is inserted before the system activity controller appears.
  6. Select a deliberately slow payload and confirm progress appears only after
     50 ms, advances without regression, and remains readable for at least
     400 ms once visible, including a stable 100% handoff when work finishes
     early.
  7. Exercise a controlled local-integrity mismatch; confirm TAPNAP is disabled
     while the applicable ordinary image/video option remains available with
     an explicit warning that verifiability is not guaranteed.
  8. Cancel during preparation, Retry a controlled failure, dismiss the system
     controller, and repeat Share; confirm no stale progress, duplicate system
     presentation, or leaked prior attachment affects the new attempt. For an
     artifact already handed to UIKit, confirm coordinator activity state can
     finish without source deletion; cleanup follows only after the retained
     activity controller releases its final ownership. Confirm a delayed
     binding, user/system dismissal, appearance, dismantle, or never-appeared
     recovery callback from attempt A cannot release a later attempt B.
  9. Complete representative AirDrop and compatible-app destinations and
     confirm the selected payload, filename/type, and source-media capability
     are the ones chosen in TAPCam. Confirm TAPCam leaves destination selection,
     completion, and dismissal to the system controller rather than replacing
     them with app UI or a proactive completion callback.
- Expected Results: Only the app-owned selector and then the single
  system-owned activity controller are presented; there is no intermediate
  empty sheet, full-screen refresh, one-frame progress flash, row dimming flash,
  blank Viewer frame, silent cold-start wait, or progress regression. The first
  tap produces app-owned visible feedback before scalable work, and the
  fixed build gives the system activity controller native file-URL activity
  items for both ordinary media and `.tapnap`; the `.tapnap` package and its
  declared type remain unchanged without requiring the failed manual typed-
  provider path. iCloud/resource loading is not
  misreported as credential failure; a missing queue record is not itself a
  failed result; local mismatch produces the approved package-disable and
  warning degradation; Cancel/failure/dismissal recover in the same stable
  surface; every temporary attempt is cleaned up; and coordinator-state
  termination is observably distinct from controller-owned source cleanup.
  Every applicable lifecycle callback is scoped to the immutable presentation
  ID, stale attempt-A callbacks cannot release attempt B, and TAPCam does not
  proactively close the system controller from destination completion. On the revised
  build, Share/Delete each remain a concentric 20pt custom vector inside a 42pt circle
  equal to Back, the Share progress ring keeps that center, and the compact
  middle capsule neither stretches nor displaces the outer controls.
- Required Evidence: Fixed build/commit, device and iOS identifiers, narrated
  screen recordings beginning before the first cold Library/Viewer/Share path
  and continuing through fast/slow/Cancel/Retry paths, screenshots of the
  app-owned and system-owned boundaries, structured milestone and cleanup logs,
  including distinct coordinator-state-ended and source-cleanup-finished
  evidence plus presentation/artifact-ID correlation, confirmation of the reset
  method, and received AirDrop/app artifacts when exercised.
- Evidence Location: `Frozen commit bf20b52 plus this detailed Board record.
  Build/install/launch and device identity are recorded here. No separate
  acceptance file, recording bundle, or received-artifact attachment was
  supplied; the owner explicitly chose direct attended acceptance and Board
  closure as sufficient for that historical run. Current reopened evidence must
  be written to
  [Docs/Acceptance/TAP-0082-share-handoff.md](Acceptance/TAP-0082-share-handoff.md).`
- Pass Conditions: Every numbered action has its expected result, timing and
  lifecycle evidence is attributable to the fixed build, received artifacts
  match the selected options, and the owner explicitly accepts the run.
- Fail Conditions: Any duplicate app/system presentation, visible transient
  flash, intermediate blank frame, silent first-tap wait before app-owned
  feedback, progress regression, stale callback,
  enabled Share before the complete original is ready, backend Verify traffic,
  exported-record absence misclassified as failure, mismatch allowed to create
  TAPNAP, missing ordinary-media warning, uncancelled preparation, incorrect
  payload, temporary-artifact lifecycle failure, a 54pt outer toolbar control,
  a non-20pt vector box, any visible vector/background/progress-ring decentering,
  a mode capsule that flex-fills the toolbar, reintroduction of the failed
  shared manual item-provider transport, deletion of a handed-off source before
  the retained activity controller releases its final ownership, treating
  dismissal/dismantle/never-appeared recovery alone as a source-deletion signal,
  a stale attempt-A callback releasing attempt B, installation of a proactive
  destination-completion callback, or a result claimed only after a warm
  re-entry. The former failure condition against bare
  file-URL inference is superseded for this owner-approved recovery and remains
  history only.
- Former Blocked Conditions / Resolution: The original gate required a frozen
  commit, owner-confirmed procedure, post-change verdict, fixtures, destinations,
  and artifact bundle. `bf20b52` supplies the frozen commit and fixed device
  delivery, and the owner supplied the final attended verdict. A separate reset
  transcript, recording bundle, received artifacts, and standalone acceptance
  file were not supplied; the owner explicitly accepted that evidence exception
  and directed closure, so it is recorded rather than silently treated as if
  those artifacts existed.
- Human Confirmation: `Accepted by the product owner on 2026-08-13 for bf20b52:
  “先把 8182 先给验收掉”. This is the final attended product verdict for the
  fixed Share delivery. The separately observed Library grid-to-Viewer motion
  issue is excluded and tracked by TAP-0084.`
- Done When: The acceptance record contains the owner-confirmed prerequisites,
  reset/install steps, fixed build/device/OS, complete evidence, per-action
  verdicts, and explicit owner acceptance. Automation or Simulator output alone
  cannot close this Task. For this closure, the owner explicitly accepted the
  fixed build/device run and directed the detailed Board record to close the
  Task despite no separate recording/artifact bundle; that conscious evidence
  exception is preserved here and in Revision History rather than inferred.
- Completion Audit: `Done for bf20b52 on iPhone 15 Pro / iOS 26.6.` Frozen
  commit, identified device, successful install/launch, prior automated and
  prototype evidence, and the owner's explicit attended verdict are present.
  The missing standalone acceptance file/recording bundle is an explicit owner-
  accepted evidence exception, not silently fabricated evidence. TAP-0084 owns
  the later Library-to-Viewer transition issue and does not invalidate this
  Share verdict. This audit remains historical and does not satisfy the reopened
  transport check.
- Reopened Acceptance Scope: On the fixed TAP-0081 build, perform attended
  physical-device Save to Files and AirDrop for representative ordinary media
  and `.tapnap`. Save to Files must complete without a selector crash and
  produce each selected file. AirDrop must discover the known-reachable peer,
  advance beyond waiting, and supply the received ordinary-media and `.tapnap`
  artifacts so their filenames, declared types, bytes, and openability can be
  checked. Record the build/commit, device/iOS, numbered actions, per-format
  verdicts, received artifacts, and relevant logs in
  [TAP-0082 Share handoff](Acceptance/TAP-0082-share-handoff.md). The prior
  `bf20b52` verdict remains history and may not be reused for the fixed build.
- Current Retest State: The native file-URL recovery represented by this Board
  revision is the transport checkpoint being frozen by the commit titled
  `Checkpoint working Share transport before lifecycle repair`; the containing
  commit supplies its identity without a predeclared hash. Its item-scoped
  presenter and expected-artifact-ID routing preserve exact-attempt dismissal/
  teardown isolation without a destination-completion callback. Intended
  ownership makes controller release the normal per-attempt temporary-directory
  cleanup boundary and the shared artifact lease the abnormal fallback, but the
  detailed log has not yet demonstrated that terminal release after dismissal.
  There is no persistent Share payload cache or prewarm; a `SIGKILL` or
  exhausted removal retries can leave OS temporary residue but do not create an
  app cache. Generic iphoneos
  `build-for-testing` passed after the dead-code cleanup and compiled the
  revised tests, but those tests were not run. The linked acceptance record now
  captures the exact four-path received/openable-artifact matrix as Pass. No
  Codex device operation, filename, hash, receiving-device identity, or final
  lifecycle-fixed build identity is claimed. TAP-0082 remains Doing until the
  remaining lifecycle race, teardown/progress attribution, and focused-test
  evidence are reconciled.
- Current Console Observation: The owner's post-Pass logs still contain
  LaunchServices `-10814`/`Code=-54`, CKShare/SWY, FileProvider, persona, and
  one gesture-gate timeout while preparing `.tapnap`. The corresponding source
  audit found no stale manual provider/open-in-place/completion transport code:
  the current path remains one direct file-URL activity controller. Both
  `.tapnap` and ordinary-image sequences show the system's LaunchServices/
  FileProvider URL probes after `tap_share_activity_controller_created` but
  before coordinator `tap_share_activity_handoff_started`. During that interval
  the coordinator still classifies the presentation as a pending handoff, and
  `discardPendingHandoff()` can explicitly remove its artifact even though the
  constructed controller has already caused the system to inspect the URL.
  This is an open source-lifetime race. The `.tapnap` sequence additionally
  reaches `tap_share_activity_sheet_dismissed` without a subsequent controller-
  dismantled or `artifactLease` terminal-cleanup milestone before the next
  Share begins, and it reports controller construction `under50ms` before
  revealing `over50ms` feedback attributed to `controllerConstruction`.
  System-probe warnings do not negate the received/openable four-path verdict,
  but source ownership, teardown, and progress attribution are not accepted.
- Current Human Confirmation: `Pass for the current recovery transport matrix
  on 2026-08-14. The owner replied “验收通过” to the immediately preceding
  explicit confirmation that ordinary image and .tapnap each succeeded through
  Save to Files and AirDrop and that every saved/received artifact opens.`
- Reopened Done When: Both physical-device destinations pass on the fixed build
  for representative ordinary media and `.tapnap`, AirDrop produces received
  artifacts for both paths, sources remain readable from controller creation
  through the activity controller's final ownership release, coordinator-state
  termination and source cleanup are evidenced separately, stale dismissal/
  teardown callbacks cannot release a newer attempt, no proactive destination-
  completion callback or persistent payload cache exists, and the linked
  acceptance record carries the owner's explicit four-path artifact verdict.
  Build/install/launch, the historical
  provider tests, candidate `35745be`, or the `bf20b52` acceptance
  alone cannot return TAP-0082 to Done.
- Current Closure Gate: `The four-path attended transport matrix is complete
  and its direct-file-URL baseline is frozen by the checkpoint commit containing
  this Board revision. Remaining before Done: eliminate the pending-handoff/
  controller-read source-lifetime race, prove terminal teardown and artifact
  cleanup, correct progress-phase attribution, execute the focused tests that
  have only compiled, and complete the linked lifecycle evidence. No additional
  Save-to-Files/AirDrop rerun is requested unless the frozen build differs from
  the owner-tested recovery.`
- Created: `2026-08-12`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-12` Created in Inbox as the evidence follow-up to `TAP-0081` so
    native system-share destinations and human-visible anti-flash behavior are
    not inferred from implementation or Simulator tests.
  - `2026-08-12` Owner approved the separate evidence scope and moved Inbox ->
    Todo. Execution remains blocked on a fixed TAP-0081 build, an accepted Web
    prototype, an owner-confirmed acceptance record, and attended human review.
  - `2026-08-13` Synchronized the owner-approved TAP-0081 scope revision into
    this open evidence Task: device acceptance now includes iCloud original
    readiness gating, actual-resource local integrity without backend Verify,
    missing exported queue-record behavior, and mismatch degradation. Status
    remains Todo and Human Confirmation remains Pending.
  - `2026-08-13` Recorded that the revised TAP-0081 implementation handoff and
    focused automated tests exist, while the exact r2 candidate approval,
    frozen Release build, owner-confirmed device procedure, attended run, and
    human confirmation remain Pending. TAP-0082 stays Todo; Simulator or unit
    evidence does not substitute for this physical-device acceptance.
  - `2026-08-13` Added the succeeded nine-group/268-test xcresult and generic
    Simulator Release build as delivery evidence. These results do not freeze a
    commit, execute the owner-confirmed device procedure, exercise AirDrop/app
    destinations, or provide human-visible anti-flash acceptance. Exact r2
    candidate approval, a fixed device build, attended execution, and Human
    Confirmation remain Pending; TAP-0082 stays Todo.
  - `2026-08-13` The product owner explicitly reported completing a physical-
    device test and accepting it as passed. Recorded that statement as Human
    Confirmation and moved TAP-0082 Todo -> Doing because attended execution
    has begun. No fixed build/commit, device/iOS identifiers, numbered-action
    verdicts, recordings/logs, or received artifacts were supplied, so the
    conversational verdict is not expanded into complete acceptance evidence
    and the Task is not Done. The owner also requested a prototype-aligned
    Share/Delete icon/background/concentricity change under TAP-0081; final
    device visual acceptance must cover the revised fixed build. Because the
    reported run occurred without the Board's required pre-run procedure and
    evidence record, this is also recorded as a workflow deviation to reconcile,
    not silently treated as a fully evidenced TAP-0082 completion.
  - `2026-08-13` Synchronized the owner's refined post-run toolbar decision into
    the still-open device check: custom Share/Delete vectors in concentric 20pt
    boxes, 42pt circles matching Back, a shared Share progress-ring center, and
    a compact non-flex-fill center capsule. The earlier device pass predates
    this revision, so the fixed revised build still requires attended optical
    confirmation. TAP-0082 remains Doing and is not marked Done.
  - `2026-08-13` Recorded that the owner approved the final updated r2 Web
    prototype and authorized SwiftUI implementation. This clears the prototype
    approval blocker but does not supply a fixed post-change native build or its
    physical-device optical verdict. TAP-0082 remains Doing pending inspection
    of the implemented 42pt/20pt/compact toolbar on that revised build.
  - `2026-08-13` Appended attributable post-change device-delivery evidence.
    Debug iphoneos build succeeded with Automatic Development signing (`Apple
    Development: Jinbo Li`, team `UD3269PSCB`) at
    `/private/tmp/TAPCamDemo-TAP0081-device/Build/Products/Debug-iphoneos/TAPCamDemo.app`.
    The app installed and launched successfully as `TAP-NAP.TAPCamDemo` on the
    connected iPhone 15 Pro (`iPhone16,1`), iOS 26.6, CoreDevice
    `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`. The post-change Simulator was
    intentionally skipped per owner instruction. Build/install/launch delivery
    is complete, but the human post-change visual/flow verdict, frozen commit,
    procedure, and review artifacts remain Pending; TAP-0082 stays Doing.
  - `2026-08-13` Appended the narrow regression-fix redelivery. The owner
    approved the interpretation; production changed only three lines: remove
    the forced outer navigation-bar visibility from `CameraView`, gate
    `DepthAlbumPickerView` navigation-bar visibility with `isViewerPresented`,
    and change fallback bottom padding 20 -> 25 to match the prototype. `git
    diff --check` and `node Prototype/prototype.test.mjs` passed. Debug iphoneos
    build/install/launch succeeded again on the same iPhone 15 Pro / iOS 26.6.
    Simulator was intentionally skipped per owner instruction. Human post-fix
    visual/flow verdict remains Pending; TAP-0082 stays Doing.
  - `2026-08-13` The owner subsequently reported a cold-first-Share failure:
    the first app-owned selector and later system handoff could each wait with
    no visible feedback, while re-entry was fast. The earlier conversational
    pass and delivered artifacts are therefore not acceptance for the current
    regression. Expanded the still-open attended run to require a true fresh-
    install/equivalent cleared-data reset, first Library/Viewer/Share execution
    before warm-up, visible acknowledgment before scalable work, explicit
    typed `.tapnap` handoff, structured milestone/cleanup logs, and a warm run
    only as comparison. TAP-0082 remains Doing with Human Confirmation Pending;
    it must not be marked Done from build/install/launch or warm-only behavior.
  - `2026-08-13` Final acceptance reconciled against frozen commit
    `bf20b52452512aefe745624bd9f80c09355abae5`, installed and launched on the
    recorded iPhone 15 Pro (`iPhone16,1`) / iOS 26.6. The owner explicitly
    directed “先把 8182 先给验收掉”, supplying the final attended verdict and
    accepting the detailed Board record despite no separate reset transcript,
    screen-recording bundle, received artifacts, or standalone TAP-0082 file.
    This explicit evidence exception is preserved rather than backfilled with
    invented detail. Moved TAP-0082 Doing -> Done. The newly observed Library
    grid-to-Viewer title/Back animation is independently tracked by TAP-0084 and
    does not reopen the accepted Share flow.
  - `2026-08-14` The owner deliberately reopened TAP-0082 Done -> Todo after the
    current build failed the system transport boundary: the Save to Files
    selector crashed, AirDrop remained waiting without a received artifact, and
    the supplied attachment reports `Could not load representation
    public.zip-archive from the item provider for opening in place`. The
    `bf20b52` acceptance and its evidence exception remain historical facts only.
    The fixed TAP-0081 build now requires attended Save to Files success and an
    actually received AirDrop artifact, documented in
    `Docs/Acceptance/TAP-0082-share-handoff.md`; current Human Confirmation is
    Pending.
  - `2026-08-14` Synchronized the executable acceptance file and current
    implementation handoff without changing status. Generic Simulator and
    iphoneos build-for-testing checks succeeded, but the implementation is not
    yet a frozen or installed device build. The recorded iPhone 15 Pro currently
    reports CoreDevice unavailable; Save to Files, AirDrop receipt/artifact
    inspection, and the owner's attended verdict therefore remain Pending.
  - `2026-08-14` Recorded frozen candidate commit `35745be` and its successful
    signed iPhone build without converting build evidence into device
    acceptance. The tool-driven install stalled while Xcode/LLDB held the prior
    app process; the expected replacement `SIGKILL` is not a product failure or
    pass. The owner explicitly took over installation and will return Xcode
    console logs; `/root` cancelled the single active `devicectl` install and
    will perform no further install/debug/launch. No successful fixed-build
    install, launch, Save to Files, AirDrop receipt, artifact inspection, or
    owner verdict is claimed. TAP-0082 remains Todo.
  - `2026-08-14` Recorded the owner's failed self-managed run of candidate
    `35745be`. AirDrop remained at “未找到用户” and produced no artifact; direct
    ordinary-image Share showed the same failure and repeated LaunchServices
    `Code=-54` diagnostics as `.tapnap`. This is failed device evidence against
    the copy-backed manual provider candidate, not acceptance. Expanded the
    next fixed-build run to cover Save to Files and AirDrop for both ordinary
    media and `.tapnap`; TAP-0082 remains Todo with Human Confirmation Pending.
  - `2026-08-14` Synchronized the owner's decision to skip a rollback commit and
    begin direct repair on `codex/tap-share-system-handoff-recovery`. TAP-0082
    will consume the later system-native file-URL build and must verify received
    artifacts plus source-lifetime behavior; the current acceptance file still
    requires synchronization before that run. No implementation or device pass
    is inferred, and `/root` remains prohibited from device debug/install/launch
    while the owner retains self-installation. Status remains Todo.
  - `2026-08-14` Synchronized the acceptance record to the implemented native
    file-URL recovery. It now covers ordinary media and `.tapnap`, controller-
    owned source lifetime, distinct activity-state-finished versus source-
    cleanup-finished evidence, Save to Files, AirDrop, and received artifacts.
    The recovery remains uncommitted and unpushed; generic iphoneos
    `build-for-testing` passed and compiled the revised tests, but those tests
    were not executed. No fixed commit, owner self-install, device run, or human
    verdict exists yet. TAP-0082 remains Todo with Human Confirmation Pending.
  - `2026-08-14` Expanded the still-open device verdict for the owner's latest
    completion-state decision and the exact-attempt implementation. The fixed
    run must show AirDrop/Save to Files completion returning to the same stable
    Viewer without reopening the app-owned popover, and repeated attempts must
    show that stale callbacks from A cannot dismiss B. The presentation-UUID/
    `expectedArtifactID` hardening compiles in a passed generic iphoneos
    `build-for-testing`, but tests were compiled rather than run. No fixed
    commit, push, self-install, device result, or human verdict exists;
    TAP-0082 remains Todo with Human Confirmation Pending.
  - `2026-08-14` Superseded the prior destination-completion auto-close
    acceptance condition after the owner stated that the feature never worked
    and directed its related dead code to be removed. The current device check
    leaves destination completion/dismissal system-owned and verifies direct
    file-URL transport, received/openable artifacts, exact-attempt teardown,
    and controller-last-owner temporary-file cleanup without a proactive
    completion callback or persistent payload cache. The owner then reported
    “现在的话分享功能已经正常” and asked to implement TAP-0082; this is recorded as
    a broad positive attended result and moves TAP-0082 Todo -> Doing. It does
    not invent confirmation that ordinary image and `.tapnap` each passed both
    Save to Files and AirDrop with an inspectable saved/received artifact; that
    exact four-path matrix and a frozen commit remain required before Done.
  - `2026-08-14` The owner explicitly replied “验收通过” to the immediately
    preceding four-item matrix. Recorded ordinary image Save to Files, ordinary
    image AirDrop, `.tapnap` Save to Files, and `.tapnap` AirDrop as Pass, with
    every saved/received artifact openable. No filenames, hashes, logs,
    receiving-device identity, commit, or final build identity are inferred.
    The attended transport matrix is complete, but the recovery remains
    uncommitted/unpushed, focused tests were compiled rather than run, and the
    cancellation/lifecycle evidence remains open. TAP-0082 therefore stays
    Doing rather than moving prematurely to Done.
  - `2026-08-14` Recorded the later successful-run console sample as diagnostic
    evidence without changing the accepted four-path verdict. Source inspection
    confirms one direct file-URL activity controller and no residual manual
    provider, open-in-place, or proactive completion callback. The observed
    LaunchServices/default-handler, CKShare/SWY, FileProvider, permission, and
    persona messages are system probing rather than a destination failure; the
    gesture-gate timeout is observation-only unless it correlates with a
    recurring visible stall. Mechanical cleanup and a generic iphoneos
    `build-for-testing` exit 0 are recorded under TAP-0081. No device/Simulator
    run, commit, push, or status transition is inferred; TAP-0082 remains Doing
    under its existing closure gates.
  - `2026-08-14` Board Steward checkpoint reconciliation preserves the owner's
    four-path transport Pass while separating it from lifecycle acceptance. The
    direct-file-URL baseline is frozen by the commit containing this record
    under subject `Checkpoint working Share transport before lifecycle repair`,
    without predeclaring a hash. Detailed logs show LaunchServices/FileProvider
    probing for both `.tapnap` and image after controller creation but before
    coordinator handoff; current pending-handoff discard can delete the source
    during that already-active system-read interval. The `.tapnap` dismissal
    also lacks controller-dismantled/`artifactLease` terminal-cleanup evidence
    before the next attempt, and its `under50ms` controller measurement precedes
    `over50ms` feedback attributed to controller construction. Source lifetime,
    teardown, and progress attribution remain open, so TAP-0082 stays Doing.

### TAP-0083 — Eliminate cold-path UI starvation and codify responsiveness guardrails

- Status: `Doing`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Runtime Responsiveness / TAP Library / Viewer`
- Labels: `cold-start`, `first-install`, `empty-cache`, `main-actor`,
  `library-snapshot`, `thumbnail-decode`, `geometry`, `progress-backpressure`,
  `observability`, `engineering-standard`
- Contract: `ProductContract §5.2–5.3`; `§8`; root `AGENTS.md`
- Match Keys: `first install freeze, cold launch hang, first Library slow,
  UI unresponsive, same snapshot repeated, UIImage data in body, per-cell
  geometry state, progress callback flood, warm re-entry fast, 首次安装卡住,
  冷启动卡顿, UI 卡死, 代码规范`
- Assignee: `Codex development session /root`
- Dev Session: `/root` with bounded implementation/review Agents
- Branch/Worktree: `Current shared main working tree; baseline main@a4cf808`
- Scope: Remove the diagnosed scalable work that can starve first visible UI
  response on a cold/empty-cache TAP Library and Viewer path, and make the rule
  durable. The bounded implementation shall:
  1. publish Library collections only when their semantic content or public
     error state changes, instead of incrementing revisions for identical
     catalog results;
  2. prevent per-cell viewport measurements from writing broad parent SwiftUI
     state on every geometry update, while preserving prefetch behavior;
  3. reuse decoded thumbnail images and keep image decoding out of SwiftUI
     `body` recomputation;
  4. coalesce high-frequency TAP Video resource-copy/loading progress to latest-
     value publication at a bounded UI cadence (target no more than 20 Hz),
     while delivering terminal progress and rejecting cancelled/stale request
     keys; and
  5. add low-cardinality structured milestones sufficient to distinguish tap,
     app-owned visible response, catalog/resource work, payload readiness,
     system presentation, dismissal, and cleanup without logging media IDs,
     file paths, URLs, hashes, or per-chunk events.
  Codify the repository rule in one canonical cold-path responsiveness standard
  and link it from root `AGENTS.md` and affected module documentation: scalable
  file I/O, media hashing, ZIP work, PhotoKit enumeration, image decoding, and
  video copying do not run as synchronous MainActor work; one synchronous
  MainActor slice targets less than 8 ms; a user action publishes stable visible
  feedback before scalable work; progress sources apply backpressure; large
  collections suppress semantic no-op publication; and every system/app
  presentation covers completion, cancellation, dismissal, initialization
  failure, presenter loss, and stale callbacks.
- Diagnostic Baseline: The supplied device log repeated identical semantic
  `tap_library_snapshot_loaded` results for the same 902/903-item catalogs.
  Source inspection found full-array republishing, parent `@State` writes from
  cell geometry, image construction reachable from cell body recomputation,
  and one MainActor task per 512 KiB TAP Video progress callback. The owner's
  observation that re-entry was fast is consistent with a cold-cache/main-
  run-loop amplification, but it is not itself proof of any single cause. The
  Share-specific typed-UTI, system handoff, and attachment-lease regression was
  closed under TAP-0081/TAP-0082 for `bf20b52`.
- Failure / Recovery: Coalescing must preserve the latest and terminal value,
  cancellation, monotonicity where the source guarantees it, and request/source
  identity. Snapshot suppression must not hide changed items or changed public
  errors. Thumbnail/cache changes must preserve invalidation and memory-warning
  behavior. Instrumentation must remain bounded and public-safe. If any guard
  cannot preserve these semantics, retain the safe current behavior, record the
  gap, and do not claim the cold-path fix complete.
- Out of Scope: Pre-generating/background-prewarming/persistently caching
  `.tapnap`; blocking first camera entry on iCloud originals, all thumbnails,
  hashes, ZIPs, system-activity prewarm, App Attest network work, or Pending
  Capture Queue batch completion; redesigning visible Library/Viewer/Share UI;
  changing TAPNAP or TAP Video formats; solving every performance issue in the
  repository; or using a warm second run as cold-path acceptance. The separate
  first-install readiness/resource-initialization state is owned by TAP-0009.
- Prototype Path/Revision/Approval: `N/A for this non-visual runtime,
  backpressure, observability, and lifecycle repair. Existing TAP-0081 approved
  visible states remain unchanged. Any new loading copy, control, hierarchy, or
  transition must return to the applicable Task's Web prototype gate.`
- Validation Gate: Focused tests must prove semantic-identical Library loads do
  not republish; a changed item/error does republish; viewport updates do not
  invalidate the full grid; cached posters are not repeatedly decoded from a
  SwiftUI body; a large burst of resource progress yields bounded UI
  publications independent of chunk count while preserving latest/terminal,
  cancel, and stale-request behavior; and presentation cleanup is attempt-
  scoped/idempotent. `git diff --check`, focused tests, and an iphoneos build
  must pass. Physical-device evidence remains separate: TAP-0047 owns the first
  large-Library cold entry, TAP-0045 owns TAP Video progress/resource behavior,
  and TAP-0082 owns the first cold Share/system handoff.
- Documentation Impact: Root `AGENTS.md`, the canonical cold-path standard,
  affected module README(s), and any Product Contract acceptance boundary must
  be reconciled by the development handoff. No new visible prototype revision
  is required unless implementation changes visible states. Project Board
  status/history remains Board-Steward-only.
- Done When: The bounded source fixes and canonical engineering standard are in
  the tree; all Validation Gate checks pass; instrumentation can attribute a
  cold first interaction without sensitive/per-item log flooding; the
  development handoff identifies every changed contract/module/governance file;
  and remaining device evidence is explicitly linked to TAP-0045, TAP-0047,
  and TAP-0082 rather than inferred from a warm run. Those evidence Tasks may
  remain open after this implementation Task is ready for Done, but no delivery
  transition occurs before Board Steward reconciliation.
- Related: Regression support for `TAP-0081`; attended Share evidence
  `TAP-0082`; TAP Video evidence `TAP-0045`; TAP Library evidence `TAP-0047`;
  adjacent first-camera/resource readiness `TAP-0009`; thumbnail policy
  `TAP-0027`
- Created: `2026-08-13`
- Updated: `2026-08-13`
- Revision History:
  - `2026-08-13` Allocated after a complete Inbox/Todo/Doing/Done/Deprecated
    search. The active TAP-0081 already owns its Share-specific first-response,
    UTI, activity-presentation, and lease-cleanup regression. No existing Task
    owns the cross-cutting Library publication/geometry/decode, TAP Video
    progress backpressure, structured cold-path observability, and repository-
    wide implementation standard, so those concerns receive this scoped
    follow-up rather than silently broadening TAP-0081 or reopening completed
    mixed-media capability Tasks.
  - `2026-08-13` The owner authorized both the current remediation and durable
    code rules (“开始修改” and the explicit requirement that future first-
    install/cold-start hangs be diagnosable and prevented). Recorded the scope,
    non-scope, recovery semantics, validation gates, governance-document impact,
    and separate physical-device evidence boundaries; moved Inbox -> Todo ->
    Doing and assigned `/root`. No implementation or acceptance completion is
    inferred; TAP-0083 remains Doing.
  - `2026-08-13` Recorded the `bf20b52` implementation handoff: Library loads
    suppress semantically identical snapshot publication; catalog merging and
    thumbnail decoding move off the main actor; viewport observation no longer
    broadly republishes parent state; TAP Video and Share progress apply bounded
    backpressure; and cold-path milestones use low-cardinality, public-safe
    logging. The generic build-for-testing gate passed. Physical-device evidence
    for TAP Video and the large/cold Library remains open under TAP-0045 and
    TAP-0047 respectively, so this implementation handoff does not establish
    attended cold-path acceptance. TAP-0083 remains Doing pending full
    Validation Gate and documentation-handoff reconciliation.

### TAP-0084 — Design a Library-to-Viewer zoom transition with stable top chrome

- Status: `Inbox`
- Kind: `Fix`
- Priority: `P1`
- Domain: `TAP Library / Viewer Transition`
- Labels: `prototype-first`, `navigation-transition`, `zoom`, `shared-element`,
  `matched-geometry`, `photo`, `live-photo`, `video`, `stable-top-chrome`,
  `back-button`, `title-animation`, `media-parity`
- Contract: `ProductContract §5.2`; `§9`; `UIPrototypeContract §1–5`
- Match Keys: `Library grid to Viewer, horizontal push, photo zoom animation,
  shared element, matched geometry, TAP图库 title slides, back button animation,
  grid cell expands, 图片进入动画, 标题滑动, 返回按钮滑动`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Define one Photos-style zoom/shared-element transition from the tapped
  TAP Library grid cell into the selected Viewer media and a corresponding
  return transition when the source cell remains available. Apply the same
  transition contract to Photo, Live Photo, and TAP Video poster entry. The
  Viewer top chrome must appear with stable identity instead of presenting the
  current unrelated horizontal navigation-push motion in which the Library
  title and Back control visibly slide as a page-level title transition.
- States / Decisions Needed: Use the repository Web prototype to decide source-
  cell-visible and source-cell-offscreen return behavior, poster/thumbnail-not-
  ready fallback, interactive cancellation, Reduce Motion fallback, top-chrome
  appearance timing, and whether dismissal is gesture-driven or Back-only. The
  result must preserve the selected media identity and must not flash a
  placeholder when Photo, Live Photo, or TAP Video uses a different renderer.
- Out of Scope: Viewer-internal previous/current/next horizontal paging; changing
  mixed-media order, selected-item identity, RAW/2D/3D behavior, Live Photo/TAP
  Video playback, Share, Delete, cold resource initialization under TAP-0009,
  or reopening accepted TAP-0081/TAP-0082. This Task controls only the Library
  grid-to-Viewer presentation boundary and its reverse transition.
- Prototype Gate: No native change is authorized. Create an exact TAP-0084 Web
  revision covering Photo, Live Photo, and TAP Video entry/return fixtures,
  stable top chrome, source-unavailable fallback, cancellation, and Reduce
  Motion; obtain explicit owner approval before moving to Todo/implementation.
- Done When: The owner approves the exact motion/fallback prototype and scope;
  SwiftUI uses one identity-stable transition contract across Photo, Live Photo,
  and TAP Video without changing Viewer paging; focused tests and native parity
  evidence cover forward/reverse, fallback, cancellation, stable top chrome,
  and Reduce Motion; and any required device-acceptance follow-up is linked.
- Related: `TAP-0058`, `TAP-0059`, `TAP-0048`; observed after accepted
  `TAP-0081`/`TAP-0082` but does not reopen them; independent from `TAP-0009`
- Created: `2026-08-13`
- Updated: `2026-08-13`
- Revision History:
  - `2026-08-13` Allocated after searching all statuses. The owner separated the
    newly observed Library grid-to-Viewer horizontal push/title/Back animation
    from the accepted Share work and asked to keep it for later. Existing
    TAP-0059 remains correctly Done because its completion concerns Viewer-
    internal mixed-media paging, not the Library presentation boundary. Created
    TAP-0084 in Inbox for prototype-first scope decisions; no code, approval,
    Todo/Doing transition, or implementation evidence is inferred.

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
| `TAP-0084` | Fix | P1 | TAP Library / Viewer Transition | `zoom, shared element, stable top chrome, title/back animation, Photo/Live/Video parity` | Approve the exact forward/reverse motion, source-unavailable fallback, cancellation, and Reduce Motion Web prototype before native work | 2026-08-13 | Split from the post-acceptance observation; independent of Viewer paging and TAP Share |

## 6. Device And Visual Acceptance Registry

These Tasks must be expanded with the template in §2.5 and confirmed with the
owner before execution.

| ID | Status | Priority | Related delivery | Scope | Procedure | Dev Session | Human Confirmation | History |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `TAP-0040` | Todo | P0 | `TAP-0008` | Clean install: every setup operation starts only after its corresponding button | [Procedure](Acceptance/TAP-0040-first-install-operations.md) | Unassigned | Pending | Created 2026-08-12 from permission regression; executable draft added 2026-08-12 |
| `TAP-0041` | Todo | P0 | `TAP-0009` | First launch after fresh install/reinstall and app update: Resource Initialization remains until real first frame/safe shutter-controls plus the first usable Library catalog metadata snapshot both succeed, then atomically marks the current update/generation and enters camera; an ordinary repeated launch with the current marker bypasses it; no Retry/Failed/timeout/skip/degraded UI and no Share/iCloud/thumb/hash/ZIP/network/queue prewarm | [Procedure](Acceptance/TAP-0041-camera-readiness.md) must be revised and owner-confirmed for install/update/repeated-launch reset cases, marker persistence/interruption, invariant checkpoint logs, and owner-approved `TAP-0009-r1-candidate` | Unassigned | Pending | Exact Web prototype approved 2026-08-13; native implementation has not started and the existing acceptance draft predates the Library-catalog/versioned-marker invariant, so this remains non-executable until revised |
| `TAP-0042` | Todo | P1 | `TAP-0053` | EV direction, ISO/S clamp, AF→MF, focus assist, front gating, transitions, device matrix | [Procedure](Acceptance/TAP-0042-pro-controls.md) | Unassigned | Pending | Migrated from camera evidence gaps; executable draft added 2026-08-12 |
| `TAP-0043` | Todo | P0 | `TAP-0012` | Standard RGB/depth per FOV and PRO fixed uncropped output | [Procedure](Acceptance/TAP-0043-fov-depth-pro-no-crop.md) | Unassigned | Pending | Created 2026-08-12 from FOV conflict; executable draft added 2026-08-12 |
| `TAP-0044` | Todo | P1 | `TAP-0056` | Live Photo capture, paired MOV, signing, Photos readback, audio and playback | [Procedure](Acceptance/TAP-0044-live-photo-chain.md) | Unassigned | Pending | Migrated from Live Photo evidence gaps; executable draft added 2026-08-12 |
| `TAP-0045` | Todo | P0 | `TAP-0011`, `TAP-0057`, `TAP-0083` | Device codec/drop/RSS/thermal/registration, iCloud-only, broad formats, zero-depth path, and cold complete-original progress that remains responsive under bounded/coalesced UI publication | [Procedure](Acceptance/TAP-0045-tap-video-device.md) must add TAP-0083 cold/progress evidence before that path is executed | Unassigned | Pending | Existing video draft remains; 2026-08-13 added cold progress/backpressure evidence without changing status |
| `TAP-0046` | Todo | P1 | `TAP-0056`, `TAP-0057` | Entitlement, production backend, assertion and final signed-export gate | [Procedure](Acceptance/TAP-0046-app-attest-production.md) | Unassigned | Pending | Migrated from App Attest evidence gaps; executable draft added 2026-08-12 |
| `TAP-0047` | Todo | P1 | `TAP-0058`, `TAP-0059`, `TAP-0083` | Limited access, Photos system delete, pending confirm, adjacency, empty close, plus first cold large-Library entry with no repeated semantic snapshot churn or UI starvation | [Procedure](Acceptance/TAP-0047-library-permission-delete.md) must add a fresh/cleared-cache large-catalog run and structured milestone evidence | Unassigned | Pending | Existing Library draft remains; 2026-08-13 added cold large-catalog responsiveness evidence without changing status |
| `TAP-0048` | Todo | P0 | `TAP-0006` | Approved Web states versus SwiftUI geometry, icons, layout, navigation and state presentation | [Procedure](Acceptance/TAP-0048-web-swiftui-parity.md) | Unassigned | Pending | Created for HTML-first workflow; executable draft added 2026-08-12 |
| `TAP-0049` | Todo | P0 | `TAP-0013` | Locked launch/first-frame/soak/capture/suspend/exit/relaunch | [Blocked Procedure](Acceptance/TAP-0049-locked-camera-lifecycle.md) | Unassigned | Pending | Executable draft added 2026-08-12; cannot run until lifecycle-correct experiment is ready |
| `TAP-0082` | Doing | P0 | `TAP-0081` | Revalidate the fixed system-native file-URL handoff on physical-device Save to Files and AirDrop for representative ordinary media and `.tapnap`, including received/openable artifacts, controller-last-owner source lifetime, and exact-attempt dismissal/teardown isolation; destination completion remains system-owned and no proactive completion callback is allowed; the previously accepted anti-flash and Viewer-toolbar results remain historical | [Procedure and evidence record](Acceptance/TAP-0082-share-handoff.md) records the superseded auto-close condition, native file-URL recovery, and exact four-path matrix Pass; old `bf20b52` Board evidence remains history only | `/root` delivery/evidence reconciliation; product-owner attended retest and self-installation | Four-path attended transport matrix Pass; direct-file-URL checkpoint self-identified by its containing commit; lifecycle/test evidence Pending | Reopened 2026-08-14 after Save to Files selector crash and AirDrop failure; candidate `35745be` later failed ordinary-image and `.tapnap` paths, ruling out a package-only cause. The owner subsequently passed ordinary image plus `.tapnap` through Save to Files plus AirDrop and confirmed every artifact opens. The checkpoint commit containing this record freezes that transport baseline under subject `Checkpoint working Share transport before lifecycle repair`, without a guessed hash. Detailed logs keep lifecycle open: both types trigger system URL probing after controller creation but before coordinator handoff while pending discard can delete the artifact; `.tapnap` dismissal lacks controller-dismantled/`artifactLease` cleanup evidence before the next attempt; and `under50ms` construction precedes `over50ms` controller-construction feedback. Focused tests compiled but were not run. TAP-0082 remains Doing; historical `bf20b52` acceptance remains history and TAP-0084 remains independent. |

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
- `2026-08-12` Allocated `TAP-0081` as a scoped follow-up to completed
  `TAP-0061` after searching all statuses; deprecated direct-share Task
  `TAP-0068` remains deprecated. Recorded owner-approved scope, external visual
  reference evidence, the repository Web-prototype gate, `/root` assignment,
  `main@a4cf808` baseline, Inbox -> Todo -> Doing transitions, 50/400 anti-flash
  policy, explicit non-goals, and the owner-audit blocker against Done.
- `2026-08-12` Allocated `TAP-0082` as the separate attended physical-device
  evidence Task for native system-share destinations and human-visible handoff
  quality. Recorded Inbox -> Todo approval, procedure/evidence requirements,
  fixed-build dependency, pass/fail/blocked rules, and Pending human
  confirmation; advanced Next Task ID to `TAP-0083`.
- `2026-08-12` Assigned approved prototype-foundation Task `TAP-0006` to
  `/root/prototype_contract_audit` on the shared `main@a4cf808` baseline and
  moved it Todo -> Doing. Its bounded delivery is the repository-owned mobile
  Web foundation plus the first TAP Share fixture revision and manifest;
  generated images remain non-canonical evidence, and explicit owner approval
  of the exact repository revision is required before either `TAP-0006` can be
  Done or native `TAP-0081` visual implementation can proceed.
- `2026-08-12` Clarified the active `TAP-0006` milestone without inventing a
  Partial status or changing its Doing state. The owner retained the prototype
  workflow but replaced the heavyweight mobile-Web runtime direction with a
  lightweight statically served HTML/CSS/JavaScript foundation, one extensible
  entry point, and the first TAP Share vertical slice. Later first-install,
  Viewfinder, and other slices remain separate contract-scoped Tasks. Updated
  `TAP-0081` so native work is gated on owner approval of the exact lightweight
  Share revision; neither Task was marked Done.
- `2026-08-12` Recorded the `TAP-0006` / `TAP-0081` prototype handoff for exact
  revision `TAP-0081-r1`: lightweight static entry, manifest, design QA,
  passing static-contract test, exercised browser state paths, 51 ms reveal /
  452 ms system-boundary timing observation for the 120 ms fixture, and two
  repository captures. Confirmed removal of the heavyweight React/Vite runtime
  and synchronized Product Contract §5.3/§9, incremental-slice prototype
  workflow, and root/Docs discoverability. Manifest status remains
  `pendingOwnerReview`; both Tasks stay Doing, with native implementation still
  gated on exact-revision owner approval.
- `2026-08-12` Recorded the owner's explicit approval of exact lightweight Web
  revision `TAP-0081-r1` (“我觉得 web 模拟流程是合理的 请开始实现”). The
  Share-slice prototype gate is satisfied and native `TAP-0081` implementation
  is authorized. `TAP-0006` and `TAP-0081` remain Doing because implementation,
  validation, handoff, documentation reconciliation, and owner audit are still
  open. Only the Board was changed in this stewardship turn; manifest status
  still requires a separately authorized synchronization.
- `2026-08-12` Recorded the native `TAP-0081` implementation handoff while
  retaining Doing status. The former separate app modal and 50/200 progress
  footer are now explicitly historical baseline evidence; current evidence
  identifies the split Share coordinator, anchored popover, stable Viewer
  control, 50/400 policy, UIKit dismissal observer, sibling system activity
  controller, and shared reference-counted temporary-artifact lease. No owner
  audit or Done transition was inferred from implementation readiness.
- `2026-08-13` Recorded the owner-approved `TAP-0081` local-integrity scope
  revision and retained Doing. Viewer browsing may load complete originals from
  local Photos/iCloud, but Share remains unavailable until the required resource
  set is ready. The Share surface derives exported-media state from a local
  check of the actual bytes, never backend/App Attest Verify; Needs Retry remains
  app-private queue-only; missing exported queue records are not failures; and
  local mismatch disables TAPNAP while preserving warned ordinary media share.
  Pre-generation, background prewarming, and persistent caches remain
  prohibited. Current implementation/prototype gaps and the expanded TAP-0082
  device-evidence scope were recorded without claiming completion.
- `2026-08-13` Reconciled the revised `TAP-0081` development handoff and retained
  Doing. Reclassified the earlier record-only/original-readiness findings as a
  closed source gap; recorded complete-original Photo/Live/TAP Video leases,
  exact-resource local byte/content-binding, identity and notification guards,
  mismatch degradation, focused passing test suites, and synchronized module /
  acceptance documentation. Explicitly bounded the local gate: it does not
  cryptographically verify App Attest assertion authenticity or create a new
  backend verdict. `TAP-0081-r2-candidate`, frozen Release/Simulator evidence,
  owner audit, and attended `TAP-0082` evidence remain Pending; neither active
  Task changed status.
- `2026-08-13` Appended final TAP-0081 automated evidence: the unified nine-group
  focused run succeeded for 268 tests, and the generic iOS Simulator Release
  build succeeded. Synchronized the TAP Video pending-signing atomicity
  invariant from `TAPVideoFormatContract §7`: independent working inode,
  `RENAME_SWAP`, preprotected and synchronized temporary record, atomic final
  rename, and failure rollback. Recorded its transient duplicate-video disk and
  I/O cost as an explicit owner-audit tradeoff. `TAP-0081` remains Doing with
  exact r2 approval, frozen commit, Simulator parity, and owner audit Pending;
  `TAP-0082` remains Todo pending attended device evidence.
- `2026-08-13` Added the succeeded one-test Simulator UI evidence for the TAP
  Video pre-player-ready Share path. The native anchored popover appeared after
  complete-original readiness while six Viewer-control frames and RAW selection
  stayed stable. Kept the full parity matrix, exact r2 approval, owner audit,
  and TAP-0082 device evidence Pending; no Task status changed.
- `2026-08-13` Reused active TAP-0081 for the owner-approved Viewer-toolbar
  parity correction rather than allocating a duplicate Task. Recorded the
  current prototype's Share/Delete glyph identities, circular backgrounds, and
  optical concentricity as bounded native visual authority for `/root`; exact
  approval of every `TAP-0081-r2-candidate` state remains pending. Also recorded
  the owner's explicit conversational report that a physical-device Share run
  passed. TAP-0082 moved Todo -> Doing, while its fixed build/commit,
  device/iOS, procedure, per-action evidence, artifacts, and post-icon-change
  confirmation remain open; neither TAP-0081 nor TAP-0082 was marked Done.
- `2026-08-13` Refined the TAP-0081 toolbar visual authority before native
  parity closure: custom prototype Share/Delete vectors occupy 20pt boxes in
  optically concentric 42pt circles equal to Back; the Share progress ring uses
  that same center; and the middle mode capsule remains compact rather than
  flex-fill. The interim 54/25/18/flexible geometry is retained only as
  superseded history. TAP-0081 and TAP-0082 remain Doing, and a post-change
  attended device optical review remains Pending.
- `2026-08-13` Recorded the owner's exact final prototype approval and native
  authorization: “已确认没有问题 请继续实施 Swift UI”. The complete current
  `TAP-0081-r2-candidate`, including 42pt Back-matched circles, concentric 20pt
  custom vectors, shared Share progress-ring center, compact mode capsule, and
  r2 resource/local-integrity states, is now approved SwiftUI authority.
  TAP-0081 and TAP-0082 remain Doing; native parity evidence and the post-build
  physical-device optical review remain Pending.
- `2026-08-13` Appended final-revision device delivery evidence. The Debug
  iphoneos app built with Automatic Development signing (`Apple Development:
  Jinbo Li`, team `UD3269PSCB`), installed, and launched successfully as
  `TAP-NAP.TAPCamDemo` on iPhone 15 Pro (`iPhone16,1`), iOS 26.6, CoreDevice
  `8104D5C9-6503-5A80-BBE3-6BBF1EB04CE7`; artifact is
  `/private/tmp/TAPCamDemo-TAP0081-device/Build/Products/Debug-iphoneos/TAPCamDemo.app`.
  The post-change Simulator run was intentionally skipped per owner instruction.
  Human visual/flow acceptance remains Pending, so TAP-0081 and TAP-0082 stay
  Doing and no Done transition was made.
- `2026-08-13` Appended the owner-approved narrow regression fix: remove
  `CameraView`'s forced outer navigation-bar visibility, gate
  `DepthAlbumPickerView` navigation-bar visibility by `isViewerPresented`, and
  change fallback bottom padding 20 -> 25 to match the prototype. `git diff
  --check` and `node Prototype/prototype.test.mjs` passed; Debug device build,
  install, and launch succeeded again on the same iPhone 15 Pro / iOS 26.6.
  Simulator remained intentionally skipped per owner instruction. Human
  post-fix visual/flow verdict remains Pending, so TAP-0081 and TAP-0082 remain
  Doing and no Done transition was made.
- `2026-08-13` Recorded the later cold-first-Share regression without marking
  TAP-0081 or TAP-0082 Done. The first app-owned selector and subsequent system
  handoff could each wait without visible feedback after install; warm re-entry
  was fast, and logs included custom `.tapnap` LaunchServices/FileProvider
  failures. Kept Share-specific visible-response, typed-UTI/provider,
  activity-presentation, and attempt-lease lifecycle remediation in TAP-0081.
  Superseded the prior delivered artifacts for acceptance and expanded TAP-0082
  to require a true cold reset, first attempt before warm-up, structured
  milestone/cleanup evidence, and a new owner verdict.
- `2026-08-13` Allocated TAP-0083 after the full registry search for the distinct
  cross-cutting cold-path implementation and governance scope: semantic Library
  snapshot suppression, non-broad viewport updates, decoded-thumbnail reuse,
  bounded TAP Video progress publication, public-safe structured milestones,
  and a canonical MainActor/backpressure/presentation-lifecycle standard.
  Recorded owner authorization, Inbox -> Todo -> Doing, `/root` assignment,
  automated gates, and separate physical-device evidence through TAP-0045,
  TAP-0047, and TAP-0082. Advanced Next Task ID to TAP-0084; no completion is
  inferred from diagnosis or a warm run.
- `2026-08-13` Reused Todo TAP-0009 for the owner's new post-Continue Resource
  Initialization decision rather than placing it in Share or allocating a
  duplicate. The revised readiness target is the existing real-first-frame/
  safe-controls gate plus the first usable TAP Library catalog metadata
  snapshot. Recorded explicit exclusions for iCloud originals, all thumbnails,
  proof/hash/ZIP work, system-activity prewarm, App Attest/network, and queue
  batches. TAP-0009 remains Todo until Product Contract §2.4, the exact first-
  install Web prototype, and owner-approved timeout/Retry/degraded behavior are
  synchronized; TAP-0041 now requires a revised attended procedure.
- `2026-08-13` Corrected TAP-0009's owner-approved readiness model before
  implementation. Resource Initialization is a non-degradable invariant that
  remains visible until both camera readiness and the first usable TAP Library
  catalog metadata snapshot succeed; only then may the app enter the
  interactive camera and persist completion. Removed Retry, Failed, timeout,
  skip, and degraded continuation from current Scope, Prototype Gate, Done When,
  and TAP-0041 acceptance scope. Preserved the superseded candidate in append-
  only Task/Board history. Abnormal noncompletion is a malignant bug diagnosed
  through bounded developer checkpoint logs, not a public product branch.
  TAP-0009 remains Todo behind Product Contract synchronization and explicit
  approval of the exact two-state Web prototype; no status changed.
- `2026-08-13` Clarified TAP-0009's cold-trigger and completion-marker semantics.
  Resource Initialization runs on the first launch after fresh install,
  reinstall, and every app update, then writes a separate current-update/
  initialization-generation marker only after camera readiness and the first
  usable Library catalog snapshot both succeed. Missing, stale, mismatched, or
  interrupted completion keeps the gate active; an ordinary repeated launch
  with the current marker skips it. This marker is independent of setup
  permissions and TAP Share and must not prewarm originals, signature/hash,
  ZIP/`.tapnap`, payloads, or system activity UI. TAP-0041 now requires install,
  reinstall/update, interruption, and repeated-launch cases. TAP-0009 remains
  Todo pending Product Contract synchronization and explicit approval of the
  exact revised Web prototype; no status changed.
- `2026-08-13` Recorded the owner's explicit approval of exact Web revision
  `TAP-0009-r1-candidate` (“原型我检查了 没有问题”). The repository prototype,
  first-install resource-initialization fixture, manifest, and design QA now
  supply approved visual authority for install/reinstall/update triggers,
  current-marker repeated-launch bypass, both readiness completion orders, the
  stable invariant, and successful camera handoff without public failure
  branches. Cleared only the TAP-0009 prototype gate; manifest/QA approval
  metadata remains a non-Board synchronization item. Native implementation has
  not started, so TAP-0009 stays Todo. TAP-0081 and TAP-0082 remain Doing
  pending their independent Share remediation and post-fix fresh-install device
  acceptance; no Task moved to Done.
- `2026-08-13` Completed the TAP-0081/TAP-0082 closure audit for frozen commit
  `bf20b52452512aefe745624bd9f80c09355abae5`, whose iphoneos build was installed
  and launched on the recorded iPhone 15 Pro / iOS 26.6. The product owner
  explicitly directed “先把 8182 先给验收掉”, accepting the fixed Share result,
  implementation/process handoff, TAP Video transient-I/O tradeoff, and attended
  device verdict. Moved TAP-0081 Doing -> Done and TAP-0082 Doing -> Done. No
  standalone TAP-0082 file, reset transcript, recording bundle, or received-
  artifact attachment was supplied; the owner explicitly accepted the detailed
  Board record as sufficient, and that evidence exception is preserved rather
  than backfilled with invented details.
- `2026-08-13` Allocated TAP-0084 in Inbox and advanced Next Task ID to TAP-0085.
  The new issue owns a prototype-first Photo/Live Photo/TAP Video Library-grid-
  to-Viewer zoom/shared-element transition, stable title/Back chrome, reverse
  motion, fallback/cancellation, and Reduce Motion decisions. It explicitly
  excludes Viewer-internal horizontal paging, TAP Share, and TAP-0009. The
  post-acceptance observation therefore does not reopen TAP-0059, TAP-0081, or
  TAP-0082; no native implementation is authorized.
- `2026-08-13` Recorded prototype source commit
  `70e8b60d4e20486a6d4847d726b393a50e22c7ba` as the repository evidence that
  manifest and design-QA metadata are `ownerApproved` for exact revisions
  `TAP-0081-r2-candidate` and `TAP-0009-r1-candidate`. This closes metadata
  synchronization only: TAP-0081 and TAP-0082 remain Done, TAP-0009 remains
  Todo, TAP-0083 remains Doing, and TAP-0084 remains Inbox.
- `2026-08-13` Closed TAP-0006 after the final Board audit. Prototype commit
  `70e8b60d4e20486a6d4847d726b393a50e22c7ba` and governance synchronization
  commit `456e30790bdae0b227ae99433e604d0c87f6dfb1` establish the lightweight
  static entry point, TAP Share slice, manifest/design-QA traceability,
  owner-approved exact revision, tests, browser evidence, and documentation
  required by its Done When. The owner explicitly agreed “同意 06 关闭 并提交且
  推送相关代码”. Moved TAP-0006 Doing -> Done in both its canonical record and
  Kanban view. Later prototype slices remain independent Tasks and do not reopen
  this completed foundation milestone; no other Task status changed.
- `2026-08-14` Recorded the owner's deliberate Share-transport reopen after a
  current real-device run on baseline `main@fe0d308`. TAP-0081 moved through
  Done -> Todo -> Doing and is assigned to `/root`; TAP-0082 moved Done -> Todo.
  Save to Files crashed its selector, AirDrop remained waiting without a
  received artifact, and the supplied attachment repeatedly reports `Could not
  load representation public.zip-archive from the item provider for opening in
  place`, so the original typed-handoff Done evidence no longer proves the
  current path. TAP-0081 is fixed to a copy-backed typed `NSItemProvider` plus
  provider-load and temporary-artifact lifetime tests, with no UI/prototype
  change. TAP-0082 now requires the fixed build to pass physical-device Save to
  Files and AirDrop with an inspected received artifact, recorded in
  `Docs/Acceptance/TAP-0082-share-handoff.md`. The `bf20b52` completion and owner
  verdict remain append-only history. No other Task status or Next Task ID
  changed.
- `2026-08-14` Appended the TAP-0081 current implementation handoff and TAP-0082
  pending evidence state without advancing either lifecycle. The app-private
  temporary file is now registered by one copy-backed typed provider using
  `fileOptions: []`, retaining custom TAPNAP UTI first, ZIP fallback, and no
  bare URL. Real provider-load tests cover both load APIs, copied bytes,
  `isInPlace == false`, suggested name, and source-lease lifetime; cleanup adds
  the low-cardinality `tap_share_temp_cleanup_finished` success milestone. The
  DepthAnalysis README and TAP-0082 acceptance record are synchronized, with no
  Share UI copy/text, state, geometry, icon, interaction, or prototype change.
  `git diff --check`, generic Simulator build-for-testing without launching
  Simulator, and generic iphoneos build-for-testing passed. The new provider
  tests passed in two audit runs, but their containing suite failed only on the
  then-stale README wording assertion; that source assertion is repaired and
  the full suite has not been rerun. The iPhone 15 Pro currently reports
  CoreDevice unavailable, the fixed build is not installed, and attended Files
  plus AirDrop artifact acceptance remains Pending. TAP-0081 stays Doing,
  TAP-0082 stays Todo, and no other Task status or Next Task ID changed.
- `2026-08-14` Recorded implementation candidate commit `35745be` (`Fix TAPNAP
  system share transport`) and its successful signed iPhone build without
  claiming installation or runtime acceptance. The tool-driven install stalled
  while Xcode/LLDB retained the previous app process, and LLDB showed the
  expected `SIGKILL` during replacement; this is delivery-tooling evidence, not
  an app crash, pass, or fail. The owner explicitly directed `/root` to stop
  debugging and device operations, self-install the build, and later provide
  Xcode console logs. `/root` immediately cancelled the single active
  `devicectl` install and will perform no further install/debug/launch action.
  Fixed-build install, launch, Files, AirDrop receipt/artifact inspection, and
  owner verdict evidence remain Pending. TAP-0081 remains Doing, TAP-0082
  remains Todo, and no other Task status or Next Task ID changed.
