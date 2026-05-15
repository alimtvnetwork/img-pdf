# Changelog

All notable changes to `jpg2pdf` are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.4] - 2026-05-15

### Fixed
- Windows installer: guarded every remaining path/temp/home lookup used before and after release download, including context-menu script staging, so failures are caught and reported safely.
- macOS/Linux installer: removed the last `$HOME` assumption from PATH guidance so `set -u` cannot abort after a successful main-branch artifact fallback.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.4`.

## [1.2.3] - 2026-05-15

### Fixed
- Windows installer: moved environment/default resolution inside the protected install block and added a top-level trap so failures before any GitHub read/download are reported safely instead of crashing the shell.
- Windows installer: made main-branch artifact extraction resilient when the temp directory variable is missing or cleanup runs after an early failure.
- macOS/Linux installer: added first-line-safe exit/signal traps before reading environment defaults, with a safe prefix fallback when `$HOME` is unavailable.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.3`.

## [1.2.2] - 2026-05-15

### Fixed
- Windows installer: wrapped the whole install flow and every GitHub read/download in safe try/catch handling so failures report cleanly instead of crashing the PowerShell session.
- Installers now fall back to the latest successful `main`-branch workflow artifact when no GitHub Release is available or the release asset download fails.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.2`.

## [1.2.1] - 2026-05-15

### Changed
- CI/CD: the cross-platform **build matrix** (Windows x64, Linux x64/arm64, macOS x64/arm64) now runs on every push to `main` and every PR — not only on tag pushes. Binaries for all five targets are produced and uploaded as workflow artifacts on every commit, so regressions on any OS are caught immediately.
- The lightweight `ci` job (linux-x64 build + version-sync check) is now PR-only, since `main` pushes already trigger the full matrix.
- Publishing to a GitHub Release still happens **only** on `v*` tag pushes or manual `workflow_dispatch` — regular commits build but don't publish.

## [1.2.0] - 2026-05-15

### Added
- **Rich GitHub release pages** modeled on the gitmap-v19 layout. Every tag push now publishes a release with a Changelog section, **Release Info** table (version, commit, branch, build date, Python version), **Checksums (SHA256)** block, **Install** snippets (Windows PowerShell quick install, Linux/macOS quick install, pinned-version installers, manual download), and an **Assets** table.
- `.github/release-notes-template.md` drives the release body; the workflow renders it via Python placeholder substitution.
- `install.ps1` and `install.sh` are now uploaded as release assets so the "Quick install" URLs in the release body resolve directly from the tag.

### Changed
- `.github/workflows/release.yml` extracts the matching `## [VERSION]` section from `CHANGELOG.md` instead of relying on `generate_release_notes: true`.
- Root `README.md` pinned-version examples bumped to `v1.2.0`.

## [1.1.0] - 2026-05-15

### Added
- **Mixed-input merge**: a single invocation now accepts images (`.jpg/.jpeg/.png/.webp/.bmp/.tif/.tiff`), PDFs (`.pdf`), HTML (`.html/.htm`), and Word documents (`.docx/.doc`) and merges them into one PDF in the order selected. Consecutive images are batched into image pages; PDFs are embedded with `pypdf`; HTML is rendered via `xhtml2pdf`; Word is converted via `docx2pdf` (Windows) with a graceful fallback message elsewhere.
- Context-menu entries on Windows now register for `.pdf`, `.html`, and `.docx` in addition to images, so right-click → "Combine into PDF" works on any supported file type.
- `--ask-strength` live preview flag for interactively choosing pencil strength before render.

### Changed
- Default pencil strength is now `subtle` (was `normal`). Affects `prompt_pencil_strength()`, `--ask-strength` help text, and the `args.pencil_strength` fallback.
- Root `README.md` rewritten: pinned-version install snippets reference `v1.1.0`, mixed-input matrix added, pencil-strength section explicitly documents `subtle` as the default.

### Fixed
- `run.ps1` no longer crashes silently when a child step fails. A top-level `trap` writes `jpg2pdf-crash.log` next to the script and pauses the console so users can read the error before the window closes.
- Friendlier error message when the compiled `jpg2pdf` binary is missing — `Invoke-Logged` wraps `Start-Process` in try/catch and points users at the rebuild command.

### Internal
- Bumped `run.ps1` bootstrap version to `0.3.0`.
- Bootstrapped the `.lovable/` institutional-memory system (overview, plan, suggestions, memory/, pending-issues/, solved-issues/, cicd-issues/, prompts/).

## [0.12.4] - prior
- Last published tag before the 1.1.0 line. See GitHub Releases for older notes.
