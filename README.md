<div align="center">

# 📄 img-pdf

**Turn a folder of images into one beautiful PDF — in a single command.**

Cross-platform CLI · Quality-preserving · Windows right-click integration · Pencil-sketch mode for faint text

[![Release](https://img.shields.io/github/v/release/alimtvnetwork/img-pdf?style=flat-square&color=4f46e5)](https://github.com/alimtvnetwork/img-pdf/releases)
[![Platforms](https://img.shields.io/badge/platforms-windows%20%7C%20macos%20%7C%20linux-2dd4a8?style=flat-square)](https://github.com/alimtvnetwork/img-pdf/releases)
[![License](https://img.shields.io/badge/license-MIT-c9a84c?style=flat-square)](#license)

<br/>

<img src="tools/jpg2pdf/docs/hero.png" alt="jpg2pdf in action — converting a folder of images into a single PDF" width="820"/>

</div>

---

## ✨ What it does

`jpg2pdf` walks a folder of images and stitches them into **one** PDF — preserving
quality, respecting orientation, and handling page sizing for you. No more
opening 30 images one-by-one, "Print to PDF", merging, repeat.

| Feature | Why it matters |
| --- | --- |
| 🖼️  **Quality-preserving** | Embeds the original JPEG bytes when possible — no recompression artifacts. |
| 📐 **Smart sizing** | `a4`, `letter`, `legal` — with `fit cover/contain` and `--orientation`. |
| ✏️  **Pencil mode** | Faint pencil-on-paper styling with **subtle / normal / extra-visible** depth. |
| 🪟 **Windows context-menu** | Right-click any folder → *"Combine into PDF"*. One terminal, all files. |
| 🍎 **macOS / Linux** | Single static binary, ad-hoc signed, drops into `~/.local/bin`. |
| 🔁 **Recursive** | `--recursive` walks subfolders in natural sort order. |

---

## 🚀 Install

### 🪟 Windows · PowerShell

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
```

Drops `jpg2pdf.exe` into `%USERPROFILE%\Tools\bin`, adds it to your **User PATH**,
and registers the Explorer right-click entries. Open a new terminal afterwards.

### 🪟 Windows · PowerShell · skip context-menu registration

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1))) -NoContextMenu
```

### 🪟 Windows · PowerShell · pin a specific version

```powershell
$env:JPG2PDF_VERSION = "v1.1.0"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
```

### 🐧 macOS · Linux · Bash

```bash
curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh | bash
```

Drops `jpg2pdf` into `~/.local/bin` (override with `JPG2PDF_PREFIX=$HOME/bin`).

### 🐧 macOS · Linux · Bash · pin a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.sh \
  | JPG2PDF_VERSION=v1.1.0 JPG2PDF_PREFIX=$HOME/bin bash
```

If PowerShell blocks scripts, use a process-only bypass for the current shell first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex
```

Or run the installer inside a bypassed PowerShell process:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex"
```

After installation, open a new terminal and run `jpg2pdf --help`, or right-click any folder in Explorer and pick *Combine images into PDF*.

### 🧹 Uninstall

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/uninstall.ps1 | iex
```

> Env var overrides: `JPG2PDF_VERSION` (pin a tag), `JPG2PDF_REPO` (use a fork),
> `JPG2PDF_NO_CONTEXT_MENU=1` (skip Explorer entries), `JPG2PDF_PREFIX` (custom
> install dir on macOS / Linux).

---

## 🎯 Use it

```bash
# The basics
jpg2pdf ~/Pictures --size a4
jpg2pdf .         --size letter --fit cover --out album.pdf
jpg2pdf .         --size legal  --orientation landscape --recursive

# Mixed selections — images + PDFs + HTML + Word, merged in selection order
jpg2pdf --files cover.jpg invoice.pdf notes.docx report.html --out bundle.pdf

# Pencil-on-paper styling for scanned notes / faint handwriting
jpg2pdf ./notes --size a4 --style pencil
jpg2pdf ./notes --size a4 --style pencil --ask-strength   # live preview, defaults to subtle
```

Supported inputs (sorted naturally; mixed selections merged in order):

| Kind  | Extensions                              | Notes |
|-------|------------------------------------------|-------|
| Image | `.jpg .jpeg .png .webp .bmp .tif .tiff` | Honors `--size/--fit/--style/...` |
| PDF   | `.pdf`                                   | Embedded as-is, page geometry preserved |
| HTML  | `.html .htm`                             | Rendered via `xhtml2pdf` |
| Word  | `.docx .doc`                             | Needs MS Word (Windows) or LibreOffice (macOS) |

<div align="center">
  <img src="tools/jpg2pdf/docs/demo.gif" alt="jpg2pdf demo — selecting mixed files and combining into one PDF" width="720"/>
</div>

### ✏️ Pencil strength — three depths

| Mode | When to use |
| --- | --- |
| `subtle`         | **Default.** Gentle softening that keeps paper texture — best for already-readable scans. |
| `normal`         | Balanced ink + paper grain. |
| `extra-visible`  | Faint / low-contrast handwriting that needs pop. |

Pick interactively with `--ask-strength` (live preview, opens with **subtle**
selected), or pass `--pencil-opacity` / `--pencil-ink-darken` for full manual
control. Your last choice is saved to `~/.jpg2pdf/config.json` and reused
automatically next run.

---

## 🪟 Windows right-click

After install, right-click works two ways — both route through a **single terminal**:

- **On a folder** → *Combine into PDF* / *Combine into PDF (pencil)*
- **On selected files** → mix images, PDFs, HTML, and Word docs in any order; they're merged into one PDF

No more 30 terminals popping up for 30 selected files. The launcher batches
everything into one conversion call.

<div align="center">
  <img src="tools/jpg2pdf/docs/context-menu.png" alt="Windows Explorer right-click menu showing 'Combine into PDF' submenu" width="520"/>
</div>

---

## 🛠️ Build from source

```bash
pip install -r tools/jpg2pdf/requirements.txt
python tools/jpg2pdf/src/jpg2pdf.py ./photos --size a4
```

---

## 📦 Repo layout

```text
img-pdf/
├── install.ps1                          # one-liner Windows installer
├── install.sh                           # one-liner macOS / Linux installer
├── run.ps1 / uninstall.ps1              # local runner + uninstaller
└── tools/jpg2pdf/
    ├── src/jpg2pdf.py                   # the CLI
    ├── scripts/register-context-menu.ps1
    ├── spec/SPEC.md                     # full spec
    ├── docs/hero.png
    ├── requirements.txt
    └── VERSION
```

---

## 🚢 Cutting a release

Tag & push — GitHub Actions builds binaries for Windows / Linux / macOS
(x64 + Apple Silicon) and publishes a Release with `SHA256SUMS.txt`:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

Released artifacts: `jpg2pdf-windows-x64.exe`, `jpg2pdf-linux-x64`,
`jpg2pdf-linux-arm64`, `jpg2pdf-macos-x64`, `jpg2pdf-macos-arm64`.

---

## License

MIT © [alimtvnetwork](https://github.com/alimtvnetwork)
