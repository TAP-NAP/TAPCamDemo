# Future External Integration TODO

The current demo does not expose a runtime external-session API. It owns the
SingleCam `AVCaptureSession` and writes one embedded HEIC artifact.

```text
Existing Camera App
        |
        v
Future external payload validation
        |
        v
Future embedded photo packager
```

External integration was removed from runtime code because arbitrary RGB/depth
bytes cannot safely be fabricated into Apple auxiliary depth without validating
alignment, calibration, orientation, and release packaging rules. Add it later
as its own vertical slice if a real host app needs it.
