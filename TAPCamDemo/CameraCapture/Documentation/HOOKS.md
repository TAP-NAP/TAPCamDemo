# Hooks

Hooks run after physical packaging and before writing.

```text
CapturePackage
      |
      v
Packaging
      |
      v
PackagedCaptureArtifact
      |
      v
Hook Pipeline
      |
      v
Writer
```

`ArtifactHookPipeline` is empty by default. v0.8 does not hash, sign,
watermark, upload, or mutate metadata automatically. Future hooks can implement
those behaviors without touching capture providers or session configuration.
