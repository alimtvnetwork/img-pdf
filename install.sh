#!/usr/bin/env sh
# One-liner installer for jpg2pdf on Linux & macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | sh
#
#   # Pin a specific version:
#   curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | JPG2PDF_VERSION=v1.2.7 sh
#
#   # Install elsewhere (default: $HOME/.local/bin):
#   curl -fsSL https://.../install.sh | JPG2PDF_PREFIX=$HOME/bin sh
#
# What it does:
#   1. Detects OS + arch.
#   2. Resolves the latest GitHub Release (or $JPG2PDF_VERSION).
#   3. If no release is available, falls back to the latest successful main-branch artifact.
#   4. Downloads the matching binary into $JPG2PDF_PREFIX (default $HOME/.local/bin).
#   5. chmod +x and reports next steps.

DEBUG="${JPG2PDF_DEBUG:-0}"
for _arg in "$@"; do
  case "$_arg" in
    --debug|--verbose|-d|-v) DEBUG=1 ;;
  esac
done

LOG_FILE="${JPG2PDF_LOG:-${TMPDIR:-/tmp}/jpg2pdf-install-$(date +%Y%m%d-%H%M%S)-$$.log}"
: > "$LOG_FILE" 2>/dev/null || LOG_FILE=""

_log() { [ -n "$LOG_FILE" ] && printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
info() { _log "INFO  $*"; printf '\033[36m[jpg2pdf]\033[0m %s\n' "$*"; }
warn() { _log "WARN  $*"; printf '\033[33m[jpg2pdf]\033[0m %s\n' "$*" >&2; }
debug(){ _log "DEBUG $*"; [ "$DEBUG" = "1" ] && printf '\033[35m[jpg2pdf:debug]\033[0m %s\n' "$*" >&2 || true; }
die()  { _log "ERROR $*"; printf '\033[31m[jpg2pdf]\033[0m %s\n' "$*" >&2; [ -n "$LOG_FILE" ] && printf '\033[31m[jpg2pdf]\033[0m Full log: %s\n' "$LOG_FILE" >&2; exit 1; }
on_exit() {
  code=$?
  if [ "$code" -ne 0 ]; then
    warn "Installer failed safely before completion (exit $code)."
    [ -n "$LOG_FILE" ] && warn "Detailed log: $LOG_FILE"
  fi
}
on_signal() { warn "Installer interrupted safely before completion."; exit 1; }
trap on_exit 0
trap on_signal HUP INT TERM

main() {

if [ "$DEBUG" = "1" ]; then
  info "Debug mode enabled. Log: ${LOG_FILE:-<unavailable>}"
  debug "uname: $(uname -a 2>/dev/null || echo unknown)"
  debug "shell: ${SHELL:-unknown}  user: $(id -un 2>/dev/null || echo unknown)"
  debug "PATH: ${PATH:-}"
  set -x
fi

DEFAULT_PREFIX="${HOME:-}/.local/bin"
if [ -z "${HOME:-}" ] && [ -z "${JPG2PDF_PREFIX:-}" ]; then
  DEFAULT_PREFIX="/usr/local/bin"
fi
HOME_DIR="${HOME:-}"
REPO="${JPG2PDF_REPO:-alimtvnetwork/img-pdf}"
VERSION="${JPG2PDF_VERSION:-}"
PREFIX="${JPG2PDF_PREFIX:-$DEFAULT_PREFIX}"
GITHUB_API="https://api.github.com"

if [ -z "$REPO" ]; then
  die "Set the repo: JPG2PDF_REPO=your-user/your-repo curl ... | sh"
fi

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Linux)  os=linux  ;;
  Darwin) os=macos  ;;
  *)      die "Unsupported OS: $uname_s (Windows: use install.ps1)";;
esac
case "$uname_m" in
  x86_64|amd64) arch=x64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) die "Unsupported architecture: $uname_m" ;;
esac

