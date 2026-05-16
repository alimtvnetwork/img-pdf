# Changelog

All notable changes to `jpg2pdf` are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] - 2026-05-16

### Fixed
- GitHub Release body no longer shows literal `\n### Changed\n- ...` escape sequences. Root cause: the workflow piped the changelog through `toJSON(...)` which emits a JSON-encoded string with literal `\n` escapes; bash then assigned that raw to `CHANGELOG` and Python substituted the escaped text verbatim. The changelog body is now passed through the step's `env:` block so real newlines are preserved end-to-end.

See the full history in [CHANGELOG.md](./CHANGELOG.md).

## [1.4.0] - 2026-05-16

### Changed
- Version bump to 1.4.0. Includes the release-notes template cleanup (dynamic `{{REPO}}`, single-line install per platform, link to full CHANGELOG.md at tag) previously staged under 1.3.8.

See the full history in [CHANGELOG.md](./CHANGELOG.md).

## [1.3.8] - 2026-05-16

### Changed
- Release notes template: replaced the three-line "generic installer" snippets with a single one-liner per platform that resolves the repo via the workflow's `{{REPO}}` placeholder (no hardcoded URLs from other projects).
- Release notes now link to the full [CHANGELOG.md](./CHANGELOG.md) at the released tag instead of inlining install variants.
- Dropped macOS rows from the release assets table since macOS binary runners are disabled; macOS users install via `install.sh` Python fallback.

## [1.3.7] - 2026-05-16

### Fixed
- macOS/Linux source fallback: installs Python dependencies into a local vendor directory first and writes wrappers that include that directory on `PYTHONPATH`, so macOS can run from Python source while binary runners are disabled.
- Installers now treat post-install `--version` failures as logged diagnostics, not fatal crashes, leaving the installed binary or Python wrapper in place for repair.
- Verbose logs now preserve guarded crash-report rows outside shell subshells and print the log path when any fallback or verification issue was recorded.

### Changed
- Installer specs and memory now explicitly require source/Python verification failures to be non-fatal once the wrapper has been installed.

## [1.3.6] - 2026-05-15

### Fixed
- Windows installer: preserved installer state across guarded try/catch steps so release, main-artifact, PATH, and context-menu phases cannot lose required variables and crash later.
- macOS/Linux installer: hardened startup, archive extraction, artifact copying, source wrapper writing, pip dependency install, and PATH guidance so failures are logged and continue to the next fallback where possible.

### Changed
- Installer specs and memory now point at the reference installer hardening pattern and require a final crash-report section with the failed variable/step, location, and fallback used.

## [1.3.5] - 2026-05-15

### Added
- macOS/Linux installer: added a final Python source fallback when no release binary or main-branch artifact is available, so macOS can still install while macOS binary runners are disabled.
- Installer specs and memory now require the full release -> main artifact -> source/Python fallback chain with crash-report logging.

### Fixed
- Installers now record guarded failures and the fallback used in a dedicated crash report section instead of exiting without enough diagnostic context.
- Windows installer now falls back to a Python wrapper install when prebuilt binaries cannot be located.

## [1.3.4] - 2026-05-15

### Changed
- CI/CD: dropped the macOS build matrix entries (`macos-13` x64 and `macos-14` arm64). GitHub-hosted macOS runners were stuck queued for hours and blocking every release. The matrix now ships Windows x64 and Linux x64/arm64 only; macOS users can build from source until macOS runners are restored.
- Release job no longer publishes `jpg2pdf-macos-x64` / `jpg2pdf-macos-arm64` assets.

## [1.3.1] - 2026-05-15

### Fixed
- Windows installer: replaced the remaining GitHub JSON reads with guarded HTTP reads plus guarded JSON parsing, so a bad release/API response cannot abort before the main-branch artifact fallback runs.
- Verified the release-missing path continues into main-branch artifact lookup instead of crashing.

### Changed
- Pinned-version install snippets in `README.md`, `tools/jpg2pdf/README.md`, `install.ps1`, and `install.sh` now reference `v1.3.1`.

## [1.3.0] - 2026-05-15

### Fixed
- Windows installer: hardened the very early bootstrap so a hostile host cannot crash the shell before logging is initialized. `$ErrorActionPreference`, the global `trap`, `Stop-Safely`/`Die` lookup, `$args` access, the argument parser loop, and the TLS 1.2 enable call are now each wrapped in their own `try/catch` (or guarded with `Get-Command Die`).
- Argument parsing now reads from a defensive `$InstallerArgs` copy of `$args` so `irm | iex` hosts that do not expose `$args` cannot fault on `.Count`.
- Verified: when no GitHub Release (or no matching asset) is available, both installers continue to fall back to the latest successful `main`-branch workflow artifact.

### Changed
- Pinned-version install snippets in `README.md`, `tools/jpg2pdf/README.md`, `install.ps1`, and `install.sh` now reference `v1.3.0`.

## [1.2.9] - 2026-05-15

### Fixed
- Windows installer: added safe wrappers around the remaining filesystem, archive, path-resolution, download, and context-menu execution reads so failures are caught before they can crash the shell.
- The release download path still falls back to the latest successful `main`-branch artifact when no release or release asset is usable.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.9`.

## [1.2.8] - 2026-05-15

### Fixed
- Windows installer: added a guarded environment-read helper and moved repo/version/debug/token/temp/PATH reads through safe fallbacks so host PowerShell profile or environment issues cannot crash before installer error handling.
- macOS/Linux installer: replaced the remaining direct temp-error-file read with a safe read helper while preserving release-to-main-artifact fallback behavior.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.8`.

## [1.2.7] - 2026-05-15

### Fixed
- Windows installer: removed the advanced `param` binding block so `irm ... | iex` cannot crash before installer-owned safe handling starts; arguments are now parsed inside the top-level guarded block.
- macOS/Linux installer: moved strict-mode execution inside a guarded `main` wrapper so unexpected startup reads fail through the safe error path instead of aborting the shell.
- Release lookup and pinned-release download still fall back to the latest successful `main`-branch workflow artifact when no usable release asset exists.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.7`.

## [1.2.6] - 2026-05-15

### Added
- Installers (`install.sh`, `install.ps1`) now support a `--debug` / `--verbose` flag (and `JPG2PDF_DEBUG=1` env var) that enables verbose tracing, environment diagnostics, and writes a full timestamped log to a temp file. Override the path with `JPG2PDF_LOG`.
- Every installer error and warning now points at the saved log file so crash output can be captured and shared.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.6`.

## [1.2.5] - 2026-05-15

### Fixed
- Windows installer: guarded session PATH updates so a missing `$env:Path` cannot crash after a release or main-branch artifact download succeeds.

### Changed
- Root and tool README pinned-version install snippets now reference `v1.2.5`.

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
