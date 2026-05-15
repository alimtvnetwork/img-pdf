# Workflow State

**Last updated:** 2026-05-15

## ✅ Done
- Mixed-input merge (images + PDF + HTML + Word) shipped.
- Context menus registered for all supported file types.
- `run.ps1` hardened with top-level trap + crash log (v0.3.0).
- Pencil-strength default switched to `subtle`.
- Version bumped to `1.1.0` in both `VERSION` and `__version__`.
- Root `README.md` updated: pinned version `v1.1.0`, mixed-input table, `--ask-strength` example.
- Memory system bootstrapped under `.lovable/`.
- Installer specs/memory require release -> main artifact -> Python source fallback with reference-style guarded crash logging.

## 🔄 In Progress
- Harden `install.ps1` and `install.sh` so every installer step logs failures and falls back without crashing.

## ⏳ Pending (Windows-only, user must do)
1. Capture real `context-menu.png` + `demo.gif` and replace placeholders.
2. Run `.\run.ps1 -Force -ShowVerbose` and smoke-test mixed selection.
3. `git tag v1.1.0 && git push origin v1.1.0` once smoke test passes.

## 🚫 Blocked
- *(none)*

## Next logical step
User runs `.\run.ps1 -Force -ShowVerbose` on Windows. If it succeeds, tag `v1.1.0`. If it crashes, share `jpg2pdf-crash.log`.
