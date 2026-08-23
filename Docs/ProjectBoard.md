# TAPCam Project Board

- Schema: `1`
- Next Task ID: `TAP-0096`
- Canonical Product Contract: [ProductContract.md](ProductContract.md)
- UI Prototype Contract: [UIPrototypeContract.md](UIPrototypeContract.md)
- Board Steward Session: `019ff4ea-acba-7051-bd0f-3d489f1caadc`
- Last updated: `2026-08-23`

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
- `TAP-0088` Prototype functional Viewfinder-control workload interactions
- `TAP-0089` Prototype functional Photo Viewer analysis workload interactions
- `TAP-0091` Eliminate out-of-preview Viewfinder chrome flicker during camera-path switching

### Todo

- `TAP-0010` Implement first-install Network/App Attest and Setup-receipt lifecycle
- `TAP-0011` Make zero-depth TAP Video non-blocking
- `TAP-0012` Align Standard FOV/depth and PRO no-crop behavior
- `TAP-0013` Rebuild lifecycle-correct Locked Camera on the experiment branch
- `TAP-0014` Remove redundant Verify UX for TAPCam-owned captures
- `TAP-0015` Implement post-setup App Attest/Pending guards and retry optimization
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
- `TAP-0090` Add machine-checkable non-Network startup lifecycle regression evidence

### Doing

- `TAP-0083` Eliminate cold-path UI starvation and codify responsiveness guardrails
- `TAP-0087` Define startup lifecycle, heavy-work budgets, and an instrumented prototype

### Done

- `TAP-0001` Establish the canonical contract, UI workflow, and Markdown board
- `TAP-0002` Reconcile active documents with the Product Contract
- `TAP-0003` Migrate unique facts, then remove obsolete documents
- `TAP-0004` Normalize TAP Library and Pending Capture Queue terminology
- `TAP-0006` Build the repository-owned HTML/Web UI prototype foundation
- `TAP-0008` Enforce explicit-action-only first-install operations
- `TAP-0009` Enforce first-frame camera-interactive readiness
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
- `TAP-0081` Unify TAP Share selection and preparation into an anchored handoff
- `TAP-0082` Device acceptance: TAP Share anchored handoff and anti-flash progress
- `TAP-0085` Restrict the current runtime target to iPhone
- `TAP-0086` Remove Locked Camera integration and entry points from main
- `TAP-0092` Clean up brittle tests, unmounted legacy code, and redundant repository information
- `TAP-0093` Freeze pre-release v1 schemas and remove developer compatibility layers
- `TAP-0094` Establish the documentation-only TAPArtifactContracts repository
- `TAP-0095` Deduplicate migrated artifact-contract prose across source repositories

### Deprecated

- `TAP-0028` Migrate legacy exported GPS copies
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
- Labels: `app-store`, `media`, `6.9-inch`, `iphone`, `rights`
- Contract: `UIPrototypeContract §9`
- Match Keys: `P3, screenshots, store media, device frame, iPhone App Store
  screenshots`
- Assignee: `Product owner`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Decide whether and how to resume 6.9-inch iPhone App Store media after
  the Web prototype foundation exists.
- Out of Scope: iPad store media while the current runtime target is iPhone-
  only; changing runtime platform support; treating Sketch exports as submit-
  ready runtime evidence.
- Done When: The owner approves or rejects a scoped Store task with real-media
  and rights requirements.
- Related: `TAP-0006`, `TAP-0085`
- Created: `2026-08-12`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-12` Migrated unfinished Sketch P3 from implicit roadmap to Inbox.
  - `2026-08-14` Removed iPad media from the active decision after the owner
    set the current TAPCamDemo runtime boundary to iPhone only under TAP-0085.
    The original Universal/iPad scope remains in this history; TAP-0007 stays
    Inbox and now concerns only separately approved 6.9-inch iPhone App Store
    media, asset rights, and submission evidence.

### TAP-0008 — Enforce explicit-action-only first-install operations

- Status: `Done`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Onboarding`
- Labels: `permissions`, `camera`, `photos`, `location`, `microphone`,
  `network`, `app-attest`, `first-install-attestation`, `explicit-action`
- Contract: `ProductContract §2.1–2.6`;
  `Docs/StartupLifecycleContract.md §2, §4`; `Docs/AppAttest/README.md`;
  prerequisite `TAP-0087`
- Match Keys: `launch prompt, Allow button, automatic permission, clean install,
  Network row, first-install App Attest, attestation bootstrap, healthz`
- Assignee: `/root`
- Dev Session: `/root`
- Branch/Worktree: `fix0809`
- Delivered Implementation Scope (`fix0809`): The completed non-Network portion
  of the owner-approved lifecycle corrections introduces a
  structured local `S/P` state-and-routing seam without changing Network or App
  Attest facts/execution, implements row-owned permission-recovery semantics,
  adds the Camera/Photos-only Required Permission Check route, and keeps PhotoKit/
  Library observation inert until the corresponding explicit Photos action
  authorizes it. Focused tests for these bounded seams are included.
- Task-Owned Unmigrated Scope: Network `/healthz` replacement, the required
  initial App Attest bootstrap/retry, canonical credential-bound `S` production
  writer, and restore-binding validation belong to `TAP-0010`. Post-setup App
  Attest and credential/network-dependent Pending Capture release/guard work
  belongs to `TAP-0015`. Those records remain real actual-to-target differences
  under their owning Tasks and are not incomplete TAP-0008 delivery.
- Current Candidate Handoff (`fix0809`, committed as `66ac001`): The bounded
  candidate lands the structured `S/P/I` reducer seam, but intentionally does not connect
  the canonical credential-bound `S` writer to production because that writer
  belongs to TAP-0010; the runtime compatibility input is independently named rather than
  represented as canonical `S`. It adds Camera/Photos Required Permission
  Check, row-owned recovery, and inert/idempotent PhotoKit observation before
  Photos authorization. Network, `/healthz`, App Attest, Network/Pending
  executors, and their retry policies have no direct candidate change. Required
  Permission Check may indirectly postpone existing camera-entry triggers by
  preventing `CameraView` from mounting until Camera/Photos are usable.
- Current Bounded Device Acceptance (`2026-08-15`): The owner exercised the
  `fix0809` bounded non-Network lifecycle flow on a physical device, reviewed
  the resulting behavior, and explicitly accepted that bounded flow. This
  acceptance covers only the implemented slice above; it does not execute the
  complete TAP-0040 first-install matrix, complete TAP-0010/TAP-0015, connect
  canonical credential-bound `S`, approve the complete TAP-0087 v19
  composition, or close TAP-0090. Those are separate Task outcomes and do not
  contradict TAP-0008 Done.
- Product Contract Context: First-Install Setup contains five explicit operations. Network,
  Camera, and Photos are required; Location and Microphone are optional and
  skippable. Camera, Photos, Location, and Microphone may request their system
  prompts only from their corresponding **Allow** actions, with no protected
  work activated beforehand. The Network action exclusively starts the
  bounded first-install App Attest registration/verification bootstrap; a
  generic `/healthz` reachability success does not complete the row. Continue
  requires successful first-install Attestation plus Camera and Photos. After
  setup, ordinary Viewfinder entry and local capture remain network-independent.
- Out of Scope: Changing Network/Camera/Photos required or
  Location/Microphone optional classification; making later App Attest health,
  Pending Capture Queue retry, or future membership networking a normal camera-
  entry gate; implementing TAP-0010's initial credential/Setup-receipt scope
  inside TAP-0008; treating initial credential bootstrap as verification of
  a captured media proof; or implementing the broader startup/work-budget
  prototype owned by TAP-0087.
- Prototype Dependency: Preserve approved `TAP-0008-r2`, including its visible
  Network row and non-system-permission presentation. `TAP-0087-r1-candidate`
  must keep the state-machine/inspector meaning as first-install App Attest
  completion. Native Network/App Attest completion now belongs to TAP-0010;
  completing TAP-0008's non-Network delivery does not approve the complete v19
  composition. The previously recorded no-Network Setup candidate is historical
  only and is not part of the current prototype gate.
- Responsibility Boundary: The non-Network local lifecycle placement completed
  here covers explicit Camera/Photos/Location/Microphone action ownership,
  row-owned permission recovery, Camera/Photos Required Permission Check,
  structured local route inputs, and permission-safe PhotoKit observation.
  `networkBootstrap` plus its initial App Attest meaning is delivery owned by
  `TAP-0010`; the App Attest/Pending children of deferred release are delivery
  owned by `TAP-0015`. Active prototype copy must identify those Task IDs
  directly rather than using a session-relative freeze label.
- Done When: The non-Network local lifecycle seams above are implemented in the
  target route positions, focused tests pass, the physical-device executed path
  has an owner-accepted bounded verdict, and every unexecuted regression or
  cross-boundary behavior has one separate owner. `TAP-0090` owns reusable
  structured regression evidence; `TAP-0040` owns full attended first-install
  evidence; `TAP-0010` and `TAP-0015` own the unmigrated credential/Network/
  Pending behavior. Those open Tasks do not keep this delivery Task open.
- Related: Common prerequisite `TAP-0087`; regression evidence `TAP-0090`;
  acceptance `TAP-0040`; visual parity `TAP-0048`; historical
  classification `TAP-0050`; retry alignment/re-scope `TAP-0010`;
  post-setup credential optimization `TAP-0015`; production App Attest evidence
  `TAP-0046`; deprecated implicit-trigger behavior `TAP-0063`
- Created: `2026-08-12`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-12` Expanded from Photos-only to every first-install action.
  - `2026-08-12` Repository audit added early Photo Library observer
    registration and startup poster backfill as explicit implementation paths
    that must be removed or proven inert before the corresponding Allow action.
  - `2026-08-14` Classified the latest cold/overwrite-install device log without
    changing status. The excerpt begins after runtime startup work and contains
    no setup-row/button timeline, so it neither proves nor disproves an
    explicit-action violation. TAP-0008 remains Todo, and TAP-0040 still owns a
    separate clean-install run that starts before the first setup interaction;
    Share completion under TAP-0081/TAP-0082 supplies no substitute evidence.
  - `2026-08-14` Added owner-approved common prerequisite `TAP-0087`. Its
    canonical install/activation taxonomy, required-permission recovery route,
    t0…tn timing contract, workload map, and linked prototype inspector must be
    established before this Task implements the native setup trigger boundary.
    TAP-0008 remains Todo with its scope and prior history unchanged.
  - `2026-08-14` Owner superseded the Network-onboarding policy before native
    implementation: ordinary camera entry/capture is network-independent;
    Camera and Photos are the only required Setup rows; Location and Microphone
    remain optional; and every permission prompt still belongs exclusively to
    its corresponding explicit action. Revised the current target from five
    operations to four permission rows, removed the desired `/healthz`
    preflight/Network row, and linked owner approval of superseding
    `TAP-0008-r3-candidate` through TAP-0087. Earlier Network policy and audit
    entries remain historical evidence and are not rewritten. TAP-0008 stays
    Todo.
  - `2026-08-14` Owner urgently corrected the immediately preceding no-Network
    direction. Fresh Installation requires the explicit Network row because it
    must complete first-install App Attest registration/verification; generic
    `/healthz` reachability is not completion. Restored Network/Camera/Photos as
    required, Location/Microphone as optional, and Continue as gated by
    Attestation + Camera + Photos. Preserved ordinary post-setup Viewfinder and
    capture as network-independent and kept later credential/Pending work out
    of the normal camera-entry gate. Restored TAP-0008-r2's visible Network row
    and delegated its corrected state-machine/inspector semantics to
    TAP-0087-r1-candidate. The false interim direction above remains history;
    TAP-0008 remains Todo.
  - `2026-08-15` Owner confirmed `networkBootstrap` as a real current-main
    mismatch but deferred its fix from the bounded `fix0809` pass. The current
    Network/App Attest implementation remains unchanged for this pass, the
    mismatch remains visible, and `/healthz` remains an observed current state
    rather than the target state. This partial decision supplies no native
    implementation, focused tests, attended TAP-0040 evidence, whole-prototype
    approval, or Done condition; TAP-0008 remains Todo.
  - `2026-08-15` Follow-up clarification applied the same Network/App Attest
    freeze inside the broader approved `deferredWorkGuard`: App Attest
    maintenance and credential/network-dependent or Network-owned Pending
    Capture recovery scheduling are deferred from `fix0809`. Only non-Network/
    App-Attest children such as video-poster backfill and recent-cover guard
    placement remain approved. This narrows implementation scope without
    changing TAP-0008 status, acceptance, or completion evidence.
  - `2026-08-15` Owner explicitly directed implementation to begin on branch
    `fix0809`. Board Steward moved TAP-0008 Todo -> Doing, assigned Assignee and
    Dev Session `/root`, and authorized only the structured non-Network `S/P`
    seam, permission recovery, Camera/Photos Required Permission Check, and
    pre-Photos observer-inert boundary. Network behavior, `/healthz`, all App
    Attest implementation, and credential/network-dependent or Network-owned
    Pending Capture recovery scheduling remain hard-frozen. This records
    development start only: no Done result, acceptance evidence, or approval of
    the complete TAP-0087 v16 composition is inferred.
  - `2026-08-15` Recorded the uncommitted bounded candidate handoff. The
    structured `S/P/I` reducer seam, Camera/Photos Required Permission Check,
    row-owned recovery, and inert/idempotent pre-authorization PhotoKit observer
    boundary are present; canonical credential-bound `S` remains unwired under
    the Network freeze and the legacy compatibility input is independently
    named. Required Permission Check can indirectly delay existing camera-entry
    triggers by withholding `CameraView`, but Network, `/healthz`, App Attest,
    Network/Pending executors, and retry policy have no direct modification.
    `build-for-testing` passed for iPhone 17 Pro / iOS 26.5; the latest
    `/private/tmp/TAPCamDemo-fix0809-final-v4.xcresult` reports 146/146 tests
    passed with 0 failed or skipped; Prototype tests report 58/58; MJS checks,
    manifest parse, and `git diff --check` pass. Native visual parity, physical-
    device acceptance, canonical credential-bound `S`/restore end-to-end
    coverage, and complete W11/W12 `t5` release remain unrun, blocked, or frozen.
    TAP-0008 remains Doing; no commit, Done, acceptance, or complete-v16 approval
    is claimed.
  - `2026-08-15` Superseded only the preceding handoff's physical-device
    evidence status: the owner exercised the bounded non-Network `fix0809`
    lifecycle flow on a physical device and explicitly accepted that bounded
    flow. The complete TAP-0040 first-install matrix remains open, and the
    Network/App Attest/Pending hard freeze, canonical credential-bound `S` gap,
    complete-v16 approval boundary, TAP-0008 Doing status, and full Done When
    remain unchanged.
  - `2026-08-15` Synchronized the active handoff after Git created commit
    `66ac001`. This supersedes only the active candidate's earlier
    `uncommitted` label; the earlier entry remains an accurate historical
    pre-commit record. TAP-0008 stays Doing, and no new implementation,
    acceptance scope, Network/App Attest/Pending behavior, Done result, complete
    v16 approval, or push is inferred from the commit fact.
  - `2026-08-15` Owner approved the final delivery/evidence responsibility
    split. The non-Network native lifecycle placement committed in `66ac001`
    is the completed TAP-0008 delivery: explicit permission action ownership,
    row recovery, Required Permission Check, structured local route inputs, and
    permission-safe observer activation. Network `/healthz` replacement,
    initial App Attest/bootstrap/retry, canonical credential-bound `S`, and
    restore binding now belong to TAP-0010; post-setup App Attest and credential/
    network-dependent Pending guards belong to TAP-0015. TAP-0090 owns the
    derived machine-checkable regression evidence, TAP-0040 retains attended
    device evidence, and TAP-0048 retains visual parity. Moved TAP-0008 Doing ->
    Done without claiming those separate Tasks complete. Historical references
    to a bounded pass or freeze remain append-only facts; active ownership is
    now expressed by stable Task IDs.

### TAP-0009 — Enforce first-frame camera-interactive readiness

- Status: `Done`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Onboarding`
- Labels: `readiness`, `first-frame`, `shutter`, `controls`, `freeze-prevention`,
  `resource-initialization`, `library-catalog`, `cold-install`, `reinstall`,
  `app-update`, `versioned-marker`, `prototype-first`
- Contract: `ProductContract §2.4–2.6`; candidate route semantics in
  `Docs/StartupLifecycleContract.md §1–2, §4` (exact owner approval remains
  pending under `TAP-0087`)
- Match Keys: `Continue, camera ready, interactive, loading gate, page freeze,
  resource initialization, please wait, first Library snapshot, first launch,
  reinstall, app update, versioned completion marker, repeated launch,
  首次安装, 重新安装, 应用更新, 资源初始化, 请稍候`
- Assignee: `/root`
- Dev Session: `/root`
- Branch/Worktree: `fix0809`
- Compatibility Responsibility: The delivered non-Network slice consumes the
  current legacy Setup compatibility seam. The canonical credential-bound,
  Network-owned `S` writer and its restore binding belong to `TAP-0010`; the
  production route consumes an independently named
  legacy compatibility input rather than representing that input as canonical
  `S`. TAP-0009 must not change when or how Network, `/healthz`, or App Attest
  completes or writes Setup state.
- Delivered Implementation Scope (`fix0809`): The candidate adds an independent,
  versioned `I`; requires one camera group comprising a real preview frame, safe
  primary controls/shutter, and required haptics plus one Library group
  comprising the first usable identity/order catalog snapshot, including a
  successful empty catalog; commit `I` and leave the stable Resource
  Initialization surface only after both groups succeed. Resource Initialization
  exposes no product Retry, Failed, timeout, skip, or degraded branch.
- Task-Owned Unmigrated Scope: Network `/healthz` replacement, initial App
  Attest/bootstrap/retry, canonical credential-bound `S`, and restore-binding
  validation belong to `TAP-0010`. Post-setup App Attest and credential/network-
  dependent Pending Capture release/guard behavior belongs to `TAP-0015`.
  Measured route-shell/real-first-frame placement belongs to `TAP-0083`.
- Product Contract Context: Drive startup from the structured `S — SetupReceipt`,
  `P — RequiredPermissionSnapshot`, and `I — InitializationCompletion` facts.
  Resource Initialization is selected only after `S` is valid and `P` is usable
  when `I` is absent, corrupt, or stale. Fresh Installation and
  Delete-and-Reinstall therefore reach it after First-Install Setup and
  Continue. An In-place App Update reaches it only when the current version,
  build, or schema makes `I` stale. A Development Replacement Install follows
  the facts actually retained: a current `I` bypasses the gate and an absent or
  stale `I` enters it. Offload-and-Reinstall with the current build and valid
  preserved `S/P/I` bypasses the gate even when caches are cold; a changed build
  or stale `I` enters it after permission routing. Same-Device Backup Restore
  and Cross-Device Migration Restore revalidate the Setup credential binding
  and the installation/device generation carried by `I`; an invalid `S` routes
  to Setup recovery, unusable `P` routes to Required Permission Check, and only
  the remaining absent/stale `I` case reaches Resource Initialization. Local
  State Inconsistency treats each invalid fact as absent rather than guessing an
  installation label. Once selected, keep the state until both readiness groups
  complete: (a) capture graph, real first preview frame, primary controls,
  shutter, and required haptics are safe; and (b) the first usable TAP Library
  catalog metadata snapshot is available. A successful empty catalog is usable;
  the gate owns catalog identity/order metadata only, not media bytes or visual
  decoding. This two-group gate is an invariant, not a best-effort operation:
  persist its versioned completion marker and enter the interactive camera only
  after both groups succeed. The only product-visible transition is
  `Resource Initialization -> interactive camera`.
- Trigger / Versioned Completion Marker: Resource Initialization has its own
  persisted `I` marker, distinct from `S` and `P`. Installation terms are
  diagnostic scenario metadata, not direct triggers. After the higher-priority
  `S/P` checks, an absent or corrupt `I`, or a mismatch in its Bundle ID,
  version, build, initialization schema, or required installation/device
  generation triggers the gate. Write the current `I` atomically only after
  both readiness groups succeed; an interrupted or abnormally incomplete run
  must leave it absent/stale so the next launch remains in the gate. Any launch
  with valid `S`, usable `P`, and an exactly current `I` bypasses this resource
  setup regardless of the colloquial install label or whether caches are cold.
- Current Behavior / Candidate Handoff (`fix0809`, committed as `66ac001`):
  Product Contract §2.4–2.5 and exact owner-approved Web revision
  `TAP-0009-r1-candidate` remain the bounded visual authority. The candidate now
  implements independent versioned `I`; a camera readiness group gated by an
  active scene, capture configuration, a real preview frame, safe primary
  controls/shutter, and required haptics; a first-usable Library identity/order
  catalog group including successful empty state; and a stable Resource
  Initialization surface with no product Retry branch. `I` uses an Application
  Support staged-file plus replace/rename two-phase atomic commit;
  `installationGenerationID` is stored in UserDefaults, while
  `deviceGenerationID` and its corrupt-state repair use ThisDeviceOnly Keychain.
  After the two readiness groups publish stable completion, two display ticks
  release only the local poster/recent-cover and App Intent deferred work in this
  candidate.
  The source placement for `returningCameraConstruction` is delivered here;
  `Task.yield` is not measurement proof that a real lightweight route-shell
  frame committed before camera construction, so that evidence and any timing
  correction remain explicitly owned by `TAP-0083` rather than TAP-0009.
- Current Validation: `build-for-testing` passed for iPhone 17 Pro on iOS 26.5.
  The latest `/private/tmp/TAPCamDemo-fix0809-final-v4.xcresult` reports 146/146
  tests passed, 0 failed, and 0 skipped. Prototype tests report 58/58; MJS
  checks, manifest parse, and `git diff --check` also pass. The owner also
  exercised the bounded non-Network `fix0809` lifecycle flow on a physical
  device and explicitly accepted that bounded flow. This remains an
  owner-accepted bounded candidate committed as `66ac001`; it is not execution
  of the complete TAP-0041 matrix.
- Current Handoff — Files Updated / Contract Decision:
  `Docs/ProductContract.md` synchronizes the Resource Initialization subtitle
  from the old `Please Wait` form to the exact owner-approved fixture/native
  copy `Please wait…`. `TAPCamDemo/CameraCapture/UI/README.md` records only a
  selected route-shell state followed by a later MainActor turn and explicitly
  does not claim a real shell-frame proof. These documentation updates do not
  approve the complete TAP-0087 v19 composition or close TAP-0041/TAP-0048.
- Post-Delivery Validation And Separate Ownership: `TAP-0090` owns reusable
  structured non-Network regression evidence; `TAP-0041` owns the remaining
  attended scenario/fault-injection verdict; `TAP-0048` owns exact visual
  parity; and `TAP-0083` owns real route-shell/first-frame placement and timing.
  Canonical credential-bound `S`/restore belongs to `TAP-0010`, while W11 App
  Attest/W12 Pending Capture release/guards belong to `TAP-0015`. None is an
  unfinished TAP-0009 delivery item after the approved responsibility split.
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
  supplies the foundation but does not absorb this later vertical slice. Its
  earlier broad install/update fixture labels are visual inputs only and do not
  define Offload, replacement-install, or restore routing; the exact
  TAP-0087-r1 canonical scenario overlay/inspector remains a candidate requiring
  owner approval.
- Done When: The non-Network native target placement is present for independent
  versioned `I`, Camera/Photos permission routing, the camera-plus-first-usable-
  catalog readiness invariant, atomic marker commit/interruption behavior,
  stable Resource Initialization without a product failure branch, and local
  post-frame deferred release; focused tests and the owner-accepted bounded
  device path pass. Separate regression, visual, attended, measured-timing, and
  credential/Pending owners are linked explicitly and may remain open without
  reopening this delivery Task.
- Related: Common prerequisite/prototype `TAP-0087`; regression evidence
  `TAP-0090`; attended evidence `TAP-0041`; visual parity `TAP-0048`; measured
  route-shell/first-frame placement `TAP-0083`; initial credential/`S`/restore
  `TAP-0010`; post-setup App Attest/Pending `TAP-0015`; `TAP-0006`, `TAP-0047`
- Created: `2026-08-12`
- Updated: `2026-08-15`
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
  - `2026-08-14` Added a diagnostic baseline from the owner's latest cold/
    overwrite-install session: the first usable 908-item catalog snapshot
    completed in `7795 ms`. This is evidence for the second readiness group in
    the approved Resource Initialization invariant, not implementation or
    acceptance. The excerpt does not contain a first-frame checkpoint, safe
    shutter/control/haptics readiness, an initialization-version marker write,
    interruption behavior, or current-marker repeated-launch bypass. TAP-0009
    therefore remains Todo and TAP-0041 still requires its independently
    revised clean-install/reinstall/update procedure. TAP-0081/TAP-0082 closure
    does not absorb or close this work.
  - `2026-08-14` Added owner-approved common prerequisite `TAP-0087`. It must
    freeze the behavior-bearing install/activation vocabulary, deterministic
    route/marker matrix, t0…tn/Δ work budgets, heavy-work ownership map, and
    instrumented prototype context before this Task revises native readiness.
    Existing approved phone visuals for `TAP-0009-r1-candidate` remain intact;
    TAP-0009 stays Todo and no implementation or acceptance is inferred.
  - `2026-08-14` Replaced the current target's ambiguous “fresh install,
    reinstall, and every app update” trigger with the candidate canonical
    `S/P/I` reducer and exact installation terms. In particular, current-build
    Offload-and-Reinstall with valid preserved `S/P/I` bypasses Resource
    Initialization, while changed-build/stale-`I` Offload, stale In-place App
    Update, and stale-fact Development Replacement Install enter it only through
    the reducer; Delete-and-Reinstall and restore cases are now distinct. Old
    broad wording above remains historical context. TAP-0009 stays Todo, and no
    approval of the exact StartupLifecycleContract/TAP-0087 candidate,
    implementation, validation, or TAP-0041 acceptance is inferred.
  - `2026-08-15` Owner explicitly approved and directed native implementation
    to begin for the prototype-gate-satisfied TAP-0009 slice on branch
    `fix0809`. Board Steward moved TAP-0009 Todo -> Doing and assigned Assignee
    and Dev Session `/root`. The bounded work depends on the current legacy
    Setup compatibility seam and hard-freezes the canonical Network-bound `S`
    writer; it implements only independent versioned `I`, the real-preview/
    safe-controls-and-shutter/required-haptics camera group, the first-usable-
    catalog Library group, and the stable Resource Initialization surface with
    no product Retry branch. Network, `/healthz`, App Attest, and credential/
    network-dependent Pending Capture scheduling remain frozen. This is a start
    transition only: no Done result, TAP-0041 device acceptance, or approval of
    the complete TAP-0087 v16 composition is inferred.
  - `2026-08-15` Recorded the uncommitted native candidate handoff: independent
    versioned `I`; active-scene configuration plus real preview, safe controls/
    shutter, and haptics; first usable Library catalog; stable no-Retry Resource
    Initialization; two-phase Application Support atomic `I` commit with
    Keychain corrupt repair; and two-display-tick release of only local poster/
    recent-cover and App Intent work. `returningCameraConstruction` remains
    partial because `Task.yield` does not prove a real route-shell frame.
    Network, `/healthz`, App Attest, Network/Pending executors, and retry policy
    have no direct change; the canonical credential-bound `S` writer and full
    W11/W12 `t5` remain blocked/frozen. `build-for-testing` passed for iPhone 17
    Pro / iOS 26.5; `/private/tmp/TAPCamDemo-fix0809-final-v4.xcresult` reports
    146/146 passed with 0 failed/skipped; Prototype reports 58/58; MJS checks,
    manifest parse, and `git diff --check` pass. Native visual parity and
    physical-device acceptance remain unrun. TAP-0009 stays Doing; this is not a
    commit, Done transition, TAP-0041 verdict, or complete-v16 approval.
  - `2026-08-15` Recorded the documentation/contract handoff:
    `Docs/ProductContract.md` now uses exact Resource Initialization subtitle
    `Please wait…` instead of the old `Please Wait` form, matching the approved
    fixture and native candidate. `TAPCamDemo/CameraCapture/UI/README.md`
    narrows the returning route-shell statement to a selected shell state plus
    a later MainActor turn, explicitly not proof of a real committed frame.
    This copy/evidence-boundary synchronization does not change TAP-0009 Doing,
    provide visual/device acceptance, or approve the complete TAP-0087 v16
    composition.
  - `2026-08-15` Corrected the handoff's storage-topology shorthand without
    changing implementation scope: `installationGenerationID` is UserDefaults-
    backed; `deviceGenerationID` and its corrupt-state repair use ThisDeviceOnly
    Keychain. The Application Support staged-file plus replace/rename path owns
    the two-phase atomic `I` record commit. This clarification prevents restore
    evidence from being read as if Keychain owned both generation identities.
  - `2026-08-15` Superseded the earlier “physical-device acceptance remains
    unrun” evidence status for the bounded candidate: the owner exercised the
    non-Network `fix0809` lifecycle flow on a physical device and explicitly
    accepted that bounded flow. Exact native visual parity and the complete
    TAP-0041 scenario/fault-injection matrix remain open; canonical credential-
    bound `S`, restore end-to-end coverage, and complete W11/W12 `t5` release
    remain blocked or frozen. TAP-0009 stays Doing because this bounded verdict
    does not satisfy its complete Done When or approve TAP-0087 v16 as a whole.
  - `2026-08-15` Synchronized the active handoff after Git created commit
    `66ac001`. This supersedes only the active candidate's earlier
    `uncommitted` label; the earlier entry remains an accurate historical
    pre-commit record. TAP-0009 stays Doing, and no new implementation,
    acceptance scope, frozen Network/App Attest/Pending behavior, Done result,
    complete-v16 approval, or push is inferred from the commit fact.
  - `2026-08-15` Owner approved delivery/evidence separation and accepted the
    committed non-Network native target placement as the completed TAP-0009
    delivery. TAP-0090 now owns reusable structured regression evidence;
    TAP-0041 retains attended scenario/fault-injection evidence; TAP-0048 owns
    visual parity; TAP-0083 owns measured route-shell/real-first-frame placement
    and the four-cell timing matrix; TAP-0010 owns initial Network/App Attest,
    canonical credential-bound `S`, and restore binding; and TAP-0015 owns
    post-setup App Attest/Pending guards. Moved TAP-0009 Doing -> Done without
    claiming any of those separate Tasks complete or approving the complete
    TAP-0087 composition. Historical bounded/frozen wording remains append-only
    context and is superseded for active ownership by these stable Task IDs.

### TAP-0010 — Implement first-install Network/App Attest and Setup-receipt lifecycle

- Status: `Todo`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Onboarding`
- Labels: `network`, `app-attest`, `setup-receipt`, `credential-binding`,
  `restore`, `retry`, `timeout`, `manual-action`
- Contract: `ProductContract §2.3`;
  `Docs/StartupLifecycleContract.md §2, §4`; related state-machine decision in
  `TAP-0087`
- Match Keys: `security preflight retry, first-install App Attest retry,
  attestation bootstrap, healthz, foreground retry, canonical S writer,
  SetupReceipt, restore credential binding, networkBootstrap`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Own the complete task-visible behavior that was deliberately not
  migrated with TAP-0008/TAP-0009: replace `/healthz` completion with the
  required Network-row App Attest registration/verification bootstrap; preserve
  bounded automatic attempts and post-timeout explicit Retry; prevent
  foreground/status refresh from silently starting a new sequence; write the
  canonical credential-bound `S — SetupReceipt` only after the required setup
  facts and Continue; and validate local credential binding for retained or
  restored receipts without treating Keychain residue as setup completion.
  Ordinary post-setup Viewfinder entry and local capture remain network-
  independent.
- Responsibility Decision: The owner retained this as the stable implementation
  Task rather than merging it back into completed TAP-0008/TAP-0009. Active
  prototype records for `networkBootstrap`, first-install credential start/
  completion meaning, canonical `S`, and restore binding must link TAP-0010
  directly and remain true actual-to-target differences until this Task ships.
- Out of Scope: Post-setup credential health/re-attestation and Pending Capture
  Queue retry optimization owned by TAP-0015; future membership networking; or
  requiring network for ordinary Viewfinder entry or local capture; capture-
  proof verification is not the first-install bootstrap success condition.
- Done When: Product/Startup contracts, prototype records, native behavior, and
  focused tests agree on explicit first-install App Attest bootstrap ownership,
  bounded attempts/timeout/manual Retry, canonical credential-bound `S` commit,
  retained/restore binding validation, and network-independent post-setup
  camera entry. `/healthz`, foreground refresh, and stale Keychain residue
  cannot satisfy or restart the operation. TAP-0040/TAP-0046 remain separate
  attended/production evidence Tasks.
- Related: Historical foundation `TAP-0051`; completed non-Network delivery
  `TAP-0008`, `TAP-0009`; common semantic/prototype owner `TAP-0087`; attended
  first-install evidence `TAP-0040`; production App Attest evidence `TAP-0046`;
  separate post-setup credential/Pending delivery `TAP-0015`
- Created: `2026-08-12`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-12` Owner selected bounded automatic attempts followed by manual retry.
  - `2026-08-12` Repository audit identified a refresh path that can restart
    the preflight after denial; implementation must keep that action inside the
    active bounded sequence or a new explicit Retry.
  - `2026-08-14` Owner removed the Network row and onboarding `/healthz`
    preflight from the current product: ordinary camera entry and capture are
    network-independent. Moved TAP-0010 Todo -> Deprecated as a superseded
    onboarding task while preserving its prior decision/audit history. App
    Attest retry remains outside scope under TAP-0015, and no membership
    networking behavior is invented.
  - `2026-08-14` Owner urgently corrected the immediately preceding decision:
    Fresh Installation retains a required Network row whose success condition
    is first-install App Attest registration/verification, not `/healthz`.
    Restored TAP-0010 Deprecated -> Todo by explicit owner decision. Its exact
    replacement/merge with TAP-0008 remains a TAP-0087 re-scope decision, so no
    implementation is authorized yet. Later credential/Pending retry remains
    TAP-0015 scope, and ordinary post-setup camera entry/capture stays network-
    independent. The false interim deprecation remains append-only history.
  - `2026-08-15` Owner resolved the prior re-scope gate through delivery/
    evidence separation. Expanded TAP-0010 from retry mechanics to the complete
    unmigrated initial Network/App Attest boundary: real bootstrap completion,
    canonical credential-bound SetupReceipt commit, and retained/restore local-
    binding validation. Raised priority P1 -> P0 because this operation is a
    required first-install gate. TAP-0008/TAP-0009 remain closed over their
    completed non-Network delivery; post-setup W11/W12 work remains TAP-0015.
    TAP-0010 stays Todo and no Network/App Attest implementation or evidence is
    inferred.

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

