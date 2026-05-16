# jpg2pdf

Combine every image in a folder into a single PDF. Quality-preserving,
cross-platform, with a one-shot Windows installer.

See [`spec/SPEC.md`](spec/SPEC.md) for the full specification.

## Install — one-liner (prebuilt binaries from GitHub Releases)

Override the repo at any time with `JPG2PDF_REPO=other-user/other-repo` (env var).

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
```

Pin a version, or skip the Explorer context-menu:

```powershell
$env:JPG2PDF_VERSION = "v1.3.8"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
$env:JPG2PDF_NO_CONTEXT_MENU = "1"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
```

Drops `jpg2pdf.exe` into `%USERPROFILE%\Tools\bin`, adds it to **User PATH**,
and registers Explorer right-click entries. Open a new terminal afterwards.

### macOS / Linux (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | bash
```

Options via env vars:

```bash
curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh \
  | JPG2PDF_VERSION=v1.3.8 JPG2PDF_PREFIX=$HOME/bin bash
```

Drops `jpg2pdf` into `$HOME/.local/bin` (override with `JPG2PDF_PREFIX`).
The script tells you the exact `export PATH=...` line to add if that
folder isn't on `PATH` yet. If no macOS binary exists, the installer falls
back to the Python source and writes a `jpg2pdf` wrapper instead of failing.
Run with `--debug` or `JPG2PDF_DEBUG=1` to print a detailed log path; source
fallback wrappers stay installed even when dependency verification needs repair.

> **macOS note:** binaries are **ad-hoc signed** (not Apple-notarized).
> The installer auto-strips `com.apple.quarantine`, so the CLI works
> straight after `curl | bash`. If you download the `.zip` from the
> Releases page manually, run once:
> `xattr -dr com.apple.quarantine ~/.local/bin/jpg2pdf`

Prebuilt assets published by `.github/workflows/release.yml`:
`jpg2pdf-windows-x64.exe`, `jpg2pdf-linux-x64`, `jpg2pdf-linux-arm64`,
plus `SHA256SUMS.txt`. macOS installs currently use the Python source fallback.

## Use

```bash
# Image folders
jpg2pdf ~/Pictures --size a4
jpg2pdf . --size letter --fit cover --out album.pdf
jpg2pdf . --size legal --orientation landscape --recursive
jpg2pdf . --size a4 --style pencil           # faint pencil-on-paper look

# Mixed selections — merged in the order given
jpg2pdf --files cover.jpg invoice.pdf notes.docx report.html --out bundle.pdf
```

Supported inputs (sorted naturally; mixed types merged in selection order):

| Kind  | Extensions                              | Notes |
|-------|------------------------------------------|-------|
| Image | `.jpg .jpeg .png .webp .bmp .tif .tiff` | Honors `--size/--fit/--style/...` |
| PDF   | `.pdf`                                   | Embedded as-is |
| HTML  | `.html .htm`                             | Rendered via `xhtml2pdf` |
| Word  | `.docx .doc`                             | Needs MS Word (Windows) or LibreOffice (macOS) |

## Build from source

```bash
pip install -r tools/jpg2pdf/requirements.txt
python tools/jpg2pdf/src/jpg2pdf.py ./photos --size a4
```

## Cutting a release

Tag and push — the workflow builds binaries for Windows and Linux and publishes
a GitHub Release. macOS is installed from source until macOS runners are restored:

```bash
git tag v1.3.8 && git push origin v1.3.8
```


## Repo layout

```
jpg2pdf/
├── spec/SPEC.md          # specification
├── src/jpg2pdf.py        # the tool
├── scripts/run.ps1       # no-install local runner
├── install.ps1           # global Windows installer
├── requirements.txt
└── README.md
```
