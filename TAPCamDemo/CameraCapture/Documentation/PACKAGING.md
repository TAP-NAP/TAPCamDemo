# Packaging

`CapturePackage` is the logical result of one shutter press. It records selected
RGB source, depth source, pairing status, zoom, crop metadata, `AVCapturePhoto`,
location, and diagnostics facts.

`PackagedCaptureArtifact` is the physical output. In Release v0.8, the only
allowed strategy is `EmbeddedPhotoPackager`.

```text
CapturePackage
      |
      v
EmbeddedPhotoPackager only
      |
      v
Single Photo Artifact
      |
      v
Local Photos Writer
```

Release rejects sidecar JSON, debug bundles, independent depth files,
independent metadata files, metrics files, and intermediate artifacts.
