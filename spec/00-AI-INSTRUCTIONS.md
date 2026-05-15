# 00 — AI Instructions (READ FIRST)

You are an AI assistant about to modify the `jpg2pdf` repository. Before you
write a single line of code, follow this protocol. The user has repeatedly
hit the same regressions; this spec exists so we never repeat them.

## Reading order (mandatory)

1. **This file** — rules of engagement.
2. `04-versioning.md` — every change ships a version bump + changelog entry.
3. The spec relevant to your task:
   - Touching `.github/workflows/**` → `01-cicd.md`
   - Touching `*.ps1` (installers, run, uninstall) → `02-powershell.md`
   - Touching `install.sh` → `03-bash-installer.md`
4. The actual file(s) you intend to edit — read fully before editing.

## Rules of engagement

### R1 — Never break the installer entry point
The user's #1 complaint: **"the install script is still crashing"**.
- The very first executable lines of `install.ps1` and `install.sh` MUST be
  wrapped in defensive guards. No bare `Set-StrictMode`, no bare `set -euo
  pipefail`, no environment variable reads (`$env:TEMP`, `$HOME`) before a
  fallback is in place.
- See `02-powershell.md` §"Bulletproof startup" and `03-bash-installer.md`
  §"Bulletproof startup".

### R2 — Always preserve the release → main-branch fallback
If a GitHub Release does not exist (or the API call fails), the installer
MUST fall back to downloading the artifact from the `main` branch. Do not
remove this fallback. Do not gate it behind `--force` or similar. It is the
default behavior. Wrap **every** GitHub API / network read in try/catch (PS)
or `if ! ...; then` (sh) and continue to the fallback path on any failure.

### R3 — Version + changelog on every change
Every PR that changes shipping code (CLI, installers, workflow) MUST:
- Bump `tools/jpg2pdf/VERSION`
- Bump `__version__` in `tools/jpg2pdf/src/jpg2pdf.py` to the same value
- Add a `[X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`
- Update pinned `vX.Y.Z` references in `README.md`, `tools/jpg2pdf/README.md`,
  `install.ps1` (`$env:JPG2PDF_VERSION`), `install.sh` (`JPG2PDF_VERSION`).

### R4 — ASCII-only in PowerShell files
Windows PowerShell 5.1 mis-parses non-ASCII characters (em-dash, arrows,
smart quotes, emoji) unless the file is saved with a UTF-8 BOM. Stick to
ASCII in `.ps1` files. Use `->` not `→`, `--` not `—`, `'` not `'`.

### R5 — Validate before declaring done
Before saying "done", run at minimum:
```bash
bash -n install.sh
python3 tools/jpg2pdf/src/jpg2pdf.py --version
grep -n "$(cat tools/jpg2pdf/VERSION)" CHANGELOG.md README.md tools/jpg2pdf/README.md install.ps1 install.sh
```
Plus any spec-specific checks listed in the relevant spec file.

### R6 — Don't touch the TanStack scaffold for product work
`src/` is an unused web scaffold. Product code lives under `tools/jpg2pdf/`.
Do not "fix" `src/` unless the user explicitly asks.

### R7 — Keep prior context
Before claiming a fix, read `.lovable/memory/` and the previous CHANGELOG
entries. The same bug class has been fixed multiple times; check whether a
prior hardening was reverted or if you are about to re-introduce a known
regression.

## Definition of done

A change is "done" only when:
- [ ] The relevant spec was read end-to-end.
- [ ] R1–R7 above are satisfied.
- [ ] Validation commands pass.
- [ ] CHANGELOG entry written in past tense, user-visible language.
- [ ] You stated explicitly which files changed and which spec sections
      governed the change.
