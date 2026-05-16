# Versioning

## Files that MUST stay in sync

| File | Format |
|------|--------|
| `tools/jpg2pdf/VERSION` | `1.1.0` (raw, no `v` prefix, no newline issues) |
| `tools/jpg2pdf/src/jpg2pdf.py` `__version__` | `__version__ = "1.1.0"` |

Bump both in the same edit batch. The CLI's `--version` output reads `__version__`; the installer reads `VERSION`.

## `run.ps1` has its own version

Independent of `jpg2pdf` itself. Currently `RunPs1Version = "0.3.0"`. Bump when changing installer behavior so users can see if they have the latest bootstrap.

## Release tags

- Format: `vMAJOR.MINOR.PATCH` (e.g. `v1.1.0`).
- Pushing a tag triggers `.github/workflows/release.yml` to build and publish binaries.
- Pinned-version examples in root `README.md` reference the latest tag — update them on each release.

## Current state (2026-05-16)

- jpg2pdf: `1.4.2` (not yet tagged; pending installer smoke tests).
- run.ps1: `0.3.0`.
- Last published tag in release map: `v1.3.4` (per `.gitmap/release/`).