### TAP-0015 — Implement post-setup App Attest/Pending guards and retry optimization

- Status: `Todo`
- Kind: `Technical`
- Priority: `P1`
- Domain: `App Attest / Pending Capture Queue`
- Labels: `credential`, `app-attest`, `pending-capture`, `deferred-work`, `t5`,
  `guard`, `retry-window`, `cooldown`, `pause`
- Contract: `ProductContract §2.4, §6`; `StartupLifecycleContract §3–4`
- Match Keys: `nextAttemptAt, retry budget, credential stage, assertion stage,
  post-setup App Attest, W11 W12, Pending recovery guard, t5 release`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Scope: Move post-setup App Attest health/recovery (`W11`) and credential/
  network-dependent Pending Capture recovery (`W12`) behind the canonical
  deferred-work release and their camera-idle/protected-data/credential guards,
  without making either a route, preview, shutter, or local-capture blocker.
  Within that owner boundary, separate credential/assertion/export retry stages
  and add the approved bounded cooldown/window/pause state from one clean current
  persistence shape with stale/cancel handling.
- Responsibility Decision: Active prototype records for post-setup App Attest
  and Pending recovery are true task-owned actual-to-target differences and
  link TAP-0015 directly. They are not incomplete TAP-0008/TAP-0009 work and
  must not use a session-relative freeze label.
- Out of Scope: Initial Network-row App Attest/bootstrap, retry, canonical `S`,
  and restore binding owned by TAP-0010; non-Network local poster/recent-cover/
  App Intent release completed by TAP-0009; or treating this technical work as
  a new ordinary camera-entry gate.
- Done When: W11/W12 cannot become eligible before the committed deferred-work
  release and their required guards; neither blocks route/preview/interaction/
  local capture; the approved stage-specific retry model and current persistence,
  scheduling, cancellation/stale behavior, and focused tests are implemented;
  and prototype records no longer show those Task-owned placement differences.
- Related: `ProductContract §6`, `TAPCamDemo/TAPLibrary/README.md`; completed
  non-Network delivery `TAP-0008`, `TAP-0009`; initial credential owner
  `TAP-0010`; prototype owner `TAP-0087`; structured non-Network evidence
  `TAP-0090`
- Created: `2026-08-12`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-12` Classified as future technical optimization.
  - `2026-08-12` Migrated the current coarse model to the Pending Capture Queue
    module README and retired the superseded standalone design document.
  - `2026-08-15` Owner assigned the unmigrated post-setup lifecycle boundary to
    this existing Task rather than creating another duplicate. Expanded scope
    to place W11 App Attest health/recovery and W12 credential/network-dependent
    Pending recovery after canonical deferred release with camera-idle/
    protected-data/credential guards, while retaining the existing fine-grained
    retry/migration work. Raised priority P2 -> P1. TAP-0015 remains Todo; no
    executor, retry, prototype, test, or evidence completion is inferred.
  - `2026-08-23` TAP-0093 superseded only the earlier development-data migration
    requirement. TAP-0015 must introduce one current pre-release persistence
    shape from a cleared container and carries no upgrade reader for old
    development records. Its deferred-work, retry, cancellation, and stale-work
    responsibilities remain Todo and unchanged.

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

- Status: `Deprecated`
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
  - `2026-08-23` Deprecated under TAP-0093's owner-approved pre-release reset
    policy. Current export completion already clears precise location from the
    retained record; old development containers are deleted/reinstalled rather
    than migrated. No current pre-export location use or Photos metadata is
    removed by this decision.

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
- Related: `TAP-0092`
- Created: `2026-08-12`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-12` Combined closely related test-only debt during board bootstrap.
  - `2026-08-12` Historical R1–R4 production splits and most source-spelling
    assertions were already completed; remaining scope is only Debug support
    isolation and oversized test-suite organization.
  - `2026-08-15` Kept this Task's structural scope intact after the repository-
    health audit created `TAP-0092` for the separate semantic cleanup of brittle
    tests, unmounted legacy code, and redundant or conflicting active prose.

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

- Status: `Done`
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
  selection. Before preparation, each option row shows its normal subtitle
  text. Selecting a Share type keeps the selector hierarchy mounted and
  immediately replaces only that clicked row's subtitle text, inside the same
  fixed slot, with a 2px determinate progress track. No percentage or Cancel
  control appears; every sibling option remains visible but disabled. The
  title, icon, recommendation badge, row, popover, sibling geometry, and view
  identity remain stable. There is no whole-popover preparation page and no
  separate app-owned ready/boundary page. As soon as the payload is ready,
  TAPCam closes the popover. Only after the real popover-dismissal/system-sheet
  presentation boundary may TAPCam construct `UIActivityViewController`; it
  must not preconstruct the controller or trigger LaunchServices/FileProvider
  probing while the app-owned popover is still visible. Photo, Live Photo, and
  TAP Video use the same presentation and
  lifecycle while retaining their existing capability matrix. Synchronize
  the Viewer toolbar with the refined approved prototype treatment: Share and
  Delete use the prototype's custom vector glyphs in 20pt boxes, optically
  centered in 42pt circular backgrounds matching the top-left Back button.
  The middle `RAW / 2D / 3D` mode capsule remains compact and centered at its
  intrinsic approved width; it must not flex-fill the remaining toolbar space.
  The Viewer Share control's existing pre-selector resource-readiness ring must
  use the same 42pt control center without moving or resizing the 20pt vector;
  it is not the selected option's payload-preparation indicator.
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
  ready media determines the result. Idle format selection shows normal
  subtitle text. Preparation keeps the selector hierarchy mounted and swaps
  only the clicked row's fixed subtitle slot to an immediately visible 2px
  determinate track; title, icon, badge, row, popover, sibling geometry, and
  identity do not change, and sibling options remain visible but disabled. No
  percentage or Cancel control is shown. Payload-ready popover dismissal,
  completed handoff, and recoverable preparation failure remain part of the
  same state machine. The former 50 ms delayed reveal and 400 ms minimum-visible
  hold are superseded and
  must be removed; payload readiness, not an artificial timer, whole-popover
  preparation page, or app-owned ready page, advances the flow. After
  the popover has actually disappeared, TAPCam constructs the controller at the
  real system-sheet boundary and presents it without preconstruction or early
  system probing. Destination selection, transfer progress, completion, and
  dismissal remain system-owned once the activity controller is presented;
  TAPCam does not install a destination-completion callback to proactively
  close that controller.
- Failure / Recovery: There is no app-owned Cancel control during preparation.
  If the app-owned presentation is torn down before system handoff, the active
  preparation stops and its per-attempt temporary directory is removed when no
  system handoff owns that source. A public-safe preparation failure remains in
  the anchored surface and offers
  Retry for the same option. Dismissing the app-owned surface cleans an
  unhanded attempt. Controller construction begins only at the exact system-
  sheet boundary after popover dismissal. The exact attempt's sheet-end signal
  ends coordinator/presentation state and asynchronously performs idempotent
  cleanup of that attempt's artifact; a stale attempt-A end signal must not
  clean attempt B. Controller deinitialization is not a normal cleanup boundary
  because SwiftUI/UIKit may retain or cache the controller after dismissal;
  artifact-lease deinitialization remains only an abnormal-path fallback.
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
- Current Native r3 Candidate Evidence: The accepted direct-file-URL transport
  checkpoint and the current uncommitted r3 implementation are split across
  `DepthAnalysisShareCoordinator`, `DepthAnalysisSharePopover`,
  `DepthViewerShareControl`, and `VerificationExportActivityView`. The stable
  control still anchors one app-owned popover to the Viewer Share action, while
  coordinator-owned selection/preparation/failure state remains outside the
  Viewer, pager, and playback session. The selector hierarchy now remains
  mounted during preparation: the clicked row keeps its title, icon, badge, row,
  and fixed subtitle slot, and that slot overlays the normal subtitle with an
  immediately visible 2px determinate track. No preparation percentage or
  Cancel control is inserted, other rows remain visible but disabled, and the
  selector/row/popover geometry and identity remain stable. The ready page,
  50 ms reveal delay, and 400 ms minimum hold are removed. Payload readiness
  closes the popover and stores an artifact-owning pending presentation without
  constructing UIKit;
  only the actual popover-disappearance/system-sheet boundary promotes that
  attempt, and `makeUIViewController` then constructs its one
  `UIActivityViewController`. The exact item Binding is the primary end signal;
  SwiftUI `onDismiss` is an exact-ID, idempotent fallback into the same end
  transition. That transition schedules attempt-scoped cleanup away from the
  main thread, does not wait for controller deinitialization, and ignores a stale
  attempt-A end after B becomes active. There is no destination-completion auto-
  close callback or timed appearance/dismantle watchdog, and package, image, and
  video continue to pass the materialized file URL directly to the system
  controller. The candidate is implemented but remains uncommitted and has not
  received native/device owner acceptance. The previous
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
  and anchored-handoff base `TAP-0081-r1`; approved resource/local-integrity and
  toolbar revision `TAP-0081-r2-candidate`; exact current preparation revision
  `TAP-0081-r3-candidate`; manifest `Prototype/manifest.json`; QA
  `Prototype/design-qa.md`. The owner approved the exact r3 candidate on
  `2026-08-14` with “对的 现在原型是我想要的”; its Board approval state is
  `ownerApproved`. The r3 authority keeps every option row and the selector
  mounted, shows normal subtitle text before preparation, and replaces only the
  clicked row's subtitle inside the same fixed slot with a 2px determinate track
  during preparation. It adds no percentage or Cancel control; title, icon,
  recommendation badge, row, popover, sibling geometry, and identity remain
  stable; other rows stay visible but disabled; payload readiness closes the
  popover without an independent preparation or ready page. Prototype source
  commit `70e8b60d4e20486a6d4847d726b393a50e22c7ba` remains the historical r2
  approval checkpoint. The
  owner selected the anchored format reference
  `exec-23c261dc-836c-4ffb-8bb0-492a01ab9816.png`, approved the preparation
  reference `exec-5f02b050-0547-4bd2-aed2-7243a9da1c5e.png`, and explicitly
  previously approved the 50 ms reveal / 400 ms minimum-visible policy in the
  development conversation; exact r3 supersedes that preparation behavior.
  Those generated images are review evidence, not the canonical prototype. The
  repository-owned r3 revision—not the generated images—is the current approved
  authority. Its refined toolbar uses custom Share/Delete
  vectors in 20pt boxes, 42pt circular backgrounds matching Back, optically
  concentric vector/background/progress-ring centers, and a compact
  intrinsic-width center mode capsule. `/root` is authorized to implement the
  full approved revision in SwiftUI.
- Prototype Evidence: The earlier `node Prototype/prototype.test.mjs` pass and
  browser review exercised r1/r2 selection, slow/threshold preparation, Cancel,
  Failure, Retry, system-dismissal return, media variants, and credential
  variants. The earlier 120 ms threshold fixture observed reveal at 51 ms and
  system-boundary handoff at 452 ms. Those timer/Cancel observations are now
  superseded UI history. Review captures are
  `Prototype/evidence/TAP-0081-r1-selection-full.png` and
  `Prototype/evidence/TAP-0081-r1-preparing-full.png`. The r2 candidate adds
  repository captures for resource loading, text-free local-integrity resolving,
  and failed-integrity degradation, together with combined comparison images
  listed in `Prototype/manifest.json`. Exact r3 manifest/QA evidence records the
  stable selector, rows, icons, titles, subtitle slots, badges, and popover
  geometry plus the selected-slot 2px track, with neither percentage nor Cancel
  UI. These establish Web visual/state QA only, while the owner's exact quote
  establishes `ownerApproved`; they do not establish native parity, timing,
  cryptographic assertion authenticity, or physical-device acceptance.
- Prototype Impact: Approved `TAP-0081-r1` remains the anchored selector base,
  and `TAP-0081-r2-candidate` remains authority for the
  previously missing Share-disabled original loading/unavailability states,
  text-free local-integrity resolution, queue-only Needs Retry, and Failed
  package-disabled/warned-direct-media degradation for Photo, Live Photo, and
  TAP Video and the refined toolbar. Exact `TAP-0081-r3-candidate` supersedes
  r1/r2 preparation timing and Cancel UI: the selected subtitle slot swaps to a
  2px determinate track with no percentage or Cancel while all geometry and
  identity remain stable. The approved current revision requires 42pt
  Back-matched outer circles, custom vectors in
  concentric 20pt boxes, a shared Share progress-ring center, and a compact
  non-flex-fill mode capsule. The prototype manifest/QA carries this current
  authority; SwiftUI must be synchronized and accepted against it. The interim
  54/25/18/flexible geometry has no continuing authority.
- Implementation Gate: `TAP-0006` supplies the repository-owned prototype
  foundation. Exact Share revision `TAP-0081-r1` received owner approval on
  `2026-08-12`; the prototype gate is satisfied and SwiftUI implementation is
  authorized. The owner subsequently approved the local-integrity behavior and
  directed implementation to continue. Native implementation and focused-test
  handoff plus a generic-Simulator Release build are recorded above. The owner
  previously approved exact r2 and its native implementation. That historical
  native build was delivered to the connected physical device at the owner's
  direction; post-change Simulator comparison was intentionally skipped. The
  owner-approved narrow regression fix removed `CameraView`'s forced outer
  navigation-bar visibility, gates `DepthAlbumPickerView` navigation-bar
  visibility with `isViewerPresented`, and changes fallback bottom padding from
  20 to the prototype-matched 25. Diff check, prototype static tests, and the
  repeated Debug device build/install/launch passed. Commit `bf20b52` freezes
  that historical cold-share remediation; its device delivery and owner verdict
  are recorded under TAP-0082. The reopened current gate is now satisfied only
  at the Web-prototype layer: exact `TAP-0081-r3-candidate` is ownerApproved, but
  native r3 parity, focused build/test evidence, and TAP-0082 attended device
  acceptance remain open, so TAP-0081 stays Doing.
- Documentation Impact: `Docs/ProductContract.md §5.3/§6`,
  `TAPCamDemo/DepthAnalysis/README.md`,
  `TAPCamDemo/DepthAnalysis/Playback/PLAYBACK.md`, the r2 historical Web sources,
  and `Docs/Acceptance/TAP-0048-web-swiftui-parity.md` record the historical
  implementation boundary. Exact r3 prototype/manifest/QA now defines the
  owner-approved current UI authority; native/module/acceptance synchronization
  remains required before Done. `Docs/UIPrototypeContract.md` needs no
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
  warning/package-disabled degradation, credential selection, the normal
  pre-preparation subtitle, selected-row determinate preparation, payload-ready
  popover dismissal, failure, and Retry states; the owner
  approves that revision; SwiftUI matches it without the separate app-owned
  modal format sheet; complete original readiness gates Share for every media
  kind; Photos/iCloud certification comes from local validation of the actual
  ready resource rather than Pending Capture Queue record presence; Needs Retry
  remains queue-only; no Share path calls backend/App Attest Verify; and the
  exact locally validated resource stays bound to the later payload attempt.
  The resource/status matrix, local pass/mismatch, missing exported record,
  iCloud loading/unavailability, package-disable/media-warning behavior,
  subtitle-to-2px-determinate-track swap, stable geometry/identity, disabled
  visible sibling rows, absence of percentage/Cancel and independent prep/ready
  pages, monotonic progress, cleanup, stale-callback, and ready-only system-
  presentation boundaries have focused tests. The custom UTI
  declares public data/content/ZIP conformances; the system handoff carries its
  explicit type; exact-attempt sheet end, SwiftUI/UIKit dismissal, stale-attempt
  protection, and asynchronous idempotent cleanup are tested without depending
  on a destination-completion callback or controller deinitialization; and a cold
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
  Linked `TAP-0082` supplies attended physical-device system-share and exact r3
  UI acceptance; Simulator evidence cannot substitute for that open gate.
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
- Superseded Reopened Approved Scope: Do not create a rollback commit for the already
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
- Current Owner-Approved Lifecycle Scope: Preserve the owner-accepted direct
  file-URL transport and anchored format selector, but remove the app-owned
  ready/boundary page and the 50 ms reveal delay plus 400 ms minimum hold.
  Before preparation, each option shows its normal subtitle. Selecting a format
  keeps the selector hierarchy mounted and immediately replaces only the
  clicked row's subtitle, in the same fixed slot, with a 2px determinate track.
  No percentage or Cancel control appears; title, icon, recommendation badge,
  row, popover, sibling geometry, and identity remain stable, and all other rows
  remain visible but disabled. There is no whole-popover preparation page.
  Payload readiness immediately dismisses the app-owned popover; only after its
  real disappearance may the system-sheet presenter construct
  `UIActivityViewController`. No controller preconstruction or early
  LaunchServices/FileProvider probing is
  permitted. The exact attempt's system-sheet end signal asynchronously cleans
  its artifact, independently of UIKit controller deinitialization, and stale
  attempt-A termination cannot affect B. The affected Web prototype/manifest,
  native implementation, tests, module/contract prose, and TAP-0082 device
  procedure must be synchronized before Done. Exact `TAP-0081-r3-candidate` is
  ownerApproved as the Web UI authority; the current native r3 implementation
  remains uncommitted and awaits the owner's self-install/device verdict.
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
- Historical Direct-File-URL Checkpoint State: The recovery represented by the
  pre-r3 checkpoint
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
- Superseded Checkpoint Console-Warning And Lifecycle Audit: After the successful four-path
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
- Owner-Approved Replacement Decision: The complete repeated-Share log proves
  that the first attempt can publish its sheet-end milestone and clear
  coordinator state while SwiftUI/UIKit still retains the old activity
  controller through the next system sheet; controller deinitialization is
  therefore rejected as the normal artifact-cleanup boundary. The owner also
  rejected the app-owned ready/boundary page and the timer-shaped 50/400
  transition. Exact owner-approved prototype `TAP-0081-r3-candidate` keeps the
  anchored selector hierarchy mounted: normal subtitle before preparation ->
  option tap -> only the clicked row's same fixed subtitle slot swaps to a 2px
  determinate track while title/icon/badge/row/popover/sibling geometry and
  identity stay fixed and sibling rows remain visible but disabled -> payload
  ready -> immediate popover close -> controller construction at the real
  system-sheet boundary -> system-owned sheet -> exact-attempt sheet end ->
  asynchronous, idempotent artifact cleanup. No percentage, Cancel control, or
  whole-popover preparation page is part of this sequence. The controller must
  not be constructed and may not start system URL probes before the app-owned
  popover is gone. This
  decision preserves the accepted direct-file-URL transport matrix. The owner
  explicitly approved the exact r3 Web prototype with “对的 现在原型是我想要的”,
  but this does not accept a native candidate or claim native build, test,
  device run, commit, or push evidence.
- Pre-Closure Native r3 Candidate Validation: Generic iOS Simulator and generic
  iphoneos `build-for-testing` both completed with exit code 0; Simulator was
  not launched. The repository Web-prototype test, focused static/source
  contract checks, `git diff --check`, and Swift parse checks passed. XCTest
  targets were compiled by the builds but were not executed, so no XCTest pass
  was claimed at that checkpoint. No physical-device install/run, owner native
  verdict, commit, or push had yet been recorded for that candidate.
- Current Closure Decision: `Accepted by the product owner on 2026-08-14.` The
  owner reviewed the current log and explicitly directed “当前任务我觉得可以视为
  标记为完成”. The exact r3 Web authority and native behavior retain
  the same contract: a row's fixed subtitle slot alone becomes a 2px
  determinate app-payload track; it is not held at 99%, padded by 400 ms, or
  repurposed as a claim that the system sheet is ready. Payload readiness closes
  the popover and the subsequent iOS-owned sheet takes over. The supplied log
  completely covers one `.tapnap` attempt only: intermediate resource cleanup
  at L70, payload ready at L72, handoff start at L73, controller creation in
  under 50 ms at L74, system LaunchServices/FileProvider probes at L75–85,
  sheet appearance at L86, dismissal at L93, controller release at L94, and
  `artifactLease` cleanup at L95. It does not prove direct-image cleanup,
  stale-attempt A/B isolation, or cleanup independent of controller release;
  direct-image transport remains supported by the owner's earlier accepted
  ordinary-image/`.tapnap` x Save to Files/AirDrop four-path matrix. Focused r3
  XCTest remains compiled but unexecuted. The owner explicitly accepted these
  evidence exceptions and directed closure; no missing test/device fact is
  invented. The exact Git identity will be the commit containing this closure
  record; no prospective hash is recorded. TAP-0008, TAP-0009, TAP-0083, and
  TAP-0041 remain independent open cold-path work.
- Reopened Done When: A fixed build uses the system-native file-URL activity
  handoff for both ordinary media and `.tapnap`; selecting a type keeps the
  selector hierarchy mounted, retains normal pre-preparation subtitle text, and
  swaps only the clicked row's same fixed subtitle slot to a 2px determinate
  track while title, icon, recommendation badge, row, popover, sibling geometry,
  and identity stay fixed and every sibling option stays visible but disabled.
  No percentage, Cancel control, whole-popover preparation page, app-owned
  ready/boundary page, 50 ms delayed reveal, or 400 ms minimum hold appears;
  payload readiness closes the popover. Controller construction and system URL
  probing begin only after actual popover disappearance at the system-sheet
  boundary. Focused tests protect the
  activity-item matrix, exact-attempt ownership, stale-A/new-B termination, and
  asynchronous idempotent artifact cleanup from the matching sheet-end signal
  even when SwiftUI/UIKit retain an old controller. No proactive destination-
  completion callback, private LaunchServices entitlement, persistent Share
  payload cache, or Share prewarm is introduced; and TAP-0082 records successful
  physical-device Save to Files plus AirDrop receipt for the representative
  ordinary-media and `.tapnap` paths together with attended exact-r3 native UI
  and lifecycle acceptance.
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
  - `2026-08-14` Recorded the owner's replacement lifecycle decision after the
    complete two-system-sheet log showed attempt A's app state ending without
    controller release or `artifactLease` cleanup before attempt B appeared.
    Removed the app-owned ready/boundary page from the approved flow and
    superseded the 50 ms delayed reveal plus 400 ms minimum hold. A format tap
    now immediately enters preparation progress; payload readiness immediately
    closes the popover; `UIActivityViewController` is constructed only after the
    popover has actually disappeared at the real system-sheet boundary, so no
    early system URL probe is permitted. The exact attempt's sheet end must
    asynchronously perform idempotent artifact cleanup without waiting for
    UIKit deinitialization. The direct-file-URL transport verdict remains Pass,
    but the current lifecycle candidate is uncommitted and unaccepted; prototype,
    implementation, tests, documentation, and device evidence remain open.
    TAP-0081 stays Doing.
  - `2026-08-14` Recorded the owner's explicit progress-geometry correction:
    preparation is not a replacement page for the whole popover. The anchored
    selector hierarchy remains mounted; only the clicked option row changes in
    place to progress plus current percentage, while all sibling options remain
    visible but disabled. Payload readiness then closes the popover before the
    later system-sheet boundary. This clarification changes current authority
    and acceptance but claims no accepted implementation, prototype sync,
    build, test, device run, commit, or push. TAP-0081 remains Doing.
  - `2026-08-14` Recorded the owner's exact prototype verdict, “对的 现在原型是
    我想要的”, and marked `TAP-0081-r3-candidate` `ownerApproved`. This final
    UI authority supersedes the preceding percentage-shaped description: each
    row shows its subtitle before preparation; after a format tap, only the
    clicked row's same fixed subtitle slot swaps to a 2px determinate track.
    There is no percentage or Cancel control, and title, icon, recommendation
    badge, row, popover, sibling geometry, and identity remain stable while
    other rows stay visible but disabled. There is no independent preparation
    or ready page; payload readiness closes the popover before the system sheet.
    Prototype approval does not accept a native candidate. TAP-0081 remains
    Doing pending native build/test evidence and attended TAP-0082 acceptance.
  - `2026-08-14` Synchronized the implemented native r3 candidate without
    converting compilation into acceptance. The selector remains mounted and
    replaces only the clicked row's fixed subtitle slot with a 2px determinate
    track; no preparation percentage or Cancel appears, sibling rows remain
    visible but disabled, and row/popover geometry stays stable. Payload
    readiness closes the popover, then the real sheet boundary constructs the
    one file-URL `UIActivityViewController`. The exact item Binding and SwiftUI
    `onDismiss` fallback feed one exact-ID, idempotent end transition; cleanup is
    scheduled off the main thread, stale A cannot end B, and no destination-
    completion auto-close callback or appearance/dismantle watchdog remains.
    Generic Simulator and iphoneos `build-for-testing` each exited 0 without
    launching Simulator; prototype, static/source, diff, and Swift parse checks
    passed. Tests compiled but were not executed. No device run, owner native
    verdict, commit, or push is claimed; TAP-0081 remains Doing.
  - `2026-08-14` The owner reviewed the latest integrated log, accepted the
    recorded evidence exceptions, and directed the current Task to be treated
    as complete. Moved TAP-0081 Doing -> Done. The log proves one complete
    `.tapnap` sequence through payload readiness, post-popover system handoff,
    sheet appearance/dismissal, controller release, and final
    `artifactLease` cleanup; its LaunchServices/FileProvider messages are
    system probes that precede successful sheet appearance. It does not prove
    the direct-image attempt, stale-A/new-B isolation, or cleanup independent of
    controller release. Direct image continues to rely on the previously
    owner-accepted four-path transport matrix, and focused r3 XCTest remains
    compiled but unexecuted. The owner explicitly accepted those gaps for this
    closure. No 99% system-readiness wait, fake progress, 400 ms hold, ready
    overlay, private entitlement, Share prewarm, or persistent payload cache is
    authorized. The containing closure commit supplies the Git identity; no
    hash is predeclared. TAP-0008, TAP-0009, TAP-0083, TAP-0040, and TAP-0041
    remain open and are not absorbed by TAP-0081.

### TAP-0082 — Device acceptance: TAP Share anchored handoff and anti-flash progress

- Status: `Done`
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
- Pre-Closure Retest State: The owner-approved Web r3 contract was implemented in
  the uncommitted native candidate. Preparation keeps the selector mounted and
  replaces only the clicked row's normal subtitle slot with a 2px determinate
  track; there is no preparation percentage or Cancel, sibling rows remain
  visible but disabled, and selector/row/popover geometry and identity remain
  stable. Payload readiness closes the popover; only the subsequent real sheet
  boundary constructs the one direct-file-URL `UIActivityViewController`. The
  exact item Binding and SwiftUI `onDismiss` fallback converge on one exact-ID,
  idempotent
  end transition, which schedules artifact cleanup off the main thread without
  waiting for controller deinitialization; a stale attempt-A signal cannot end
  B. Destination completion/dismissal remains system-owned, with no proactive
  auto-close callback or timed appearance/dismantle watchdog. Generic iOS
  Simulator and generic iphoneos `build-for-testing` each completed with exit
  code 0 without launching Simulator. Prototype, static/source, diff, and Swift
  parse checks passed; XCTest targets compiled but were not run. The accepted
  direct-file-URL four-path transport matrix remains baseline evidence, not
  acceptance of this r3 candidate. No owner self-install/device verdict, fixed
  commit, or push existed at this checkpoint, so TAP-0082 remained Doing.
- Superseded Checkpoint Console Observation: The owner's post-Pass logs contain
  LaunchServices `-10814`/`Code=-54`, CKShare/SWY, FileProvider, persona, and
  one gesture-gate timeout while preparing `.tapnap`. The corresponding source
  audit found no stale manual provider/open-in-place/completion transport code:
  the checkpoint path remained one direct file-URL activity controller. Both
  `.tapnap` and ordinary-image sequences show the system's LaunchServices/
  FileProvider URL probes after `tap_share_activity_controller_created` but
  before coordinator `tap_share_activity_handoff_started`. During that interval
  the coordinator still classifies the presentation as a pending handoff, and
  `discardPendingHandoff()` can explicitly remove its artifact even though the
  constructed controller has already caused the system to inspect the URL.
  This was the checkpoint source-lifetime race that the r3 source candidate now
  replaces; its integrated physical-device verdict remains open. The `.tapnap`
  sequence additionally
  reaches `tap_share_activity_sheet_dismissed` without a subsequent controller-
  dismantled or `artifactLease` terminal-cleanup milestone before the next
  Share begins, and it reports controller construction `under50ms` before
  revealing `over50ms` feedback attributed to `controllerConstruction`.
  System-probe warnings do not negate the received/openable four-path verdict,
  but source ownership, teardown, and progress attribution were not accepted at
  that checkpoint.
- Replacement Acceptance Scope: On the next fixed build, a format tap must
  keep the anchored selector hierarchy mounted, replace only the clicked row's
  normal subtitle in the same fixed slot with a 2px determinate track, and leave
  every sibling option visible but disabled. Title, icon, recommendation badge,
  row, popover, sibling geometry, and identity must remain stable. There must be
  no percentage, Cancel control, whole-popover preparation page, app-owned
  ready/boundary page, 50 ms delayed reveal, or 400 ms minimum hold. Payload
  readiness must close the popover; only after actual disappearance may
  controller creation and LaunchServices/FileProvider probes begin at the real
  system-sheet boundary. Closing each system sheet must publish the matching
  attempt's asynchronous `artifactLease` cleanup even if SwiftUI/UIKit retain
  that controller, and a late attempt-A end must not clean B. The previously
  accepted four-path direct-file-URL transport verdict remains historical Pass,
  but it does not accept this new lifecycle/progress implementation.
- Current Human Confirmation: `Pass for the current recovery transport matrix
  on 2026-08-14. The owner replied “验收通过” to the immediately preceding
  explicit confirmation that ordinary image and .tapnap each succeeded through
  Save to Files and AirDrop and that every saved/received artifact opens. After
  reviewing the later integrated log and its stated evidence limits, the owner
  explicitly directed on 2026-08-14 “当前任务我觉得可以视为标记为完成”.`
- Current Prototype Confirmation: `Exact TAP-0081-r3-candidate is ownerApproved
  on 2026-08-14 from the owner quote “对的 现在原型是我想要的”. This confirms the
  Web UI contract only and is not native-build or device-acceptance evidence.`
- Reopened Done When: Both physical-device destinations pass on the fixed build
  for representative ordinary media and `.tapnap`, AirDrop produces received
  artifacts for both paths, and native UI matches ownerApproved
  `TAP-0081-r3-candidate`: the selector stays mounted, only the clicked row's
  normal subtitle swaps in the same fixed slot to a 2px determinate track,
  sibling rows remain visible but disabled, all listed geometry and identity
  remain stable, and neither percentage nor Cancel appears. The payload-ready-
  popover-close/post-dismiss controller-construction sequence is visible. No
  independent preparation/ready page or early system URL probe occurs, and the
  matching sheet-end signal asynchronously cleans its exact artifact even if the
  old controller remains retained. Stale dismissal/teardown callbacks cannot
  release a newer attempt, no proactive destination-
  completion callback or persistent payload cache exists, and the linked
  acceptance record carries the owner's explicit four-path artifact verdict.
  Build/install/launch, the historical
  provider tests, candidate `35745be`, or the `bf20b52` acceptance
  alone cannot return TAP-0082 to Done.
