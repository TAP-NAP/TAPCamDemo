# Packaging

`CapturePackage` is the logical result of one shutter press. It records selected
RGB source, depth source, pairing status, zoom, crop metadata, `AVCapturePhoto`,
location, and diagnostics facts.

`PackagedCaptureArtifact` is the physical output. The only runtime strategy is
`EmbeddedPhotoPackager`.

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

Sidecar JSON, debug bundles, independent depth files, independent metadata
files, metrics files, and intermediate artifacts are absent from runtime code.
