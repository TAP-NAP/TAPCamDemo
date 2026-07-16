# CZstd

`CZstd` is a local Swift Package Manager package. The Xcode application target
links its `CZstd` library product through `Packages/CZstd`; it is intentionally
not an unpinned remote package dependency.

The package wraps the official Zstandard `lib` source subset pinned in
`ZSTD_SOURCE.json`. Do not hand-edit the upstream-derived directories or
headers under `Vendor/zstd`; `module.modulemap` is the local SwiftPM adapter and
has a separately pinned SHA-256.

## Verify the vendored source

From the repository root, run:

```sh
Packages/CZstd/Scripts/verify-vendored-zstd.sh
```

The script downloads the recorded upstream archive to a temporary directory,
checks its SHA-256, and compares the vendored production subset byte-for-byte:
`common`, `compress`, `decompress`, `zdict.h`, `zstd.h`, and `zstd_errors.h`.
The SwiftPM-specific local `module.modulemap` is not an upstream file; its own
SHA-256 is recorded and checked separately. An already-downloaded archive can
be supplied as the first argument for offline verification.

## Update policy

1. Choose a reviewed upstream Zstandard release.
2. Download its source archive and verify the release provenance.
3. Update `ZSTD_SOURCE.json` with the version, URLs, and archive SHA-256.
4. Replace `common`, `compress`, `decompress`, and the three public headers from
   that verified archive; do not merge individual C-file edits. Review any
   required `module.modulemap` change separately and update its recorded hash.
5. Run the verification script, `swift test --package-path Packages/CZstd`, the
   TAP Video golden-vector tests, and the physical-device codec benchmark.
6. Review benchmark evidence manually. If the accepted recommendation changes,
   update `TAPDepthCompressionProductionPolicy.preferredCodec` in a separate,
   explicit code review. A benchmark run never changes runtime policy itself.

For LOC and lint reporting, treat `Vendor/zstd` as managed third-party source,
not application Swift/C implementation.