asset="jpg2pdf-${os}-${arch}"
case "$asset" in
  jpg2pdf-windows-*) die "Use install.ps1 on Windows." ;;
esac

if command -v curl >/dev/null 2>&1; then
  GET() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "User-Agent: jpg2pdf-installer" -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
    else
      curl -fsSL -H "User-Agent: jpg2pdf-installer" -H "Accept: application/vnd.github+json" "$1"
    fi
  }
  DL() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fL -H "User-Agent: jpg2pdf-installer" -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" "$1" -o "$2"
    else
      curl -fL -H "User-Agent: jpg2pdf-installer" -H "Accept: application/vnd.github+json" "$1" -o "$2"
    fi
  }
elif command -v wget >/dev/null 2>&1; then
  GET() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -qO- --header="User-Agent: jpg2pdf-installer" --header="Accept: application/vnd.github+json" --header="Authorization: Bearer $GITHUB_TOKEN" "$1"
    else
      wget -qO- --header="User-Agent: jpg2pdf-installer" --header="Accept: application/vnd.github+json" "$1"
    fi
  }
  DL() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -O "$2" --header="User-Agent: jpg2pdf-installer" --header="Accept: application/vnd.github+json" --header="Authorization: Bearer $GITHUB_TOKEN" "$1"
    else
      wget -O "$2" --header="User-Agent: jpg2pdf-installer" --header="Accept: application/vnd.github+json" "$1"
    fi
  }
else
  die "Need curl or wget to download."
fi

try_get() {
  tg_desc="$1"
  tg_url="$2"
  tg_err_file="${TMPDIR:-/tmp}/jpg2pdf-installer-get-$$.err"
  if tg_body="$(GET "$tg_url" 2>"$tg_err_file")"; then
    rm -f "$tg_err_file"
    printf '%s' "$tg_body"
    return 0
  fi
  tg_err="$(cat "$tg_err_file" 2>/dev/null || true)"
  rm -f "$tg_err_file"
  warn "$tg_desc failed: $tg_err"
  return 1
}

try_download() {
  td_desc="$1"
  td_url="$2"
  td_dest="$3"
  if DL "$td_url" "$td_dest"; then
    return 0
  fi
  warn "$td_desc failed: $td_url"
  return 1
}

