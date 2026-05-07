<#
.SYNOPSIS
  One-shot bootstrap for jpg2pdf on Windows.
  Pulls the repo, compiles the Python CLI into a standalone jpg2pdf.exe,
  and registers it on the User PATH so `jpg2pdf` works from anywhere.

.USAGE
  # Remote (no clone needed beforehand):
  iwr -useb https://raw.githubusercontent.com/<you>/<repo>/main/run.ps1 | iex

  # Local (run from inside the cloned repo):
  .\run.ps1
  .\run.ps1 -RepoUrl https://github.com/<you>/<repo>.git -InstallDir "$HOME\Tools\jpg2pdf"

  # After it finishes, OPEN A NEW TERMINAL:
  jpg2pdf "C:\Photos" --size a4
  jpg2pdf . --size letter --fit cover --out album.pdf
  jpg2pdf . --size legal --orientation landscape --recursive
#>
[CmdletBinding()]
param(
    [string]$RepoUrl    = "https://github.com/CHANGE_ME/jpg2pdf.git",
    [string]$InstallDir = (Join-Path $HOME "Tools\jpg2pdf"),
    [string]$Branch     = "main",
    [switch]$NoCompile,         # skip PyInstaller, use a .cmd shim that calls python
    [switch]$Force              # rebuild even if jpg2pdf.exe already exists
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[jpg2pdf] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[jpg2pdf] $m" -ForegroundColor Yellow }
function Die ($m){ Write-Host "[jpg2pdf] $m" -ForegroundColor Red; exit 1 }

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
        Die "winget unavailable. Install Python 3 from https://python.org and re-run."
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

# ---------- 3. Pull / clone repo ----------
# If we're already running INSIDE a checkout, prefer that location.
$localRepo = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "tools\jpg2pdf\src\jpg2pdf.py"))) {
    $localRepo = $PSScriptRoot
    Info "Using local repo at: $localRepo"
    $InstallDir = $localRepo
    if ($git -and (Test-Path (Join-Path $localRepo ".git"))) {
        Info "git pull..."
        git -C $localRepo pull --ff-only
    }
} elseif ($git) {
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
    Die "Git not available and no local repo found. Install Git or run from a cloned copy."
}

$srcScript = Join-Path $InstallDir "tools\jpg2pdf\src\jpg2pdf.py"
$reqsFile  = Join-Path $InstallDir "tools\jpg2pdf\requirements.txt"
if (-not (Test-Path $srcScript)) { Die "Missing $srcScript" }

# ---------- 4. Python deps ----------
Info "Installing Python dependencies..."
& $py -m pip install --user --upgrade --quiet -r $reqsFile
if ($LASTEXITCODE -ne 0) { Die "pip install failed." }

# ---------- 5. Compile to standalone .exe (PyInstaller) ----------
$binDir = Join-Path $HOME "Tools\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$exePath = Join-Path $binDir "jpg2pdf.exe"
$shimPath = Join-Path $binDir "jpg2pdf.cmd"

if ($NoCompile) {
    Info "Skipping compile (-NoCompile). Writing .cmd shim instead."
    if (Test-Path $exePath) { Remove-Item $exePath -Force }
    @"
@echo off
"$py" "$srcScript" %*
"@ | Set-Content -Path $shimPath -Encoding ASCII
    Info "Wrote shim: $shimPath"
}
else {
    if ((Test-Path $exePath) -and -not $Force) {
        Info "jpg2pdf.exe already exists. Use -Force to rebuild."
    } else {
        Info "Installing PyInstaller..."
        & $py -m pip install --user --upgrade --quiet pyinstaller
        if ($LASTEXITCODE -ne 0) { Die "Failed to install PyInstaller." }

        $buildDir = Join-Path $env:TEMP "jpg2pdf_build"
        $distDir  = Join-Path $env:TEMP "jpg2pdf_dist"
        $workDir  = Join-Path $env:TEMP "jpg2pdf_work"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $buildDir,$distDir,$workDir

        Info "Compiling jpg2pdf.exe with PyInstaller (this can take a minute)..."
        & $py -m PyInstaller `
            --onefile `
            --name jpg2pdf `
            --console `
            --distpath $distDir `
            --workpath $workDir `
            --specpath $buildDir `
            $srcScript
        if ($LASTEXITCODE -ne 0) { Die "PyInstaller build failed." }

        $built = Join-Path $distDir "jpg2pdf.exe"
        if (-not (Test-Path $built)) { Die "Build succeeded but $built not found." }
        Copy-Item -Force $built $exePath
        if (Test-Path $shimPath) { Remove-Item $shimPath -Force }   # prefer .exe over .cmd
        Info "Built: $exePath"

        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $buildDir,$distDir,$workDir
    }
}

# ---------- 6. Add bin folder to USER PATH (persistent) ----------
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
$env:Path = "$env:Path;$binDir"   # current session

Info "Done! Open a NEW terminal, then try:"
Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
Write-Host "    jpg2pdf . --size letter --fit cover --out album.pdf" -ForegroundColor Green
Write-Host "    jpg2pdf . --size legal --orientation landscape --recursive" -ForegroundColor Green
