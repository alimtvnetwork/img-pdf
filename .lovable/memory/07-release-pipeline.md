# Release Pipeline

## Trigger

Push a semver tag: `git tag v1.1.0 && git push origin v1.1.0`.

## Workflow

`.github/workflows/release.yml` builds the full matrix on every push to `main`, every PR, and every tag push:
- Windows x64 → `jpg2pdf-windows-x64.exe`
- Linux x64 + arm64 → `jpg2pdf-linux-x64`, `jpg2pdf-linux-arm64`
- macOS x64 + arm64 → `jpg2pdf-macos-x64`, `jpg2pdf-macos-arm64` (ad-hoc signed, NOT notarized)
- `SHA256SUMS.txt`

Only `v*` tag pushes and manual release runs publish a GitHub Release with all assets.

## Installer fallback

`install.ps1` must wrap the whole flow plus every GitHub read/download in try/catch-style handling. Missing releases or missing release assets must not crash the installer. If no release is available, or the release asset download fails, both installers must fall back to the latest successful `main`-branch workflow artifact for the current OS/arch.

## macOS quarantine

Binaries are ad-hoc signed. The `install.sh` auto-strips `com.apple.quarantine`. Manual `.zip` downloads need:
```
xattr -dr com.apple.quarantine ~/.local/bin/jpg2pdf
```

## After release

Update root `README.md` and `tools/jpg2pdf/README.md` pinned-version examples to the new tag.

## Release index

`.gitmap/release/*.json` tracks past releases. Latest known in code: `v1.2.2`.
