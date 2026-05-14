# jpg2pdf — Specification

## Goal
Command-line tool that combines a folder (or a selected list of files) into a
single PDF. Accepts images, existing PDFs, HTML pages, and Word documents in
any mix and merges them in the given order. One-shot Windows install with a
global PATH binary and **Explorer context-menu** integration.

## Non-goals
- No OCR or image editing.
- No GUI (context menu + small Tk dialogs only).

## Supported platforms
- Windows 10/11 (primary; `run.ps1` bootstraps everything).
- macOS / Linux (the Python CLI works directly).

## Inputs
Either:
- **A folder path** → every supported file inside it (optionally recursive).
- **A list of file paths** → exact files in the order given (used by the
  "Combine into PDF" context-menu entries; the registry uses
  `MultiSelectModel=Player` so all selected files are passed in one call,
  preserving selection order).

Supported extensions (case-insensitive):

| Kind   | Extensions                                       | Renderer |
|--------|--------------------------------------------------|----------|
| Image  | `.jpg .jpeg .png .webp .bmp .tif .tiff`          | Pillow (existing pipeline; honours `--size/--fit/--style/...`) |
| PDF    | `.pdf`                                           | embedded as-is, page geometry preserved |
| HTML   | `.html .htm`                                     | `xhtml2pdf` (pure Python) |
| Word   | `.docx .doc`                                     | `docx2pdf` (needs MS Word on Windows or LibreOffice on macOS) |

Folder input is sorted naturally (`img2.jpg` before `img10.jpg`). Mixed
selections are merged into a single PDF in selection order; consecutive
images are batched into one image-PDF chunk for efficiency.

`--size`, `--fit`, `--orientation`, `--dpi`, `--rotate`, `--auto-rotate`, and
`--style pencil` apply ONLY to image inputs. PDFs / HTML / Word keep their
own page geometry.

## CLI
```
jpg2pdf <folder>                   [options]
jpg2pdf --files <f1> <f2> ...      [options]
jpg2pdf --files-from <listfile>    [options]   # one path per line (UTF-8)
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--size` | `a4` | `a4` 595×842 pt, `letter` 612×792 pt, `legal` 612×1008 pt. |
| `--orientation` | `portrait` | `landscape` swaps W/H. |
| `--fit` | `contain` | `contain` / `cover` / `stretch` / `original`. |
| `--out` | `<folder>.pdf` next to folder, or `images.pdf` next to first selected file | Output path. |
| `--recursive` | off | Folder mode only — include subfolders. |

## Quality
No re-encoding when `--fit original`. Otherwise Pillow LANCZOS resize only
when needed; PDF embed uses Pillow defaults (high quality).

## Exit codes
- `0` success
- `1` bad input / no images / dependency failure

## Windows context menu

Registered under HKCU (no admin). Three roots:

1. **On a folder** (Directory + Directory\Background)
   `Images to PDF ▸`
   - Convert All to **A4**
   - Convert All to **Letter**
   - Convert All to **Legal**
   - Convert All (recursive) to A4
   - Configure / Update…

2. **On image files** (`.jpg .jpeg .png .webp .bmp .tif .tiff`)
   `Images to PDF ▸`
   - Convert Selected to **A4**
   - Convert Selected to **Letter**
   - Convert Selected to **Legal**

   Uses `MultiSelectModel=Player` so Windows passes ALL selected files in a
   single invocation, in selection order.

Each menu entry calls `jpg2pdf.exe` with the appropriate `--size` and either
the folder path or `--files <selected paths>`. Output is written next to the
folder / first selected file. A console window briefly shows progress.

## File layout
```
repo/
├── run.ps1                          ← bootstrap (pull, compile, install, register)
├── tools/jpg2pdf/
│   ├── spec/SPEC.md
│   ├── src/jpg2pdf.py               ← the CLI
│   ├── scripts/
│   │   ├── register-context-menu.ps1
│   │   └── unregister-context-menu.ps1
│   ├── requirements.txt
│   └── README.md
```

## `run.ps1` behaviour
1. Install Python 3 + Git via `winget` if missing.
2. Pull/clone repo into `%USERPROFILE%\Tools\jpg2pdf` (or use local checkout).
3. `pip install -r requirements.txt` and `pyinstaller`.
4. Compile `jpg2pdf.exe` (PyInstaller `--onefile`).
5. Copy to `%USERPROFILE%\Tools\bin\jpg2pdf.exe` and add that folder to **User PATH**.
6. Run `register-context-menu.ps1` to install the Explorer entries.

Switches:
- `-NoCompile` — use a `.cmd` shim around `python` instead of an .exe.
- `-NoContextMenu` — skip registry changes.
- `-Unregister` — remove context menu entries (and exit).
- `-Force` — rebuild even if .exe exists.

## Uninstall
```
.\run.ps1 -Unregister
```
Then delete `%USERPROFILE%\Tools\jpg2pdf` and
`%USERPROFILE%\Tools\bin\jpg2pdf.exe`, and remove `%USERPROFILE%\Tools\bin`
from User PATH if no longer needed.
