# 01 — CI/CD Spec

Pipeline file: `.github/workflows/release.yml`.

## Goals

1. Build the `jpg2pdf` CLI for **all supported OSes** (Linux, macOS, Windows)
   on every push that should produce an artifact.
2. Publish a GitHub Release on version tags (`v*.*.*`).
3. Always upload artifacts on `main` so installers can fall back to the
   main-branch artifact when no Release exists.

## Triggers

- `push` to `main` → build matrix, upload artifacts to the workflow run.
  Do **not** create a Release here.
- `push` of tag `v*.*.*` → build matrix, then a `release` job that creates
  a GitHub Release and attaches the built artifacts.
- `workflow_dispatch` → manual run, same as `main`.

## Build matrix

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - { os: ubuntu-latest,  target: linux   }
      - { os: macos-latest,   target: macos   }
      - { os: windows-latest, target: windows }
```

Each job:
1. Checkout.
2. Setup Python (pinned minor version, e.g. `3.11`).
3. Install build deps (`pip install -r tools/jpg2pdf/requirements.txt` if present, plus `pyinstaller`).
4. Build artifact: `pyinstaller` one-file binary named
   `jpg2pdf-${{ matrix.target }}${{ matrix.target == 'windows' && '.exe' || '' }}`.
5. Upload via `actions/upload-artifact@v4` with name `jpg2pdf-${{ matrix.target }}`.

## Release job

Runs only on tag push. `needs: [build]`. Steps:
1. `actions/download-artifact@v4` (no name → downloads all).
2. `softprops/action-gh-release@v2` with `files: dist/**/*` and
   `generate_release_notes: true`.

## Hard rules

- **R1.** Never remove the `main`-branch artifact upload. Installers depend on it.
- **R2.** Artifact names must stay stable: `jpg2pdf-linux`, `jpg2pdf-macos`,
  `jpg2pdf-windows`. Renaming breaks installers.
- **R3.** Workflow file must be valid YAML — run `yamllint` or
  `python -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))" .github/workflows/release.yml`.
- **R4.** Pin action versions to a major (`@v4`), not `@latest`.
- **R5.** Do not add steps that require secrets the repo doesn't have. If a
  signing/notarization step is added, gate it behind
  `if: secrets.MAC_CERT != ''`.

## Validation checklist

- [ ] `python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` passes.
- [ ] Matrix contains all three OSes.
- [ ] Artifact names match what `install.ps1` and `install.sh` expect
      (grep both installers for `jpg2pdf-windows`, `jpg2pdf-linux`, `jpg2pdf-macos`).
- [ ] Release job is gated on `startsWith(github.ref, 'refs/tags/v')`.
