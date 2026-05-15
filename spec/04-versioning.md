# 04 — Versioning & Changelog Spec

Every shipping change must bump the version and add a changelog entry.

## Version sources of truth

These MUST stay in lockstep:

| File | Format |
|------|--------|
| `tools/jpg2pdf/VERSION` | `1.2.7` (no `v`) |
| `tools/jpg2pdf/src/jpg2pdf.py` `__version__` | `"1.2.7"` |
| `install.ps1` `$env:JPG2PDF_VERSION` default | `v1.2.7` |
| `install.sh` `JPG2PDF_VERSION` default | `v1.2.7` |
| `README.md` pinned references | `v1.2.7` |
| `tools/jpg2pdf/README.md` pinned references | `v1.2.7` |
| `CHANGELOG.md` newest entry | `## [1.2.7] - YYYY-MM-DD` |

## SemVer rules

- **PATCH** (`1.2.x`): bug fix, doc-only change, installer hardening, CI tweak that doesn't change artifact names.
- **MINOR** (`1.x.0`): new user-visible feature, new flag, new supported input format.
- **MAJOR** (`x.0.0`): breaking CLI flag change, breaking artifact name change, dropped OS support.

## Changelog format (Keep-a-Changelog)

```markdown
## [1.2.7] - 2026-05-15
### Added
- ...
### Changed
- ...
### Fixed
- Hardened install.ps1 startup so ...
```

Write entries in the **user's voice**: what they will notice, not the
internal mechanism. Group by Added / Changed / Fixed / Removed.

## Bump procedure

1. Decide the new version per SemVer rules above.
2. Update all 7 files in the table (one shot, parallel edits).
3. Run validation:
   ```bash
   V=$(cat tools/jpg2pdf/VERSION)
   grep -c "$V" CHANGELOG.md tools/jpg2pdf/src/jpg2pdf.py
   grep -c "v$V" README.md tools/jpg2pdf/README.md install.ps1 install.sh
   ```
   Every count should be `>= 1`.
4. State the new version and the changelog summary in your final reply.
