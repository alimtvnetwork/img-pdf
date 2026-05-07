# jpg2pdf — Specification

## Goal
A small command-line tool that combines every image in a folder into one
PDF. Optimised for ease of installation on Windows (one PowerShell command)
and for preserving image quality.

## Non-goals
- No OCR, no compression, no image editing.
- No GUI.

## Supported platforms
- Windows 10/11 (primary, via `install.ps1`)
- macOS / Linux (works because the core is plain Python)

## Inputs
- A folder path (positional, default = current directory).
- Supported file extensions (case-insensitive):
  `.jpg .jpeg .png .webp .bmp .tif .tiff`
- Files are sorted **naturally** (`img2.jpg` before `img10.jpg`).

## CLI
```
jpg2pdf <folder> [--size a4|letter|legal]
                 [--orientation portrait|landscape]
                 [--fit contain|cover|stretch|original]
                 [--out <file.pdf>]
                 [--recursive]
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--size` | `a4` | Page size. `a4` 595×842 pt, `letter` 612×792 pt, `legal` 612×1008 pt. |
| `--orientation` | `portrait` | `landscape` swaps width/height. |
| `--fit` | `contain` | `contain` = fit inside, no crop. `cover` = fill, may crop. `stretch` = distort to page. `original` = embed at native pixel size, centered. |
| `--out` | `<folder>.pdf` next to the folder | Output PDF path. |
| `--recursive` | off | Include subfolders. |

## Quality policy
- No re-encoding when `--fit original` is chosen.
- Otherwise Pillow resizes with LANCZOS only when needed; embedded JPEGs use
  Pillow's PDF default (high quality, no extra compression pass).

## Exit codes
- `0` success
- `1` bad folder / no images / dependency failure

## File layout
```
jpg2pdf/
├── spec/
│   └── SPEC.md            # this document
├── src/
│   └── jpg2pdf.py         # the tool
├── scripts/
│   └── run.ps1            # local runner (no install)
├── install.ps1            # one-shot installer (clone + PATH + shim)
├── requirements.txt
└── README.md
```

## Installer behaviour (`install.ps1`)
1. Ensure **Python 3** present (winget install if missing).
2. Ensure **Git** present (winget install if missing).
3. Clone (or `git pull`) the repo into `%USERPROFILE%\Tools\jpg2pdf`.
4. `pip install --user -r requirements.txt`.
5. Write a `jpg2pdf.cmd` shim into `%USERPROFILE%\Tools\bin`.
6. Append that bin folder to the **User PATH** (persistent).
7. Print usage examples. User opens a new terminal → `jpg2pdf` works globally.

## Uninstall
Delete `%USERPROFILE%\Tools\jpg2pdf` and `%USERPROFILE%\Tools\bin\jpg2pdf.cmd`,
then remove `%USERPROFILE%\Tools\bin` from the User PATH if no longer needed.
