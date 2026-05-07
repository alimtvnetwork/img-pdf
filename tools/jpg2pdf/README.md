# jpg2pdf

Combine every image in a folder into a single PDF. Quality-preserving,
cross-platform, with a one-shot Windows installer.

See [`spec/SPEC.md`](spec/SPEC.md) for the full specification.

## Install (Windows, PowerShell)

```powershell
iwr -useb https://raw.githubusercontent.com/<you>/<repo>/main/install.ps1 | iex
```

The installer will:
1. Install Python 3 + Git via `winget` if missing.
2. Clone this repo into `%USERPROFILE%\Tools\jpg2pdf`.
3. `pip install` Pillow.
4. Drop a `jpg2pdf.cmd` shim into `%USERPROFILE%\Tools\bin`.
5. Add that folder to your **User PATH** so `jpg2pdf` works from anywhere.

Open a new terminal afterwards.

## Use

```powershell
jpg2pdf "C:\Photos" --size a4
jpg2pdf . --size letter --fit cover --out album.pdf
jpg2pdf . --size legal --orientation landscape --recursive
```

Supported inputs: `.jpg .jpeg .png .webp .bmp .tif .tiff` (sorted naturally).

## Without installing globally

```powershell
.\scripts\run.ps1 "C:\Photos" -a4
```

## macOS / Linux

```bash
pip install -r requirements.txt
python src/jpg2pdf.py ./photos --size a4
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
