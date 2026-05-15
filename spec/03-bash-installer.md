# 03 — Bash Installer Spec (`install.sh`)

Target shells: `bash` 3.2+ (macOS default) and `bash` 5.x (Linux).
Stick to POSIX-friendly bash — no `[[ =~ ]]` features that 3.2 lacks if avoidable.

## Bulletproof startup

```bash
#!/usr/bin/env bash
# Do NOT enable `set -u` until safe defaults are in place.
set -eo pipefail

# Provide fallbacks for every env var we read.
HOME_DIR="${HOME:-$PWD}"
TMP_DIR="${TMPDIR:-/tmp}"
JPG2PDF_VERSION="${JPG2PDF_VERSION:-v1.2.7}"
JPG2PDF_REPO="${JPG2PDF_REPO:-owner/jpg2pdf}"
JPG2PDF_DEBUG="${JPG2PDF_DEBUG:-0}"

# Now it is safe to enable nounset.
set -u

# Master error handler so users always see a friendly message + log path.
LOG_FILE=""
on_error() {
  local code=$?
  echo "jpg2pdf installer failed (exit $code)" >&2
  [ -n "$LOG_FILE" ] && echo "Full log: $LOG_FILE" >&2
  exit "$code"
}
trap on_error ERR
trap 'on_error' INT TERM
```

### Forbidden

- `set -euo pipefail` on line 1 before fallbacks are in place.
- Reading `$HOME`, `$TMPDIR`, `$XDG_*` without a `${VAR:-default}` fallback.
- Unguarded `curl ... | bash` — always check exit status and fall back.

### Required

- Every `curl` to GitHub API wrapped:
  ```bash
  if ! release_json=$(curl -fsSL "$api/releases/tags/$JPG2PDF_VERSION" 2>>"$LOG_FILE"); then
    release_json=""
  fi
  ```
- Release -> main -> source/Python fallback:
  ```bash
  asset_url=""
  if [ -n "$release_json" ]; then
    asset_url=$(printf '%s' "$release_json" | grep ... )
  fi
  if [ -z "$asset_url" ]; then
    warn "No release found, falling back to main-branch artifact..."
    asset_url=$(get_main_branch_artifact_url) || true
  fi
  if [ -z "$asset_url" ]; then
    warn "No binary artifact found, falling back to source/Python install..."
    install_from_source || true
  fi
  [ -n "$asset_url" ] || [ "$installed_from_source" = "1" ] || die "Could not locate jpg2pdf binary or install from source."
  ```

When platform binaries are unavailable (notably macOS while macOS runners are
disabled), `install.sh` must install from Python source instead of failing. The
source fallback downloads the repo tarball for the pinned tag or `main`, extracts
it, runs a best-effort `python -m pip install --user -r tools/jpg2pdf/requirements.txt`,
and writes an executable wrapper at `$JPG2PDF_PREFIX/jpg2pdf`. Each network,
archive, Python, pip, copy, and wrapper step must be guarded with `if ...; then`
style handling and must log the exact fallback used.

## Debug/verbose flag

`--debug` / `--verbose` / `-d` / `-v` or `JPG2PDF_DEBUG=1`:
- Sets `LOG_FILE="${TMP_DIR}/jpg2pdf-install-$(date +%Y%m%d-%H%M%S)-$$.log"`.
- Enables `set -x` redirecting xtrace to the log: `exec {BASH_XTRACEFD}>>"$LOG_FILE"`.
- All `info/warn/die` functions tee to log.

## Validation checklist

- [ ] `bash -n install.sh` exits 0.
- [ ] `shellcheck install.sh` (if available) has no error-level findings.
- [ ] `JPG2PDF_REPO=does/not-exist bash install.sh` exits with a friendly
      message, not a stack trace.
- [ ] `env -u HOME bash install.sh --help` does not crash on unset HOME.
- [ ] `JPG2PDF_VERSION` matches `tools/jpg2pdf/VERSION`.
