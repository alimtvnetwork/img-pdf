<#
.SYNOPSIS
  One-shot bootstrap for jpg2pdf on Windows:
    pull repo → install Python deps → compile jpg2pdf.exe →
    add to User PATH → register Explorer context menu.

.USAGE
  .\run.ps1
  .\run.ps1 -RepoUrl https://github.com/<you>/<repo>.git
  .\run.ps1 -NoCompile           # use .cmd shim instead of compiled .exe
  .\run.ps1 -NoContextMenu       # skip Explorer registry entries
  .\run.ps1 -Unregister          # remove context menu and exit
  .\run.ps1 -Force               # rebuild .exe even if it already exists

.NOTES
  Open a NEW terminal after install so PATH changes take effect.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl     = "https://github.com/CHANGE_ME/jpg2pdf.git",
    [string]$InstallDir  = (Join-Path $HOME "Tools\jpg2pdf"),
    [string]$Branch      = "main",
    [switch]$NoCompile,
    [switch]$NoContextMenu,
    [switch]$Unregister,
    [switch]$Force,
    [switch]$Verbose,                                    # alias for $script:VerboseMode = $true
    [string]$LogDir      = (Join-Path $env:TEMP "jpg2pdf-logs"),
    [string]$LogFile     = $null                         # if set, overrides LogDir
)

$ErrorActionPreference = "Stop"

# ---------- Logging ----------
$script:VerboseMode = [bool]$Verbose -or ($PSBoundParameters['Verbose'] -eq $true) -or ($VerbosePreference -ne 'SilentlyContinue')

if (-not $LogFile) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogFile = Join-Path $LogDir "run-$stamp.log"
}
$script:LogFile = $LogFile

function _Log {
    param([string]$Level, [string]$Msg)
    $line = "{0} [{1,-5}] {2}" -f (Get-Date -Format "HH:mm:ss.fff"), $Level, $Msg
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
}
function Info($m){ _Log "INFO" $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Cyan }
function Warn($m){ _Log "WARN" $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Yellow }
function Die ($m){ _Log "ERROR" $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Red;
                   Write-Host "[jpg2pdf] Full log: $script:LogFile" -ForegroundColor Red; exit 1 }
function Verb($m){ _Log "VERB" $m; if ($script:VerboseMode) { Write-Host "[jpg2pdf]   $m" -ForegroundColor DarkGray } }

# Run an external command, tee stdout+stderr to the log file.
# In verbose mode, stream live to console; otherwise show only on failure.
function Invoke-Logged {
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure
    )
    $argDisplay = ($ArgumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    Verb "$Label -> $FilePath $argDisplay"
    _Log "RUN" "$FilePath $argDisplay"

    $tmpOut = [IO.Path]::GetTempFileName()
    $tmpErr = [IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
        $code = $proc.ExitCode

        $out = if (Test-Path $tmpOut) { Get-Content -Raw -LiteralPath $tmpOut } else { "" }
        $err = if (Test-Path $tmpErr) { Get-Content -Raw -LiteralPath $tmpErr } else { "" }

        if ($out) { _Log "OUT " "[$Label]`n$out" }
        if ($err) { _Log "ERR " "[$Label]`n$err" }

        if ($script:VerboseMode) {
            if ($out) { Write-Host $out }
            if ($err) { Write-Host $err -ForegroundColor DarkYellow }
        }

        if ($code -ne 0) {
            if (-not $script:VerboseMode) {
                # On failure, dump captured output so the user sees it without re-running.
                if ($out) { Write-Host "----- stdout -----" -ForegroundColor DarkGray; Write-Host $out }
                if ($err) { Write-Host "----- stderr -----" -ForegroundColor DarkGray; Write-Host $err -ForegroundColor DarkYellow }
            }
            Warn "$Label failed with exit code $code (see $script:LogFile)"
            if (-not $AllowFailure) { Die "$Label failed (exit $code)." }
        } else {
            Verb "$Label OK (exit 0)"
        }
        return $code
    } finally {
        Remove-Item -LiteralPath $tmpOut,$tmpErr -ErrorAction SilentlyContinue
    }
}

Info "Log file: $script:LogFile"
if ($script:VerboseMode) { Info "Verbose mode ON" }