- Superseded Pre-Closure Gate: `The four-path attended transport matrix was complete
  and its direct-file-URL baseline is frozen by the checkpoint commit containing
  this Board revision. Native r3 implementation and generic compilation are now
  present, but tests were compiled rather than run and neither a fixed commit nor
  attended device evidence exists. Remaining before Done: execute the focused
  tests, freeze the candidate, and have the owner self-install and accept the
  integrated exact-r3 UI, payload-ready popover-to-sheet boundary, exact-ID
  Binding/onDismiss end behavior, off-main cleanup, and stale-A/new-B isolation.
  Transport need not be re-proven by a separate scope unless the fixed build
  changes the accepted direct-file-URL path, but the integrated fixed build still
  requires owner acceptance.`
- Current Completion Audit: `Done by explicit owner decision on 2026-08-14.`
  Exact `TAP-0081-r3-candidate` is ownerApproved and its native implementation
  compiled for generic Simulator and iphoneos without launching Simulator.
  Focused r3 XCTest was compiled but not executed. The owner's earlier attended
  matrix remains the evidence for ordinary image and `.tapnap` through Save to
  Files and AirDrop with openable artifacts. The later supplied log completely
  proves only one `.tapnap` attempt: L70 intermediate cleanup, L72 payload
  ready, L73 handoff, L74 controller construction under 50 ms, L75–85 system
  probes, L86 sheet appearance, L93 dismissal, L94 controller release, and L95
  final `artifactLease` cleanup. It does not independently prove direct-image
  cleanup, stale-A/new-B isolation, or artifact cleanup before/independent of
  controller release. The owner explicitly accepted those evidence exceptions
  and directed closure. The determinate 2px track remains scoped to app-owned
  payload work: it is not stalled at 99%, extended by 400 ms, or used to fake
  system-sheet readiness; payload readiness closes the popover and iOS owns the
  following presentation. The containing closure commit supplies the final Git
  identity, with no guessed hash. TAP-0008/TAP-0040, TAP-0009/TAP-0041, and
  TAP-0083 remain independently open.
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
  - `2026-08-14` Synchronized the owner-approved replacement flow into the open
    device gate. The current candidate's app-owned ready/boundary page, 50 ms
    delayed reveal, 400 ms minimum hold, preconstructed controller, early system
    probing, and controller-deinit normal cleanup boundary are superseded.
    Acceptance now requires immediate preparation progress after format
    selection, payload-ready popover dismissal, controller construction only at
    the subsequent real system-sheet boundary, and matching sheet-end
    asynchronous artifact cleanup even while UIKit retains the old controller.
    The four-path direct-file-URL transport result remains Pass, but no fixed
    replacement build, prototype synchronization, commit, or owner verdict is
    claimed. TAP-0082 remains Doing.
  - `2026-08-14` Synchronized the owner's progress-geometry correction into the
    open device gate. Acceptance must show the selector hierarchy remaining
    mounted, only the clicked option row changing in place to progress plus
    current percentage, and every sibling option staying visible but disabled.
    A whole-popover preparation page is explicitly rejected; payload readiness
    closes the popover before the system sheet. The current candidate remains
    unaccepted, and TAP-0082 remains Doing.
  - `2026-08-14` Synchronized owner approval of exact Web revision
    `TAP-0081-r3-candidate` (“对的 现在原型是我想要的”) into the open device
    gate. The native acceptance target is the same-slot subtitle-to-2px-
    determinate-track swap with no percentage or Cancel, stable selector/title/
    icon/badge/row/popover/sibling geometry and identity, and visible disabled
    sibling rows. No independent preparation or ready page may appear; payload
    readiness closes the popover before the system sheet. Web approval clears
    the prototype gate only; the native build and attended device verdict remain
    open, so TAP-0082 remains Doing.
  - `2026-08-14` Synchronized the native r3 implementation and compilation
    evidence into the open device gate. The candidate implements the approved
    same-slot 2px progress geometry with no preparation percentage/Cancel,
    closes the popover when payload is ready, constructs the controller only at
    the later sheet boundary, and converges exact item-Binding plus SwiftUI
    `onDismiss` through one exact-ID, idempotent, off-main cleanup transition;
    stale A cannot end B, and no destination-completion auto-close callback or
    timed watchdog remains. Generic Simulator and iphoneos
    `build-for-testing` each exited 0 without launching Simulator; prototype,
    static/source, diff, and Swift parse checks passed. Tests compiled but were
    not run. No owner self-install/device verdict, commit, or push is claimed;
    TAP-0082 remains Doing.
  - `2026-08-14` The owner reviewed the latest integrated log, accepted its
    explicit evidence limitations, and directed the current Task to be treated
    as complete. Moved TAP-0082 Doing -> Done. The earlier attended four-path
    ordinary-image/`.tapnap` x Save to Files/AirDrop matrix remains Pass. The
    new log proves one complete `.tapnap` attempt only, through intermediate
    cleanup, payload-ready handoff, system probes, sheet appearance/dismissal,
    controller release, and final artifact cleanup; it does not establish the
    direct-image teardown, stale-A/new-B isolation, or cleanup independent of
    controller release. Focused r3 XCTest remains compiled but unexecuted. The
    owner explicitly accepted those gaps rather than asking that missing
    artifacts be inferred. App-payload progress remains truthful and immediate;
    it does not wait at 99% for system readiness, add a 400 ms hold, or show a
    ready overlay. The containing closure commit supplies its own hash. This
    evidence closure does not close TAP-0008, TAP-0009, TAP-0083, TAP-0040, or
    TAP-0041.

### TAP-0083 — Eliminate cold-path UI starvation and codify responsiveness guardrails

- Status: `Doing`
- Kind: `Fix`
- Priority: `P0`
- Domain: `Runtime Responsiveness / TAP Library / Viewer`
- Labels: `cold-start`, `first-install`, `empty-cache`, `main-actor`,
  `library-snapshot`, `thumbnail-decode`, `geometry`, `progress-backpressure`,
  `observability`, `engineering-standard`
- Contract: `ProductContract §5.2–5.3`; `§8`;
  `ColdPathResponsiveness §8–9`; candidate
  `Docs/StartupLifecycleContract.md §3, §6` (exact approval pending under
  `TAP-0087`); root `AGENTS.md`
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
     keys;
  5. add low-cardinality structured milestones sufficient to distinguish tap,
     app-owned visible response, catalog/resource work, payload readiness,
     system presentation, dismissal, and cleanup without logging media IDs,
     file paths, URLs, hashes, or per-chunk events; and
  6. own the native startup comparison on the same physical iPhone across the
     complete 2 × 2 matrix: Debug attached; the same Debug artifact detached and
     launched from the Home Screen; optimized Release/Profile attached; and the
     same optimized Release/Profile artifact, or equivalent TestFlight product
     build, detached. Recreate the same source commit, canonical installation
     context, `S/P/I` route facts, scenario, Library/Pending scale, and cache/
     reset condition for each cell as applicable. Record `Δt0–t1` through
     `Δt3–t4`, namespaced `S/P/C/L/V` spans, deferred-work release, MainActor
     stalls, and the active workload/owner. Build configuration and debugger
     attachment are measurement dimensions, never route facts. Only optimized,
     debugger-detached evidence may close a native startup timing threshold; the
     other three cells diagnose compilation/attachment amplification and cannot
     waive a source-visible blocker.
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
  closed under TAP-0081/TAP-0082 for `bf20b52`. A later cold/overwrite-install
  log adds a more discriminating baseline: camera configuration/start overlaps
  startup, Locked Camera import/context starts while
  `managerSessionCount=0`, the first 908-item Library catalog snapshot takes
  `7795 ms`, and App Attest reset/network work ends in a credential-preparation
  failure. By contrast, the observed Share source fetch is about `11.7 ms`,
  `.tapnap` packaging about `27.5 ms`, and activity-controller construction
  under 50 ms. This shifts the diagnostic priority away from ZIP/Share payload
  work toward cold startup/catalog/credential and unnecessary lifecycle overlap,
  but the log does not establish that any one operation ran synchronously on
  MainActor or caused the visible stall.
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
- Lifecycle Placement Responsibility: TAP-0083 owns the remaining real route-
  shell/first-frame proof and any resulting performance correction for
  `returningCameraConstruction`, camera discovery, and capture-session object
  construction. The implementation handoff in completed TAP-0009 establishes
  source placement but `Task.yield` is not a committed-frame measurement.
  TAP-0090 may assert deterministic non-Network event order, but it cannot close
  this physical timing boundary or replace the four-cell iPhone matrix.
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
  must pass. TAP-0083 itself, not a linked evidence Task, must execute and record
  all four physical-iPhone startup cells. Every cell records the exact source
  commit and artifact/configuration, install method, device/OS, `S/P/I` facts
  and scenario, Library/Pending counts, cold/warm resource and cache-reset
  condition, interval/span values, deferred-work start, stalls/workload owner,
  and evidence method. Debug attached, Debug detached, and optimized attached
  are diagnostic comparisons; only optimized Release/Profile detached may close
  a recorded native startup timing threshold. A warm rerun is comparison only.
  TAP-0045, TAP-0047, and TAP-0082 retain their feature-specific Video, Library,
  and Share evidence ownership and do not substitute for this startup matrix.
- Documentation Impact: Root `AGENTS.md`, the canonical cold-path standard,
  affected module README(s), and any Product Contract acceptance boundary must
  be reconciled by the development handoff. No new visible prototype revision
  is required unless implementation changes visible states. Project Board
  status/history remains Board-Steward-only.
- Done When: The bounded source fixes and canonical engineering standard are in
  the tree; all automated Validation Gate checks pass; instrumentation can
  attribute a cold first interaction without sensitive/per-item log flooding;
  the complete four-cell physical-iPhone startup matrix is recorded against the
  same controlled scenario facts; and only a passing optimized Release/Profile,
  debugger-detached run is used to close each applicable native startup timing
  threshold. Debug attached/detached and optimized attached results cannot close
  or waive a threshold. The matrix's milestone/timing definitions must consume
  the exact owner-approved StartupLifecycleContract/TAP-0087 revision; while
  that revision remains a candidate, no threshold closure or Done transition is
  inferred. The development handoff identifies every changed contract/module/
  governance file. TAP-0045 and TAP-0047 may remain open for their independent
  Video/Library evidence, and TAP-0082 remains independent historical Share
  evidence, but none may absorb or defer this Task's startup matrix. No delivery
  transition occurs before Board Steward reconciliation.
- Related: Regression support for `TAP-0081`; attended Share evidence
  `TAP-0082`; TAP Video evidence `TAP-0045`; TAP Library evidence `TAP-0047`;
  adjacent first-camera/resource readiness `TAP-0009`; thumbnail policy
  `TAP-0027`; common prerequisite `TAP-0087`; structured non-Network regression
  evidence `TAP-0090`
- Created: `2026-08-13`
- Updated: `2026-08-15`
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
  - `2026-08-14` Added the owner's cold/overwrite-install log as a diagnostic
    baseline and retained Doing. In the same session, camera startup,
    `managerSessionCount=0` Locked Camera import/context work, a 908-item first
    Library catalog snapshot taking `7795 ms`, and App Attest reset/network
    failure overlap the cold path. Share itself fetches its source in about
    `11.7 ms`, builds `.tapnap` in about `27.5 ms`, and constructs the system
    controller in under 50 ms. The evidence therefore prioritizes startup/
    catalog/credential/lifecycle overlap over ZIP or Share packaging, but does
    not prove a MainActor causal chain. TAP-0083 stays Doing until its focused
    validation and documentation handoff complete. TAP-0081/TAP-0082 closure
    does not close this cross-cutting responsiveness Task.
  - `2026-08-14` Added owner-approved common prerequisite `TAP-0087` without
    changing this Task's Doing status or implementation scope. TAP-0087 now
    owns the combined startup taxonomy, t0…tn/Δ work-budget contract, complete
    startup/heavy-work trigger map, and reviewer-only interactive inspector
    that TAP-0083 explicitly did not own as visible prototype work. TAP-0083
    continues to own its bounded runtime remediation and validation after that
    common prerequisite is established.
  - `2026-08-14` Owner assigned TAP-0083 the complete physical-iPhone startup
    measurement matrix across Debug versus optimized Release/Profile and
    debugger attached versus detached. All four cells must be recorded under
    controlled matching scenario facts; only optimized, debugger-detached
    evidence may close a native startup timing threshold, while the other three
    cells remain diagnostic. TAP-0045/TAP-0047/TAP-0082 keep their independent
    feature evidence boundaries and cannot substitute for this matrix. No matrix
    execution, threshold pass, exact StartupLifecycleContract/TAP-0087 candidate
    approval, or status transition is claimed; TAP-0083 remains Doing.
  - `2026-08-15` Owner's delivery/evidence split assigned TAP-0083 the remaining
    measured route-shell/real-first-frame placement for
    `returningCameraConstruction`, camera discovery, and capture-session object
    construction. TAP-0009 is Done for its native source-placement delivery;
    TAP-0090 owns reusable non-Network structural assertions but cannot supply a
    rendered-frame acknowledgement, native elapsed time, or the required four-
    cell physical-iPhone matrix. TAP-0083 remains Doing and no timing threshold
    or regression result is inferred.

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

### TAP-0085 — Restrict the current runtime target to iPhone

- Status: `Done`
- Kind: `Technical`
- Priority: `P1`
- Domain: `Platform / Build Configuration`
- Labels: `iphone-only`, `supported-platforms`, `device-family`, `ipad`,
  `mac-catalyst`, `macos`, `visionos`, `build-settings`
- Contract: `ProductContract §1.1`; `UIPrototypeContract §3`; `§9`
- Match Keys: `iPhone only, no iPad support, no Mac support, Universal target,
  TARGETED_DEVICE_FAMILY, SUPPORTED_PLATFORMS, SUPPORTS_MACCATALYST,
  Designed for iPhone/iPad, visionOS compatibility, unrelated platform code`
- Assignee: `/root` documentation and validation reconciliation; product owner
  authored the existing Xcode project setting change
- Dev Session: `019ff4ea-acba-7051-bd0f-3d489f1caadc`
- Branch/Worktree: `main` / `origin/main` at merge
  `37d0c61`; independent TAP-0085 implementation commit
  `28d5aef683848c3043f0777b6f3c9665a897864b`
- Scope: Make the main TAPCamDemo application target iPhone-only in both Debug
  and Release. Its supported build platforms are iPhone device and iPhone
  Simulator; the Simulator remains a development/validation destination rather
  than an additional production platform. Preserve the owner-authored main-app
  settings that target device family `1` and disable Mac Catalyst, Designed for
  iPhone/iPad on Mac, and visionOS compatibility routes.
- Out of Scope: iPad UI or runtime support, adaptive iPad layout, multitasking,
  Stage Manager, pointer/keyboard work, Mac Catalyst, native macOS, Designed for
  iPhone/iPad on Mac, visionOS compatibility, any platform-specific refactor or
  acceptance undertaken only for those unsupported platforms, or producing App
  Store media under TAP-0007. App Store Connect Mac or Vision availability is
  an external distribution setting and is not proven or fully controlled by
  these Xcode project flags.
- Prototype Impact: `N/A`; this is a build/product-support boundary and does
  not intentionally change visible iPhone UI.
- Current Evidence: Product Contract §1.1, UI Prototype Contract §3/§9, and the
  root README now state the same iPhone-only boundary. Independent Debug and
  Release effective-setting checks for the main application resolve
  `SUPPORTED_PLATFORMS` to `iphoneos iphonesimulator`,
  `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, and
  `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` to `NO`, and
  `TARGETED_DEVICE_FAMILY` to `1`. The existing generic iphoneos
  `build-for-testing` passed, and its built app `Info.plist` reports
  `UIDeviceFamily = [1]`. TAP-0007 is synchronized to the distinct 6.9-inch
  iPhone App Store-media decision. A current `main` recheck at merge
  `37d0c61` independently reconfirmed the same Debug/Release effective settings,
  completed generic/platform=iOS Debug `build-for-testing` with
  `CODE_SIGNING_ALLOWED=NO`, and inspected the built app `Info.plist` with
  `UIDeviceFamily = [1]`; neither Simulator nor a physical device was launched.
  The owner-approved settings, documentation, and validation evidence are
  frozen separately from TAP-0081/TAP-0082 by implementation commit
  `28d5aef683848c3043f0777b6f3c9665a897864b`, now present in both `main` and
  `origin/main` through merge `37d0c61`.
- Done When: The Product Contract, UI Prototype Contract, and root README all
  state the same iPhone-only current scope; main-app Debug and Release effective
  settings resolve to iPhone device/Simulator only with device family `1` and
  the unsupported compatibility routes disabled; a built app reports
  `UIDeviceFamily = [1]`; a generic iOS build gate passes; TAP-0007 remains a
  distinct 6.9-inch iPhone App Store-media decision; and the owner-authored
  project settings plus documentation and validation evidence are frozen in a
  separate TAP-0085 commit.
- Completion Audit: `Satisfied on 2026-08-14.` Every recorded Done When item is
  present: the three current documents agree, main-app Debug and Release resolve
  to iPhone device/Simulator with device family `1` and all three unsupported
  Mac/XR routes disabled, the generic iOS build gate passes, the built app
  reports `UIDeviceFamily = [1]`, TAP-0007 remains an independent Inbox
  decision, and the dedicated implementation is frozen in `28d5aef` and merged
  at `37d0c61`. Commit `28d5aef` also carries an adjacent shared-scheme
  `LaunchAction` change from Release to Debug. That neighbor is not claimed as
  TAP-0085 scope or evidence; per the owner's instruction to preserve the
  complete current mainline, it remains untouched and is not used to broaden
  this Task.
- Related: `TAP-0007`
- Created: `2026-08-14`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-14` Allocated after a complete Inbox/Todo/Doing/Done/Deprecated
    search found no runtime-platform Task. TAP-0007 overlaps only in historical
    iPad store-media wording and remains a separate App Store asset decision.
    Created TAP-0085 in Inbox.
  - `2026-08-14` The owner stated that the `project.pbxproj` change is owner-
    authored and that the current product does not consider iPad or Mac support,
    because doing so would introduce unrelated factors while changing code.
    This explicitly approved the bounded iPhone-only scope; moved Inbox -> Todo
    -> Doing because the owner patch already exists. Product-contract,
    UI-prototype-contract, README, effective-build-setting, built-plist, generic
    iOS build, and separate-commit evidence remain open, so no Done transition
    is inferred.
  - `2026-08-14` Reconciled current documentation and build evidence. Product
    Contract §1.1, UI Prototype Contract §3/§9, and the root README now agree on
    the iPhone-only scope. Debug and Release effective settings independently
    report iPhone device/Simulator only, all three unsupported compatibility
    flags `NO`, and device family `1`; generic iphoneos `build-for-testing`
    passed and the built app reports `UIDeviceFamily = [1]`. All recorded Done
    When conditions except the required separate TAP-0085 commit are now met,
    so TAP-0085 remains Doing solely for that freeze point.
  - `2026-08-14` Closed the remaining freeze point and moved TAP-0085 Doing ->
    Done. Independent implementation commit
    `28d5aef683848c3043f0777b6f3c9665a897864b` follows the TAP-0081/TAP-0082
    closure commit and is present on clean `main` / `origin/main` through merge
    `37d0c61`. A fresh mainline audit reconfirmed both main-app Debug/Release
    settings, all three unsupported compatibility flags `NO`, device family
    `1`, a successful generic/platform=iOS Debug `build-for-testing` with code
    signing disabled, and built-app `UIDeviceFamily = [1]`; Simulator and device
    were not launched. TAP-0007 remains Inbox and Next Task ID is unchanged.
    The same implementation commit contains an adjacent scheme LaunchAction
    Release-to-Debug change; it is explicitly excluded from TAP-0085 evidence
    and remains untouched under the owner's instruction to preserve the current
    mainline rather than pop, rewrite, or redo another Task.

### TAP-0086 — Remove Locked Camera integration and entry points from main

- Status: `Done`
- Kind: `Technical`
- Priority: `P0`
- Domain: `Locked Camera / Main-Tree Simplification`
- Labels: `instant`, `locked-camera`, `remove-production-integration`,
  `extension-targets`, `startup-lifecycle`, `cold-path`, `main-tree-cleanup`
- Contract: `ProductContract §4`; root `AGENTS.md` implementation and
  documentation-impact rules
- Match Keys: `delete locked camera, remove lock-screen launch, remove capture
  extension, remove control extension, remove appex, delete lock-screen entry,
  删除锁屏启动, 删除锁屏相机, 删除入口`
- Assignee: `/root`
- Dev Session: `/root` instant implementation authorized by the product owner
- Branch/Worktree: `main` working tree; actual implementation baseline
  `main@6c45a77`
- Build/Commit: Containing closure commit with subject
  `Remove Locked Camera integration from main`. Its exact hash is supplied by
  Git after this Board update is included and is not fabricated prospectively.
- Scope: Remove the current main-tree Locked Camera integration completely:
  delete the `TAPCamLockedCameraCaptureExtension` and
  `TAPCamLockedCameraControlExtension` native targets, products, dependencies,
  embed phases, build configurations, file groups, and their source/resource
  directories; delete the shared `TAPCamLockedCameraIntents` sources used by
  those targets and the containing app; remove main-app Locked Camera framework
  imports, app-context publication, session-content importing, intent handoff,
  URL/user-activity/startup routing, transition/import state, and Library/
  Pending Capture Queue wiring that exists only for the removed entry; and
  remove tests, fixtures, localizations, lint inputs, entitlements, URL/activity
  declarations, and documentation that serve only that main-tree integration.
  Keep ordinary Camera capture, TAP Library and Pending Capture Queue behavior,
  normal App Intents/manual-control intents, and unrelated app startup paths
  intact.
- Out of Scope: Implementing or promoting a replacement Locked Camera feature;
  changing the lifecycle-correct experiment defined by TAP-0013 or its blocked
  TAP-0049 attended procedure; deleting or rewriting Git history or the
  dedicated experiment branch; removing ordinary Camera, Library, queue, or App
  Intents functionality merely because it shares a module; changing current
  media/signing formats; or treating this removal as proof that the future
  experiment passes.
- Prototype Path/Revision/Approval: `N/A by explicit owner direction.` This
  removes a non-current experimental/system entry from main and intentionally
  adds no app-owned iPhone UI. Any future Locked Camera experiment or promotion
  remains independently prototype/acceptance-gated under TAP-0013/TAP-0049.
- Implemented Scope: The accepted main-tree implementation removes both Locked
  Camera extension targets, their `.appex` products/embed phases/build
  configurations/source-resource directories, and the shared
  `TAPCamLockedCameraIntents` source. It removes the containing app's Locked
  Camera framework import, context publication, session-content import runtime,
  URL/user-activity/intent handoff, startup routing, route state, Library wait/
  refresh state, Pending Capture Queue import path, dedicated notifications,
  localizations, project declarations, tests, and lint references. Ordinary
  Camera capture, TAP Library, the ordinary Pending Capture Queue, retained App
  Intents/manual-control intents, and unrelated startup behavior remain in the
  project and compile.
- Tests And Builds Run: A fresh generic iPhone Debug `build-for-testing` with
  `CODE_SIGNING_ALLOWED=NO` completed with exit code 0 and compiled the app plus
  test targets. The resulting project exposes only three retained targets; the
  built app contains zero `.appex` products, and its parsed `Info.plist` has no
  Locked Camera URL declaration. Repository production-source scans, the
  project-object `F2E` identifier scan, `plutil`, `jq`, and `git diff --check`
  passed. Simulator and physical device were not launched, and runtime tests
  were not executed. `Scripts/lint-tap-video-refactor.sh` successfully passed
  the removed-file/reference portion, then exited nonzero on three pre-existing
  non-TAP-0086 complexity/length violations; that run is not reported as a lint
  pass and those unrelated findings do not block this bounded removal. A final
  read-only review reported no P0 or P1 finding.
- Development Handoff:
  - Contract Sections Read: `ProductContract §4`; TAP-0080, TAP-0013,
    TAP-0049, TAP-0070, TAP-0083, and this TAP-0086 record.
  - Approved Scope: Remove the main-tree Locked Camera code and entry while
    preserving normal Camera/Library/Queue/App Intents plus the isolated future
    experiment and Git history.
  - Prototype/Manifest: `N/A`; no new app-owned UI, and the removed lock-screen
    surface is experimental/system-owned rather than an approved current UI.
  - Product Contract: `Docs/ProductContract.md` §4 now states that the shipping
    main project embeds no Locked Camera extension or runtime entry/import path
    and that experiments belong only on dedicated branches.
  - UI Prototype Contract: `N/A`; prototype authority/workflow did not change.
  - Root README: `N/A`; it contained no current Locked Camera integration claim.
  - Module README: `TAPCamDemo/TAPLibrary/README.md` removes the deleted locked-
    capture importer ownership row.
  - Test README: `TAPCamDemoTests/README.md` removes the deleted suite and its
    claimed coverage.
  - Specialized Contract: `N/A`; no public media, signing, security, or cross-
    project format contract changed.
  - Acceptance Record: `N/A for this removal`; TAP-0049 remains the blocked,
    independent attended procedure for a future TAP-0013 experiment and was not
    executed or satisfied.
  - AGENTS.md: `N/A`; repository workflow/governance did not change.
  - Other synchronized artifacts: `TAPCamDemo/Localizable.xcstrings` removes
    Locked Camera-only copy; `TAPCamDemo-Info.plist` removes its URL entry;
    `TAPDiagnosticsOSLogPrivacyTests` and associated tests reflect the retained
    production logging/source set; the lint manifest no longer requires the
    deleted importer.
  - Obsolete Files Removed: the complete
    `TAPCamLockedCameraCaptureExtension/`,
    `TAPCamLockedCameraControlExtension/`, and
    `TAPCamLockedCameraIntents/` trees;
    `LockedCameraAppContextPublisher.swift`,
    `LockedCaptureSessionContentImporter.swift`,
    `TAPPendingLockedCaptureImporter.swift`, and
    `TAPLockedCameraSessionContentTests.swift`.
  - Remaining Gaps/Risks: Runtime tests and device/Simulator execution were
    deliberately not run and are not claimed; they are not required by this
    Instant removal's Done When after the retained targets compiled and static/
    product evidence found no unresolved runtime dependency. The three existing
    lint complexity/length violations are outside TAP-0086 and remain visible
    without weakening this Task's evidence.
  - Follow-up Tasks: TAP-0013/TAP-0049 remain the isolated experiment/evidence
    path; TAP-0083 remains the independent cold-path governance Task.
  - Proposed Status: `Done` after explicit product-owner acceptance and Board
    Steward completion audit; the containing closure commit uses the recorded
    subject without a fabricated prospective hash.
- Done When: A complete repository source/project/product scan finds no Locked
  Camera production target, embedded `.appex`, source import, shared intent,
  startup/context/handoff/import route, app-owned entry, runtime localization,
  build entitlement/declaration, or test/lint dependency in main. Only explicit
  Product Contract, Board, acceptance-procedure, or historical references that
  preserve the isolated future experiment boundary may remain, and none may
  describe a main-tree production integration. A generic iPhone
  `build-for-testing` and test-target compilation pass; the built main app
  contains no Locked Camera extension product; ordinary Camera, Library,
  Pending Capture Queue, and retained App Intents still compile; `git diff
  --check` passes; and the development handoff reconciles Project Board,
  Product Contract §4, affected module/test READMEs, acceptance impact, removed
  files, validation commands, and every remaining experimental/historical
  reference. Simulator and physical-device launch are not required for this
  Instant removal unless build/source evidence exposes an unresolved runtime
  dependency.
- Current Closure Gate: `Passed by explicit product-owner acceptance.` The
  owner stated “完成验收现在把 0086 标记为 done 并提交”. Board Steward verified
  the accepted implementation, recorded validation limits and documentation
  impact, and moved TAP-0086 Doing -> Done. This acceptance does not turn the
  unrun Simulator/device/runtime checks or unrelated lint findings into passes.
- Related: Distinct from documentation cleanup `TAP-0080`, isolated replacement
  experiment `TAP-0013`, its attended evidence `TAP-0049`, deprecated capability
  claim `TAP-0070`, and cross-cutting cold-path governance `TAP-0083`
