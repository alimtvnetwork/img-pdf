<#
.SYNOPSIS
  One-shot installer for jpg2pdf on Windows.
  Clones the repo, installs Python + Pillow, and registers a global
  `jpg2pdf` command via a shim on the User PATH.

.USAGE
  # Remote install (recommended):
  iwr -useb https://raw.githubusercontent.com/<you>/<repo>/main/install.ps1 | iex

  # Local install from a cloned copy:
  .\install.ps1
  .\install.ps1 -RepoUrl https://github.com/<you>/<repo>.git -InstallDir "$HOME\Tools\jpg2pdf"

  # After install, open a NEW terminal:
  jpg2pdf "C:\Photos" --size a4
#>
[CmdletBinding()]
param(
    [string]$RepoUrl    = "https://github.com/CHANGE_ME/jpg2pdf.git",
    [string]$InstallDir = (Join-Path $HOME "Tools\jpg2pdf"),
    [string]$Branch     = "main"
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[install] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[install] $m" -ForegroundColor Yellow }
function Die ($m){ Write-Host "[install] $m" -ForegroundColor Red; exit 1 }

function Get-Python {
    foreach ($n in @("python","py")) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
}

# ---------- 1. Python ----------
$py = Get-Python
if (-not $py) {
    Info "Python not found. Installing via winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die "winget not available. Install Python 3 from https://python.org and re-run."
    }
    winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    Refresh-Path
    $py = Get-Python
    if (-not $py) { Die "Python installed but not on PATH. Open a new terminal and re-run." }
}
Info "Python: $py"

# ---------- 2. Git ----------
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Info "Git not found. Installing..."
    winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
    Refresh-Path
    $git = Get-Command git -ErrorAction SilentlyContinue
}

# ---------- 3. Clone / pull repo ----------
if ($git) {
    if (Test-Path (Join-Path $InstallDir ".git")) {
        Info "Updating repo in $InstallDir ..."
        git -C $InstallDir fetch --depth=1 origin $Branch
        git -C $InstallDir reset --hard "origin/$Branch"
    } else {
        Info "Cloning $RepoUrl -> $InstallDir ..."
        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
        git clone --depth=1 --branch $Branch $RepoUrl $InstallDir
    }
} else {
    Warn "Git not available — skipping clone. Ensure repo files are already in $InstallDir."
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

$script = Join-Path $InstallDir "tools\jpg2pdf\src\jpg2pdf.py"
$reqs   = Join-Path $InstallDir "tools\jpg2pdf\requirements.txt"
if (-not (Test-Path $script)) { Die "Missing $script" }

# ---------- 4. Pillow ----------
Info "Installing Python dependencies..."
& $py -m pip install --user --upgrade --quiet -r $reqs
if ($LASTEXITCODE -ne 0) { Die "pip install failed." }

# ---------- 5. CMD shim ----------
$binDir = Join-Path $HOME "Tools\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$shim = Join-Path $binDir "jpg2pdf.cmd"
@"
@echo off
"$py" "$script" %*
"@ | Set-Content -Path $shim -Encoding ASCII
Info "Wrote shim: $shim"

# ---------- 6. Persist on User PATH ----------
$userPath = [Environment]::GetEnvironmentVariable("Path","User")
if (-not $userPath) { $userPath = "" }
$paths = $userPath.Split(";") | Where-Object { $_ -ne "" }
if ($paths -notcontains $binDir) {
    $newPath = ($paths + $binDir) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Info "Added $binDir to User PATH (persistent)."
} else {
    Info "$binDir already on User PATH."
}
$env:Path = "$env:Path;$binDir"

Info "Done! Open a NEW terminal, then try:"
Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
Write-Host "    jpg2pdf . --size letter --fit cover --out album.pdf" -ForegroundColor Green
Write-Host "    jpg2pdf . --size legal --orientation landscape --recursive" -ForegroundColor Green
