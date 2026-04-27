# MultiCam Mode TODO

v0.8 can report `requiresMultiCam`, but it does not run MultiCam capture.
MultiCam is only for multiple independent camera inputs that cannot be expressed
by one Apple paired photo-depth pipeline.

## Future Flow

```text
Selected physical RGB camera
        |
        v
Selected independent depth source
        |
        v
AVCaptureMultiCamSession
        |
        v
AVCaptureDataOutputSynchronizer
        |
        v
Aligned RGB + Depth payload
```

## Required Work

- Add `MultiCamCaptureSessionController`.
- Check `AVCaptureMultiCamSession.isMultiCamSupported`.
- Use only formats where `AVCaptureDevice.Format.isMultiCamSupported` is true.
- Track `hardwareCost` and `systemPressureCost`; reject unsustainable plans.
- Synchronize RGB and depth streams with `AVCaptureDataOutputSynchronizer`.
- Record RGB timestamp, depth timestamp, synchronization method, and alignment
  status in the manifest.
- Do not embed unaligned depth as standard HEIC auxiliary depth in Release.

## Release Gate

Release can use MultiCam depth only when the depth map is proven or transformed
into the final RGB image coordinate system. Debug may capture synchronized but
unaligned data later, but those artifacts must be marked experimental and must
not masquerade as ordinary photo-depth HEIC files.
