# Future Hooks TODO

The current SingleCam demo does not compile a runtime hook pipeline. It writes:

```text
CapturePackage
      |
      v
EmbeddedPhotoPackager
      |
      v
PackagedCaptureArtifact
      |
      v
Writer
```

Hashing, signing, watermarking, upload, and post-package metadata mutation are
future product work. When one of those features becomes real, add the smallest
runtime hook surface needed for that feature instead of keeping an empty
pipeline in the demo.
