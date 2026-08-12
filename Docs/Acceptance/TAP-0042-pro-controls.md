# TAP-0042 — Professional Camera Control Matrix

- Status: `Draft — not executed`
- Related Delivery: `TAP-0053`
- Contract: `ProductContract §3.1`
- Build/Commit: `To be frozen before execution`
- Device/iOS Matrix: `Owner decision required`
- Human Confirmation: `Pending`

The owner must freeze the device/iOS matrix before execution. At minimum it
should include one eligible LiDAR Pro device and one non-eligible device. A
single-device result must never be generalized to an untested family.

## Preconditions

- Fixed near/far focus targets, a high-contrast exposure target, controllable
  light, tripod, recording, and public-safe diagnostics are available.
- Readback includes active device/format, ISO, shutter, lens position, exposure
  target offset, AF/MF state, generation, clamp, and risk state.
- Camera preferences, Basic EV, ISO, shutter, and focus are reset.
- **Owner live:** judge exposure direction, control feel, focus plane, frosted
  transitions, and black-screen risk.

## Procedure

1. In Standard, confirm Basic EV and FOV selector work and Standard did not
   silently choose the LiDAR PRO source.
2. **Owner live:** enter PRO. Frost must remain until a real preview is
   interactive. Confirm rear LiDAR 24 mm / 1x, `EV / ISO / S / Focus / ƒ`, no
   Basic EV/FOV, and read-only `ƒ`.
3. In `A/A`, move EV positive and negative; compare perceived brightness with
   `exposureTargetOffset` direction.
4. Adjust ISO through middle and device limits (`M/A`), restore Auto, then do
   the same with shutter (`A/M`).
5. Set both manually (`M/M`): both values persist and EV becomes a read-only
   meter. Restore one parameter at a time and finally return to `A/A`.
6. **Owner live:** tap AF, drag the temporary EV rail, and confirm its focus
   anchor does not move. A new tap resets temporary EV. Long press locks AF/AE;
   ordinary focus events must not clear the locked overlay.
7. Confirm an unlocked focus overlay does not disappear by a fixed timer and
   clears on real runtime invalidation.
8. Open Focus without moving it: AF remains. The first real drag enters MF and
   locks the current lens position before numeric writes.
9. Drag MF continuously and verify latest-wins with no stale value jump.
10. **Owner live:** tap near/far targets in MF. Focus-only assist must not change
    exposure, and shutter stays disabled until honest locked readback. Rapid taps
    and slider movement must reject stale request results.
11. Check the MF loupe: tapped position is centered, the main preview stays 1x,
    and disabling the magnifier does not disable focus assist.
12. Switch PRO to front and back. Frost remains until interactive; front exposes
    no PRO/MF, and returning restores suspended rear PRO intent without
    rewriting the saved preference.
13. Switch PHOTO/TAP VIDEO and confirm the same eligible PRO device/control
    contract; recording stress belongs to `TAP-0045`.
14. Check Default Off, Default On, Remember Last State, and safe Standard
    fallback.
15. Repeat availability/startup/front/back checks on the non-eligible device;
    PRO must not appear and Standard remains usable.

## Expected Results

- EV direction, preview, and readback agree; ISO/S Auto and Manual modes clamp
  honestly and expose no impossible values.
- AF/MF/assist results belong to the active device and generation; assist never
  writes exposure or leaves UI/device mode disagreement.
- The main preview, loupe, and recorder do not create a second hardware preview
  or crop the primary view.
- Front camera never exposes MF; every Standard/PRO and rear/front transition
  keeps frost until the destination preview is interactive.

## Required Evidence

- Capability/readback logs, continuous video, EV/ISO/S/Meter/lens table, and
  AF/MF/generation timeline for each device.
- Eligible/non-eligible screenshots and any generated capture artifacts.
- **Owner live:** written acceptance of exposure, focus, loupe, transition feel,
  and absence of black screens.

## Verdict

- **Pass:** the frozen matrix completes with no stale write, false capability,
  black screen, or mode mismatch, and the owner accepts subjective behavior.
- **Fail:** direction/readback mismatch; unsupported controls appear; AF/MF
  results go stale; assist changes exposure; front MF appears; or frost leaves
  before a real destination preview.
- **Blocked:** the matrix, required devices, diagnostics, stable targets, or
  owner attendance are unavailable.