- Created: `2026-08-14`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-14` Allocated after a complete Inbox/Todo/Doing/Done/Deprecated
    search. TAP-0080 removed competing experiment prose and explicitly did not
    own code deletion; TAP-0013 and TAP-0049 retain a lifecycle-correct
    dedicated-branch experiment and attended procedure; TAP-0083 owns general
    cold-path responsiveness rather than feature removal; and deprecated
    TAP-0070 rejects the old production-capability claim without removing the
    integration. No existing Task owns complete main-tree target, entry,
    startup/handoff/import, source, and resource removal, so TAP-0086 is not a
    duplicate.
  - `2026-08-14` The owner directed “删除锁屏启动相关的代码和入口” and
    authorized allocation with “可以在 kanban 中新建一个 instant task 如果
    kanban 中没有类似的任务”. Created TAP-0086 in Inbox, recorded the
    bounded deletion/preservation scope and objective Done When, approved it to
    Todo, assigned `/root`, and moved Todo -> Doing for immediate execution on
    `main@6c45a77`. No implementation, deletion, build, test, documentation
    synchronization, commit, or Done transition is inferred by this allocation.
  - `2026-08-14` Corrected the implementation baseline from the earlier
    allocation placeholder `main@37d0c61` to actual `main@6c45a77` and recorded
    the complete uncommitted development handoff. Both extension targets and
    `.appex` products, shared intents, containing-app startup/context/session-
    import/URL/user-activity/route/queue integration, and dedicated resources/
    tests are removed while ordinary Camera/Library/Queue/App Intents remain.
    Product Contract §4, the TAP Library/test READMEs, localization, Info.plist,
    privacy harness, and lint inputs are synchronized; UI prototype, UI
    Prototype Contract, TAP-0049 acceptance, specialized contracts, root README,
    and AGENTS.md are N/A for the recorded reasons. A fresh generic iPhone Debug
    build-for-testing with signing disabled exited 0, only three targets remain,
    the app contains zero `.appex`, built Info has no Locked Camera URL, and
    source/project scans plus `plutil`, `jq`, and diff-check passed. Simulator/
    device and runtime tests were not run. The lint script passed its deleted-
    file gate but exited nonzero on three pre-existing unrelated complexity/
    length findings, so no lint pass is claimed; final read-only review found no
    P0/P1 issue. Per the owner's review-before-commit rule, TAP-0086 remains
    Doing pending result acceptance; only then may the containing commit subject
    `Remove Locked Camera integration from main` be created and closure audited.
  - `2026-08-14` The owner explicitly completed acceptance with “完成验收现在把
    0086 标记为 done 并提交”. Board Steward audited the accepted removal against
    Done When and moved TAP-0086 Doing -> Done. The generic iPhone Debug build-
    for-testing remains the build evidence; the retained project has three
    targets, the built app has zero `.appex` and no Locked Camera URL, and the
    recorded production-source/project/product scans passed. Simulator/device
    launches and runtime tests remain unrun and are not recharacterized as
    passes. The lint command still exited nonzero only for the three recorded
    pre-existing non-task complexity/length findings; no full lint pass is
    claimed. The implementation and Board closure are carried by the containing
    commit subject `Remove Locked Camera integration from main`; no prospective
    hash is written before Git creates it. TAP-0013, TAP-0049, TAP-0083, all
    other statuses, and Next Task ID remain unchanged.

### TAP-0087 — Define startup lifecycle, heavy-work budgets, and an instrumented prototype

- Status: `Doing`
- Kind: `Technical`
- Priority: `P0`
- Domain: `Startup Lifecycle / Runtime Observability / UI Prototype`
- Labels: `startup-lifecycle`, `install-context`, `process-launch`,
  `foreground-resume`, `launch-screen`, `first-frame`, `timing-budget`,
  `workload-map`, `state-machine`, `observability`, `web-prototype`,
  `permission-recovery`, `library`, `thumbnails`, `app-attest`,
  `pending-queue`, `2d`, `3d`
- Contract: `ProductContract §2–3, §5, §8–9`;
  `Docs/StartupLifecycleContract.md`; `UIPrototypeContract`;
  `ColdPathResponsiveness`; `Docs/AppAttest/README.md`
- Match Keys: `first install, app update, overwrite install, reinstall, offload
  reinstall, backup restore, device migration, permission revoked, t0 t1,
  launch screen to first frame, heavy operation, library initialization,
  thumbnail, attestation, re-sign queue, 2D analysis, 3D analysis, process
  owner, queue, state-machine inspector, 启动词汇, 覆盖安装, 重装, 重操作,
  状态机高亮`
- Assignee: `/root`
- Dev Session: `/root`
- Branch/Worktree: `Current shared main working tree; baseline main@985425f`
- Dependency Role: Owner-approved common prototype/semantic prerequisite that
  TAP-0008 and TAP-0009 consumed for their now-completed non-Network delivery,
  and that TAP-0083 still consumes for measured timing. Completing TAP-0087
  does not close TAP-0010, TAP-0015, TAP-0040, TAP-0041, TAP-0048, TAP-0083,
  or TAP-0090.
- Scope:
  1. Define canonical, behavior-bearing terminology for Fresh Installation,
     In-place App Update, Development Replacement Install,
     Delete-and-Reinstall, Offload-and-Reinstall with distinct current-build and
     changed-build cases, Same-Device Backup Restore, Cross-Device Migration
     Restore, Local State Inconsistency, Foreground Process Launch, Foreground
     Resume, Settings Return, Interrupted Relaunch, Cold Resource Path, and Warm
     Resource Path. Routing must use the actual structured `S/P/I` facts,
     current generation, and current permissions; a scenario or colloquial
     install label never selects a route by itself.
  2. Define first-install bootstrap and revoked-required-permission routing. For
     a Fresh Installation, First-Install Setup contains Network, Camera, and
     Photos as required rows; Location and Microphone remain optional. The
     Network row's explicit
     action owns initial App Attest registration/verification, and generic
     `/healthz` reachability is not its completion condition; this credential
     bootstrap is also not verification of a captured media proof. Camera or
     Photos revocation enters an app-owned Required Permission Check page;
     Network failure never enters that page. After setup, ordinary Viewfinder
     entry and local capture remain network-independent. Later App Attest
     health/recovery, Pending Capture work, and separately approved future
     membership networking are feature-owned and must not become a normal
     camera-entry gate. Permission actions use targeted status refresh after
     Settings/system boundaries.
  3. Define t0…tn milestones as events and Δ intervals as durations from system
     activation and the system-owned Launch Screen through first app frame,
     route acknowledgement, primary visual readiness, interactive readiness,
     and deferred-work eligibility. Every interval records allowed and
     prohibited work, blocker status, owner/actor/queue, completion,
     cancellation, recovery, and marker effects.
  4. Produce a source-grounded heavy-work registry and state-machine map for
     camera discovery/session/first preview/haptics; TAP Library store/catalog/
     PhotoKit observation; thumbnails and video posters; App Attest preparation
     and attestation; Pending Capture Queue retry/re-sign/export; 2D analysis;
     3D/depth/point-cloud analysis; and other material cold, foreground, and
     Viewer operations discovered by audit. Each entry records trigger,
     preconditions, runtime owner/queue, blocking/deferred status, state values,
     retry/cancel/stale-work behavior, output, and timing band. Mocked
     Viewfinder-control and Viewer 2D/3D workloads appear only as clearly marked
     `Deferred / child task` nodes, never as implemented TAP-0087 behavior. The
     registry must distinguish the explicit, required first-install App Attest
     bootstrap from post-setup deferred credential health/recovery and Pending
     Capture Queue work; only the former may block Continue inside Setup.
  5. Create an independent repository-owned static Prototype entry at
     `Prototype/startup-lifecycle.html`, driven by
     `Prototype/startup-model.mjs` as the single reducer/model and
     `Prototype/startup-prototype.mjs` as the page controller. Preserve
     `Prototype/index.html` as the historical entry containing the independently
     approved TAP-0008/TAP-0009/TAP-0081 slices; those prior slice approvals
     remain intact but neither approve nor define the TAP-0087 composition.
     Preserve approved `TAP-0008-r2`, including its Network row, visual language,
     assets, and geometry, and keep approved `TAP-0009-r1-candidate` as an
     immutable visual input. Produce composed state-machine/inspector revision
     `TAP-0087-r1-candidate`; its Network node represents first-install App
     Attest registration/verification rather than generic reachability. The
     reviewable journey is system-owned Launch Screen reference fixture ->
     scenario-dependent First-Install Setup, Required Permission Check, and/or
     Resource Initialization -> Viewfinder -> TAP Library -> Photo Viewer. The
     Prototype includes a Viewfinder page, Library page, Photo Viewer page,
     t0…tn timeline, and reviewer-only workload/state-machine inspector outside
     the iPhone canvas. Library entry, catalog/thumbnail states, opening a
     photo, and returning to Library are functional simulated transitions
     because they are required to inspect heavy-work timing. Prototype actions
     update and highlight the corresponding work, state node, transition edge,
     marker, and timing band.
  6. Keep TAP-0087's Viewfinder capture/control buttons as visual mocks only;
     this Task does not implement their operational control state machines. The
     Photo Viewer may show the `RAW / 2D / 3D` capsule, but TAP-0087 does not
     implement 2D or 3D analysis interaction/workflow behavior. Functional
     prototype/inspector treatment is deferred to child Tasks TAP-0088 and
     TAP-0089 after TAP-0008, TAP-0009, and TAP-0083 complete.
  7. Synchronize the resulting terminology and behavior into Product Contract,
     `ColdPathResponsiveness`, `UIPrototypeContract`, the Prototype manifest/
     README/QA, `Docs/AppAttest/README.md`, and affected module README
     responsibilities. The App Attest documentation must distinguish required
     initial bootstrap from post-setup deferred health/recovery. This
     synchronized contract/prototype is the common prerequisite consumed by
     TAP-0008, TAP-0009, and TAP-0083.
- Out of Scope:
  - Native TAP-0008 or TAP-0009 SwiftUI implementation.
  - Functional Viewfinder control-state/workload interactions; child TAP-0088
    owns that later prototype/inspector slice without duplicating native Camera
    feature delivery.
  - Functional Photo Viewer RAW/2D/3D analysis interactions or workflows; child
    TAP-0089 owns that later prototype/inspector slice without duplicating
    native Viewer/analysis delivery or claiming Video 3D.
  - Fixing or optimizing every inventoried heavy operation inside TAP-0087;
    gaps become scoped follow-up Tasks.
  - Native implementation of the first-install App Attest bootstrap/retry,
    canonical credential-bound `S`, or restore binding; TAP-0010 owns that
    delivery after the responsibility split.
  - Implementing post-setup App Attest/Pending retry optimization or inventing
    future membership networking; TAP-0015 separately owns credential retry
    optimization.
  - Share, AirDrop, or system Share behavior, which is closed and excluded.
  - Restoring Locked Camera, adding iPad support, or applying an old stash.
  - Faking iOS permission dialogs or treating reviewer-only inspector chrome as
    product UI.
  - Treating Launch Screen as an initialization or progress surface.
  - Claiming device performance or native parity from the Web prototype.
- Prototype Path/Revision/Approval: Independent entry
  `Prototype/startup-lifecycle.html`; single reducer/model
  `Prototype/startup-model.mjs`; page controller
  `Prototype/startup-prototype.mjs`; manifest `Prototype/manifest.json`. The
  manifest records `TAP-0087-r1-candidate` as `ownerReviewRequired`.
  `Prototype/index.html` remains the historical entry containing independently
  approved TAP-0008/TAP-0009/TAP-0081 slices; their approvals remain intact but
  do not approve the TAP-0087 composition, semantics, screens, or reviewer
  inspector. Approved `TAP-0008-r2`, including the visible Network row, remains
  the Setup visual input; TAP-0087 changes its inspector/state-machine meaning
  from reachability to first-install App Attest completion without silently
  changing the approved phone geometry. The previously recorded no-Network
  Setup candidate is historical only. Approved `TAP-0009-r1-candidate` remains
  an immutable visual input. The Launch Screen is visibly labeled system-owned reference
  material, and the inspector is visibly labeled reviewer-only tooling. Exact
  owner approval of `TAP-0087-r1-candidate` and the synchronized contract
  revision remains pending. The mismatch-specific `fix0809` decision below is
  partial review only and does not satisfy this whole-composition approval gate.
- Current Responsibility-Split Owner Decision: TAP-0008 and TAP-0009 have
  completed their non-Network native lifecycle placement and are Done as
  delivery Tasks. Their implemented but unverified lifecycle/workload records
  now derive regression ownership from TAP-0090, except that real route-shell/
  first-frame placement for `returningCameraConstruction` derives from
  TAP-0083. `networkBootstrap`, first-install credential start/completion,
  canonical credential-bound `S`, and restore binding remain actual-to-target
  differences owned by TAP-0010. Post-setup App Attest and credential/network-
  dependent Pending release/guards remain actual-to-target differences owned
  by TAP-0015. Exact native visual parity belongs to TAP-0048 and attended
  evidence remains TAP-0040/TAP-0041. `/healthz` remains observed current
  behavior and must never be shown as the target state. This stable Task-owned
  split supersedes active per-pass freeze wording without rewriting archived
  v17/v18 facts or approving the complete TAP-0087 composition.
- Archived v17 `fix0809` Reviewer Outcome Overlay Decision (`d4b19d9`): The
  owner approved a JSON-driven reviewer-only overlay that records the bounded
  `fix0809@66ac001`
  implementation and evidence outcome without rewriting the source-audited
  `main@4cc02e5f12f2` `actual`, `target`, `alignment`, or `mismatch` baseline
  truth and without claiming mainline delivery. `implementedLogAccepted` uses a
  yellow background and yellow border; `implementedNotLogVerified` uses a
  yellow background and red border and explicitly cannot be read as aligned;
  `deferredFrozen` keeps Network/App Attest and credential/network-dependent or
  Network-owned Pending records red with a red border; baseline-aligned records
  keep their existing green presentation. The same manifest-backed outcome was
  projected onto the right lifecycle cards, Timing lifecycle cards, and
  Workload **actual** difference cards. Existing dashed connector ownership and
  geometry, circular actual-phase anchors, and blue prototype Workload target
  effects remained unchanged. This was reviewer chrome only and authorized no
  Swift change. TAP-0087, TAP-0008, and TAP-0009 remained Doing; the complete
  v17 composition and synchronized contract remained `ownerReviewRequired`.
- Archived v17 Reviewer Outcome QA (`2026-08-15`; archive commit `d4b19d9`): The
  native candidate baseline for this pass was `66ac001`, while the immutable
  source-audit baseline was `main@4cc02e5f12f2`; the complete v17 reviewer state
  is retained in Git commit `d4b19d9`. This reviewer-only change created no
  Swift or native implementation commit. The manifest-backed four-state result
  was projected consistently onto
  the right lifecycle cards, Timing lifecycle cards, and Workload **actual**
  cards, with dashed connectors, circular actual-phase anchors, and existing
  blue prototype Workload targets unchanged. In the Codex in-app Browser at
  `1349 x 876`, Resource Initialization sequence `10` rendered six lifecycle
  cards with six one-to-one dashed paths and nine Workload actual cards: three
  `implementedLogAccepted`, four `implementedNotLogVerified`, and two
  `deferredFrozen`, with five existing blue targets and five dashed paths. The
  fresh-install sequence `6` frozen case rendered one actual card, one existing
  blue target, and one dashed path. Timing -> Ordered log -> Timing restored the
  same projections and connectors, and the browser console reported zero errors
  or warnings. Visual evidence is
  `Prototype/evidence/TAP-0087-r1-v17-fix0809-outcome-cards.png` and
  `Prototype/evidence/TAP-0087-r1-v17-fix0809-outcome-workload.png`. This verifies
  the archived v17 reviewer overlay only; it did not close TAP-0087, TAP-0008,
  or TAP-0009.
- Archived v18 Active-Record Pruning Decision: The owner approved `d4b19d9` as
  the complete v17 archive and approved a smaller active v18 reviewer catalog.
  The active manifest and its right lifecycle, Timing lifecycle, and Workload
  **actual** projections must remove records that were originally aligned and
  records whose v17 outcome was `implementedLogAccepted`. Active v18 retains
  only unresolved records: nine Lifecycle records and eight Workload records,
  comprising `implementedNotLogVerified` and `deferredFrozen` outcomes. This is
  active reviewer-record pruning, not a rewrite of the archived v17 facts, a
  new native-alignment claim, or authorization to change Swift. TAP-0087,
  TAP-0008, and TAP-0009 remain Doing; the complete v18 composition and
  synchronized contract remain `ownerReviewRequired`.
- Archived v18 Active-Record Implementation And QA (`2026-08-15`): Active JSON
  record deletion is complete rather than implemented as a display-only filter.
  The active Lifecycle catalog has nine unresolved records, partitioned between
  five lifecycle-lane owners and four workload-lane owners; eight are
  `implementedNotLogVerified` yellow/red and one is `deferredFrozen` red/red.
  The active Workload catalog has eight unresolved records, seven timing and one
  semantic; four are `implementedNotLogVerified` and four are `deferredFrozen`.
  Active `implementedLogAccepted` and originally aligned counts are both zero;
  commit `d4b19d9` remains the complete v17 archive.
  In the Codex in-app Browser at `1575 x 1204`, the right lifecycle panel showed
  five cards. Resource Initialization sequence `10` rendered five lifecycle
  cards/five dashed paths at actual anchors `t0` and `t2`, plus six Workload
  actual cards (four yellow/red and two frozen), three existing blue targets,
  three dashed paths, and all 16 canonical Workload trace effects. Fresh-install
  sequence `6` rendered three Workload actual cards, including one frozen card,
  with one existing blue target and one dashed path. Timing -> Ordered log ->
  Timing restored the same records, targets, and connectors. Visual evidence is
  `Prototype/evidence/TAP-0087-r1-v18-remaining-lifecycle.png` and
  `Prototype/evidence/TAP-0087-r1-v18-remaining-workload.png`.
  Prototype tests passed `58/58`; all six Prototype MJS syntax checks, manifest
  parse, and `git diff --check` passed. There is no Swift diff. This closes the
  active-record pruning implementation and reviewer QA only: TAP-0087, TAP-0008,
  and TAP-0009 remain Doing, and the complete v18 composition remains
  `ownerReviewRequired`.
- Implemented v19 Reviewer Semantics And Browser DOM QA (`2026-08-15`):
  - An implemented-but-unverified non-Network lifecycle record is no longer an
    active position mismatch. Merge its candidate/current context into the
    existing target-position card, use a yellow background with a red border,
    label it **已实现 · 待回归**, and link its stable verification owner. Do not
    render a separate actual card, blue duplicate target, **不一致** label, or
    dashed difference connector. TAP-0090 owns the general non-Network
    regression records; `returningCameraConstruction` links TAP-0083 for its
    real route-shell/first-frame timing boundary.
  - Truly unmigrated behavior keeps the red current-main actual card, existing
    blue target, and exactly one red dashed actual-to-target connector. Network/
    initial App Attest/canonical `S`/restore records link TAP-0010; post-setup
    App Attest and credential/network-dependent Pending records link TAP-0015.
    Visible and accessible copy names the owning Task directly and does not use
    a session-relative status label.
  - The same semantics apply to the right lifecycle cards, the Timing
    **08/09 生命周期** lane, and the existing Timing **Workload** lane. Workload-
    owned truths remain only in Workload. Implemented Workload records decorate
    their exact existing target effect yellow/red with no actual duplicate or
    connector; unmigrated Workload records retain the red-actual/blue-target
    difference pair and connector.
  - Historical `actual`/`target` audit facts remain manifest data and the v17
    archive remains recoverable at `d4b19d9`; placement in the active reviewer
    is derived from the record's v19 state and linked Task IDs.
  - The renderer, manifest, and tests now implement this v19 projection. Root
    verified it in the Codex in-app Browser through DOM counts and computed
    styles without retaining a screenshot. Ordinary sequence `17` rendered five
    right-side follow-up target cards and zero right-side differences; five
    Timing lifecycle follow-up cards and zero lifecycle paths; and four yellow
    Workload targets plus two red actual cards, two blue targets, and two paths.
    Fresh sequence `27` rendered two yellow Workload targets plus four red
    actual cards, four blue targets, and four paths. The console had zero errors
    or warnings. Prototype tests passed `58/58`; MJS syntax, manifest JSON, and
    diff checks passed. This verifies the v19 reviewer implementation only; it
    does not claim TAP-0090 regression completion, native visual parity, device
    acceptance, or whole-composition approval. TAP-0087 remains `Doing` and the
    complete composition remains `ownerReviewRequired` pending exact owner
    review.
- Done When:
  - The canonical glossary and deterministic scenario/route/marker matrix are
    recorded, including required first-install Attestation + Camera + Photos,
    optional Location/Microphone, and Continue gating.
  - The t0…tn/Δ timing contract and interval work budgets cover every approved
    scenario.
  - A source-grounded workload registry covers every approved heavy-operation
    family with trigger, owner/queue, blocking, state, recovery, and output;
    deferred Viewfinder-control and Viewer-analysis nodes link to TAP-0088 and
    TAP-0089 without claiming implementation.
  - The independent `Prototype/startup-lifecycle.html` entry, driven by
    `Prototype/startup-model.mjs` and `Prototype/startup-prototype.mjs`,
    deterministically demonstrates Launch Screen -> scenario-dependent setup/
    permission/initialization -> Viewfinder -> Library -> Photo Viewer, plus
    return-to-Library and linked inspector highlighting, with Network/App
    Attest, Camera, and Photos required and Location/Microphone optional. The
    Network row completes only on approved initial App Attest credential
    bootstrap, not `/healthz`; Network failure remains a Setup state rather than
    a Permission Check route. Camera/Photos revocation uses Required Permission
    Check, while post-setup network failure does not block Viewfinder or local
    capture. Exact TAP-0008-r2 and TAP-0009-r1-candidate phone visuals remain
    inputs; `Prototype/index.html` remains their historical entry rather than
    the TAP-0087 implementation surface.
  - Viewfinder controls remain visual-only mocks, and the Photo Viewer capsule
    introduces no functional 2D/3D analysis workflow in this Task.
  - Static prototype tests, accessibility/interaction checks, and visual design
    QA pass.
  - The manifest records `TAP-0087-r1-candidate` with the dedicated entry/model/
    controller mapping, including deliberate system-owned, reviewer-only,
    deferred, first-install-versus-post-setup App Attest, and native differences.
  - The product owner explicitly approves exact `TAP-0087-r1-candidate` and
    the synchronized contract revision.
  - Remaining native implementation, regression, parity, and performance gaps
    are handed to TAP-0010, TAP-0015, TAP-0083, TAP-0090, TAP-0040, TAP-0041,
    or TAP-0048; TAP-0087 completion does not close those Tasks.
- Related: Foundation `TAP-0006`; completed non-Network native delivery
  `TAP-0008`, `TAP-0009`; measured timing `TAP-0083`; deferred prototype
  children `TAP-0088`, `TAP-0089`;
  structured regression `TAP-0090`; evidence `TAP-0040`, `TAP-0041`,
  `TAP-0045`, `TAP-0047`, `TAP-0048`; credential
  optimization `TAP-0015`; historical onboarding foundations `TAP-0050`,
  `TAP-0051`; first-install retry re-scope `TAP-0010`; thumbnail policy
  `TAP-0027`
- Created: `2026-08-14`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-14` Allocated after the development session completed a full
    Inbox/Todo/Doing/Done/Deprecated search. TAP-0006 is the completed static
    prototype foundation; TAP-0008 and TAP-0009 own their native setup and
    readiness delivery; TAP-0083 overlaps cold-path guardrails but explicitly
    excludes visible prototype work and assigns first-install/resource
    readiness to TAP-0009. No existing Task owns the combined install taxonomy,
    t0…tn/Δ work-budget contract, cross-feature heavy-work trigger map, and
    interactive reviewer inspector, so TAP-0087 is an independent common
    prerequisite rather than a silent expansion or reopening.
  - `2026-08-14` The product owner explicitly approved the complete Scope,
    Out-of-Scope boundary, dependencies, prototype gate, and Done When, and
    directed `/root` to start. Recorded the canonical lifecycle sequence
    Inbox -> Todo -> Doing, assigned `/root` on baseline `main@985425f`, added
    prerequisite links to TAP-0008/TAP-0009/TAP-0083, and advanced allocation
    through child IDs TAP-0088/TAP-0089 to Next Task ID TAP-0090. No contract,
    prototype, implementation, test, acceptance, commit, push, or downstream
    status transition is inferred by allocation.
  - `2026-08-14` Owner clarified the exact review journey and deferred
    interaction boundary before implementation. TAP-0087 includes the
    system-owned Launch Screen reference, scenario-dependent Setup/Permission/
    Initialization, Viewfinder, Library, and Photo Viewer pages; Library
    catalog/thumbnail/open/return transitions are functional for timing review.
    Viewfinder controls remain visual mocks and Viewer 2D/3D interactions remain
    Deferred nodes. Allocated Inbox children TAP-0088 and TAP-0089 for those
    later prototype/inspector interactions after TAP-0008/TAP-0009/TAP-0083.
  - `2026-08-14` Owner removed Network from first-install Setup rather than
    merely making it nonblocking. Ordinary camera entry/capture is network-
    independent; Camera/Photos are the only required permission gates;
    Location/Microphone remain optional; and revoked Camera/Photos route to
    Required Permission Check. Revised the prototype gate so TAP-0087 preserves
    only TAP-0008-r2's non-Network visual language/assets/geometry, produces
    superseding `TAP-0008-r3-candidate` without Network plus composed
    `TAP-0087-r1-candidate`, and keeps TAP-0009-r1-candidate frozen. TAP-0010 is
    superseded as onboarding work; App Attest retry remains TAP-0015 scope and
    no membership behavior is inferred. TAP-0087 stays Doing, and no downstream
    status changes are implied.
  - `2026-08-14` Owner urgently corrected the immediately preceding no-Network
    direction. Fresh Installation requires Network/Camera/Photos, with the
    Network row completing initial App Attest registration/verification rather
    than generic `/healthz`; Location/Microphone remain optional. Network
    failure stays in Setup and never routes to Required Permission Check, which
    remains Camera/Photos-only. After setup, ordinary Viewfinder entry/capture
    remains network-independent and later credential/Pending work is deferred.
    Restored TAP-0008-r2 including its Network row as the visual input, removed
    the no-Network TAP-0008-r3 requirement, and assigned corrected semantics to
    TAP-0087-r1-candidate. Restored TAP-0010 to Todo pending exact re-scope/
    merge. The false interim direction remains append-only history; TAP-0087
    remains Doing and no downstream status transition is inferred.
  - `2026-08-14` Canonicalized the active Scope vocabulary to Fresh
    Installation, In-place App Update, Development Replacement Install,
    Delete-and-Reinstall, Offload-and-Reinstall current/changed-build cases,
    Same-Device Backup Restore, Cross-Device Migration Restore, Local State
    Inconsistency, and the exact activation/resource terms. Colloquial aliases
    remain only in Match Keys for find-before-create. Routing remains based on
    structured `S/P/I` facts rather than labels. TAP-0087 stays Doing;
    `Docs/StartupLifecycleContract.md` and `TAP-0087-r1-candidate` remain exact
    candidates requiring product-owner approval, so no contract/prototype gate
    or downstream status is closed by this terminology correction.
  - `2026-08-14` Corrected the Board's prototype-path projection to the actual
    independent TAP-0087 entry at `Prototype/startup-lifecycle.html`, with
    `Prototype/startup-model.mjs` as the single reducer/model and
    `Prototype/startup-prototype.mjs` as the page controller. Preserved
    `Prototype/index.html` as the historical entry for independently approved
    TAP-0008/TAP-0009/TAP-0081 slices; those approvals do not transfer to the
    TAP-0087 composition. TAP-0087 remains Doing, and exact owner approval of
    `TAP-0087-r1-candidate` plus the synchronized contract revision remains
    pending. No implementation, validation, or status completion is inferred.
  - `2026-08-15` Owner completed a mismatch-specific partial review for the
    bounded `fix0809` pass: the eleven non-Network canonical lifecycle mismatch
    IDs recorded in the current `fix0809` boundary are approved-to-fix.
    `networkBootstrap` is also confirmed as a real mismatch, but its fix is
    deferred from this pass; the existing Network/App Attest implementation is
    retained, the mismatch remains visible, and `/healthz` remains current-main
    evidence rather than a target-state claim. This decision does not approve
    the complete TAP-0087 v16 composition or synchronized contract revision,
    does not satisfy the exact owner-approval Done condition, and causes no
    TAP-0008/TAP-0009/TAP-0083 or acceptance status transition. TAP-0087 remains
    Doing.
  - `2026-08-15` Follow-up clarification narrowed the approved
    `deferredWorkGuard` parent without changing its lifecycle-card disposition:
    its App Attest maintenance child and every credential/network-dependent or
    Network-owned Pending Capture recovery-scheduling child are
    `deferredFrozen`. Only non-Network/App-Attest guard-placement children such
    as video-poster backfill and recent cover remain in the bounded `fix0809`
    scope. TAP-0087 remains Doing; no whole-composition approval, downstream
    implementation authority, acceptance, or status transition is inferred.
  - `2026-08-15` Owner approved the JSON-driven `fix0809` reviewer outcome
    overlay. The immutable source-audit baseline remains
    `main@4cc02e5f12f2`; `fix0809@66ac001` outcome is an orthogonal display
    record. Implemented and bounded-log-accepted records use yellow/yellow;
    implemented records not verifiable by that log use yellow/red and are not
    considered aligned; frozen Network/App Attest/Pending records remain
    red/red; baseline-aligned records remain green. The rule applies only to
    the right lifecycle, Timing lifecycle, and Workload actual cards; dashed
    connectors, actual-phase circles, and blue prototype Workload targets stay
    unchanged. This partial reviewer-overlay approval changes no Swift code,
    product state, Task status, complete-v16 approval boundary, acceptance
    matrix, frozen behavior, or push state. TAP-0087, TAP-0008, and TAP-0009
    remain Doing and the complete composition remains `ownerReviewRequired`.
  - `2026-08-15` Board Steward synchronized the completed v17 reviewer-overlay
    QA without rewriting the preceding v16 decision or evidence history. Git
    HEAD/native candidate remains `66ac001`, and the source-audit baseline
    remains `main@4cc02e5f12f2`. Browser verification at `1349 x 876` confirmed
    all four manifest-defined presentation states across the right lifecycle,
    Timing lifecycle, and Workload actual projections. Resource Initialization
    sequence `10` produced six lifecycle cards/six dashed paths and nine
    Workload actual cards (three log-accepted yellow/yellow, four implemented-
    but-unverified yellow/red, and two frozen red/red), with five existing blue
    targets/five dashed paths. Fresh-install sequence `6` produced one frozen
    actual/one existing blue target/one dashed path. Timing/log round-trip
    restoration passed, and the browser console reported zero errors or
    warnings. The two v17 PNGs are recorded under `Prototype/evidence/`. No
    Swift or native commit, Task status transition, whole-composition approval,
    acceptance-matrix expansion, frozen behavior change, or push is inferred.
    TAP-0087, TAP-0008, and TAP-0009 remain Doing; the complete v17 composition
    remains `ownerReviewRequired`.
  - `2026-08-15` Owner approved v18 active-record pruning after Git commit
    `d4b19d9` preserved the complete v17 reviewer state as the archive. Active
    v18 removes originally aligned and `implementedLogAccepted` records from the
    manifest-backed right lifecycle, Timing lifecycle, and Workload actual
    projections. The retained active catalog contains only unresolved records:
    nine Lifecycle and eight Workload records whose outcomes are
    `implementedNotLogVerified` or `deferredFrozen`. This approval does not
    rewrite the v17 archive, claim that an unlisted historical record never
    existed, authorize Swift changes, change native behavior, expand acceptance,
    or approve the complete v18 composition. TAP-0087, TAP-0008, and TAP-0009
    remain Doing; complete v18 remains `ownerReviewRequired`.
  - `2026-08-15` Board Steward recorded completion and reviewer QA of the v18
    active-record pruning without rewriting the preceding decision or any v17
    history. The active JSON arrays now physically contain only nine unresolved
    Lifecycle records (five lifecycle-lane owners plus four workload-lane
    owners; eight yellow/red and one frozen) and eight unresolved Workload
    records (seven timing plus one semantic; four yellow/red and four frozen).
    Active accepted/aligned counts are zero; `d4b19d9` remains the complete v17
    archive. At `1575 x 1204`, the Browser verified five right-side lifecycle
    cards; Resource Initialization sequence `10` verified five lifecycle paths
    at `t0`/`t2`, six Workload actual cards, three existing blue targets/paths,
    and all 16 canonical Workload effects; fresh-install sequence `6` verified
    three actuals including one frozen plus one blue target/path. Timing/log
    round-trip restoration passed. Two v18 PNGs record the result. Prototype
    tests passed `58/58`; six MJS syntax checks, manifest parse, and diff check
    passed; no Swift diff exists. This closes only v18 pruning implementation
    and reviewer QA. TAP-0087, TAP-0008, and TAP-0009 remain Doing; the complete
    v18 composition remains `ownerReviewRequired`.
  - `2026-08-15` Owner approved a tentative v19 reviewer meaning after
    separating delivery from evidence. Implemented-but-unverified non-Network
    records move to and merge with their target card/effect in yellow with a red
    border, link TAP-0090 or the measured-timing owner TAP-0083, and render no
    actual duplicate, **不一致** label, or dashed difference connector. Truly
    unmigrated initial Network/App Attest/`S`/restore records retain a red actual
    to blue target difference owned by TAP-0010; post-setup App Attest/Pending
    differences retain that form under TAP-0015. Visible copy names stable Task
    ownership instead of a session-relative freeze. TAP-0048 retains visual
    parity and TAP-0040/TAP-0041 retain attended evidence. TAP-0008/TAP-0009
    move to Done for their completed non-Network delivery; TAP-0087 remains
    Doing until the v19 prototype/manifest/tests/QA and exact owner review are
    complete. No regression, native, device, or whole-composition pass is
    inferred.
  - `2026-08-15` Board Steward synchronized the completed v19 reviewer
    implementation and no-screenshot Browser QA. The manifest and renderer now
    merge implemented-but-unverified records into yellow/red target cards or
    workload effects with no actual duplicate or connector, while Task-owned
    unmigrated records retain their red-actual/blue-target difference and
    direct TAP-0010/TAP-0015 link. DOM/computed-style verification in the Codex
    in-app Browser found, for ordinary sequence `17`, five right follow-up cards
    with zero differences, five Timing lifecycle follow-ups with zero paths,
    and four yellow Workload targets plus two red actuals/two blue targets/two
    paths. Fresh sequence `27` produced two yellow Workload targets plus four
    red actuals/four blue targets/four paths. Console errors/warnings were zero;
    Prototype tests passed `58/58`, and MJS syntax, manifest JSON, and diff
    checks passed. No photo, screenshot, or screen recording was retained as
    proof. TAP-0087 remains Doing and the complete composition remains
    `ownerReviewRequired`; no TAP-0090 regression, native parity, device
    acceptance, commit, or owner approval is inferred.

### TAP-0088 — Prototype functional Viewfinder-control workload interactions

- Status: `Inbox`
- Kind: `Technical`
- Priority: `P1`
- Domain: `UI Prototype / Viewfinder Observability`
- Labels: `prototype`, `inspector`, `viewfinder-controls`, `workload-map`,
  `state-machine`, `deferred`, `child-task`
- Contract: `UIPrototypeContract`; `ProductContract §3`; parent `TAP-0087`
- Match Keys: `functional Viewfinder mock, control state inspector, capture
  button state, camera control workload interaction, 取景器控件状态, 控件高亮`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Activation Gate: Deliberately deferred in Inbox. It may move to Todo only
  after `TAP-0008`, `TAP-0009`, and `TAP-0083` are Done and the owner starts
  this child scope.
- Scope: Extend the TAP-0087 visual-only Viewfinder control mocks and reviewer
  inspector into functional simulated control-state and workload interactions,
  using existing Camera capability contracts as inputs. Highlight control
  state, trigger, owner/queue, work node, transition, timing band, cancellation,
  and stale-work behavior without implementing native camera functionality.
- Out of Scope: Native Viewfinder controls, capture/session implementation,
  white-balance delivery, source switching, or changing current Camera
  capabilities owned by TAP-0053, TAP-0017, TAP-0018, and related Camera Tasks.
- Done When: After activation, one Task-scoped prototype revision supplies the
  approved functional Viewfinder-control/inspector interactions, deterministic
  fixtures, manifest traceability, static interaction/accessibility tests,
  visual QA, and explicit owner approval without claiming native delivery.
- Related: Parent `TAP-0087`; blocked by completion of `TAP-0008`, `TAP-0009`,
  `TAP-0083`; native capability owners `TAP-0053`, `TAP-0017`, `TAP-0018`;
  device evidence `TAP-0042`