json_value() {
  key="$1"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

download_release_asset() {
  tag="$1"
  out="$2"
  url="https://github.com/$REPO/releases/download/$tag/$asset"
  info "Downloading $url"
  try_download "Release download" "$url" "$out"
}

unpack_artifact() {
  zip_file="$1"
  extract_dir="$2"
  mkdir -p "$extract_dir"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip_file" -d "$extract_dir"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$zip_file" "$extract_dir" <<'PYC'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    zf.extractall(sys.argv[2])
PYC
    return 0
  fi
  if [ "$os" = "macos" ] && command -v ditto >/dev/null 2>&1; then
    ditto -x -k "$zip_file" "$extract_dir"
    return 0
  fi
  return 1
}

download_main_artifact() {
  out="$1"
  info "Looking for latest main-branch artifact named $asset ..."
  runs_json="$(try_get "Main-branch workflow lookup" "$GITHUB_API/repos/$REPO/actions/workflows/release.yml/runs?branch=main&status=success&per_page=10")" || return 1
  artifacts_urls="$(printf '%s' "$runs_json" | grep -o '"artifacts_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -n 's/.*"artifacts_url":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 10)"
  [ -n "$artifacts_urls" ] || return 1

  for artifacts_url in $artifacts_urls; do
    artifacts_json="$(try_get "Artifact lookup" "$artifacts_url?per_page=100")" || continue
    artifact_line="$(printf '%s\n' "$artifacts_json" | tr '{' '\n' | grep '"name"[[:space:]]*:[[:space:]]*"'"$asset"'"' | grep -v '"expired"[[:space:]]*:[[:space:]]*true' | head -n 1 || true)"
    [ -n "$artifact_line" ] || continue
    archive_url="$(printf '%s' "$artifact_line" | json_value archive_download_url)"
    [ -n "$archive_url" ] || continue

    tmp_base="${TMPDIR:-/tmp}"
    tmp_root="$tmp_base/jpg2pdf-artifact-$$"
    zip_file="$tmp_root/artifact.zip"
    extract_dir="$tmp_root/unzipped"
    rm -rf "$tmp_root"
    mkdir -p "$tmp_root"
    if try_download "Main-branch artifact download" "$archive_url" "$zip_file"; then
      if unpack_artifact "$zip_file" "$extract_dir"; then
        candidate="$extract_dir/$asset"
        if [ ! -f "$candidate" ]; then
          candidate="$(find "$extract_dir" -type f -name "$asset" | head -n 1 || true)"
        fi
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
          cp "$candidate" "$out"
          rm -rf "$tmp_root"
          return 0
        fi
        warn "Artifact archive did not contain $asset."
      else
        warn "Could not unpack artifact archive. Install unzip, python3, or ditto."
      fi
    fi
    rm -rf "$tmp_root"
  done
  return 1
}

mkdir -p "$PREFIX"
target="$PREFIX/jpg2pdf"
installed_from=""

if [ -n "$VERSION" ]; then
  info "Installing jpg2pdf $VERSION ($os/$arch)"
  if download_release_asset "$VERSION" "$target"; then
    installed_from="release $VERSION"
  fi
  if [ -z "$installed_from" ]; then
    warn "Release asset was not available. Falling back to the latest successful main-branch artifact."
    if download_main_artifact "$target"; then
      installed_from="latest main-branch artifact"
      VERSION=""
    fi
  fi
else
  info "Resolving latest release of $REPO ..."
  if api_json="$(try_get "Latest release lookup" "$GITHUB_API/repos/$REPO/releases/latest")"; then
    VERSION="$(printf '%s' "$api_json" | json_value tag_name)"
    if [ -n "$VERSION" ]; then
      info "Installing jpg2pdf $VERSION ($os/$arch)"
      if download_release_asset "$VERSION" "$target"; then
        installed_from="release $VERSION"
      fi
    fi
  else
    warn "No GitHub Release found. Falling back to the latest successful main-branch artifact."
  fi

  if [ -z "$installed_from" ]; then
    if download_main_artifact "$target"; then
      installed_from="latest main-branch artifact"
    fi
  fi
fi

if [ -z "$installed_from" ]; then
  die "Could not install jpg2pdf. Publish a release, run the main-branch build, or set GITHUB_TOKEN if artifact access requires it."
fi

chmod +x "$target"

if [ "$os" = "macos" ] && command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
fi

if "$target" --version >/dev/null 2>&1; then
  info "Installed from $installed_from: $("$target" --version) -> $target"
else
  warn "Binary saved from $installed_from but --version failed; the file may be corrupt."
fi

case ":$PATH:" in
  *":$PREFIX:"*) info "$PREFIX is already on PATH." ;;
  *)
    warn "$PREFIX is not on your PATH."
    [ -n "$HOME_DIR" ] || HOME_DIR="$PREFIX"
    case "${SHELL:-}" in
      */zsh)  rc="$HOME_DIR/.zshrc"  ;;
      */bash) rc="$HOME_DIR/.bashrc" ;;
      *)      rc="$HOME_DIR/.profile" ;;
    esac
    printf '       Add this line to %s :\n         export PATH="%s:$PATH"\n' "$rc" "$PREFIX"
    ;;
esac

info "Done. Try:"
printf '    jpg2pdf ~/Pictures --size a4\n'
printf '    jpg2pdf . --size a4 --style pencil\n'
}

if ! ( set -eu; main "$@" ); then
  die "Installer failed safely before completion. Re-run with --debug for details."
fi
