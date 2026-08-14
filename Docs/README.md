# TAPCam Documentation

Start here. The current documentation set is intentionally organized by
authority so an Agent does not need to read every historical design before
working on one Task.

## Canonical Product And Work Management

| Role | Document |
| --- | --- |
| Current capabilities, state machines, non-goals, future/experimental scope, and claim boundaries | [ProductContract.md](ProductContract.md) |
| Markdown task database and Inbox/Todo/Doing/Done/Deprecated views | [ProjectBoard.md](ProjectBoard.md) |
| HTML/Web prototype authority and Prototype → SwiftUI → acceptance workflow | [UIPrototypeContract.md](UIPrototypeContract.md) and [live prototype](../Prototype/README.md) |

Every Agent must follow the repository rules in [../AGENTS.md](../AGENTS.md):
read the Product Contract, find or revise a Task before creating one, and use a
separate DeviceAcceptance Task for attended physical-device evidence.

## Current Specialized Contracts

Specialized documents remain only when they own a unique implementation,
format, security, or cross-project responsibility. They do not override the
Product Contract.

| Responsibility | Entry |
| --- | --- |
| App Attest client/backend boundary | [AppAttest/README.md](AppAttest/README.md) |
| App Attest backend interface | [AppAttest/BackendContract.md](AppAttest/BackendContract.md) |
| Live Photo cross-project browser verification contract | [LivePhotoBrowserVerification.md](LivePhotoBrowserVerification.md) |
| TAP Video MP4/KLV/manifest/proof/content-binding contract | [TAPVideoFormatContract.md](TAPVideoFormatContract.md) |
| Installation/activation vocabulary, startup routing, t0…tn milestones, and heavy-work ownership | [StartupLifecycleContract.md](StartupLifecycleContract.md) |
| First-install, empty-cache, large-Library, first-Share, and system-presentation responsiveness standard | [ColdPathResponsiveness.md](ColdPathResponsiveness.md) |
| Camera output profile and packaging contract | [../TAPCamDemo/CameraCapture/Output/README.md](../TAPCamDemo/CameraCapture/Output/README.md) |
| Camera runtime module boundary | [../TAPCamDemo/CameraCapture/README.md](../TAPCamDemo/CameraCapture/README.md) |
| User-facing TAP Library and Viewer boundary | [../TAPCamDemo/DepthAnalysis/README.md](../TAPCamDemo/DepthAnalysis/README.md) |
| App-private Pending Capture Queue implementation | [../TAPCamDemo/TAPLibrary/README.md](../TAPCamDemo/TAPLibrary/README.md) |
| Test and automation boundary | [../TAPCamDemoTests/README.md](../TAPCamDemoTests/README.md) |

The Swift module is still named `TAPLibrary`, but current prose calls its
private signing/export/retry responsibility the **Pending Capture Queue**.
**TAP Library** refers only to the user-facing mixed-media grid and Viewer.

## Acceptance

`Docs/Acceptance/` stores executable evidence records. A physical-device report
must be linked from its `DeviceAcceptance` Task and contain prerequisites,
install/reset steps, numbered actions, expected results, required evidence, and
explicit human confirmation.

Acceptance reports establish only what their procedure exercised. They do not
define current product scope.

## Historical Material And Retention

Old PRDs, design phases, branch audits, AITrace, POCs, experiments, and Sketch
pilot documents were migrated through `TAP-0003`. Unique current obligations
and acceptance procedures now live in the minimal active set; obsolete files
were removed from the current tree. Git history remains the recoverable archive.

Do not add an old file back to the active reading path merely for traceability.
Create or revise a Task when its idea needs to be reconsidered.