- Created: `2026-08-14`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-14` Allocated as an owner-directed deferred child after all-status
    duplicate search found native Camera capability Tasks but no exact
    prototype/inspector follow-up for functional Viewfinder-control workload
    interactions. Kept Inbox and Unassigned; no native capability, prototype
    implementation, approval, or prerequisite completion is inferred.

### TAP-0089 — Prototype functional Photo Viewer analysis workload interactions

- Status: `Inbox`
- Kind: `Technical`
- Priority: `P1`
- Domain: `UI Prototype / Photo Viewer Observability`
- Labels: `prototype`, `inspector`, `photo-viewer`, `raw`, `2d`, `3d`,
  `analysis-workload`, `state-machine`, `deferred`, `child-task`
- Contract: `UIPrototypeContract`; `ProductContract §5`; parent `TAP-0087`
- Match Keys: `functional Photo Viewer mock, RAW 2D 3D inspector, analysis
  workload interaction, point cloud state, viewer mode state, 分析状态高亮`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Activation Gate: Deliberately deferred in Inbox. It may move to Todo only
  after `TAP-0008`, `TAP-0009`, and `TAP-0083` are Done and the owner starts
  this child scope.
- Scope: Extend TAP-0087's visual-only Photo Viewer `RAW / 2D / 3D` capsule and
  reviewer inspector into functional simulated analysis-state and workload
  interactions for the existing Photo Viewer capability boundaries. Highlight
  trigger, owner/queue, loading/readiness, work node, transition, timing band,
  cancellation, failure, and stale-work behavior without implementing native
  Viewer or analysis functionality.
- Out of Scope: Reimplementing native Viewer paging, RAW/2D analysis, static 3D
  point projection, TAP Video 3D, or advanced per-frame video-depth analysis;
  claiming Video 3D; or changing capability decisions owned by TAP-0059,
  TAP-0060, TAP-0016, and TAP-0038.
- Done When: After activation, one Task-scoped prototype revision supplies the
  approved functional Photo Viewer analysis/inspector interactions,
  deterministic fixtures, explicit Deferred handling for unsupported/future
  modes, manifest traceability, static interaction/accessibility tests, visual
  QA, and owner approval without claiming native or Video 3D delivery.
- Related: Parent `TAP-0087`; blocked by completion of `TAP-0008`, `TAP-0009`,
  `TAP-0083`; capability boundaries `TAP-0059`, `TAP-0060`, `TAP-0016`,
  `TAP-0038`
- Created: `2026-08-14`
- Updated: `2026-08-14`
- Revision History:
  - `2026-08-14` Allocated as an owner-directed deferred child after all-status
    duplicate search found the existing native Viewer/static-3D/video-3D
    capability Tasks but no exact prototype/inspector follow-up for functional
    Photo Viewer RAW/2D/3D workload interactions. Kept Inbox and Unassigned; no
    native analysis, Video 3D, prototype implementation, approval, or
    prerequisite completion is inferred.

### TAP-0090 — Add machine-checkable non-Network startup lifecycle regression evidence

- Status: `Todo`
- Kind: `Evidence`
- Priority: `P0`
- Domain: `Startup Lifecycle / Regression Observability`
- Labels: `startup-lifecycle`, `non-network`, `structured-log`, `jsonl`,
  `regression`, `event-order`, `simulator`, `device-evidence`, `no-screenshot`
- Contract: `ProductContract §2.1–2.6`; `StartupLifecycleContract §2–5`;
  `UIPrototypeContract §4.1`; evidence consumers `TAP-0040`, `TAP-0041`
- Match Keys: `lifecycle regression harness, startup trace, structured startup
  log, JSONL evidence, machine-checkable event order, implemented awaiting
  regression, 黄色红边, log 不足, 无截图 proof`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Responsibility: Supply reusable regression instrumentation and assertions for
  the non-Network native lifecycle placement completed by `TAP-0008` and
  `TAP-0009`. This Task validates that delivery; it does not reopen those
  delivery Tasks or absorb their attended evidence Tasks.
- Scope:
  1. Define one privacy-safe, versioned JSON/JSONL activation trace. Every event
     carries at least schema version, run/scenario ID, monotonically increasing
     sequence and clock value, source commit/build configuration, runtime
     platform, activation kind, public-safe `S/P/I` disposition, route, event,
     workload/checkpoint, logical owner/executor, result, and correlation or
     predecessor ID. It must not contain media identifiers, file paths, URLs,
     hashes, App Attest key material, or credential identifiers.
  2. Add deterministic automated/Simulator assertions for the in-scope
     non-Network boundaries: no permission request or protected Camera/PhotoKit
     work before its explicit action; row-owned denied/restricted recovery;
     Camera/Photos-only Required Permission Check routing and targeted refresh;
     observer-inert startup followed by one eligible idempotent activation;
     independent versioned `I` invalidation/atomic commit/interruption behavior;
     camera-plus-first-usable-catalog readiness ordering; stable Resource
     Initialization with no product failure branch; and local video-poster,
     recent-cover, and App Intent release only after the committed local
     deferred-work barrier.
  3. Produce a machine-readable assertion report that maps each assertion to
     the stable TAP-0087 lifecycle/workload record IDs it verifies, without
     duplicating one lifecycle parent as multiple completion claims.
  4. Make the same schema usable by the attended `TAP-0040`/`TAP-0041`
     procedures. Automated and Simulator results prove deterministic structure
     and ordering only; the separate owner-attended Tasks retain real system
     permission, preview, haptic, capture, and device verdict ownership.
- Evidence Form: Retain structured JSON/JSONL logs, the machine-readable
  assertion report, build/commit/device metadata, and an owner-live textual
  verdict when consumed by a DeviceAcceptance Task. Do not save a photo,
  screenshot, or screen recording as proof.
- Out of Scope: Changing product lifecycle behavior while adding evidence;
  Network `/healthz` replacement, initial App Attest, canonical credential-
  bound `S`, or restore binding owned by `TAP-0010`; post-setup App Attest and
  credential/network-dependent Pending guards owned by `TAP-0015`; real route-
  shell/first-frame placement and numeric 2 x 2 timing owned by `TAP-0083`;
  prototype-to-native visual parity owned by `TAP-0048`; or closing attended
  `TAP-0040`/`TAP-0041`. A failing assertion returns a scoped defect to the
  responsible delivery Task instead of silently broadening TAP-0090.
- Done When: The versioned public-safe schema, instrumentation, fixture matrix,
  and assertions are committed; focused tests prove every in-scope positive and
  prohibited-order condition; a clean automated/Simulator run emits parseable
  artifacts with stable record-ID mapping and no sensitive fields; the
  `TAP-0040`/`TAP-0041` procedures can consume the same trace without photo,
  screenshot, or recording proof; and failures remain attributable to one
  delivery owner. Device acceptance, visual parity, performance thresholds, and
  Task-owned Network/App Attest/Pending behavior may remain open separately.
- Related: Validates completed delivery `TAP-0008`, `TAP-0009`; prototype
  projection `TAP-0087`; attended consumers `TAP-0040`, `TAP-0041`; measured
  timing `TAP-0083`; visual parity `TAP-0048`; excluded initial credential
  delivery `TAP-0010`; excluded post-setup credential/Pending delivery
  `TAP-0015`
- Created: `2026-08-15`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-15` Allocated after a complete Inbox/Todo/Doing/Done/Deprecated
    duplicate search. TAP-0040/TAP-0041 already own attended device verdicts,
    TAP-0083 owns real shell/first-frame timing and its four-cell physical-
    iPhone matrix, and TAP-0048 owns visual parity; none owns a reusable,
    machine-checkable non-Network lifecycle trace and regression harness. The
    owner approved that exact remaining evidence responsibility, so the Board
    recorded the required lifecycle Inbox -> Todo without splitting one
    assertion Task per prototype record. No instrumentation, regression result,
    device verdict, or downstream Task closure is inferred.

### TAP-0091 — Eliminate out-of-preview Viewfinder chrome flicker during camera-path switching

- Status: `Inbox`
- Kind: `Fix`
- Priority: `P1`
- Domain: `Camera / Viewfinder Presentation`
- Labels: `camera-path-switch`, `lens-switch`, `front-rear-switch`,
  `viewfinder-chrome`, `redraw`, `flicker`, `transition-boundary`
- Contract: `ProductContract §3.1`; `UIPrototypeContract §4`
- Match Keys: `切换镜头闪烁, 切换相机闪烁, 设置按钮重绘, preview 外元素重绘,
  camera switch flicker, lens switch redraw, settings button flash, chrome
  remount, FOV switch flicker, front rear switch flicker`
- Assignee: `Unassigned`
- Dev Session: `Unassigned`
- Branch/Worktree: `Unassigned`
- Affected States: The exact reproducing path must be frozen before Todo,
  distinguishing current Standard FOV selection, front/rear camera switching,
  and Photographer Mode camera-path restoration. Cover transition start,
  in-progress, successful readiness, and failure/recovery for the approved path.
- Prototype Impact: Expected `N/A` only if the fix preserves the current
  hierarchy, icon identity, geometry, copy, and intended transition appearance.
  Any intentional visible change requires a Task-scoped Web-prototype revision
  and explicit owner approval before native implementation closes.
- Scope: Reproduce, diagnose, and remove the user-visible redraw/flicker of
  Viewfinder chrome outside the preview window while the approved camera path
  is switching. The Settings button and other out-of-preview controls must
  retain stable visual identity and placement while interaction is safely
  disabled or restored; preview-owned transition treatment remains confined to
  its approved boundary.
- Out of Scope: Designing true camera-source switching owned by `TAP-0018`;
  changing capture/FOV/depth semantics; redesigning Viewfinder hierarchy,
  controls, copy, icons, or layout; masking unrelated startup or camera-session
  latency; or treating an unverified implementation mechanism as the cause.
- Done When: The owner-approved reproduction matrix identifies the exact
  trigger, build, iPhone/iOS, affected chrome, and expected stable boundary;
  the approved native fix preserves out-of-preview chrome across the reproduced
  success and failure/recovery states; contract-focused regression coverage and
  Simulator checks pass; prototype/documentation impact is reconciled; and a
  separate attended physical-device acceptance child records before/after
  evidence without broadening `TAP-0018`.
- Related: `TAP-0018`; `TAP-0088`; allocate a dedicated DeviceAcceptance child
  when this Inbox scope is approved for Todo
- Created: `2026-08-15`
- Updated: `2026-08-15`
- Revision History:
  - `2026-08-15` Allocated after a complete Inbox/Todo/Doing/Done/Deprecated
    search found camera switching and Viewfinder prototype Tasks but no Task
    owning the reported runtime chrome flicker. Preserved the owner's raw
    observation: “在切换镜头的时候 viewfinder 的 UI 元素会闪烁，或者更准确地说，
    出现了 preview 窗口之外的元素的重绘，比如设置按钮等等”. Kept Inbox and
    Unassigned pending an exact reproduction matrix; no root cause, UI redesign,
    implementation, validation, prototype exception, or acceptance is claimed.
  - `2026-08-15` Renumbered the uncommitted local allocation from provisional
    `TAP-0090` to canonical `TAP-0091` during mainline synchronization because
    main had already allocated `TAP-0090` to non-Network lifecycle regression
    evidence. Preserved both Tasks and advanced the allocator without changing
    either Task's scope or status.

### TAP-0092 — Clean up brittle tests, unmounted legacy code, and redundant repository information

- Status: `Done`
- Kind: `Technical`
- Priority: `P0`
- Domain: `Repository Health / Tests / Documentation`
- Labels: `repository-health`, `test-debt`, `brittle-test`, `source-spelling`,
  `dead-code`, `legacy-unmounted`, `documentation-drift`, `cleanup`
- Contract: `ProductContract §1`; `AGENTS.md §4`, `§5`, `§7`
- Match Keys: `仓库清理, 不合适的测试, 过度测试, 源码拼写测试, 旧代码,
  无用代码, 冗余信息, 重复文档, brittle tests, source inspection, dead code,
  stale docs, repository cleanup`
- Assignee: `/root` orchestrator with medium-reasoning child Agents
- Dev Session: `/root` (single active coordinating Session; each approved
  `replace` item may be delegated to one medium-reasoning child Agent)
- Branch/Worktree: `main` shared checkout at approval baseline
  `42c5e9355cbcdf9e6a0d7c7f750aeb4ef54ecb6f`; no dedicated worktree
- Owner Target Date: `2026-08-24`
- Prior Approved Execution Scope (`2026-08-21`): Replace-only. Approved rows are `T92-SRC-001`
  through `T92-SRC-006`, `T92-START-011`, the replacement stage only of
  `T92-CODE-002`, `T92-DOC-001` through `T92-DOC-003`, and conditional
  `T92-DOC-004` only after its recorded code-decision prerequisite is met.
  `retain`, `defer`, standalone/conditional `migrate-delete`, production-code
  deletion after `T92-CODE-002`, and execution of `T92-DOC-004` before its
  prerequisite remain unauthorized. Simulator validation is allowed, but every
  Simulator test that does not change or strengthen a cleanup conclusion must
  be recorded individually as non-contributing evidence rather than counted as
  support for replacement or deletion.
- Current Owner Expansion (`2026-08-23`): Direct deletion is approved for
  production/support code proven unmounted, disabled, or legacy-only; tests
  proven to assert source spelling, exact implementation shape, fake Simulator
  success, or an already-removed path; stale or duplicated README prose; and
  pre-release compatibility/version branches that do not serve current runtime,
  security, public-format, persistence, or cross-project obligations. Preserve
  active UX/UI and production behavior. Keep recovery, state-machine, security,
  privacy, format, persistence, and future-change prerequisite regressions.
  App Attest hardware/backend and physical-camera evidence remains device-only;
  Simulator no-op returns must not count as passes. Execute independently
  validated deletion slices and score the same repository-health rubric after
  each slice; stop after three consecutive score increases. This owner decision
  supersedes only the old replace-before-delete restriction and does not
  authorize active-production refactoring.
- Responsibility: Execute one bounded repository-health cleanup pass against the
  2026-08-15 audit baseline. Remove only debt that has evidence and an explicit
  disposition; preserve current product behavior, security properties, public
  formats, persistence migrations, and still-owned compatibility obligations.
- Scope:
  1. Freeze a per-file/per-test cleanup manifest classifying each candidate as
     retain, replace with contract-focused behavior coverage, migrate then
     delete, or defer to an existing Task, with evidence and an owning Task for
     every non-deletion.
  2. Remove or replace source-spelling, exact-layout, duplicated-fixture, and
     implementation-order tests that do not protect a current contract. Retain
     security, privacy, format, fail-closed, state-machine, and architecture
     guards where source inspection is the appropriate boundary, and run them
     through an explicit static-gate profile rather than presenting them as UI
     behavior evidence.
  3. Retire confirmed unmounted legacy production paths together with tests and
     prose that exist only to preserve those paths, after migrating any unique
     current obligation and verifying that no production route, public format,
     persistence migration, or cross-project interface still depends on them.
  4. Reconcile directly conflicting or duplicated active documentation, reduce
     repeated implementation/test inventories to stable responsibility and
     command summaries, update inbound links, and leave superseded detail in Git
     history rather than another active archive.
  5. Triage the current deterministic and parallel-sensitive test failures,
     record declared/executed/passed/failed/skipped counts, and leave one
     repeatable repository-health validation path for the cleaned scope.
- Coordination Boundary: `TAP-0029` retains Debug-support isolation and large-
  suite file organization; `TAP-0014` retains the product-facing owned-capture
  Verify decision; `TAP-0002`, `TAP-0003`, and `TAP-0079` remain the completed
  document-authority and historical-retention foundations. This Task consumes
  their boundaries without silently changing their lifecycle states.
- Out of Scope: Changing product behavior or visible UI; deleting a compatibility
  seam solely because a static search finds no caller; removing security/privacy/
  format coverage to improve a test count; restoring AITrace or creating a new
  historical-prose archive; absorbing the structural work owned by `TAP-0029`;
  claiming the whole repository is permanently debt-free after one pass; or
  executing any `retain`, `defer`, or pure/next-stage `migrate-delete` item not
  included in the replace-only approval above.
- Done When: The owner-approved bounded cleanup manifest is fully dispositioned;
  every deleted test, source file, document section, and localization key has an
  evidence-backed obligation check; retained compatibility seams have a current
  owner and reason; the same repository-health score increases after three
  independently validated iterations and execution stops at that boundary;
  builds, references, links, and retained focused gates show no new cleanup
  regression; full and diagnostic runs report exact executed/passed/failed/
  skipped counts with every residual failure classified rather than presented
  as a pass; documentation-impact and obsolete-file records are complete; and
  no current UX/UI, production, security, format, persistence, or acceptance
  boundary is broadened by the cleanup.
- Prior Execution Handoff (`2026-08-21`):
  - Task ID: `TAP-0092`
  - Dev Session: `/root` orchestrator with medium-reasoning child Agents
  - Branch/Worktree: shared `main`; baseline
    `42c5e9355cbcdf9e6a0d7c7f750aeb4ef54ecb6f`; no commit or push
  - Contract Sections Read: `ProductContract §1`; `AGENTS.md §4`, `§5`, `§7`;
    complete Task and manifest
  - Approved Scope: replace-only rows recorded above
  - Implemented Scope: `T92-DOC-001`, `T92-DOC-002`, and `T92-DOC-003`
    validated. `T92-SRC-001` through `006`, `T92-START-011`, and replacement-
    stage `T92-CODE-002` could not prove an equal-strength controlled
    regression through existing production behavior seams, so all attempted
    Swift test edits were reverted and those items returned to Pending.
    Conditional `T92-DOC-004` is Blocked/unchanged because its code-disposition
    prerequisite is unmet.
  - Prototype Path/Revision/Approval: N/A for product/UI change. Prototype
    contract tests passed `20/20`; this is documentation/prototype health, not
    new UI approval, Simulator parity, or device acceptance.
  - Tests And Builds Run: pre-mutation Simulator baseline `822 executed / 813
    passed / 9 failed / 0 skipped`; valid serialized diagnosis classified six
    persistent and three parallel-sensitive failures. Final Debug Simulator
    `build-for-testing` succeeded. Focused slice runs, invalid zero-executed
    attempts, known failures, and every test whose contribution was `None` are
    recorded individually in the evidence ledger. A green test did not satisfy
    a Pending replacement without controlled-regression proof.
  - Evidence And Acceptance:
    [cleanup manifest](TAP-0092CleanupManifest.md) and
    [execution evidence ledger](TAP-0092CleanupEvidence.md). Transient source
    reports are `/private/tmp/TAP0092BaselineReport.md`, each
    `/private/tmp/T92-*Result.md`, and `/private/tmp/TAP0092FinalValidation.md`.
    The final validation snapshot predates the completed DOC-001 r3 wording
    correction and evidence cross-link; current link/diff checks supersede only
    those two stale observations. Fourth-round independent read-only review
    accepted the ledger for Board handoff after confirming zero per-xcresult
    count deltas, complete run inventory without duplicates, consistent
    arithmetic, and reciprocal links. This evidence acceptance does not satisfy
    any Pending/Blocked replacement or the Task Done When.
  - Documentation Impact:
    - Project Board: this record and global revision log updated by Board Steward
    - Product Contract: N/A; no product behavior or claim boundary changed
    - UI Prototype/Manifest: N/A; no prototype artifact changed
    - UI Prototype Contract: N/A; workflow unchanged
    - Module README: `TAPCamDemoTests/README.md` replaced with a stable
      reader-first entry point; `DepthAnalysis/README.md` unchanged
    - Specialized Contract: Camera packaging documentation now links five
      canonical future-work Tasks without changing format/signing boundaries
    - Acceptance Record: TAP-0048 procedure reconciled to the approved
      r1-geometry/r3-behavior and TAP-0082 superseding decision; its parity
      verdict remains Pending
    - AGENTS.md: N/A; repository workflow unchanged
  - Obsolete Files Removed: none; no production/test Swift deletion
  - Remaining Gaps/Risks: eight approved replace scopes are Pending, conditional
    `T92-DOC-004` is Blocked, and baseline/focused known failures remain open;
    the accepted evidence ledger records rather than closes these gaps
  - Follow-up Task IDs: existing owners `TAP-0029`, `TAP-0014`, `TAP-0048`
  - Proposed Status: remain `Doing`; Done When is not met
- Completion Handoff (`2026-08-23`):
  - Task ID: `TAP-0092`
  - Dev Session: `/root` Board Steward and implementation coordinator with
    read-only legacy-code, test-value, and documentation/version auditors
  - Branch/Worktree: shared `main` checkout from baseline
    `42c5e9355cbcdf9e6a0d7c7f750aeb4ef54ecb6f`; no commit or push
  - Build/Commit: Xcode 26.6 / macOS 26.6, iPhone 17 Pro iOS 26.5
    Simulator `742A3184-E1C7-44FC-99E0-0C8DFE807698`; working tree only
  - Contract Sections Read: complete cross-cutting `ProductContract`; complete
    TAP-0092 record and Board operating rules; `UIPrototypeContract`; relevant
    App Attest, startup, output, TAP Video, Live Photo, acceptance, module
    README, current implementation, and test surfaces
  - Approved Scope: the `2026-08-23` direct-deletion expansion and fixed-score
    stop rule recorded above; preserve mounted behavior, UX/UI, security,
    privacy, public formats, persistence, and cross-project obligations
  - Implemented Scope: completed three independently reversible closures:
    unmounted owned-capture backend Verify; speculative output-resource plan;
    former analysis drawer/inspectors/ViewModel/HUD plus fake Camera/UI evidence.
    Removed all `137` frozen low-value tests plus `16` tests exclusive to
    deleted islands, added one current `AnalysisPhotoSlot` load-failure
    regression, excluded two physical-device artifact tests from Simulator
    declaration, removed `94` proven-orphan localization keys, reconciled active
    documentation, and removed test-target-only marketing/build versions while
    retaining app `0.2 (2)` and every current public/security schema version.
  - Prototype Path/Revision/Approval: N/A for visual approval; no visible state,
    hierarchy, copy placement, interaction, or native UI behavior changed.
    Historical prototype QA prose was pruned without changing the approved
    prototype revision or behavior.
  - Tests And Builds Run: every iteration's Debug Simulator
    `build-for-testing` passed. Iteration 1 focused `60 total / 58 passed / 2
    known failed / 0 skipped`; Iteration 2 focused `39/39`; Iteration 3 retained
    focused gates `161/159/2/0`; full Unit target `664/655/9/0`; serialized
    failure diagnostics `109/105/4/0`. Five full-run-only failures passed
    serialized. Final incremental `build-for-testing` after localization cleanup
    also passed.
  - Evidence And Acceptance: [cleanup manifest](TAP-0092CleanupManifest.md) and
    [execution evidence ledger](TAP-0092CleanupEvidence.md). The fixed score rose
    `20.0 -> 27.3 -> 33.4 -> 84.1`; the third consecutive increase triggers the
    owner-required stop. Source declarations fell `822 -> 670`; Simulator-
    executable tests `822 -> 668`; production Swift LOC `72,558 -> 69,020`;
    test Swift LOC `29,132 -> 24,727`; localization keys `471 -> 377`; broken
    local Markdown targets and lost public/security obligations remain zero.
  - Files Updated:
    - Project Board: this status, completion handoff, Kanban projection, and
      append-only revision history
    - Product Contract: N/A; no product behavior, state, term, or claim changed
    - UI Prototype/Manifest: historical QA evidence only; active visual truth
      unchanged
    - UI Prototype Contract: N/A; workflow unchanged
    - Module README: root, App, CameraCapture, Output, DepthAnalysis, and Tests
      current-reading paths clarified
    - Specialized Contract: App Attest endpoint prose and startup responsibility
      clarified; current format/schema versions retained
    - Acceptance Record: obsolete TAP-0082 attempt history removed; TAP-0046
      physical-device plus production-backend trust boundary retained
    - AGENTS.md: N/A; repository workflow unchanged
  - Obsolete Files Removed: two owned-capture Verify files; speculative output-
    resource plan; ten former analysis inspector/drawer files; legacy mutable
    analysis ViewModel; never-mounted metadata HUD; fake Camera-controls test
    harness; two fake UI-test files; and their exclusive tests, prose, model
    slices, and localization keys. Git remains the archive.
  - Remaining Gaps/Risks: four serialized failures remain explicit: frozen
    Share stale-callback, OSLog reviewed-label, and Simplified Chinese catalog
    failures, plus unsigned-Simulator Keychain `-34018`. Eight CameraCapture
    micro-documents, three compatibility families, and four pre-release TODO
    families remain intentionally owned; they are not a fourth cleanup
    iteration. Device App Attest trust remains unaccepted under TAP-0046.
  - Follow-up Task IDs: `TAP-0029` for Debug/support suite structure;
    `TAP-0046` for physical-device App Attest production acceptance; existing
    startup and compatibility owners including `TAP-0010` and `TAP-0022`
  - Proposed Status: `Done`; the fixed three-increase stop condition and revised
    objective Done When are satisfied without a product/UI change
- Related: Structural test debt `TAP-0029`; owned-capture Verify cleanup
  `TAP-0014`; documentation authority and retention `TAP-0002`, `TAP-0003`,
  `TAP-0079`; deprecated legacy UI responsibilities `TAP-0067`, `TAP-0069`
- Created: `2026-08-15`
- Updated: `2026-08-23`
- Revision History:
  - `2026-08-15` Allocated after an all-status duplicate and responsibility
    search. The closest active match, `TAP-0029`, owns only Debug-support
    isolation and oversized-suite organization, so it remains separate. The
    owner explicitly set P0 and the target date `2026-08-24` for the broader
    semantic cleanup of inappropriate tests, unmounted old code, redundant
    information, and stale active documentation. Kept Inbox and Unassigned until
    the exact cleanup manifest and safety boundaries are approved; no deletion,
    test fix, document rewrite, product change, validation pass, commit, or push
    is inferred.
  - `2026-08-21` Product owner approved every manifest row whose disposition is
    `replace`, with a strict replace-only boundary. Moved Inbox -> Todo after
    recording the exact approved IDs, keeping every `retain`, `defer`, and pure
    or later `migrate-delete` stage Pending. For `T92-CODE-002`, approval covers
    replacement/migration of valuable tests to current seams only and does not
    authorize production-code deletion. `T92-DOC-004` is approved only after
    its code-decision prerequisite is satisfied. No implementation, validation,
    deletion, product/UI change, commit, or push is inferred by this approval.
  - `2026-08-21` Bound `/root` as the single coordinating development Session
    on the shared `main` checkout and moved Todo -> Doing. The owner directed
    one medium-reasoning child Agent per approved replace item and allowed
    iPhone Simulator validation. Every Simulator test that contributes nothing
    to the cleanup conclusion must be recorded individually as non-contributing;
    running it cannot be used as replacement/deletion evidence. No test result,
    code/document mutation outside the approved replace rows, Done transition,
    commit, or push is inferred.
  - `2026-08-21` Board Steward synchronized the replace-only execution handoff
    to the [manifest](TAP-0092CleanupManifest.md) and
    [evidence ledger](TAP-0092CleanupEvidence.md). Three documentation rows are
    Validated; six source clusters, the startup row, and the CODE-002
    replacement stage are Pending after equal-strength controlled regressions
    could not be proved through existing production behavior seams; DOC-004 is
    Blocked/unchanged on its unmet code-disposition prerequisite. Every
    attempted Swift test edit was reverted, so production/test Swift diff is
    zero. The baseline remains `822/813/9/0` with six persistent and three
    parallel-sensitive failures; final Debug Simulator `build-for-testing` and
    Prototype `20/20` passed, but green gates do not complete Pending rows.
    Focused known failures, invalid zero-executed attempts, and per-test
    non-contribution records are linked in the ledger. Evidence second review
    is still running; TAP-0092 remains Doing with no deletion, acceptance,
    commit, push, or Done claim.
  - `2026-08-21` Superseded only the preceding evidence-review-status clause:
    fourth-round independent read-only review accepted the evidence ledger for
    Board handoff with zero per-xcresult count deltas, no missing or duplicate
    run entries, consistent arithmetic, and factual reciprocal links. This
    acceptance confirms evidence completeness; it does not turn green tests
    into controlled-regression proof, resolve eight Pending scopes or blocked
    DOC-004, close baseline/focused failures, or satisfy Done When. TAP-0092
    remains Doing with no additional mutation, deletion, commit, or push.
  - `2026-08-23` The owner broadened TAP-0092 from replace-only cleanup to
    evidence-backed direct deletion of confirmed unmounted/disabled/legacy code,
    source-spelling and fake-Simulator tests, stale README prose, and unnecessary
    pre-release compatibility/version branches. Active UX/UI, production
    behavior, security/privacy, public formats, persistence, and cross-project
    obligations remain protected. Related cleanup Tasks may be reconciled in the
    same pass. The owner also required one fixed health score after every bounded
    iteration and termination after three consecutive improvements. No deletion,
    validation result, status change, commit, or push is inferred by this scope
    revision.
  - `2026-08-23` Completed the owner-approved bounded cleanup in three
    independently validated iterations. The fixed repository-health score rose
    `20.0 -> 27.3 -> 33.4 -> 84.1`, satisfying the explicit three-consecutive-
    increase stop rule. Removed `3,538` production Swift LOC, `4,405` test Swift
    LOC, `152` net source test declarations, `154` Simulator-executable tests,
    `94` orphan localization keys, and `47` brittle Markdown line anchors while
    retaining zero broken local links and zero lost current public/security
    obligations. All iteration and final Debug test builds passed; focused,
    full, and serialized runs plus four classified residual failures are linked
    in the evidence ledger. Moved Doing -> Done. No current UX/UI or mounted
    production behavior, device/backend acceptance, commit, or push is claimed.

### TAP-0093 — Freeze pre-release v1 schemas and remove developer compatibility layers

- Status: `Done`
- Kind: `Task`
- Priority: `P0`
- Domain: `Release Readiness / Public Formats / Security / Persistence / Documentation`
- Labels / Match Keys: `pre-release, schema v1, TAPCamVerifier, reset developer data, remove migration, prototype pruning`
- Owner / Agent: Product owner / `/root`
- Dev Session: `/root` on shared `main`
- Contract: `ProductContract §1.2`, `§2.5`, `§3.2`–`§3.4`, and `§6`;
  `TAPVideoFormatContract`; `LivePhotoBrowserVerification`; `AppAttest` contracts;
  `StartupLifecycleContract`
- Current Behavior: The unreleased app remains at `0.2 (2)`. Every distinct
  current public/security family uses its own v1 identifier in TAPCamDemo and
  TAPCamVerifier. The Verifier accepts current capture packages only through
  `.tapnap` or the TAPNAP MIME with a valid current-v1 root sidecar. Pre-release
  local development compatibility readers and migrations are removed under the
  clear-container recovery policy. Prototype revisions and active visual truth
  remain unchanged.
- Approved Scope:
  1. Keep the App marketing/build version at `0.2 (2)`.
  2. Give every distinct current public-format or security-schema family its
     own unambiguous `v1` identifier and version field. Synchronize TAPCamDemo,
     TAPCamVerifier, fixtures, tests, contracts, and acceptance procedures; reject
     the superseded development identifiers instead of carrying readers for them.
  3. Treat all pre-release local development data as disposable. Remove old
     preference keys, fallback decoders, maintenance migrations, compatibility
     aliases, and their migration-only tests. A developer with old data must clear
     the app container or delete and reinstall.
  4. Remove redundant Prototype history/assertions while preserving every active
     fixture, behavior, approved/candidate revision string, and current UI truth.
  5. Remove legacy `.zip`/`application/zip`/ZIP-magic package recognition and
     missing/invalid-sidecar fallback after the owner's explicit approval. Keep
     bounded ZIP-compatible parsing inside current `.tapnap` packages.
- Out Of Scope: No App version change; no unrelated visible UI, navigation,
  layout, or interaction change beyond removing the obsolete ZIP token from the
  Verifier's supported-format filter/copy; no weakening of App Attest, proof-slot, canonicalization,
  hashing, fail-closed validation, privacy, current Pending Capture Queue state
  transitions, or Photos export gates; no production-data upgrade promise; no
  Prototype revision consolidation; no device/backend acceptance claim.
- Failure / Recovery: Unknown or superseded public schema identifiers fail as
  unsupported. Old local development data is not migrated; clearing the app
  container or deleting and reinstalling is the only supported recovery. Current
  malformed data, missing proof/resources, credential mismatch, and cryptographic
  failures remain fail-closed.
- Done When: App `0.2 (2)` and all unrelated current UX/UI remain unchanged;
  every distinct current public/security schema family reports `v1` in both
  repositories; the verifier accepts the new current families only through
  current raw-media or `.tapnap`/TAPNAP-MIME inputs with a valid v1 sidecar;
  pre-release local compatibility readers/keys/migrations and exclusive tests are
  gone without removing active runtime transitions; Prototype tests pass with the
  current revision unchanged; TAPCamDemo builds and focused format, integrity,
  startup, preference, persistence, and Prototype tests pass; TAPCamVerifier Rust,
  TypeScript, and production builds pass; contracts, READMEs, fixtures, and
  acceptance procedures describe only current truth; both worktrees preserve
  unrelated user files; and no commit or push is made without owner direction.
