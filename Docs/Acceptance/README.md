# Acceptance Reports

This folder stores executable evidence records linked from
[`DeviceAcceptance` Tasks](../../../TAPCamKanban/ProjectBoard.md). Evidence does not define product
scope; the canonical scope remains [ProductContract.md](../ProductContract.md).

Reports distinguish:

- product-owner-attended physical-device acceptance;
- Simulator UI and automation evidence;
- physical-device output, Photos, depth, proof, manifest, performance, and
  operational evidence.

Before executing a physical-device gap, the Agent must show the product owner
the proposed scope and procedure. A report is not complete unless it contains:

```md
# <Task ID> — <Acceptance title>

- Related Delivery:
- Product Contract:
- Build/Commit:
- Device/iOS:
- Date:
- Operator:

## Preconditions

## Reset / Install Procedure

1. ...

## Procedure And Expected Results

| Step | Action | Expected result | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | ... | ... | ... | ... |

## Required Evidence

- Public-safe structured logs / JSON / JSONL (or `N/A`):
- Automated assertion reports (or `N/A`):
- Procedure-approved image/video (or `N/A`):
- Output artifacts (or `N/A`):
- Result bundles (or `N/A`):
- Owner-live textual verdict:

## Verdict Conditions

- Pass:
- Fail:
- Blocked:

## Human Confirmation

`Pending` or `Accepted by <owner>, <date>`
```

Simulator results, automated clicks, or an Agent reading logs cannot be recorded
as attended device acceptance. When acceptance fails, keep the report and Task
history, link a Fix Task, and rerun through a new dated result rather than
overwriting the failure.

## Current Procedures

- [TAP-0040 — First-Install Explicit Operations](TAP-0040-first-install-operations.md)
- [TAP-0041 — First Camera-Interactive Readiness](TAP-0041-camera-readiness.md)
- [TAP-0042 — Professional Camera Control Matrix](TAP-0042-pro-controls.md)
- [TAP-0043 — Standard FOV/Depth And PRO No-Crop](TAP-0043-fov-depth-pro-no-crop.md)
- [TAP-0044 — Live Photo Capture, Signing, Readback, Audio, And Playback](TAP-0044-live-photo-chain.md)
- [TAP-0045 — TAP Video Device, Zero-Depth, Performance, And iCloud](TAP-0045-tap-video-device.md)
- [TAP-0046 — Production App Attest And Final Signed-Export Gate](TAP-0046-app-attest-production.md)
- [TAP-0047 — TAP Library Permission And Delete Semantics](TAP-0047-library-permission-delete.md)
- [TAP-0048 — Approved Web Prototype To SwiftUI Parity](TAP-0048-web-swiftui-parity.md)
- [TAP-0049 — Lifecycle-Correct Locked Camera Experiment](TAP-0049-locked-camera-lifecycle.md)

Each procedure's own `Status` and `Human Confirmation` fields are the active
truth. Some remain unexecuted or blocked, TAP-0041 records a bounded accepted
slice with its full matrix open, and TAP-0048 records evidence in progress.
Before any new run, confirm that procedure's build, device/iOS matrix,
controlled reset, evidence retention, budgets, and owner-live checkpoints.
