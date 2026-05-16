# Release Pipeline

## Trigger

Push a semver tag: `git tag v1.1.0 && git push origin v1.1.0`.

## Workflow

`.github/workflows/release.yml` builds on every push to `main`, every PR, and every tag push:
- Windows x64 -> `jpg2pdf-windows-x64.exe`
- Linux x64 + arm64 -> `jpg2pdf-linux-x64`, `jpg2pdf-linux-arm64`
- macOS binary targets are currently disabled because GitHub-hosted macOS runners were backlogged. macOS installs must fall back to Python source when no binary exists.
- `SHA256SUMS.txt`

Only `v*` tag pushes and manual release runs publish a GitHub Release with all assets.

## Installer fallback

`install.ps1` must wrap the whole flow plus every GitHub read/download in try/catch-style handling. Missing releases or missing release assets must not crash the installer. If no release is available, or the release asset download fails, both installers must fall back to the latest successful `main`-branch workflow artifact for the current OS/arch. If no binary artifact exists (especially macOS while macOS runners are disabled), installers must fall back again to a Python source install from the pinned tag or `main`, write a `jpg2pdf` wrapper, and log every failed variable/step plus the fallback used.

Use the defensive installer pattern from `alimtvnetwork/coding-guidelines-v20/install.ps1`: top-level trap/handler, master guarded body, every step wrapped, no raw crashes, and a final verbose-log crash report section. Be careful that PowerShell step wrappers must not hide later-needed variables in child scope; installer state should be script-scoped or assigned outside guarded scriptblocks.

If a source/Python wrapper is installed but `jpg2pdf --version` fails because dependencies are missing, the installer must log the verification failure and still leave the wrapper in place. Only fail fatally when release, main artifact, and source/Python wrapper installation all fail.

## macOS quarantine

Binaries are ad-hoc signed. The `install.sh` auto-strips `com.apple.quarantine`. Manual `.zip` downloads need:
```
xattr -dr com.apple.quarantine ~/.local/bin/jpg2pdf
```

## After release

Update root `README.md` and `tools/jpg2pdf/README.md` pinned-version examples to the new tag.

## Release index

`.gitmap/release/*.json` tracks past releases. Latest known in code: `v1.2.2`.