- Related: `TAP-0092` repository-health cleanup; `TAP-0010` canonical Setup receipt;
  `TAP-0022` external import; `TAP-0023` TAP Video `.tapnap` transport;
  `TAP-0044` Live Photo acceptance; `TAP-0046` App Attest production acceptance;
  `TAP-0062` browser verification contract; `TAP-0078` TAP Video format contract
- Created: `2026-08-23`
- Updated: `2026-08-23`
- Revision History:
  - `2026-08-23` Allocated after an all-status responsibility search. TAP-0092 is
    already Done and intentionally retained current versions/compatibility for an
    owner decision; TAP-0010, TAP-0022, and TAP-0023 own future feature delivery,
    not this pre-release reset. The owner explicitly kept App `0.2 (2)`, approved
    purpose-specific v1 renumbering in TAPCamDemo and TAPCamVerifier, allowed all
    development data to be cleared instead of migrated, and kept Prototype
    revisions while authorizing redundant-history deletion. Recorded the new item
    through Inbox -> Todo approval, assigned `/root`, and moved Todo -> Doing for
    implementation on `main@334ba24`. Advanced Next Task ID to `TAP-0094`. No
    implementation, validation result, UI change, device acceptance, commit, or
    push is inferred by this allocation.
  - `2026-08-23` `/root` completed the bounded implementation candidate in both
    worktrees. App `0.2 (2)` and all mounted UI remain unchanged. Still Photo,
    Live Photo, TAP Video, their content bindings, TAP Video KLV, and the already-
    current registration/proof/App Attest families now use distinct v1
    identifiers; old wire identifiers fail closed, and TAPCamVerifier has the
    same family routing plus a mixed-family negative regression. Pre-release
    startup, preference, and Pending compatibility readers/migrations were
    removed in favor of clear-container recovery while protected-data, privacy,
    crash, export/readback, and current queue transitions remain. Prototype
    revision/copy is unchanged; only unreferenced evidence, one unused tool,
    one unused history array, and stale assertions were removed. The Verifier's
    existing `.zip`/ZIP-magic/missing-sidecar compatibility remains implemented
    and documented because removing that current public input needs an explicit
    owner decision beyond schema renumbering.
  - `2026-08-23` Validation passed: final Simulator `build-for-testing`; final
    six-suite schema/signing/startup run `95 passed / 0 failed / 0 skipped`;
    supplemental production-path runs `132/132` and `81/81`; Prototype `58/58`;
    JS proof-slot reference `4/4`; TAPCamVerifier Rust `44/44`, Vitest `119/119`
    including four local real HEIC/JPEG decoder regressions, TypeScript
    typecheck, rustfmt, and production build. A separate Startup run remained
    `32 passed / 1 failed`, with only the pre-existing Simulator Keychain
    `errSecMissingEntitlement (-34018)` baseline. Both Markdown link scans and
    `git diff --check` passed. No physical-device/App Attest backend acceptance,
    commit, or push is claimed. TAP-0093 remains Doing only for the explicit
    legacy `.zip` retain/remove decision.
  - `2026-08-23` The owner explicitly approved removing the Verifier's legacy
    `.zip`, `application/zip`, generic ZIP-magic, and missing/invalid-sidecar
    fallback. `resolveCaptureInput` now accepts package input only through the
    `.tapnap` extension or TAPNAP MIME, requires the current v1 root sidecar,
    resolves only exact declared resources, and directly rejects unsupported
    archive markers. Bounded `fflate` parsing and every size/entry/resource
    limit remain because `.tapnap` is still ZIP-compatible internally. The file
    picker, Chinese/English supported-format copy, README, verifier flow,
    cross-project browser contract, and cleanup manifest now describe only the
    current input. Input cases reduced `19 -> 11`; full Verifier validation
    passed Rust `44/44`, Vitest `111/111`, TypeScript/production build, and both
    worktree diff checks. No Demo runtime code, App version, Prototype revision,
    layout/navigation, ignored local media fixture, device/backend acceptance,
    commit, or push changed. Moved Doing -> Done.
  - `2026-08-23` The owner classified
    `StartupInitializationPolicyTests.corruptKeychainDeviceGenerationRepairsInPlace`
    returning `errSecMissingEntitlement (-34018)` under the unsigned Simulator
    test host as a known legacy test-infrastructure issue. It predates TAP-0093,
    remains recorded as a failure rather than pass/skip, establishes no
    production Keychain regression, does not block TAP-0093 closure, and does
    not alter or satisfy TAP-0046 physical-device acceptance. No new Task was
    created for this owner-classified non-blocking baseline.

### TAP-0094 — Establish the documentation-only TAPArtifactContracts repository

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `Cross-project contracts / Public formats / Verification`
- Labels: `cross-repo-contract`, `artifact-manifest`, `still-photo`,
  `live-photo`, `tap-video`, `content-binding`, `proof`, `tapnap`, `versioning`
- Contract: `ProductContract §1.2`, `§3.2`–`§3.4`, and `§6`;
  `LivePhotoBrowserVerification`; `TAPVideoFormatContract`
- Match Keys: `TAPArtifactContracts, Mobile app Verifier contract, photo manifest,
  artifact manifest, cross-repo schema, manifest fields, browser verification`
- Owner / Agent: Product owner / `/root`
- Dev Session: `/root` current collaboration session
- Branch/Worktree: `/Users/harold/TAPCamDemo` shared `main` for Board
  coordination; `/Users/harold/TAPArtifactContracts` is the separate delivery
  repository; no additional Demo branch or worktree
- Starting Behavior: TAP-0062 owns the existing cross-project Live Photo browser
  verification contract, TAP-0078 owns the existing canonical TAP Video format
  contract, and TAP-0093 froze the current distinct v1 families and synchronized
  them across TAPCamDemo and TAPCamVerifier. Those Done conditions remain true,
  but the producer and verifier still obtain their shared artifact-format truth
  from repository-local documents and implementations rather than one
  independently versioned contract repository.
- Approved Scope:
  1. Establish `TAPArtifactContracts` as the language-neutral, documentation-only
     authority for the current Still Photo, Live Photo, and TAP Video artifact
     manifest fields consumed across TAPCamDemo and TAPCamVerifier.
  2. Document current content-binding and proof obligations, including signed
     resource roles, canonicalization/hash inputs, proof-envelope relationships,
     and fixed proof-slot obligations, without weakening fail-closed behavior.
  3. Document the current container embedding locations and routing boundaries
     for still media, Live Photo resources, TAP Video/KLV resources, and the
     `.tapnap` root sidecar and declared-resource mapping.
  4. Document format-family identifiers, version fields, compatibility and
     rejection rules, and provide normative positive and negative examples,
     including parseable JSON examples where the format is JSON-shaped.
  5. Update the source repositories' authority statements and cross-links so
     shared wire obligations point to `TAPArtifactContracts`, while each source
     repository continues to own its runtime implementation and local product
     behavior.
- Out of Scope: No TAPCamDemo or TAPCamVerifier runtime code; no Swift,
  TypeScript, Rust, WASM, SDK, code generator, generated bindings, or runtime
  dependency; no UI or Prototype change; no product capability or acceptance
  claim; and no change to existing wire bytes, identifiers, manifest fields,
  canonicalization, proof semantics, container layout, or manifest embedding
  location. The extraction must not merge distinct Still, Live, Video, content-
  binding, proof, or registration families into one schema.
- Failure / Recovery: If an obligation cannot be traced consistently to the
  current producer, verifier, specialized contract, and fixture evidence, keep
  the existing source document authoritative for that obligation, record the
  discrepancy, and leave this Task Doing. Any proposed wire-format or runtime
  change stops this documentation-only Task and requires a separately approved
  Task before authority can move.
- Done When: `TAPArtifactContracts` contains a self-consistent authority map and
  normative documentation for all approved Still/Live/Video manifest fields,
  content binding/proof, container embedding, `.tapnap` routing, and current
  version/compatibility rules; every JSON example parses with a standard JSON
  parser and its field names, identifiers, resource roles, and relationships
  match current source fixtures without changing serialized bytes; positive and
  negative examples state expected acceptance or rejection; TAPCamDemo and
  TAPCamVerifier source documents synchronize their authority statements and
  reciprocal cross-links without changing runtime source or dependencies;
  redundant normative prose is either migrated and removed or explicitly kept
  for a unique repository-local responsibility; link and contradiction scans
  pass; and the development session returns the complete structured handoff from
  §2.6, including every documentation-impact row, validation evidence, remaining
  gaps, exact per-repository commit/push status, owner authorization for any
  independent-repository publication, and confirmation that no TAPCamDemo or
  TAPCamVerifier commit or push is claimed.
- Related: `TAP-0062` Live Photo browser verification contract; `TAP-0078` TAP
  Video format contract; `TAP-0093` current v1 schema and compatibility reset;
  `TAP-0022` external import; `TAP-0023` TAP Video `.tapnap` transport;
  `TAP-0044`–`TAP-0046` device/backend acceptance boundaries