# Capture environment context up front — invaluable when debugging.
_Log "ENV " ("PSVersion={0} OS={1} User={2} CWD={3}" -f `
    $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, $env:USERNAME, (Get-Location).Path)

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

# ---------- Locate repo (local checkout preferred) ----------
$localRepo = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "tools\jpg2pdf\src\jpg2pdf.py"))) {
    $localRepo = $PSScriptRoot
    $InstallDir = $localRepo
}

# ---------- -Unregister short-circuit ----------
if ($Unregister) {
    $unreg = Join-Path $InstallDir "tools\jpg2pdf\scripts\unregister-context-menu.ps1"
    if (-not (Test-Path $unreg)) { Die "Missing $unreg" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $unreg
    exit $LASTEXITCODE
}

# ---------- 1. Python ----------
$py = Get-Python
if (-not $py) {
    Info "Python not found. Installing via winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die "winget unavailable. Install Python 3 from https://python.org and re-run."
    }
    Invoke-Logged -Label "winget install Python" -FilePath "winget" -ArgumentList @(
        "install","-e","--id","Python.Python.3.12",
        "--accept-source-agreements","--accept-package-agreements"
    )
    Refresh-Path
    $py = Get-Python
    if (-not $py) { Die "Python installed but not on PATH. Open a new terminal and re-run." }
}
Info "Python: $py"
Invoke-Logged -Label "python --version" -FilePath $py -ArgumentList @("--version") -AllowFailure | Out-Null

# ---------- 2. Git ----------
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Info "Git not found. Installing..."
    Invoke-Logged -Label "winget install Git" -FilePath "winget" -ArgumentList @(
        "install","-e","--id","Git.Git",
        "--accept-source-agreements","--accept-package-agreements"
    )
    Refresh-Path
    $git = Get-Command git -ErrorAction SilentlyContinue
}
if ($git) { Verb "git: $($git.Source)" }

# ---------- 3. Pull / clone repo ----------
if ($localRepo) {
    Info "Using local repo at: $localRepo"
    if ($git -and (Test-Path (Join-Path $localRepo ".git"))) {
        Info "git pull..."
        Invoke-Logged -Label "git pull" -FilePath $git.Source `
            -ArgumentList @("-C", $localRepo, "pull", "--ff-only") -AllowFailure | Out-Null
    }
} elseif ($git) {
    if (Test-Path (Join-Path $InstallDir ".git")) {
        Info "Updating repo in $InstallDir ..."
        Invoke-Logged -Label "git fetch" -FilePath $git.Source `
            -ArgumentList @("-C",$InstallDir,"fetch","--depth=1","origin",$Branch)
        Invoke-Logged -Label "git reset" -FilePath $git.Source `
            -ArgumentList @("-C",$InstallDir,"reset","--hard","origin/$Branch")
    } else {
        Info "Cloning $RepoUrl -> $InstallDir ..."
        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
        Invoke-Logged -Label "git clone" -FilePath $git.Source `
            -ArgumentList @("clone","--depth=1","--branch",$Branch,$RepoUrl,$InstallDir)
    }
} else {
    Die "Git unavailable and no local repo. Install Git or run from a cloned copy."
}

$srcScript = Join-Path $InstallDir "tools\jpg2pdf\src\jpg2pdf.py"
$reqsFile  = Join-Path $InstallDir "tools\jpg2pdf\requirements.txt"
$regScript = Join-Path $InstallDir "tools\jpg2pdf\scripts\register-context-menu.ps1"
if (-not (Test-Path $srcScript)) { Die "Missing $srcScript" }

# ---------- 4. Python deps ----------
Info "Installing Python dependencies..."
# Drop --quiet so log captures real pip output for troubleshooting.
$pipArgs = @("-m","pip","install","--user","--upgrade","--disable-pip-version-check","-r",$reqsFile)
if ($script:VerboseMode) { $pipArgs += "--verbose" }
Invoke-Logged -Label "pip install -r requirements.txt" -FilePath $py -ArgumentList $pipArgs

# ---------- 5. Compile (PyInstaller) or shim ----------
$binDir = Join-Path $HOME "Tools\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$exePath  = Join-Path $binDir "jpg2pdf.exe"
$shimPath = Join-Path $binDir "jpg2pdf.cmd"
$entryPath = $null

if ($NoCompile) {
    Info "Writing .cmd shim (no compile)..."
    if (Test-Path $exePath) { Remove-Item $exePath -Force }
    @"
@echo off
"$py" "$srcScript" %*
"@ | Set-Content -Path $shimPath -Encoding ASCII
    $entryPath = $shimPath
    Info "Shim: $shimPath"
} else {
    if ((Test-Path $exePath) -and -not $Force) {
        Info "jpg2pdf.exe already exists. Use -Force to rebuild."
    } else {
        Info "Installing PyInstaller..."
        $piInstall = @("-m","pip","install","--user","--upgrade","--disable-pip-version-check","pyinstaller")
        if ($script:VerboseMode) { $piInstall += "--verbose" }
        Invoke-Logged -Label "pip install pyinstaller" -FilePath $py -ArgumentList $piInstall

        $buildDir = Join-Path $env:TEMP "jpg2pdf_build"
        $distDir  = Join-Path $env:TEMP "jpg2pdf_dist"
        $workDir  = Join-Path $env:TEMP "jpg2pdf_work"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $buildDir,$distDir,$workDir

        Info "Compiling jpg2pdf.exe (PyInstaller, ~1 min)..."
        $piArgs = @(
            "-m","PyInstaller","--onefile","--name","jpg2pdf","--console","--noconfirm",
            "--distpath",$distDir,"--workpath",$workDir,"--specpath",$buildDir,
            "--log-level", $(if ($script:VerboseMode) { "DEBUG" } else { "WARN" }),
            $srcScript
        )
        Invoke-Logged -Label "pyinstaller build" -FilePath $py -ArgumentList $piArgs

        $built = Join-Path $distDir "jpg2pdf.exe"
        if (-not (Test-Path $built)) { Die "PyInstaller finished but $built not found." }
        Copy-Item -Force $built $exePath
        if (Test-Path $shimPath) { Remove-Item $shimPath -Force }
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $buildDir,$distDir,$workDir
        Info "Built: $exePath"
    }
    $entryPath = $exePath
}

# ---------- 6. Persist on User PATH (safe update) ----------
function Update-UserPath {
    param([Parameter(Mandatory=$true)][string]$Dir)

    # 1. Confirm the folder actually exists before touching PATH.
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        Warn "Bin folder does not exist, skipping PATH update: $Dir"
        return $false
    }
    $resolved = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')

    # 2. Read current User PATH (may be $null on a fresh profile).
    $current = [Environment]::GetEnvironmentVariable("Path","User")
    if (-not $current) { $current = "" }

    # 3. Split, trim, drop empties, dedupe case-insensitively, normalise trailing slashes.
    $cmp = [System.StringComparer]::OrdinalIgnoreCase
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
    $cleaned = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $current.Split(';')) {
        $e = $entry.Trim().TrimEnd('\')
        if (-not $e) { continue }
        if ($seen.Add($e)) { [void]$cleaned.Add($e) }
    }
    $alreadyPresent = $seen.Contains($resolved)
    $rawCount = ($current.Split(';') | Where-Object { $_.Trim() }).Count
    $hadDuplicates = ($cleaned.Count -lt $rawCount)

    if ($alreadyPresent -and -not $hadDuplicates) {
        Info "$resolved already on User PATH (no changes)."
    }
    else {
        if (-not $alreadyPresent) { [void]$cleaned.Add($resolved) }
        $newPath = ($cleaned -join ';')

        # Back up the previous value so the user can recover if needed.
        try {
            [Environment]::SetEnvironmentVariable("PathBackup_jpg2pdf", $current, "User")
        } catch { Warn "Could not write PATH backup: $_" }

        try {
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        } catch {
            Warn "Failed to update User PATH: $_"
            return $false
        }

        if ($alreadyPresent) {
            Info "User PATH cleaned (removed duplicates). $resolved already present."
        } else {
            Info "Added $resolved to User PATH (persistent). Backup in env var 'PathBackup_jpg2pdf'."
        }
    }

    # Update current session only if missing.
    $sessionEntries = $env:Path.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') }
    if ($sessionEntries -notcontains $resolved) {
        $env:Path = "$($env:Path.TrimEnd(';'));$resolved"
    }
    return $true
}

[void](Update-UserPath -Dir $binDir)

# ---------- 7. Register Explorer context menu ----------
if (-not $NoContextMenu) {
    if (-not (Test-Path $regScript)) {
        Warn "Missing $regScript — skipping context-menu registration."
    } else {
        Info "Registering Explorer context menu..."
        & powershell -NoProfile -ExecutionPolicy Bypass -File $regScript -ExePath $entryPath
    }
}

Info "Done! Open a NEW terminal, then try:"
Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
Write-Host "    jpg2pdf . --size letter --fit cover --out album.pdf" -ForegroundColor Green
Write-Host "    jpg2pdf . --size legal --orientation landscape --recursive" -ForegroundColor Green
Write-Host ""
Info "Right-click a folder, folder background, or selected images:"
Write-Host "    Images to PDF >  Convert All / Selected to A4 / Letter / Legal" -ForegroundColor Green
