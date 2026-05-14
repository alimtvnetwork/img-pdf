#!/usr/bin/env sh
# One-liner installer for jpg2pdf on Linux & macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | sh
#
#   # Pin a specific version:
#   curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | JPG2PDF_VERSION=v0.5.0 sh
#
#   # Install elsewhere (default: $HOME/.local/bin):
#   curl -fsSL https://.../install.sh | JPG2PDF_PREFIX=$HOME/bin sh
#
# What it does:
#   1. Detects OS + arch.
#   2. Resolves the latest GitHub Release (or $JPG2PDF_VERSION).
#   3. Downloads the matching binary into $JPG2PDF_PREFIX (default $HOME/.local/bin).
#   4. chmod +x and reports next steps.

set -eu

REPO="${JPG2PDF_REPO:-alimtvnetwork/img-pdf}"
VERSION="${JPG2PDF_VERSION:-}"
PREFIX="${JPG2PDF_PREFIX:-$HOME/.local/bin}"

info() { printf '\033[36m[jpg2pdf]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[jpg2pdf]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[jpg2pdf]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$REPO" = "alimtvnetwork/img-pdf" ]; then
  die "Set the repo: JPG2PDF_REPO=your-user/your-repo curl ... | sh  (or edit install.sh)."
fi

# --- detect platform -------------------------------------------------------
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

# Linux arm64 is not currently published — fall through with a clear error.
asset="jpg2pdf-${os}-${arch}"
case "$asset" in
  jpg2pdf-windows-*) die "Use install.ps1 on Windows." ;;
  jpg2pdf-linux-arm64) die "No prebuilt binary for linux/arm64. Build from source: see README." ;;
esac

# --- pick a downloader -----------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  DL() { curl -fsSL "$1" -o "$2"; }
  GET() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  DL() { wget -qO "$2" "$1"; }
  GET() { wget -qO- "$1"; }
else
  die "Need curl or wget to download."
fi

# --- resolve version -------------------------------------------------------
if [ -z "$VERSION" ]; then
  info "Resolving latest release of $REPO ..."
  api_json="$(GET "https://api.github.com/repos/$REPO/releases/latest")" \
    || die "Could not query GitHub releases."
  VERSION="$(printf '%s' "$api_json" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)"
  [ -n "$VERSION" ] || die "Could not parse latest tag from GitHub API."
fi
info "Installing jpg2pdf $VERSION ($os/$arch)"

# --- download --------------------------------------------------------------
url="https://github.com/$REPO/releases/download/$VERSION/$asset"
mkdir -p "$PREFIX"
target="$PREFIX/jpg2pdf"
info "Downloading $url"
DL "$url" "$target" || die "Download failed: $url"
chmod +x "$target"

# --- smoke test ------------------------------------------------------------
if "$target" --version >/dev/null 2>&1; then
  info "Installed: $("$target" --version) -> $target"
else
  warn "Binary saved but --version failed; the file may be corrupt."
fi

# --- PATH hint -------------------------------------------------------------
case ":$PATH:" in
  *":$PREFIX:"*) info "$PREFIX is already on PATH." ;;
  *)
    warn "$PREFIX is not on your PATH."
    case "${SHELL:-}" in
      */zsh)  rc="$HOME/.zshrc"  ;;
      */bash) rc="$HOME/.bashrc" ;;
      *)      rc="$HOME/.profile" ;;
    esac
    printf '       Add this line to %s :\n         export PATH="%s:$PATH"\n' "$rc" "$PREFIX"
    ;;
esac

info "Done. Try:"
printf '    jpg2pdf ~/Pictures --size a4\n'
printf '    jpg2pdf . --size a4 --style pencil\n'