- Created: `2026-08-23`
- Updated: `2026-08-23`
- Development Handoff (`2026-08-23`):
  - Task ID: `TAP-0094`
  - Dev Session: `/root` current collaboration session
  - Branch/Worktree: TAPCamDemo shared `main` remains a working tree only;
    `/Users/harold/TAPArtifactContracts` is clean on local branch
    `codex/tap-0094-artifact-contracts`, tracking `origin/main` for the Private
    [TAP-NAP/TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
    repository whose default branch is `main`; TAPCamVerifier retained its
    pre-existing dirty changes
  - Build/Commit: documentation-only, so no product build was run. The independent
    repository's initial commit is
    `049f58749ca97b360b5683f516181df6f005482f` with message
    `docs: establish TAPArtifactContracts (TAP-0094)`, containing `23` files and
    `2,885` lines. It was pushed to `origin/main`; `git ls-remote origin
    refs/heads/main` exactly matched local HEAD. No TAPCamDemo or TAPCamVerifier
    commit or push was made or is claimed.
  - Contract Sections Read: `ProductContract §1.2`, `§3.2`–`§3.4`, and `§6`;
    complete TAP-0062, TAP-0078, TAP-0093, and TAP-0094 records;
    `LivePhotoBrowserVerification`; `TAPVideoFormatContract`; affected App
    Attest, packaging, output, and Verifier documentation
  - Approved Scope: extract only the current shared Still/Live/Video artifact
    manifest fields, content binding/proof, container embedding, `.tapnap`
    routing, version/compatibility rules, and normative examples into a
    language-neutral documentation repository without changing runtime code or
    wire behavior
  - Implemented Scope: initialized TAPArtifactContracts with `23` managed
    content files, all Markdown or JSON, including `7` synthetic JSON examples.
    The documents cover Still Photo, Live Photo, and TAP Video manifests;
    capture binding and proof; photo and video containers; `.tapnap`; versioning
    and adoption; known divergences; and positive/negative examples. TAPCamDemo
    synchronized Product Contract, root/documentation indexes, specialized
    contracts, packaging, and output-module shared-authority references.
    TAPCamVerifier added authority references only in its README and
    `Docs/VerificationFlow.md`, preserving all pre-existing dirty changes.
  - Prototype Path/Revision/Approval: `N/A`; no UI, interaction, copy, Prototype
    manifest, or visual authority changed
  - Tests And Builds Run: all `7/7` synthetic JSON examples parsed with `jq`;
    the final broader local Markdown-link scan passed `27/27`; final `jq`
    semantic assertions against the actual `.schema.id` and
    `pairedLivePhotoVideo` role were rerun under `set -e` and exited `0`; the
    Swift manifest-field-set comparison and current-ID/old-version scans passed;
    two additional anchors resolved; TAPCamDemo and TAPCamVerifier
    `git diff --check` passed. Four Markdown trailing-space defects were fixed
    before commit and the final staged diff check passed. Two read-only
    pre-publication audits found no blocker: the target contains only `16`
    Markdown plus `7` JSON files and no credential, PII, real coordinate,
    absolute path, private fixture/blob, executable code, or package. Family,
    proof, embedding, and documentation-only boundary checks were self-
    consistent. No app, Rust, TypeScript, or production build was run because
    the approved change is documentation-only.
  - Evidence And Acceptance: the validation above establishes local document,
    example, field, identifier, and whitespace consistency only; it makes no
    device, backend, decoder, or runtime acceptance claim. The divergences
    document explicitly preserves known implementation differences, including
    the no-depth producer versus the Rust verifier's reconstructed
    `depthResource` representation, instead of silently redefining the wire
    contract. GitHub repository readback reports visibility `Private`, default
    branch `main`, and admin permission; a default-branch README fetch succeeded.
    The repository had returned `404` before owner-authorized creation. It was
    not changed to Public or otherwise given broader exposure.
  - Documentation Impact:
    - Project Board: this TAP-0094 handoff, Revision History, and global Board
      Revision Log updated by the Board Steward
    - Product Contract: `Docs/ProductContract.md` now points shared artifact-
      format authority to TAPArtifactContracts without changing product behavior
    - UI Prototype/Manifest: `N/A`; the artifact manifest is unrelated to the UI
      Prototype manifest and no UI artifact changed
    - UI Prototype Contract: `N/A`; prototype workflow and authority unchanged
    - Module README: `README.md`, `Docs/README.md`,
      `TAPCamDemo/CameraCapture/Output/README.md`, and
      `TAPCamDemo/CameraCapture/Documentation/PACKAGING.md` synchronize local
      ownership and shared-contract links
    - Specialized Contract: `Docs/LivePhotoBrowserVerification.md`,
      `Docs/TAPVideoFormatContract.md`, `Docs/AppAttest/BackendContract.md`, and
      `Docs/AppAttest/README.md` synchronize shared authority; TAPCamVerifier
      `README.md` and `Docs/VerificationFlow.md` add authority references only
    - Acceptance Record: `N/A`; this documentation extraction requires no
      physical-device procedure and satisfies no existing acceptance Task
    - AGENTS.md: TAPArtifactContracts adds repository-local documentation and
      no-runtime constraints; TAPCamDemo `AGENTS.md` is `N/A` because repository
      workflow did not change
  - Obsolete Files Removed: none; current source documents retain unique local
    runtime and product responsibilities while delegating shared authority
  - Remaining Gaps/Risks: no TAP-0094 closure blocker remains. Private visibility
    preserves GitHub's minimal default exposure and is recorded accurately;
    making the repository Public was neither approved nor required. Known
    producer/verifier divergences remain explicit conformance facts rather than
    format changes. TAPCamDemo and TAPCamVerifier authority-link edits remain in
    their existing working trees and were deliberately not committed or pushed.
  - Follow-up Task IDs: none allocated
  - Proposed Status: `Done`; the independent authority is published and
    read back at the owner-approved Private remote, every recorded Done When
    check is satisfied, and no runtime or wire-format change is claimed
- Closure Gate: `Passed`; Board Steward accepted the owner-authorized remote
  publication and complete validation/readback evidence, then moved Doing ->
  Done without committing or pushing TAPCamDemo or TAPCamVerifier.
- Revision History:
  - `2026-08-23` Captured in Inbox after an all-status search. Preserved owner
    intent: first score the current repository, then extract the contract shared
    by the Mobile app and Verifier into a separate repository; the manifest in
    scope is the per-capture artifact field contract used when the phone creates
    a photo and again when the browser verifies it, not the UI Prototype
    manifest. TAP-0062, TAP-0078, and TAP-0093 remain Done because their recorded
    completion conditions still hold; TAP-0094 is a scoped ownership follow-up,
    not a reopening. Advanced Next Task ID to `TAP-0095`. No implementation,
    lifecycle approval, source-document authority change, commit, or push was
    inferred by Inbox capture.
  - `2026-08-23` The owner explicitly approved the documentation-only boundary
    and requested that work start. Froze the scope to current Still/Live/Video
    manifest fields, content binding/proof, container embedding, `.tapnap`
    routing, version/compatibility rules, and normative examples; explicitly
    excluded all Mobile/Verifier runtime code, SDK/codegen/runtime dependencies,
    and every wire-byte or embedding-location change. Moved Inbox -> Todo after
    scope approval, bound the current `/root` collaboration session on Demo
    shared `main`, then moved Todo -> Doing. This Board transition itself changes
    no contract document, runtime behavior, test result, acceptance, commit, or
    push state.
  - `2026-08-23` Board Steward synchronized the documentation-only implementation
    and validation handoff. TAPArtifactContracts is locally initialized on
    `codex/tap-0094-artifact-contracts` with `23` managed Markdown/JSON content
    files and `7` synthetic JSON examples covering the approved shared contract
    surface. JSON parsing passed `7/7`, the final broader local Markdown-link
    scan passed `27/27`, final `jq` semantic assertions under `set -e` exited
    `0`, and Swift field-set comparison, ID/old-version scans, and both source-
    repository diff checks passed. TAPCamDemo and TAPCamVerifier authority links
    are synchronized without runtime, dependency, wire-format, or embedding-
    location changes; known divergences remain explicit. No build, commit, push,
    device/backend acceptance, remote, tag, or published URL is claimed.
    TAP-0094 remains Doing pending owner authorization for remote creation and
    commit/push.
  - `2026-08-23` The owner explicitly confirmed creation and push of the
    independent repository. The previously absent GitHub target now exists as
    Private [TAP-NAP/TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
    with default branch `main`; the Board preserves that minimal visibility and
    does not claim Public exposure. Initial commit
    `049f58749ca97b360b5683f516181df6f005482f` (`docs: establish
    TAPArtifactContracts (TAP-0094)`) contains `23` documentation/JSON files and
    `2,885` lines. The clean local `codex/tap-0094-artifact-contracts` branch
    tracks `origin/main`; `git ls-remote` matched local HEAD exactly, GitHub
    repository readback confirmed Private/default-main/admin, and default-branch
    README retrieval succeeded. Two read-only audits found no publication or
    contract blocker; JSON `7/7`, links `27/27` plus two anchors, semantic/field/
    ID/version checks, final staged diff check, and source-repository diff checks
    passed. No runtime/code/dependency/wire/embedding change or device/backend
    acceptance is claimed. TAPCamDemo and TAPCamVerifier remain uncommitted and
    unpushed in their existing working trees. The complete handoff now satisfies
    Done When; Board Steward moved Doing -> Done.

### TAP-0095 — Deduplicate migrated artifact-contract prose across source repositories

- Status: `Done`
- Kind: `Documentation`
- Priority: `P0`
- Domain: `Cross-project contracts / Documentation retention`
- Labels: `tap-artifact-contracts`, `normative-prose`, `deduplicate`,
  `shared-authority`, `docs-only`, `commit-hygiene`
- Contract: `ProductContract §1`, `§1.2`, `§3.2`–`§3.4`, and `§6`;
  `AGENTS.md §5` and `§7`; TAP-0094 published authority
- Match Keys: `delete migrated shared specification, remove duplicate normative
  prose, contract repo cleanup, Demo Verifier contract deduplication, source-repo
  authority cleanup, separate task-owned commits`
- Owner / Agent: Product owner / `/root`
- Dev Session: `/root` current collaboration session
- Branch/Worktree: TAPCamDemo shared `main`; TAPCamVerifier existing dirty
  checkout with all pre-existing changes protected; TAPArtifactContracts local
  checkout tracking the existing Private `origin/main`
- Starting Behavior: TAP-0094 is Done and the Private
  [TAP-NAP/TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
  remote `main` is the shared artifact-contract authority. TAPCamDemo and
  TAPCamVerifier now link that authority, but their local documents still retain
  normative material migrated into the shared repository. Removing proven
  duplication is a new source-repository cleanup and commit boundary; it does
  not invalidate or reopen TAP-0094.
- Approved Scope:
  1. Inventory candidate shared normative prose in TAPCamDemo and TAPCamVerifier
     and map each candidate to an exact TAPArtifactContracts section and current
     obligation before deleting anything.
  2. If a shared obligation is missing or incomplete in TAPArtifactContracts,
     add and validate that documentation first; do not delete the source copy
     until the shared authority covers it without changing the contract.
  3. Migrate the complete cross-repository signing-generation contract: algorithm
     identities, exact inputs, serialization/canonicalization boundaries, and
     the required construction and processing order for every current family.
  4. Migrate the complete verification contract: extraction, reconstruction,
     validation and comparison order, failure order, and every fail-closed stop
     used when rebuilding and verifying current artifacts.
  5. For each Still Photo, Live Photo, and TAP Video family, document a complete
     per-layer hash-participation map that identifies which artifact bytes and
     resources, manifest portions, `signedResources`, `contentDigest`, and
     `signingBinding` inputs participate at each digest, binding, and proof level.
     This coverage must exist in TAPArtifactContracts before equivalent source-
     repository normative prose is deleted.
  6. Inventory every example and fixture plus each production and test reference.
     Retain a real hermetic test/runtime dependency locally and label it as a
     mirror of the shared canonical vector, never as a second authority. If no
     necessary local dependency exists, migrate the vector to TAPArtifactContracts
     and remove it from the source repository. Copying a JSON vector into the
     shared repository is allowed within this docs/examples-only scope.
  7. Remove only duplicated shared format/schema/binding/proof/container/
     transport/version prose. Retain repository-local product policy,
     implementation ownership, operational behavior, verification flow,
     limitations, and concise authority links.
  8. Reconcile affected indexes and links so every retained document has one
     unique role and no local prose silently redefines the shared contract.
  9. Prepare separate, reviewable task-owned documentation/example commits for
     each affected repository. In TAPCamVerifier, stage only TAP-0095 paths or
     hunks and exclude every pre-existing dirty change from the Task commit.
- Commit / Push Boundary: The owner explicitly approved starting TAP-0095 and
  creating task-owned documentation commits in each affected repository.
  TAPArtifactContracts already has a Private remote `main`; this approval does
  not change its visibility. Commit approval does not silently authorize a
  TAPCamDemo or TAPCamVerifier push. The handoff must report, per repository,
  the exact commit hash, included paths, remote/push status, and any worktree
  changes deliberately left outside the commit.
- Out of Scope: No Swift, TypeScript, Rust, WASM, runtime source, SDK, codegen,
  generated binding, package, or runtime dependency change; no wire byte,
  identifier, field, canonicalization, proof semantic, container layout, or
  manifest embedding-location change; no deletion of unique local product,
  implementation, operations, or verification-flow obligations; no broad
  repository cleanup; no mixing of TAPCamVerifier's pre-existing dirty changes;
  and no TAPArtifactContracts visibility change.
- Failure / Recovery: If exact shared coverage cannot be demonstrated, retain
  the source prose until the shared repository is completed and validated. If a
  TAPCamVerifier edit cannot be isolated from pre-existing dirty work, do not
  commit it; record the path/hunk and return it as a gap. Any discovered need to
  change runtime behavior or serialized artifacts stops this docs-only Task and
  requires a separately approved Task.
- Done When: A migration ledger maps every removed normative section to exact
  TAPArtifactContracts coverage and records why every retained source section is
  repository-local; before any corresponding source deletion, the shared
  authority completely specifies signing-generation algorithms, exact inputs
  and processing order; verification extraction/reconstruction/comparison and
  failure order; and a Still/Live/Video per-layer matrix showing how artifact
  bytes, manifest portions, `signedResources`, `contentDigest`, and
  `signingBinding` participate in each digest, binding, and proof. A fixture
  ledger accounts for every example/fixture and every production/test reference:
  necessary hermetic dependencies remain local only as clearly identified
  mirrors of shared canonical vectors, while examples without a necessary local
  dependency are present in TAPArtifactContracts and removed from source repos.
  TAPCamDemo and TAPCamVerifier retain concise authority links plus only their
  product/implementation/operations/flow responsibilities; Markdown links and
  anchors, all JSON examples/vectors, identifier/version scans, signing and
  verification semantic assertions, family/hash-participation checks, and
  repository diff checks pass; changed content is limited to task-owned docs/
  examples and no runtime, dependency, wire-format, or embedding-location delta
  exists; TAPArtifactContracts remains Private unless the owner separately
  decides otherwise; separate task-owned commits are created for each affected
  repository with exact path inventories and push status, and TAPCamVerifier's
  pre-existing dirty changes are demonstrably excluded; the complete §2.6
  structured handoff records documentation impact, removed prose/examples,
  retained mirror dependencies, validation, per-repository commit/push evidence,
  remaining worktree changes, and any unresolved gap.
- Related: `TAP-0094` shared contract authority; `TAP-0002` active-document
  reconciliation; `TAP-0003` migrate-then-delete retention; `TAP-0062` Live
  Photo browser contract; `TAP-0078` TAP Video contract extraction; `TAP-0092`
  bounded repository cleanup
- Created: `2026-08-23`
- Updated: `2026-08-23`
- Development Handoff (`2026-08-23`):
  - Task ID: `TAP-0095`
  - Dev Session: `/root` current collaboration session
  - Branch/Worktree: TAPArtifactContracts is clean on local branch
    `codex/tap-0094-artifact-contracts`, tracking the Private `origin/main`;
    TAPCamDemo shared `main` has the exact task implementation commit, and this
    handoff will be carried by a subsequent Board-only local unpushed closure
    commit whose hash is reported by the Session final handoff rather than
    self-recorded here; TAPCamVerifier is on its existing dirty `main`, with
    task content isolated from every pre-existing change
  - Build/Commit:
    - TAPArtifactContracts commit
      `63f96b31de193c3ad456ffa500cc0db03fb97142` (`docs: define signing and
      verification contract`) contains exactly these `12` task paths:
      `ADOPTION.md`, `CHANGELOG.md`, `CONTRACTS.md`, `KNOWN_DIVERGENCES.md`,
      `README.md`, `SOURCE_SNAPSHOT.md`,
      `bindings/capture-binding-and-proof-v1.md`,
      `containers/tap-video-container-v1.md`, `examples/README.md`,
      `examples/vectors/tap-video-display-transform-v1.json`,
      `examples/vectors/tap-video-klv-zstd1-v1-golden-vector.json`, and
      `manifests/tap-video-v1.md`. The clean local HEAD and `origin/main` both
      resolve to this commit; it is pushed to the existing Private remote.
    - TAPCamDemo commit `3f49286d53afafa056cb4f138a2c9b2535ec76a8`
      (`docs: adopt shared artifact contracts`) contains exactly `14` task
      paths: `AGENTS.md`, `Docs/Acceptance/TAP-0044-live-photo-chain.md`,
      `Docs/AppAttest/BackendContract.md`, `Docs/AppAttest/README.md`,
      `Docs/Fixtures/TAPVideoManifestV1GoldenVectors.json`, deleted
      `Docs/LivePhotoBrowserVerification.md`, `Docs/ProductContract.md`,
      `Docs/README.md`, `Docs/TAPVideoFormatContract.md`, `README.md`,
      `TAPCamDemo/CameraCapture/Documentation/PACKAGING.md`,
      `TAPCamDemo/CameraCapture/Output/README.md`,
      `TAPCamDemo/TAPLibrary/README.md`, and `TAPCamDemoTests/README.md`. Local
      `main` was ahead of `origin/main` by this one implementation commit at
      implementation handoff and was not pushed. This record will be carried by
      a subsequent Board-only local unpushed closure commit; its hash cannot be
      self-recorded in this commit and is reported by the Session final handoff.
    - TAPCamVerifier commit
      `d780636dcfbe8e006f4bea02415c9495906df2fa` (`docs: adopt shared artifact
      contracts`) is on local `main`, contains exactly `README.md` and
      `Docs/VerificationFlow.md`, and is not pushed. Its isolated index tree
      `9a7e30784f2f5afb89a2832f2f5dfa2f26356454` and parent
      `20972aff2675cab4a8bb9936bd7fba9115d21951` exactly match clean-branch
      verification commit `75026adf6c5012757941eb0fb822b5a89a505344`.
      All `18` pre-existing tracked dirty paths and `5` untracked QR-artifact
      paths stayed outside the Task commit; their working-file SHA values were
      unchanged across the commit operation.
    - No app, Rust, TypeScript, WASM, or production build was run because the
      approved change is documentation/examples only.
  - Contract Sections Read: `ProductContract §1`, `§1.2`, `§3.2`–`§3.4`, and
    `§6`; complete TAP-0094 and TAP-0095 records; root `AGENTS.md §5` and `§7`;
    affected Demo product, App Attest, TAP Video, packaging/output, queue,
    acceptance, fixture, and test documentation; affected Verifier README and
    verification-flow responsibilities; complete changed shared contracts and
    examples
  - Approved Scope: complete the shared signing-generation, verification,
    per-family hash-participation, container/manifest, and fixture authority
    before deleting duplicate normative prose; retain unique repository-local
    product, lifecycle, server, report, playback, and executable-test roles;
    isolate each repository's task-owned docs/examples commit without changing
    runtime, wire bytes, embedding, dependencies, or Private visibility
  - Implemented Scope:
    - Migration Ledger — signing and verification: shared
      `bindings/capture-binding-and-proof-v1.md` is now the sole prose authority
      for TAP capture canonical JSON, hash primitives, Still/Live/Video hash
      participation, `signedResources`, complete `contentDigest` and
      `signingBinding` construction, producer signing order, full versus Live
      primary-only local reconstruction/comparison/failure order, and the App
      Attest `clientDataHash`, CBOR assertion, `SHA-256(authenticatorData ||
      clientDataHash)` nonce, registered-public-key signature, and RP-ID
      verification relationship. Backend credential state, counter persistence,
      out-of-order policy, replay, endpoint, and audit behavior remain local to
      Demo's App Attest backend contract.
    - Migration Ledger — manifest/container/vector: shared
      `manifests/tap-video-v1.md`, `containers/tap-video-container-v1.md`, and
      the two exact vector JSON files now own TAP Video fields, display
      transforms, `mebx` key mapping, KLV/zstd bytes, bounds, and compatibility.
      Demo's `Docs/TAPVideoFormatContract.md`, packaging/output documents,
      Pending queue documentation, and tests retain only finalization,
      persistence, Photos, playback, evidence, Swift ownership, and executable
      implementation roles.
    - Migration Ledger — Live Photo: the shared Live manifest, photo-container,
      binding/proof, and `.tapnap` documents own the cross-repository artifact
      obligations formerly repeated in
      `Docs/LivePhotoBrowserVerification.md`. Code review found that document's
      three-state verdict, jump behavior, and Photos-adjustment prose was not
      implemented and was not a current Product Contract obligation; it was
      deleted as stale historical prose rather than migrated. Current website
      behavior is `valid`/`invalid` with attached warnings and remains recorded
      as repository-local flow in TAPCamVerifier `Docs/VerificationFlow.md`.
    - Migration Ledger — source ownership: TAPCamDemo retains Product Contract
      claims, capture/finalization/signing/persistence/Photos lifecycle,
      backend endpoint/counter/replay operations, device acceptance, Swift
      module ownership, and local executable-test guidance. TAPCamVerifier
      retains input routing, scoped result/report presentation, playback,
      warning attachment, and server-request flow. Both source repositories use
      concise shared-authority links instead of parallel format definitions.
    - Migration Ledger — rejected duplicate: the root README's old diagram that
      placed a proof body inside `manifest.proofs` was removed, not migrated,
      because current manifests require `proofs: []` and store the proof only in
      the fixed slot.
    - Fixture Ledger: TAPArtifactContracts now contains `9` parseable shared
      JSON documents, including the new exact KLV/zstd and eight-direction
      display-transform vectors. Demo's composite
      `Docs/Fixtures/TAPVideoManifestV1GoldenVectors.json` remains because
      `TAPVideoManifestTests` reads that exact path; only its `depthFrame`
      member mirrors the shared exact vector, while its manifest object is local
      decoder input rather than a second authority. The literal vector in
      `TAPVideoStreamingTests` remains to prove deterministic producer encoding,
      and the literal in Verifier `src/video/tapVideo.test.ts` remains to exercise
      the browser decoder. Runtime-generated fixtures and ignored real media
      remain local executable inputs, not duplicate contract documents.
  - Prototype Path/Revision/Approval: `N/A`; no UI hierarchy, copy, interaction,
    Prototype state, or visual authority changed
  - Tests And Builds Run: shared commit diff check passed; `jq` parsed `9/9`
    shared JSON files; local Markdown targets passed `28/28` and anchors `2/2`;
    display transforms passed `8/8`; the exact KLV sequence is `128` bytes with
    ordered `TVER/FRAM/PTS /COMP/ULEN/CALI/DPTH` records; zstd decode, raw hash,
    and Demo `depthFrame` mirror comparisons passed. Demo commit diff check,
    JSON parsing, exact mirror diff, and every touched Markdown link passed; the
    only deleted-path text left is append-only historical Board backtick prose,
    not an active Markdown link. The isolated Verifier documentation commit
    passed diff check, link review, and behavior/ownership review. No build was
    run under the docs/examples-only boundary.
  - Evidence And Acceptance: the shared-release audit found no remaining
    contract or publication blocker; the signing/hash matrix, App Attest
    verification boundary, `mebx` wrapper, eight transform cases, KLV vector,
    Live full/primary-only scopes, fixture ledger, and accepted/rejected JSON
    outcomes are self-consistent. Commit trees and path inventories demonstrate
    that only task-owned Markdown/JSON/Agent-guidance content changed. This is
    documentation consistency and publication evidence only; it makes no
    device, backend-deployment, or runtime acceptance claim.
  - Documentation Impact:
    - Project Board: this TAP-0095 migration/fixture ledger, structured handoff,
      Revision History, Kanban transition, closure gate, and global Board
      Revision Log
    - Product Contract: `Docs/ProductContract.md` retains product scope and
      delegates shared artifact/signing/verification authority without changing
      behavior
    - UI Prototype/Manifest: `N/A`; no UI or Prototype artifact changed
    - UI Prototype Contract: `N/A`; prototype workflow and authority unchanged
    - Module README: Demo root/Docs indexes, CameraCapture packaging/output,
      TAPLibrary, and test READMEs retain local responsibilities; Verifier
      `README.md` retains product/runtime entry points and shared links
    - Specialized Contract: TAPArtifactContracts' binding, TAP Video manifest/
      container, adoption/divergence, and vector documents are updated; Demo App
      Attest backend/README and TAP Video operational contract retain only their
      unique responsibilities; Verifier `Docs/VerificationFlow.md` retains its
      local verification flow
    - Acceptance Record: `Docs/Acceptance/TAP-0044-live-photo-chain.md` updates
      its shared authority link only; no device procedure was run and no
      acceptance verdict changed
    - AGENTS.md: Demo `AGENTS.md` names the repository-recorded shared authority
      in its documentation-impact matrix; no lifecycle or Agent workflow rule
      changed. TAPArtifactContracts `AGENTS.md` is unchanged in TAP-0095.
  - Obsolete Files Removed: `Docs/LivePhotoBrowserVerification.md`; its unique
    current obligations were either already in shared authority or retained in
    current Product/Verifier flow, while unimplemented historical behavior was
    deliberately not promoted. Duplicate format/signing prose and the incorrect
    root README proof-placement diagram were removed from retained documents.
  - Remaining Gaps/Risks: no TAP-0095 closure blocker remains. The stale Swift
    comment at
    `TAPCamDemo/CameraCapture/Output/TAPDepthManifestSchema.swift:37-39` still
    says proof data belongs in manifest `proofs`; changing code comments was
    outside this docs-only Task. Shared `KNOWN_DIVERGENCES.md` continues to
    record Verifier `mebx` key-mapping enforcement, no-depth reconstruction,
    TAP Video semantic-validation breadth, and canonical-JSON edge-vector gaps.
    Four groups of pre-existing broken links outside the touched documentation
    surface remain unchanged and were not used as TAP-0095 evidence.
  - Follow-up Task IDs: none allocated; the explicit existing divergences and
    untouched repository-health facts remain recorded without broadening this
    Task or creating an unapproved follow-up
  - Proposed Status: `Done`; the shared authority is complete and published,
    source duplication is removed with unique local roles preserved, all three
    isolated task commits exist with exact push status, validation passes, and
    no runtime, dependency, wire-format, embedding, or visibility change is
    claimed
- Closure Gate: `Passed`; Board Steward reconciled the migration and fixture
  ledgers, commit trees, validation, remaining gaps, and documentation-impact
  matrix against Done When, then moved Doing -> Done. TAPArtifactContracts
  remains Private and pushed; TAPCamDemo and TAPCamVerifier commits remain local
  and unpushed as explicitly recorded.
- Revision History:
  - `2026-08-23` Captured in Inbox after an all-status title/label/match-key/
    domain/contract/scope search. TAP-0002, TAP-0003, TAP-0078, and TAP-0092 are
    completed governance/cleanup foundations, not active owners. TAP-0094 remains
    Done because its published-authority completion condition is still true;
    source-repository deduplication and isolated commits are a scoped follow-up,
    not a reopening. Allocated TAP-0095 and advanced Next Task ID to `TAP-0096`.
    No document implementation, deletion, validation, commit, push, visibility
    change, or other lifecycle transition is inferred by Inbox capture.
  - `2026-08-23` The owner explicitly approved the docs-only scope, requested
    execution, and authorized task-owned commits. Froze migrate-before-delete,
    unique-local-responsibility retention, no runtime/wire/embed change,
    TAPCamVerifier dirty-worktree isolation, per-repository commit/push
    accounting, and unchanged Private visibility. Moved Inbox -> Todo after
    scope approval, bound the current `/root` collaboration session across the
    three existing checkouts, then moved Todo -> Doing. This lifecycle record
    itself changes no implementation document, runtime, artifact, validation,
    commit, push, or remote state.
  - `2026-08-23` The owner expanded the in-progress TAP-0095 scope without
    changing its delivery goal or lifecycle state. Before deleting equivalent
    source prose, TAPArtifactContracts must now completely own signing-generation
    algorithms/inputs/order, verification reconstruction/comparison/failure
    order, and explicit Still/Live/Video per-layer participation of artifact
    bytes, manifest portions, `signedResources`, `contentDigest`, and
    `signingBinding`. Every example/fixture must be checked against all
    production/test references: necessary hermetic dependencies stay local only
    as labeled mirrors of a shared canonical vector; unnecessary local copies
    migrate to the shared repository and are removed. JSON-vector copying is
    authorized, but changes and commits remain task-owned docs/examples only;
    runtime/wire/embed boundaries and TAPCamVerifier dirty-worktree isolation are
    unchanged. No implementation, deletion, validation, commit, push, visibility
    change, new Task, or status transition is inferred; TAP-0095 remains Doing.
  - `2026-08-23` Board Steward accepted the completed three-repository handoff.
    Shared commit `63f96b31de193c3ad456ffa500cc0db03fb97142`
    publishes the sole signing/hash/reconstruction/App Attest and TAP Video
    manifest/container/vector prose authority to the existing Private
    `origin/main`; Demo commit
    `3f49286d53afafa056cb4f138a2c9b2535ec76a8` preserves only product,
    lifecycle, backend, acceptance, and local-test roles across `14` paths; and
    Verifier commit `d780636dcfbe8e006f4bea02415c9495906df2fa`
    preserves only routing/scope/report/playback/server-flow roles across two
    paths. Shared JSON `9/9`, links `28/28`, anchors `2/2`, transforms `8/8`,
    exact KLV/zstd/hash/mirror checks, and all affected-repository diff/link/
    ownership checks passed. Verifier's `18` tracked plus `5` untracked
    pre-existing dirty paths remained byte-stable and outside its commit. The
    obsolete Live browser document and incorrect README proof diagram were
    removed without migrating stale or false behavior. No runtime, dependency,
    wire, embedding, visibility, device, or backend-acceptance change occurred.
    The complete handoff satisfies Done When; moved TAP-0095 Doing -> Done.

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
| `TAP-0088` | Technical | P1 | UI Prototype / Viewfinder Observability | `functional Viewfinder control mock, inspector, workload interaction` | Activate only after TAP-0008/TAP-0009/TAP-0083 complete; prototype control-state/workload interactions without duplicating native Camera delivery | 2026-08-14 | Owner-directed deferred TAP-0087 child; Inbox and Unassigned |
| `TAP-0089` | Technical | P1 | UI Prototype / Photo Viewer Observability | `RAW 2D 3D inspector, analysis workload interaction, Deferred mode` | Activate only after TAP-0008/TAP-0009/TAP-0083 complete; prototype Photo Viewer analysis interactions without native or Video 3D claims | 2026-08-14 | Owner-directed deferred TAP-0087 child; Inbox and Unassigned |
| `TAP-0091` | Fix | P1 | Camera / Viewfinder Presentation | `camera or lens switch, preview-external chrome redraw, settings button flicker` | Freeze the exact reproducing path/device/build and stable preview-versus-chrome boundary before implementation; decide prototype N/A only if visual intent remains unchanged | 2026-08-15 | Owner-reported runtime observation preserved and renumbered after mainline allocated TAP-0090; Inbox and Unassigned |

## 6. Device And Visual Acceptance Registry

These Tasks must be expanded with the template in §2.5 and confirmed with the
owner before execution.

| ID | Status | Priority | Related delivery | Scope | Procedure | Dev Session | Human Confirmation | History |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `TAP-0040` | Todo | P0 | completed non-Network delivery `TAP-0008`; structured regression `TAP-0090`; initial Network/App Attest delivery `TAP-0010`; prototype `TAP-0087`; production App Attest evidence `TAP-0046` | Fresh Installation behavior, exercised for acceptance through the specified Delete-and-Reinstall reset path: all five Setup operations start only from their corresponding explicit actions; Network/App Attest, Camera, and Photos are required, Location/Microphone optional, and Continue requires Attestation + Camera + Photos. Network completion proves the approved initial App Attest bootstrap, not generic `/healthz` reachability. | [Procedure](Acceptance/TAP-0040-first-install-operations.md) remains Draft/not executed. It consumes TAP-0090 structured JSON/JSONL event-order assertions for the delivered non-Network boundaries and TAP-0010 instrumentation for the still-unmigrated initial Network/App Attest boundary. It requires a pinned build/device scope and owner confirmation; retained proof is structured logs/assertion reports plus an owner-live textual verdict, with no photo, screenshot, or screen recording. | Unassigned | Pending | Created 2026-08-12 from permission regression; executable draft added 2026-08-12. The 2026-08-14 cold/overwrite-install log has no setup-row/button timeline and therefore is diagnostic context only, not explicit-action evidence; a separate clean-install run remains required. On 2026-08-14 the owner removed Network from onboarding; the linked draft was marked stale for a four-row rewrite. Later the same day, the owner corrected that interim direction: Network remains required but means first-install App Attest completion. The concurrent TAP-0087 candidate now reflects that semantic/retry correction, but no procedure execution, evidence, or human verdict is claimed. Canonical terminology correction: the remaining attended evidence is Fresh Installation behavior exercised through the explicit Delete-and-Reinstall reset procedure; “cold/overwrite-install” and “clean-install” above remain historical wording only. On 2026-08-15 delivery/evidence separation marked TAP-0008 Done for non-Network placement, assigned its reusable regression evidence to TAP-0090, and assigned the initial Network/App Attest/`S`/restore implementation to TAP-0010. TAP-0040 remains Todo and is not closed by either delivery status. |
| `TAP-0041` | Todo | P0 | completed non-Network delivery `TAP-0009`; structured regression `TAP-0090`; measured timing `TAP-0083`; visual parity `TAP-0048`; initial credential/restore `TAP-0010`; post-setup App Attest/Pending `TAP-0015`; prototype `TAP-0087` | Under the `S -> P -> I` route, Resource Initialization remains only for valid `S`, usable `P`, and absent/corrupt/stale `I` until real first frame/safe shutter-controls/haptics plus the first usable Library catalog metadata snapshot both succeed; it then atomically writes current `I` and enters camera. Valid current `S/P/I` bypasses the gate regardless of installation label or cold caches; no Retry/Failed/timeout/skip/degraded UI and no Share/iCloud/thumb/hash/ZIP/network/queue prewarm. | [Procedure](Acceptance/TAP-0041-camera-readiness.md) records the `fix0809@66ac001` candidate and the owner-accepted bounded non-Network device path. The full attended matrix remains open and consumes TAP-0090 structured ordering evidence; TAP-0083 separately supplies measured route-shell/first-frame timing, TAP-0048 supplies visual parity, TAP-0010 supplies canonical `S`/restore behavior, and TAP-0015 supplies W11/W12 guards. Durable proof is structured logs/assertion reports plus an owner-live textual verdict, with no photo, screenshot, or screen recording. | `/root` bounded device run; complete matrix unassigned | Bounded `fix0809` flow accepted 2026-08-15; complete matrix Pending | Exact Web prototype was approved 2026-08-13. The original registry history recorded that native implementation had not started; that statement is preserved as historical status. An earlier 2026-08-14 audit stated that the acceptance draft predated the Library-catalog/versioned-marker invariant. A later consistency audit confirmed that the concurrent candidate included the first usable catalog, versioned `I` marker, interruption, and current-marker bypass; its then-remaining gaps were the canonical installation matrix, Debug-only timing boundary, and owner confirmation. The 2026-08-14 log contributed only a 908-item first-catalog baseline of `7795 ms` and lacked first frame, safe controls/shutter/haptics, marker, interruption, and repeated-launch evidence. The 2026-08-15 candidate update adds `build-for-testing`, 146/146 focused tests with 0 failed/skipped, 58/58 Prototype tests, MJS checks, manifest parse, and `git diff --check`. Later on 2026-08-15 the owner exercised the bounded non-Network `fix0809` lifecycle flow on a physical device and explicitly accepted that bounded flow. Delivery/evidence separation now marks TAP-0009 Done for that non-Network delivery while TAP-0041 remains Todo for the unexecuted full owner-attended matrix. Canonical credential-bound `S`/restore is task-owned by TAP-0010, W11/W12 release is task-owned by TAP-0015, measured shell/first-frame placement by TAP-0083, and visual parity by TAP-0048; none is silently accepted by this bounded verdict. |
| `TAP-0042` | Todo | P1 | `TAP-0053` | EV direction, ISO/S clamp, AF→MF, focus assist, front gating, transitions, device matrix | [Procedure](Acceptance/TAP-0042-pro-controls.md) | Unassigned | Pending | Migrated from camera evidence gaps; executable draft added 2026-08-12 |
| `TAP-0043` | Todo | P0 | `TAP-0012` | Standard RGB/depth per FOV and PRO fixed uncropped output | [Procedure](Acceptance/TAP-0043-fov-depth-pro-no-crop.md) | Unassigned | Pending | Created 2026-08-12 from FOV conflict; executable draft added 2026-08-12 |
| `TAP-0044` | Todo | P1 | `TAP-0056` | Live Photo capture, paired MOV, signing, Photos readback, audio and playback | [Procedure](Acceptance/TAP-0044-live-photo-chain.md) | Unassigned | Pending | Migrated from Live Photo evidence gaps; executable draft added 2026-08-12 |
| `TAP-0045` | Todo | P0 | `TAP-0011`, `TAP-0057`, `TAP-0083` | Device codec/drop/RSS/thermal/registration, iCloud-only, broad formats, zero-depth path, and cold complete-original progress that remains responsive under bounded/coalesced UI publication | [Procedure](Acceptance/TAP-0045-tap-video-device.md) must add TAP-0083 cold/progress evidence before that path is executed | Unassigned | Pending | Existing video draft remains; 2026-08-13 added cold progress/backpressure evidence without changing status |
| `TAP-0046` | Todo | P1 | `TAP-0056`, `TAP-0057`; initial App Attest `TAP-0010`; post-setup credential/Pending `TAP-0015` | Entitlement, production backend, assertion and final signed-export gate | [Procedure](Acceptance/TAP-0046-app-attest-production.md) | Unassigned | Pending | Migrated from App Attest evidence gaps; executable draft added 2026-08-12. On 2026-08-15 linked the stable initial and post-setup implementation owners without changing this evidence Task's status. |
| `TAP-0047` | Todo | P1 | `TAP-0058`, `TAP-0059`, `TAP-0083` | Limited access, Photos system delete, pending confirm, adjacency, empty close, plus first cold large-Library entry with no repeated semantic snapshot churn or UI starvation | [Procedure](Acceptance/TAP-0047-library-permission-delete.md) must add a fresh/cleared-cache large-catalog run and structured milestone evidence | Unassigned | Pending | Existing Library draft remains; 2026-08-13 added cold large-catalog responsiveness evidence without changing status |
| `TAP-0048` | Todo | P0 | `TAP-0006`, completed delivery `TAP-0008`, `TAP-0009`; reviewer prototype `TAP-0087` | Approved Web states versus SwiftUI geometry, icons, layout, navigation and state presentation, including Required Permission Check and Resource Initialization | [Procedure](Acceptance/TAP-0048-web-swiftui-parity.md) | Unassigned | Pending | Created for HTML-first workflow; executable draft added 2026-08-12. On 2026-08-15 delivery/evidence separation made TAP-0048 the stable owner of exact native visual parity after TAP-0008/TAP-0009 delivery closure; no parity run or verdict is inferred. |
| `TAP-0049` | Todo | P0 | `TAP-0013` | Locked launch/first-frame/soak/capture/suspend/exit/relaunch | [Blocked Procedure](Acceptance/TAP-0049-locked-camera-lifecycle.md) | Unassigned | Pending | Executable draft added 2026-08-12; cannot run until lifecycle-correct experiment is ready |
| `TAP-0082` | Done | P0 | `TAP-0081` | System-native direct-file-URL handoff for ordinary media and `.tapnap`; ownerApproved r3 native flow uses the same-slot 2px app-payload track with no percentage/Cancel/400 ms hold/ready overlay, closes the popover at payload readiness, and then yields to the iOS-owned sheet. | [Procedure and evidence record](Acceptance/TAP-0082-share-handoff.md) plus this Board's explicit evidence-exception audit; old `bf20b52` evidence remains history only. | `/root` delivery/evidence reconciliation; product-owner attended retest and closure decision | Accepted 2026-08-14: prior ordinary-image/`.tapnap` x Save to Files/AirDrop matrix Pass with openable artifacts; exact r3 Web ownerApproved and native candidate compiled; latest log proves one complete `.tapnap` lifecycle. | Owner directed closure after reviewing the evidence limits. Focused r3 XCTest was compiled, not run. The latest log proves only `.tapnap` L70 intermediate cleanup -> L72 payload ready -> L73 handoff -> L74 controller under 50 ms -> L75–85 system probes -> L86 sheet appeared -> L93 dismissed -> L94 controller released -> L95 artifact cleanup. Direct image relies on the earlier accepted four-path matrix; stale-A/B and cleanup independent of controller release are not claimed. TAP-0008/0009/0083/0040/0041 remain open and independent. The containing closure commit supplies the final hash. |

## 7. Completed Task Registry

These records bootstrap known completed work. Their historical completion does
not replace the Product Contract, and linked device evidence may remain open.

| ID | Domain | Completed scope | Related evidence | Completed/recorded | Revision History |
| --- | --- | --- | --- | --- | --- |
| `TAP-0001` | Governance | Canonical Product Contract, UI workflow, Markdown board schema, initial inventory, and Agent rules established | N/A | 2026-08-12 | Created and completed in the board-bootstrap task; revised root Agent lifecycle on 2026-08-12 to require ordered reading, pre-implementation discussion, prototype-first UI, validation, documentation-impact tracking, and Board Steward closure |
| `TAP-0050` | Onboarding | Network/Camera/Photos required; Location/Microphone optional | `TAP-0040` | Before board bootstrap; recorded 2026-08-12 | Imported from then-current policy. Historical completion is preserved; on 2026-08-14 the owner superseded its Network-onboarding classification through TAP-0008/TAP-0087. The interim target had Camera/Photos required, Location/Microphone optional, and no Network Setup row. Later the same day, the owner corrected that interim direction: Network/Camera/Photos remain required, with Network now meaning successful first-install App Attest registration/verification rather than generic reachability. TAP-0050 remains Done. |
| `TAP-0051` | Onboarding | Bounded wall-clock Network retry foundation and pure policy boundary | `TAP-0040` | Before board bootstrap; recorded 2026-08-12 | Historical implementation foundation is preserved. On 2026-08-14 the owner temporarily removed the Network row and onboarding retry UX, so TAP-0010 was marked Deprecated while App Attest retry remained separately owned by TAP-0015. Later the same day, the owner corrected that interim direction: the bounded first-install retry foundation remains relevant to App Attest bootstrap, and TAP-0010 is restored to Todo pending exact re-scope/merge; post-setup credential optimization remains TAP-0015. TAP-0051 remains Done. |
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
- `2026-08-14` Recorded the owner's failed physical-device result for candidate
  `35745be`. AirDrop remained at “未找到用户” without a received artifact, and
  ordinary-image Share produced the same failure and repeated LaunchServices
  `Code=-54` diagnostics as `.tapnap`. This cross-format evidence rejects the
  package/custom-UTI-only diagnosis and the copy-backed manual provider
  candidate; its compile and provider-test results are retained as historical
  evidence but cannot close TAP-0081 or TAP-0082.
- `2026-08-14` The owner declined a separate rollback commit with “这条就算了
  直接开始改吧” and approved immediate recovery on the unpushed
  `codex/tap-share-system-handoff-recovery` branch. TAP-0081 remains Doing with
  revised scope to restore the pre-`bf20b52` system-native file-URL activity
  item for ordinary media and `.tapnap`, preserve the anchored UI/progress/
  exact-attempt lease, and prevent source cleanup before the system consumer's
  terminal boundary. The prior active prohibition on bare file-URL handoff is
  superseded; private LaunchServices entitlements remain prohibited. TAP-0082
  remains Todo and now requires received Save to Files and AirDrop artifacts
  for representative ordinary-media and `.tapnap` paths. Its acceptance file
  must be synchronized before execution. No recovery implementation, test,
  device delivery, or owner pass is inferred, and no other Task status or Next
  Task ID changed.
- `2026-08-14` Recorded the uncommitted TAP-0081 recovery implementation
  handoff. Package, image, and video artifacts now pass `[artifact.fileURL]`
  directly to the system activity controller; the failed shared manual
  `UIActivityItemsConfiguration` / `NSItemProvider` transport is removed. The
  activity controller strongly retains the artifact and explicitly performs
  idempotent cleanup when that final owner deinitializes; completion,
  `onDismiss`, and representable dismantle end coordinator state but are not
  source-deletion signals, and artifact-lease deinitialization remains an
  abnormal fallback. Product Contract §5.3, the DepthAnalysis README, and the
  TAP-0082 acceptance record are synchronized. Generic iphoneos
  `build-for-testing` passed and compiled the revised tests, but those tests
  were not run. The recovery is not committed or pushed; no device operation,
  installation, launch, received artifact, or owner verdict is claimed.
  TAP-0081 remains Doing, TAP-0082 remains Todo, and no other Task status or
  Next Task ID changed.
- `2026-08-14` Recorded the owner's requirement that AirDrop/Save to Files
  completion ends TAPCam's app-owned Share presentation and returns to the same
  stable Viewer; system destination UI remains system-owned and the TAP Share
  popover does not reopen automatically. The uncommitted implementation now
  keys an item-scoped system-sheet presenter by presentation UUID and routes
  binding, `onDismiss`, appearance, completion, and dismantle with an
  `expectedArtifactID`, preventing stale callbacks from attempt A from
  dismissing B. Controller callbacks capture the UUID rather than the
  presentation object, and presentation initialization always transfers
  artifact ownership to the controller. Generic iphoneos `build-for-testing`
  passed after this hardening and compiled the revised tests, but those tests
  were not run. Nothing is committed or pushed, no device operation or owner
  verdict is claimed, TAP-0081 remains Doing, TAP-0082 remains Todo, and no
  other Task status or Next Task ID changed.
- `2026-08-14` Superseded the destination-completion auto-close direction after
  the owner explained that it never worked and directed its related code to be
  removed. Current TAP-0081 no longer installs `completionWithItemsHandler` or
  carries its unused completion-state machinery; user/system dismissal,
  representable dismantle, and never-appeared recovery end coordinator state,
  while controller release owns normal per-attempt temporary-file cleanup.
  Exact presentation-ID guards and system-native file-URL transport remain.
  The cache audit confirms no persistent Share payload cache or prewarm;
  `SIGKILL` or exhausted cleanup retries may leave OS-temporary residue but do
  not constitute an app cache. Generic iphoneos `build-for-testing` passed
  after cleanup and compiled tests without running them. No Codex device
  operation, commit, or push is claimed. The owner reported “现在的话分享功能已经
  正常” and asked to implement TAP-0082, so TAP-0082 moved Todo -> Doing with a
  broad positive human result. Done still requires explicit confirmation of
  ordinary image and `.tapnap` through both Save to Files and AirDrop with
  saved/received artifacts that open. TAP-0081 remains Doing; no other Task
  status or Next Task ID changed.
- `2026-08-14` Recorded the owner's explicit “验收通过” verdict against the
  immediately preceding ordinary image/`.tapnap` × Save to Files/AirDrop
  matrix. All four transport paths and artifact openability are Pass; no
  filename, hash, log, receiving-device identity, commit, or final build
  identity is inferred. The acceptance record and Device Acceptance Registry
  now reflect that exact verdict. TAP-0081 and TAP-0082 remain Doing because
  the accepted recovery is still uncommitted/unpushed, focused tests were
  compiled rather than run, and cancellation/lifecycle evidence remains open.
  No other Task status or Next Task ID changed.
- `2026-08-14` Allocated TAP-0085 after an all-status search found no existing
  runtime-platform Task and advanced Next Task ID to TAP-0086. The owner
  identified the current `project.pbxproj` platform restriction as owner-
  authored and explicitly limited current product support to iPhone so iPad and
  Mac concerns do not introduce unrelated implementation factors. TAP-0085
  moved Inbox -> Todo -> Doing with product/document/build validation and a
  separate commit still open. Revised TAP-0007 without changing its Inbox
  status: it now owns only a future 6.9-inch iPhone App Store-media decision,
  while its prior Universal/iPad wording remains append-only history. No
  TAP-0081/TAP-0082 status or acceptance evidence changed.
- `2026-08-14` Reconciled TAP-0085 documentation and validation evidence.
  Product Contract §1.1, UI Prototype Contract §3/§9, and the root README now
  agree on the iPhone-only runtime boundary. Independent Debug and Release
  effective-setting checks report `iphoneos iphonesimulator`, all three
  unsupported compatibility flags `NO`, and device family `1`; the existing
  generic iphoneos build passed and its app reports `UIDeviceFamily = [1]`.
  TAP-0085 remains Doing solely until these owner-authored settings and their
  synchronized evidence are frozen in a separate TAP-0085 commit. No other
  Task status or Next Task ID changed.
- `2026-08-14` Reconciled the owner's post-Pass `.tapnap` Share console sample
  with a read-only current-source audit. TAP-0081/TAP-0082 now record that the
  production handoff is one direct file URL in one activity controller, with no
  residual manual provider, open-in-place, or destination-completion callback;
  LaunchServices `-10814`/`Code=-54`, CKShare/SWY, FileProvider, and persona
  messages are system probing and do not negate the successful four-path
  transport verdict or authorize private entitlements/document handlers. The
  gesture-gate timeout is observation-only unless paired with a reproducible
  visible stall and correlated structured milestones. Also recorded removal of
  the unused TAPNAP `UTType` helper, repair of the stale presentation-binding
  source assertion, and generic iphoneos `build-for-testing` exit 0. No device
  or Simulator run, commit, push, lifecycle transition, or Next Task ID change
  is claimed; TAP-0081 and TAP-0082 remain Doing.
- `2026-08-14` Board Steward recorded the direct-file-URL transport checkpoint
  that will be identified by the commit containing this revision under subject
  `Checkpoint working Share transport before lifecycle repair`; no prospective
  hash is fabricated. The owner's ordinary-image/`.tapnap` Save to Files and
  AirDrop matrix remains Pass. The newly supplied detailed log and source audit
  keep lifecycle explicitly open: both artifact kinds trigger system URL probes
  after controller creation but before coordinator handoff, while current
  pending-handoff discard may delete that already-inspected source; `.tapnap`
  dismissal is not followed by controller-dismantled or `artifactLease`
  terminal cleanup before the next Share; and an `under50ms` construction
  measurement precedes `over50ms` feedback attributed to the same construction
  phase. This checkpoint separates working transport from the still-defective
  source-lifetime, teardown, and progress-attribution state. TAP-0081 and
  TAP-0082 remain Doing. No other Task record/status or Next Task ID changed.
- `2026-08-14` Board Steward recorded the owner's replacement TAP Share
  lifecycle decision after the complete repeated-sheet log disproved controller
  deinitialization as a prompt normal cleanup boundary. The approved flow removes
  the app-owned ready/boundary page and the 50 ms reveal plus 400 ms hold: a
  format tap immediately shows preparation progress, payload readiness closes
  the popover, and `UIActivityViewController` is constructed only after actual
  popover disappearance at the real system-sheet boundary, without
  preconstruction or early system probes. The matching sheet-end signal owns
  asynchronous, idempotent artifact cleanup even if SwiftUI/UIKit retains the
  old controller; stale A termination cannot affect B. The direct-file-URL
  transport matrix remains Pass, but the current lifecycle candidate is
  uncommitted and unaccepted. TAP-0081 and TAP-0082 remain Doing; no other Task
  status or Next Task ID changed.
- `2026-08-14` Board Steward recorded the owner's explicit correction to TAP
  Share progress geometry. Preparation does not replace the whole popover: the
  selector hierarchy stays mounted, the clicked option row alone changes in
  place to progress plus current percentage, and every sibling option remains
  visible but disabled. Payload readiness then closes the popover before the
  real system-sheet boundary. TAP-0081 and TAP-0082 remain Doing, the current
  candidate remains unaccepted, and no implementation, prototype sync, build,
  test, device run, commit, push, other status, or Next Task ID change is
  claimed.
- `2026-08-14` Board Steward recorded the owner quote “对的 现在原型是我想要的”
  as exact `ownerApproved` status for `TAP-0081-r3-candidate`. The final UI
  contract shows subtitle text before preparation, then swaps only the clicked
  row's same fixed slot to a 2px determinate track; it shows no percentage or
  Cancel, preserves selector/title/icon/badge/row/popover/sibling geometry and
  identity, keeps all other rows visible but disabled, and introduces no
  independent preparation or ready page. Payload readiness closes the popover
  before the system sheet. TAP-0081 and TAP-0082 remain Doing pending native
  build/test and attended device acceptance; no other status or Next Task ID
  changed.
- `2026-08-14` Board Steward synchronized the implemented native
  `TAP-0081-r3-candidate` without converting compilation into acceptance. The
  selected row now replaces only its fixed subtitle slot with a 2px determinate
  track, with no preparation percentage/Cancel and no geometry/identity change;
  payload readiness closes the popover before the sheet boundary constructs the
  one direct-file-URL controller. Exact item-Binding and SwiftUI `onDismiss`
  signals converge on one exact-ID, idempotent end transition that schedules
  cleanup off the main thread; stale A cannot end B, and no destination-
  completion auto-close callback or timed watchdog remains. Generic Simulator
  and iphoneos `build-for-testing` each exited 0 without launching Simulator;
  prototype, static/source, diff, and Swift parse checks passed, but tests were
  compiled rather than run. No device run, owner native verdict, commit, push,
  status transition, or Next Task ID change is claimed. TAP-0081 and TAP-0082
  remain Doing pending owner self-installation and acceptance.
- `2026-08-14` Board Steward recorded the owner's explicit current closure
  decision and moved TAP-0081/TAP-0082 Doing -> Done. Exact r3 progress remains
  an honest app-payload indicator only: no 99% system-readiness wait, fake
  completion, 400 ms hold, or ready overlay is introduced; payload readiness
  closes the popover and iOS owns the following Share sheet. The previously
  accepted ordinary-image/`.tapnap` x Save to Files/AirDrop matrix remains the
  direct-image transport evidence. The newest log fully proves one `.tapnap`
  attempt only: intermediate cleanup L70, payload ready L72, handoff L73,
  controller creation under 50 ms L74, system probes L75–85, sheet appearance
  L86, dismissal L93, controller release L94, and final artifact cleanup L95.
  It does not prove direct-image teardown, stale-A/new-B isolation, or cleanup
  independent of controller release; focused r3 XCTest was compiled but not
  run. The owner explicitly accepted these evidence exceptions. No prospective
  commit hash is fabricated; the containing closure commit supplies it.
  Cold-state evidence is deliberately separated and emphasized: the same
  session overlaps camera startup, Locked Camera import/context despite
  `managerSessionCount=0`, a 908-item first catalog snapshot taking `7795 ms`,
  and App Attest reset/network failure, while Share fetch/package/controller
  work is only about `11.7 ms`/`27.5 ms`/under 50 ms. This reprioritizes
  investigation toward startup/catalog/credential/lifecycle overlap without
  proving MainActor causation. TAP-0008 remains Todo because the log has no
  setup-row/button timeline and TAP-0040 still needs an independent clean-
  install run. TAP-0009 remains Todo because the 7.795 s catalog measurement is
  only its second readiness group and supplies no first-frame, controls/
  shutter/haptics, marker, interruption, or repeated-launch evidence; TAP-0041
  remains Todo pending a revised procedure. TAP-0083 remains Doing. TAP-0010
  and all other Task records/statuses and Next Task ID are unchanged.
- `2026-08-14` Board Steward closed TAP-0085 after its final independent-freeze
  condition became current Git evidence. Moved TAP-0085 Doing -> Done and
  recorded implementation commit
  `28d5aef683848c3043f0777b6f3c9665a897864b`, now in clean `main` and
  `origin/main` through merge `37d0c61`. The owner-approved iPhone-only
  Product/UI-prototype/README boundary, main-app Debug and Release effective
  settings (`iphoneos iphonesimulator`, device family `1`, and all three Mac/XR
  routes `NO`), generic/platform=iOS Debug build-for-testing with code signing
  disabled, and built-app `UIDeviceFamily = [1]` were rechecked on main; no
  Simulator or physical device was launched. The adjacent shared-scheme
  LaunchAction Release-to-Debug change in `28d5aef` is not TAP-0085 scope or
  completion evidence and remains untouched under the owner's instruction to
  preserve current mainline state. TAP-0007 remains Inbox; Next Task ID and all
  other Task records/statuses are unchanged.
- `2026-08-14` Allocated TAP-0086 after a complete all-status Locked Camera
  duplicate search and advanced Next Task ID to TAP-0087. Existing TAP-0080 is
  completed documentation migration with no code-deletion scope; TAP-0013 and
  TAP-0049 preserve the separate lifecycle-correct experiment/evidence path;
  TAP-0083 owns cross-cutting cold-path governance; and deprecated TAP-0070
  rejects the old capability claim. None owns complete removal of the current
  main-tree Locked Camera targets, embedded products, entry routes, shared
  intents, containing-app startup/context/handoff/import wiring, and dedicated
  tests/resources. The owner explicitly directed “删除锁屏启动相关的代码和
  入口” and authorized a new Instant Task when no match existed. TAP-0086 moved
  Inbox -> Todo -> Doing, assigned to `/root` on baseline `main@6c45a77`, with
  ordinary Camera/Library/Pending Queue/App Intents, Git history, and the
  dedicated experiment branch preserved. Prototype impact is N/A by owner
  direction. Done requires a zero-production-reference source/project/product
  scan, generic iPhone build plus test compilation, a built app with no Locked
  Camera `.appex`, retained-path compilation, and full documentation/handoff
  reconciliation. No implementation, deletion, validation, commit, or Done
  transition is claimed; all other statuses are unchanged.
- `2026-08-14` Board Steward recorded the complete uncommitted TAP-0086
  implementation and validation handoff while deliberately keeping the Task in
  Doing for product-owner review. The actual baseline is `main@6c45a77`. The
  candidate removes both Locked Camera extension targets and embedded `.appex`
  products, their shared intents, the containing app's framework/context/
  session-import/URL/user-activity/startup/route/queue wiring, and dedicated
  resources and tests, while preserving ordinary Camera, Library, Pending
  Capture Queue, retained App Intents, Git history, and the isolated experiment
  path. Product Contract §4, TAP Library/test READMEs, localization, Info.plist,
  privacy diagnostics, and lint inputs are synchronized; prototype/manifest,
  UI Prototype Contract, acceptance record, specialized contract, root README,
  and AGENTS.md are N/A for the reasons recorded in the Task handoff. A fresh
  generic iPhone Debug `build-for-testing` with code signing disabled exited 0;
  only three retained targets remain, the built app contains zero `.appex`, its
  parsed Info has no Locked Camera URL, and source/project scans plus `plutil`,
  `jq`, and diff-check passed. Simulator/device launch and runtime tests were
  not performed. The lint script cleared its removed-file/reference gate but
  exited nonzero on three pre-existing unrelated complexity/length violations,
  so no full lint pass is claimed; final read-only review found no P0/P1 issue.
  Per the owner's review-before-commit rule, no commit, push, acceptance, or
  Done transition is recorded. After owner acceptance, the implementation may
  be committed separately with subject `Remove Locked Camera integration from
  main`, then returned to the Board Steward for closure. TAP-0013, TAP-0049,
  TAP-0083, every other Task status, and Next Task ID remain unchanged.
- `2026-08-14` The owner explicitly accepted TAP-0086 with “完成验收现在把 0086
  标记为 done 并提交”. Board Steward completed the Done When audit and moved
  TAP-0086 Doing -> Done. The accepted main-tree result removes both extension
  targets, embedded `.appex` products, shared intents, all containing-app Locked
  Camera startup/context/session-import/URL/user-activity/route/queue wiring,
  and dedicated resources/tests while preserving ordinary Camera, Library,
  Pending Capture Queue, retained App Intents, Git history, and the isolated
  experiment path. The generic iPhone Debug build-for-testing exited 0; three
  retained targets remain, the built app has zero `.appex` and no Locked Camera
  URL, and the recorded source/project/product and document-impact checks
  passed. Simulator/device launches and runtime tests remain unrun and are not
  claimed as passes. The lint command remains nonzero only for the three
  recorded pre-existing unrelated complexity/length violations, so no full lint
  pass is claimed. The implementation plus closure record belong to the
  containing commit subject `Remove Locked Camera integration from main`; no
  prospective hash is fabricated before Git creates it. TAP-0013, TAP-0049,
  TAP-0083, all other statuses, and Next Task ID remain unchanged.
- `2026-08-14` Allocated TAP-0087 after the development session's complete all-
  status duplicate search and advanced Next Task ID through deferred children
  TAP-0088/TAP-0089 to TAP-0090. TAP-0006 owns only the completed static
  prototype foundation; TAP-0008/TAP-0009 own native setup/readiness delivery;
  and TAP-0083 explicitly excludes visible prototype work and delegates first-
  install/resource readiness. The owner approved TAP-0087 as their independent
  P0 common prerequisite for canonical install/activation terminology,
  deterministic route/marker semantics, t0…tn/Δ work budgets, a source-grounded
  cross-feature heavy-work map, and an instrumented reviewer-only inspector.
  The review journey is system Launch Screen -> scenario-dependent Setup/
  Permission/Initialization -> Viewfinder -> Library -> Photo Viewer, with
  Library catalog/thumbnail/open/return timing transitions in scope. Viewfinder
  controls and Photo Viewer 2D/3D workflows remain visual/Deferred only.
  Recorded TAP-0087 Inbox -> Todo -> Doing, `/root` assignment, baseline
  `main@985425f`, and prerequisite links in TAP-0008/TAP-0009/TAP-0083 without
  changing their statuses or old history. All-status child searches found no
  exact prototype/inspector follow-up, so TAP-0088 and TAP-0089 were allocated
  Inbox/Unassigned, blocked until TAP-0008/TAP-0009/TAP-0083 complete, and
  linked to the existing native Camera and Viewer/3D capability Tasks rather
  than duplicating them. No contract/prototype/code change, validation,
  acceptance, commit, push, or Done transition is claimed by this Board-only
  allocation; every unrelated record and status remains unchanged.
- `2026-08-14` Board Steward recorded the owner's superseding startup-network
  decision without rewriting historical completion or evidence. Ordinary
  camera entry/capture is network-independent; first-install Setup contains
  only Camera/Photos as required permission gates and Location/Microphone as
  optional rows; revoked Camera/Photos route to Required Permission Check; and
  Setup contains no Network row or onboarding `/healthz` preflight. TAP-0008
  now targets that four-row explicit-action contract and depends on owner-
  approved `TAP-0008-r3-candidate`. TAP-0087 preserves TAP-0008-r2's non-
  Network visual language/assets/geometry, keeps TAP-0009-r1-candidate frozen,
  and must
  produce `TAP-0008-r3-candidate` plus composed inspector/journey
  `TAP-0087-r1-candidate`. Moved TAP-0010 Todo -> Deprecated because its
  onboarding retry surface no longer exists; App Attest retry remains outside
  that Task under TAP-0015, and no membership behavior is inferred. TAP-0050
  and TAP-0051 remain Done as historical facts with supersession notes.
  TAP-0040 remains Todo, but its linked procedure is explicitly stale and must
  be revised by `/root` before execution to remove Network and cover the four
  permission rows. TAP-0009 and TAP-0083 retain their statuses; Next Task ID
  remains TAP-0090. This is a Board-only, uncommitted revision: no Product
  Contract, prototype, acceptance file, code, validation, commit, or push is
  claimed.
- `2026-08-14` Board Steward recorded the owner's urgent correction to the
  immediately preceding no-Network direction and preserved that false interim
  entry as append-only history. Fresh Installation keeps Network, Camera, and
  Photos as required Setup operations; Location and Microphone remain optional.
  The explicit Network action must complete the approved first-install App
  Attest credential registration/verification bootstrap, not merely generic
  `/healthz` reachability, before Continue can join Camera and Photos readiness.
  This bootstrap is not capture-proof verification. After setup, ordinary
  Viewfinder entry and local capture remain network-independent; Camera/Photos
  revocation enters Required Permission Check, while Network failure does not;
  later credential/Pending work remains feature-owned and deferred. Revised
  TAP-0008 to the five-operation target and restored TAP-0010 Deprecated -> Todo
  pending exact re-scope/merge rather than authorizing implementation. TAP-0087
  now preserves approved TAP-0008-r2 including its Network row, keeps
  TAP-0009-r1-candidate frozen, removes the no-Network TAP-0008-r3 requirement,
  and assigns corrected semantics to TAP-0087-r1-candidate. TAP-0040 remains
  Todo; its concurrent procedure candidate now replaces generic `/healthz`
  evidence with initial App Attest bootstrap/retry evidence and retains
  Network, but no execution or owner verdict is claimed. TAP-0050/TAP-0051
  remain Done with both interim and corrected history preserved. TAP-0008/TAP-0009/
  TAP-0010/TAP-0040 remain Todo; TAP-0083/TAP-0087 remain Doing; Next Task ID
  remains TAP-0090. This Board-only correction claims no native/prototype/
  acceptance implementation, validation, commit, or push; concurrent TAP-0087
  contract/module work remains owned by its development session.
- `2026-08-14` Board Steward normalized the active TAP-0009 and TAP-0087 startup
  vocabulary without rewriting prior history. TAP-0009 now routes through
  structured `S/P/I` facts and distinguishes Fresh Installation,
  Delete-and-Reinstall, In-place App Update, Development Replacement Install,
  Offload-and-Reinstall current/changed-build cases, Same-Device Backup Restore,
  Cross-Device Migration Restore, and Local State Inconsistency; a current
  preserved `I` bypasses Resource Initialization even when an
  Offload-and-Reinstall follows a Cold Resource Path. TAP-0087 Scope now uses
  the exact canonical installation, activation, and resource-path terms.
  Corrected the TAP-0041 registry projection after
  confirming its concurrent draft already covers the Library-catalog checkpoint,
  versioned marker, interruption, and current-marker bypass; its remaining gaps
  are the full canonical installation matrix, explicit Debug-only diagnostics/
  timing-evidence boundary, frozen build/device scope, and owner confirmation.
  TAP-0009/TAP-0041 remain Todo and TAP-0087 remains Doing. The exact
  `Docs/StartupLifecycleContract.md` and `TAP-0087-r1-candidate` revisions remain
  candidates requiring owner approval. Next Task ID remains TAP-0090. This was
  a Board-only consistency update; it claims no other document change, native or
  prototype implementation, acceptance execution, status transition, commit,
  or push.
- `2026-08-14` Board Steward corrected the final TAP-0087/TAP-0083 Board
  projections without changing lifecycle state. TAP-0087 now records its actual
  independent candidate entry `Prototype/startup-lifecycle.html`, single reducer/
  model `Prototype/startup-model.mjs`, and page controller
  `Prototype/startup-prototype.mjs`; `Prototype/index.html` remains the
  historical entry for independently approved TAP-0008/TAP-0009/TAP-0081 slices,
  whose approvals do not transfer to TAP-0087. TAP-0083 now owns the complete
  physical-iPhone Debug versus optimized Release/Profile startup matrix, each
  with the debugger attached and detached, under controlled matching facts. All
  four cells are mandatory;
  only optimized, debugger-detached evidence may close a native startup timing
  threshold, and TAP-0045/TAP-0047/TAP-0082 cannot substitute their feature-
  specific evidence for that matrix. The TAP-0040 registry now names Fresh
  Installation behavior and its explicit Delete-and-Reinstall reset procedure;
  earlier “clean install” wording remains historical only. TAP-0083 and TAP-0087
  remain Doing, TAP-0040 remains Todo, and exact owner approval of
  `TAP-0087-r1-candidate` plus the synchronized contract revision remains
  pending. Next Task ID remains TAP-0090. This Board-only revision claims no
  prototype/native implementation, matrix execution, threshold pass, acceptance
  verdict, commit, or push.
- `2026-08-15` Board Steward recorded the owner's attended physical-device
  acceptance of the bounded non-Network `fix0809` lifecycle flow and superseded
  only the earlier statement that physical-device acceptance for that bounded
  candidate had not run. TAP-0008 and TAP-0009 remain Doing because their full
  Done When boundaries are not satisfied. TAP-0041 remains Todo: its bounded
  flow has owner confirmation, while exact native visual parity and the complete
  canonical scenario/fault-injection matrix retain a Pending verdict. The
  Network/App Attest/Pending freeze, canonical credential-bound `S`, restore
  end-to-end gaps, complete W11/W12 `t5` release, TAP-0040 full first-install
  matrix, and TAP-0087 v16 approval boundary remain unchanged. This Board-only
  synchronization changes no implementation, prototype, contract, acceptance
  procedure, other Task status, Next Task ID, commit, or push state.
- `2026-08-15` Board Steward recorded the owner's TAP-0087 reviewer-overlay
  decision and synchronized the active TAP-0008/TAP-0009 handoffs to commit
  `66ac001` without rewriting their earlier pre-commit history. The overlay
  preserves `main@4cc02e5f12f2` as immutable source-audit mismatch truth and
  uses manifest-backed outcomes: yellow/yellow for implemented plus bounded-log
  accepted, yellow/red for implemented but not log-verifiable and therefore not
  aligned, red/red for frozen Network/App Attest/Pending work, and unchanged
  green for baseline-aligned records. It applies to the right lifecycle cards,
  Timing lifecycle cards, and Workload actual cards only; dashed connectors,
  actual-phase anchors, and blue prototype Workload targets remain unchanged.
  This Board-only synchronization authorizes no Swift change, changes no Task
  status or acceptance procedure, does not approve the complete TAP-0087 v16
  composition, and records no push. TAP-0087, TAP-0008, and TAP-0009 remain
  Doing; Next Task ID remains TAP-0090.
- `2026-08-15` Board Steward synchronized the completed TAP-0087 v17 reviewer-
  overlay QA while preserving every earlier v16 decision and evidence entry as
  append-only history. Git HEAD/native candidate remains `66ac001`; the
  immutable source-audit baseline remains `main@4cc02e5f12f2`. The JSON-backed
  yellow/yellow, yellow/red, red/red, and baseline-green outcomes now project
  across the right lifecycle, Timing lifecycle, and Workload actual cards while
  dashed connectors, circular actual-phase anchors, and existing blue prototype
  Workload targets remain unchanged. At `1349 x 876`, Resource Initialization
  sequence `10` rendered six lifecycle cards/six dashed paths and nine Workload
  actual cards (three log-accepted, four implemented but not log-verified, and
  two frozen) with five blue targets/five paths; fresh-install sequence `6`
  rendered one frozen actual/one blue target/one path. Timing -> Ordered log ->
  Timing restored the projection, and the browser console reported zero errors
  or warnings. Evidence is recorded in
  `Prototype/evidence/TAP-0087-r1-v17-fix0809-outcome-cards.png` and
  `Prototype/evidence/TAP-0087-r1-v17-fix0809-outcome-workload.png`. This Board-
  only synchronization changes no Swift code, native commit, Task or acceptance
  status, frozen behavior, or push state. TAP-0008, TAP-0009, and TAP-0087 remain
  Doing; the complete v17 composition remains `ownerReviewRequired`; Next Task
  ID remains TAP-0090.
- `2026-08-15` Board Steward recorded the owner's TAP-0087 v18 active-record
  pruning decision. Commit `d4b19d9` remains the complete v17 reviewer archive;
  active v18 removes originally aligned and `implementedLogAccepted` records
  from the manifest-backed right lifecycle, Timing lifecycle, and Workload
  actual projections and retains only nine unresolved Lifecycle records plus
  eight unresolved Workload records with `implementedNotLogVerified` or
  `deferredFrozen` outcomes. This Board-only synchronization preserves all
  earlier v17 history and evidence, changes no Swift or native behavior, records
  no new implementation/QA/acceptance claim, and changes no Task status or push
  state. TAP-0008, TAP-0009, and TAP-0087 remain Doing; the complete v18
  composition remains `ownerReviewRequired`; Next Task ID remains TAP-0090.
- `2026-08-15` Board Steward synchronized completed v18 active-record deletion
  and reviewer QA. Active JSON now contains nine unresolved Lifecycle records
  (five lifecycle-lane plus four workload-lane owners; eight yellow/red plus one
  frozen) and eight unresolved Workload records (seven timing plus one semantic;
  four yellow/red plus four frozen); active accepted/aligned counts are zero,
  while `d4b19d9` remains the complete v17 archive. Codex in-app Browser at
  `1575 x 1204` verified five right lifecycle cards; Resource Initialization
  sequence `10` verified five lifecycle cards/paths at `t0` and `t2`, six
  Workload actual cards, three blue targets/paths, and 16 canonical effects;
  fresh-install sequence `6` verified three actuals including one frozen and one
  blue target/path. Timing/log round-trip restoration passed, and two v18 PNGs
  record the evidence. Prototype tests passed `58/58`; all six MJS checks,
  manifest parse, and diff check passed. This Board-only synchronization changes
  no Swift or native behavior, Task or acceptance status, complete-composition
  approval, or push state. TAP-0008, TAP-0009, and TAP-0087 remain Doing; the
  complete v18 composition remains `ownerReviewRequired`; Next Task ID remains
  TAP-0090.
- `2026-08-15` Board Steward recorded the owner's delivery/evidence split after
  a complete all-status duplicate and responsibility audit. The committed
  non-Network native lifecycle target placement is the completed TAP-0008 and
  TAP-0009 delivery, so both moved Doing -> Done without treating separate
  evidence or cross-boundary behavior as complete. Existing TAP-0010 was
  re-scoped and raised to P0 for initial Network/App Attest, canonical
  credential-bound `S`, and restore binding; existing TAP-0015 was re-scoped
  and raised to P1 for post-setup App Attest/Pending deferred guards and retry
  optimization; TAP-0083 retains measured route-shell/first-frame placement;
  TAP-0048 retains visual parity; and TAP-0040/TAP-0041 retain attended device
  acceptance. No existing Task owned reusable machine-checkable non-Network
  lifecycle regression evidence, so allocated TAP-0090 Inbox -> Todo with a
  privacy-safe JSON/JSONL schema, automated/Simulator assertion matrix, and an
  explicit no-photo/no-screenshot/no-recording evidence boundary, then advanced
  Next Task ID to TAP-0091. Tentative TAP-0087 v19 semantics merge implemented-
  but-unverified records into yellow/red target cards/effects with no difference
  connector; truly unmigrated records retain red-actual/blue-target differences
  and link TAP-0010 or TAP-0015 directly instead of using per-session freeze
  copy. TAP-0087 remains Doing; TAP-0010, TAP-0015, TAP-0040, TAP-0041,
  TAP-0048, and TAP-0090 remain Todo; TAP-0083 remains Doing. This Board-only
  update claims no new native/prototype implementation, regression pass, visual
  parity, device verdict, commit, or push.
- `2026-08-15` Board Steward synchronized the implemented TAP-0087 v19 reviewer
  projection and root's no-screenshot in-app Browser DOM/computed-style QA.
  Ordinary sequence `17` showed five right follow-up cards/zero differences,
  five Timing lifecycle follow-ups/zero paths, and four yellow Workload targets
  plus two red actuals/two blue targets/two paths. Fresh sequence `27` showed
  two yellow Workload targets plus four red actuals/four blue targets/four
  paths. The Browser console had zero errors/warnings; Prototype tests passed
  `58/58`, and MJS syntax, manifest JSON, and diff checks passed. No photo,
  screenshot, or screen recording was retained. TAP-0087 remains Doing and the
  complete composition remains `ownerReviewRequired`; no TAP-0090 regression,
  native parity, device acceptance, commit, owner approval, other status, or
  Next Task ID change is inferred.
- `2026-08-15` Resolved the mainline synchronization ID collision without
  dropping either Task. Mainline `TAP-0090` remains the approved Todo for
  machine-checkable non-Network startup lifecycle regression evidence. The
  uncommitted local Viewfinder chrome-flicker capture was renumbered to
  `TAP-0091`, remains Inbox/P1/Unassigned with its original observation and
  scope intact, and appears in the detailed registry plus Inbox projection.
  Advanced Next Task ID to TAP-0092. This conflict resolution changes no
  Product Contract, prototype, native code, Task lifecycle state, validation,
  acceptance, commit, or push claim.
- `2026-08-15` Board Steward allocated `TAP-0092` as an Inbox/P0 repository-
  health cleanup after the owner clarified that the requested work concerns
  inappropriate and brittle tests, unmounted old code, redundant information,
  and stale active documentation rather than Agent Trace/PR integration. The
  owner target date is `2026-08-24`. An all-status responsibility audit kept
  `TAP-0029` separate for Debug-support isolation and oversized-suite structure,
  while TAP-0092 owns one bounded semantic cleanup pass with per-item retention,
  migration, replacement, or deletion evidence. Advanced Next Task ID to
  TAP-0093. This Board-only allocation changes no Product Contract, product or
  UI behavior, source/test/document content outside the Board, lifecycle state
  of existing Tasks, validation, acceptance, commit, or push claim.
- `2026-08-21` Board Steward recorded the owner's partial
  [`TAP-0092` cleanup manifest](TAP-0092CleanupManifest.md) decision and started
  execution through the required lifecycle sequence. Every row whose
  disposition is `replace` moved from Pending to approved; TAP-0092 moved Inbox
  -> Todo after the replace-only boundary was frozen, then Todo -> Doing after
  `/root` was bound as the single coordinating Session on the shared `main`
  checkout at baseline `42c5e9355cbcdf9e6a0d7c7f750aeb4ef54ecb6f`.
  Each approved item may be delegated to one medium-reasoning child Agent.
  `T92-CODE-002` permits replacement of valuable legacy-seam tests only, not
  production-code deletion; `T92-DOC-004` may execute only after its code-
  decision prerequisite is met. Every `retain`, `defer`, standalone/conditional
  `migrate-delete`, and later deletion stage remains Pending. iPhone Simulator
  validation is allowed, but each Simulator test that does not affect the
  cleanup conclusion must be logged individually as non-contributing and cannot
  support replacement, deletion, device acceptance, or product-behavior claims.
  This lifecycle/approval synchronization records no implementation or test
  result, product/UI change, deletion, Done transition, commit, or push; Next
  Task ID remains TAP-0093.
- `2026-08-21` Board Steward synchronized the TAP-0092 replace-only execution
  handoff and established reciprocal links among the canonical Task,
  [cleanup manifest](TAP-0092CleanupManifest.md), and
  [execution evidence ledger](TAP-0092CleanupEvidence.md). DOC-001/002/003 are
  Validated. SRC-001 through SRC-006, START-011, and the CODE-002 replacement
  stage are Pending because existing production behavior seams could not prove
  equal-strength controlled regressions; all experimental Swift test edits were
  reverted and current production/test Swift diff is zero. Conditional DOC-004
  is Blocked and unchanged because its code-disposition prerequisite is unmet.
  The recorded validation boundary is baseline `822 executed / 813 passed / 9
  failed / 0 skipped`, six persistent plus three parallel-sensitive failures,
  successful final Debug Simulator `build-for-testing`, and Prototype `20/20`.
  Focused known failures, zero-executed infrastructure attempts, and the
  per-test `Contribution: None` ledger remain explicit; green tests are not
  replacement completion evidence. Independent evidence second review remains
  in progress, so TAP-0092 remains Doing. This update claims no product/UI
  behavior change, production/test Swift mutation, device acceptance, complete
  evidence approval, Done transition, commit, or push; Next Task ID remains
  TAP-0093.
- `2026-08-21` Board Steward superseded only the preceding TAP-0092 evidence-
  review-status clause after fourth-round independent read-only review accepted
  the execution ledger: every recorded xcresult count has zero delta, the run
  inventory has no missing or duplicate entries, the arithmetic is consistent,
  and reciprocal Board/manifest/evidence links are complete. This acceptance
  validates the ledger as a handoff record; it does not complete the eight
  Pending or one Blocked replacement scopes, authorize a deletion, satisfy Done
  When, or change the Task from Doing. The earlier append-only history remains
  intact. No product/UI behavior, production/test Swift content, device
  acceptance, commit, push, or Next Task ID changed.
- `2026-08-23` Board Steward synchronized the completed TAP-0092 three-iteration
  cleanup from the [manifest](TAP-0092CleanupManifest.md) and
  [evidence ledger](TAP-0092CleanupEvidence.md). The fixed health score increased
  `20.0 -> 27.3 -> 33.4 -> 84.1`, so the owner-mandated stop condition is met
  and the Task moved Doing -> Done. All Debug test builds passed; final focused,
  full Unit, and serialized diagnostic counts and the four classified residual
  failures remain explicit. Current UX/UI, mounted production behavior,
  security/privacy, public formats, persistence readers, and device/backend
  acceptance were not broadened or claimed. No commit, push, or Next Task ID
  change is inferred.
- `2026-08-23` Board Steward synchronized the TAP-0093 implementation and
  validation candidate. App `0.2 (2)`, mounted UX/UI, and Prototype revision/copy
  remain unchanged; distinct Still/Live/Video public and security families are
  v1 in TAPCamDemo and TAPCamVerifier; pre-release local compatibility layers
  are removed under clear-container recovery; and redundant Prototype/docs/tests
  were pruned without deleting real fixture decoder coverage. Final Demo build,
  focused `95/95`, Verifier Rust `44/44`, Vitest `119/119`, Prototype `58/58`,
  JS `4/4`, typecheck, rustfmt, production build, link scans, and diff checks
  passed. The only separate Startup failure is the recorded Simulator Keychain
  `-34018` baseline. TAP-0093 stays Doing pending an explicit owner decision on
  deleting the Verifier's currently supported legacy `.zip` input; current code
  and contracts continue to support it. No device/backend acceptance, commit,
  push, other lifecycle transition, or Next Task ID change is inferred.
- `2026-08-23` Board Steward recorded the owner's final TAP-0093 decisions. The
  Verifier now rejects legacy `.zip`, `application/zip`, generic ZIP-magic, and
  missing/invalid-sidecar fallback while retaining bounded ZIP-compatible
  parsing for current `.tapnap` packages. Rust `44/44`, Vitest `111/111`,
  TypeScript/production build, contract scans, and diff checks passed; prior
  Demo/Prototype validation remains applicable because this closure changed no
  Demo runtime or Prototype file. The separate unsigned-Simulator Keychain
  `errSecMissingEntitlement (-34018)` failure is owner-classified as a known
  legacy non-blocking test-infrastructure issue, not a production or TAP-0046
  acceptance verdict. TAP-0093 moved Doing -> Done. No new Task, App version,
  device/backend acceptance, commit, push, or Next Task ID change is inferred.
- `2026-08-23` Board Steward allocated TAP-0094 in Inbox after an all-status
  search and preserved the owner's complete distinction between the per-capture
  artifact manifest shared by the Mobile app and browser Verifier and the
  unrelated UI Prototype manifest. TAP-0062, TAP-0078, and TAP-0093 remain Done;
  TAP-0094 is their scoped cross-repository authority follow-up. Advanced Next
  Task ID to TAP-0095. This capture changed no contract authority, runtime code,
  validation, acceptance, commit, or push state.
- `2026-08-23` The owner explicitly approved TAP-0094's documentation-only
  scope and requested execution. The Board Steward froze Still/Live/Video
  manifest fields, content binding/proof, container embedding, `.tapnap`
  routing, version/compatibility rules, and normative examples as in scope;
  excluded Mobile/Verifier runtime code, SDKs, code generation, runtime
  dependencies, and any wire-byte or embedding-location change; moved TAP-0094
  Inbox -> Todo -> Doing; and bound the current `/root` collaboration session
  on Demo shared `main`. No implementation, validation, acceptance, commit, or
  push is claimed by this lifecycle transition.
- `2026-08-23` Board Steward synchronized the TAP-0094 local implementation and
  validation handoff while retaining `Doing`. TAPArtifactContracts is locally
  initialized on `codex/tap-0094-artifact-contracts` with `23` managed Markdown/
  JSON content files and `7` parseable synthetic JSON examples; shared authority
  references are synchronized in TAPCamDemo and in two bounded TAPCamVerifier
  documents without runtime, SDK/codegen, dependency, wire-format, or embedding-
  location changes. JSON `7/7`, the final broader local link scan `27/27`, final
  `jq` semantic assertions under `set -e` with exit `0`, Swift field-set
  comparison, current-ID/old-version scans, and Demo/Verifier diff checks passed.
  Known divergences remain documented. No build, commit, push,
  remote, tag, published URL, or device/backend acceptance is claimed. Closure
  remains pending owner authorization for remote creation/publication and
  commit/push.
- `2026-08-23` Board Steward completed TAP-0094 after the owner authorized and
  confirmed independent-repository creation and push. The GitHub target is
  Private [TAP-NAP/TAPArtifactContracts](https://github.com/TAP-NAP/TAPArtifactContracts)
  on default branch `main`, not Public. Initial commit
  `049f58749ca97b360b5683f516181df6f005482f` contains `23` documentation/JSON
  files and `2,885` lines; the clean local branch tracks `origin/main`, remote
  HEAD matches exactly, and GitHub repository plus README readback succeeded.
  Two publication audits and the complete JSON/link/anchor/semantic/field/
  identifier/version/diff-check evidence found no blocker. No runtime, SDK,
  codegen, dependency, wire-format, manifest-embedding, device, or backend claim
  changed. TAPCamDemo and TAPCamVerifier remain uncommitted and unpushed in
  their existing working trees. TAP-0094 moved Doing -> Done; no other Task,
  Next Task ID, commit, or push is inferred.
- `2026-08-23` Board Steward allocated TAP-0095 in Inbox after an all-status
  responsibility search. Completed TAP-0002/TAP-0003/TAP-0078/TAP-0092 remain
  foundations, and TAP-0094 remains Done because the independently published
  shared authority still satisfies its completion condition. TAP-0095 owns the
  distinct follow-up: fill any shared-repository documentation gap first, then
  delete only covered duplicate normative prose from TAPCamDemo/TAPCamVerifier
  while preserving repository-local responsibilities and dirty-worktree
  isolation. Advanced Next Task ID to TAP-0096. No implementation, deletion,
  validation, commit, push, visibility, or existing lifecycle state changed by
  capture.
- `2026-08-23` The owner approved TAP-0095's docs-only scope, requested start,
  and authorized task-owned commits. The Board Steward recorded migrate-before-
  delete coverage, no runtime/wire/embed changes, unique local product/
  implementation/flow retention, TAPCamVerifier pre-existing-dirty exclusion,
  separate per-repository commit/push evidence, and unchanged Private shared-
  repository visibility as mandatory boundaries. Moved TAP-0095 Inbox -> Todo ->
  Doing and bound the current `/root` collaboration session across the existing
  checkouts. Commit authorization does not silently claim a TAPCamDemo or
  TAPCamVerifier push. This Board-only transition changes no implementation
  document, artifact, validation result, commit, push, or remote state.
- `2026-08-23` Board Steward completed TAP-0095 after reconciling the full
  migration/fixture ledger, three isolated commit trees, validation evidence,
  documentation impact, and explicit remaining gaps. Private shared commit
  `63f96b31de193c3ad456ffa500cc0db03fb97142` is pushed to `origin/main` with
  the sole shared signing-generation, hash-participation, reconstruction,
  App Attest verification, TAP Video manifest/container, and exact-vector prose
  authority. Local unpushed Demo commit
  `3f49286d53afafa056cb4f138a2c9b2535ec76a8` contains `14` docs/example/
  Agent-guidance paths and preserves product/lifecycle/backend/acceptance/test
  roles. Local unpushed Verifier commit
  `d780636dcfbe8e006f4bea02415c9495906df2fa` contains only `README.md` and
  `Docs/VerificationFlow.md`; its tree and parent exactly match isolated clean-
  branch verification commit `75026adf6c5012757941eb0fb822b5a89a505344`,
  and all `18` tracked plus `5` untracked pre-existing dirty paths remained
  unchanged and outside the commit. Shared JSON `9/9`, links `28/28`, anchors
  `2/2`, transforms `8/8`, KLV/zstd/hash/mirror checks, and affected-source
  diff/link/ownership checks passed. The stale unimplemented Live browser prose
  and incorrect README proof placement were removed without changing runtime,
  dependencies, wire bytes, embedding, Private visibility, or acceptance. Done
  When is satisfied; TAP-0095 moved Doing -> Done. No new Task or Next Task ID
  change was made, and no Demo/Verifier push is claimed.
