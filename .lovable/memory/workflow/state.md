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
- *(none — awaiting user-side install smoke test)*

## ⏳ Pending
1. Capture real `context-menu.png` + `demo.gif` and replace placeholders.
2. Smoke-test the v1.3.6 installers on Windows/macOS/Linux with debug logging.
3. `git tag v1.3.6 && git push origin v1.3.6` once smoke tests pass.

## 🚫 Blocked
- *(none)*

## Next logical step
User runs the v1.3.6 installer with debug logging on the failing machine. If it crashes, share the printed `jpg2pdf-install-*.log`.
