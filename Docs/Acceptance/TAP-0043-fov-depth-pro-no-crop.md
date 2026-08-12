# TAP-0043 — Standard FOV/Depth And PRO No-Crop

- Status: `Draft — not executed`
- Related Delivery: `TAP-0012`
- Contract: `ProductContract §3.1`
- Build/Commit: `To be frozen before execution`
- Device/iOS: `Owner must choose a device with multiple Standard FOVs and eligible PRO`
- Human Confirmation: `Pending`

## Preconditions

- Use a tripod, stable light, center/edge landmarks, and near/far objects that
  reliably yield depth.
- Export original HEIC, manifest/crop/source/zoom facts, and Apple depth.
- Freeze the preview-to-output mapping and tolerance before execution; do not
  loosen it after seeing results.
- **Owner live:** compare preview and final composition.

## Reset And Install

1. Install the frozen build, complete setup, select default HEIC, reset Basic
   EV, disable scene-changing flash behavior, and begin clean logs.
2. Record the device capability matrix and every visible Standard FOV.
3. Do not move the camera or scene until all comparisons finish.

## Procedure

1. Capture a reference screenshot of the default Standard preview and FOV list.
2. For every visible Standard FOV: select and stabilize it; capture the preview;
   record RGB/depth source, raw zoom, and generation; take a photo; export
   original/manifest/depth facts; compare final RGB landmarks under the frozen
   mapping; then compare RGB/depth landmarks in the 2D depth view.
3. Rapidly traverse all Standard FOVs in both directions and capture once more;
   the artifact must use the final generation and plan.
4. **Owner live:** enter PRO after frosted readiness. Confirm the selector is
   hidden and the view is fixed rear LiDAR 24 mm / 1x.
5. Take at least three PRO photos in the same scene. Each must report the fixed
   source, raw zoom 1.0, full-frame/no product crop, aligned RGB/depth, and the
   matching manifest facts.
6. Return to Standard and verify the prior Standard selection/mapping resumes
   without PRO source or crop residue.

## Expected Results

- Every displayed Standard FOV resolves to an explicit RGB/depth capture plan;
  preview and output correspond under the frozen mapping and RGB/depth
  landmarks align.
- Rapid switching cannot write a stale source, zoom, or generation.
- PRO is always the fixed eligible 24 mm / 1x full-frame path, never a cropped
  or multi-focal product surface.

## Required Evidence

- Per-FOV preview, original HEIC, manifest/source/zoom/crop summary, depth facts,
  RGB/depth landmark comparison, and generation log.
- Three equivalent PRO evidence packages, Standard↔PRO recording, and the full
  result matrix.
- **Owner live:** written acceptance of preview/final composition and no-crop.

## Verdict

- **Pass:** every FOV actually displayed by the chosen device passes and all
  fixed PRO source/zoom/crop conditions hold.
- **Fail:** a visible FOV has no valid RGB/depth plan; preview/output exceeds the
  frozen mapping; stale plan data lands; Standard silently uses the PRO path; or
  PRO crops/zooms/exposes multiple focal choices.
- **Blocked:** a suitable device/scene, originals/manifest/depth, or pre-frozen
  mapping/tolerance is unavailable. A FOV not offered by that device is recorded
  as unavailable, not silently passed.
