# jpg2pdf — Engineering Spec Folder

This folder is the **single source of truth** for any AI assistant (or human contributor)
working on the `jpg2pdf` CLI tool, its installers, and its CI/CD pipeline.

If you are an AI model reading this repository, **start here**:

1. Read [`00-AI-INSTRUCTIONS.md`](./00-AI-INSTRUCTIONS.md) first — it tells you
   the order to read the rest of the spec and the rules you must follow.
2. Then read the other spec files referenced from there before making any change.
3. Do not skip the validation checklist at the end of each spec.

## Files

| File | Purpose |
|------|---------|
| `00-AI-INSTRUCTIONS.md` | Mandatory reading order + rules of engagement for AI assistants. |
| `01-cicd.md`            | GitHub Actions release pipeline: triggers, jobs, artifacts, failure modes. |
| `02-powershell.md`      | Rules for writing/editing `install.ps1`, `uninstall.ps1`, `run.ps1` and other `.ps1` files. |
| `03-bash-installer.md`  | Rules for `install.sh` (POSIX, macOS/Linux). |
| `04-versioning.md`      | How to bump versions, update changelog, and keep docs in sync. |

## Project shape (quick reference)

- The product is a **Python CLI** under `tools/jpg2pdf/` (NOT the TanStack scaffold in `src/`).
- Installers live at the repo root: `install.ps1` (Windows) and `install.sh` (macOS/Linux).
- Release pipeline: `.github/workflows/release.yml`.
- Version file: `tools/jpg2pdf/VERSION` (must match `__version__` in `src/jpg2pdf.py`).
- Changelog: `CHANGELOG.md` (Keep-a-Changelog format).
