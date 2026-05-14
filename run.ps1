<#
.SYNOPSIS
  One-shot bootstrap for jpg2pdf on Windows:
    pull repo -> install Python deps -> compile jpg2pdf.exe ->
    add to User PATH -> register Explorer context menu.

.USAGE
  .\run.ps1
  .\run.ps1 -RepoUrl https://github.com/<you>/<repo>.git
  .\run.ps1 -NoCompile           # use .cmd shim instead of compiled .exe
  .\run.ps1 -NoContextMenu       # skip Explorer registry entries
  .\run.ps1 -Unregister          # remove context menu and exit
  .\run.ps1 -Force               # rebuild .exe even if it already exists
  .\run.ps1 -Version             # print script / repo / installed exe versions and exit
  .\run.ps1 -SelfUpdate          # git pull + rebuild ONLY if version/source/deps changed
  .\run.ps1 -ShowVerbose         # stream subprocess output live to the console
  .\run.ps1 -LogFile C:\my.log   # custom log path (default: %TEMP%\jpg2pdf-logs\run-<timestamp>.log)

.NOTES
  Open a NEW terminal after install so PATH changes take effect.
  Every winget/git/pip/PyInstaller invocation is captured to the log file with
  full stdout/stderr; on failure the captured output is also printed to the
  console so you don't have to re-run to see it.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl     = "https://github.com/alimtvnetwork/img-pdf.git",
    [string]$InstallDir  = (Join-Path $HOME "Tools\jpg2pdf"),
    [string]$Branch      = "main",
    [switch]$NoCompile,
    [switch]$NoContextMenu,
    [switch]$Unregister,
    [switch]$Force,
    [switch]$Version,
    [switch]$SelfUpdate,
    [switch]$ShowVerbose,
    [string]$LogDir      = (Join-Path $env:TEMP "jpg2pdf-logs"),
    [string]$LogFile     = $null
)

$RunPs1Version = "0.2.0"

$ErrorActionPreference = "Stop"

# ---------- Logging ----------
$script:VerboseMode = [bool]$ShowVerbose -or ($VerbosePreference -ne 'SilentlyContinue')

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
function _Tag([string]$t,[ConsoleColor]$c){ Write-Host -NoNewline "[" -ForegroundColor DarkGray; Write-Host -NoNewline $t -ForegroundColor $c; Write-Host -NoNewline "] " -ForegroundColor DarkGray }
function Info($m){ _Log "INFO" $m; _Tag " ok " Green;   Write-Host $m -ForegroundColor Gray }
function Warn($m){ _Log "WARN" $m; _Tag "warn" Yellow;  Write-Host $m -ForegroundColor Yellow }
function Die ($m){ _Log "ERROR" $m; _Tag "fail" Red;    Write-Host $m -ForegroundColor Red
                   _Tag "fail" Red; Write-Host "Full log: $script:LogFile" -ForegroundColor DarkGray; exit 1 }
function Verb($m){ _Log "VERB" $m; if ($script:VerboseMode) { _Tag "dbg " DarkGray; Write-Host $m -ForegroundColor DarkGray } }

function Show-Banner {
    param([string]$Version)
    $line = ('-' * 60)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkGray
    Write-Host "   jpg2pdf installer" -NoNewline -ForegroundColor Magenta
    Write-Host "   v$Version" -ForegroundColor DarkGray
    Write-Host "   images -> PDF, with Explorer right-click integration" -ForegroundColor DarkGray
    Write-Host "  $line" -ForegroundColor DarkGray
    Write-Host ""
}
function Show-Section {
    param([int]$N,[int]$Total,[string]$Title)
    Write-Host ""
    Write-Host ("  [{0}/{1}] " -f $N,$Total) -NoNewline -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("  " + ('-' * (8 + $Title.Length))) -ForegroundColor DarkGray
}
function Show-Footer {
    Write-Host ""
    Write-Host ("  " + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host "   Installation complete." -ForegroundColor Green
    Write-Host "   Open a NEW terminal so PATH changes take effect." -ForegroundColor DarkGray
    Write-Host ("  " + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host ""
}

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

# ---------- Top-level crash handler ----------
# Catches ANY unhandled terminating error so the user sees a clean diagnosis
# (and the window doesn't disappear when run via double-click).
trap {
    $err = $_
    try { _Log "FATAL" (($err | Out-String).Trim()) } catch {}
    Write-Host ""
    Write-Host ("  " + ('=' * 60)) -ForegroundColor Red
    Write-Host "   jpg2pdf installer crashed" -ForegroundColor Red
    Write-Host ("  " + ('=' * 60)) -ForegroundColor Red
    Write-Host "  $($err.Exception.Message)" -ForegroundColor Yellow
    if ($err.InvocationInfo -and $err.InvocationInfo.PositionMessage) {
        Write-Host ""
        Write-Host $err.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    if ($script:LogFile) {
        Write-Host ""
        Write-Host "  Log file: $script:LogFile" -ForegroundColor DarkGray
        if (Test-Path -LiteralPath $script:LogFile) {
            Write-Host "  ----- last 40 log lines -----" -ForegroundColor DarkGray
            try {
                Get-Content -LiteralPath $script:LogFile -Tail 40 |
                    ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            } catch {}
            Write-Host "  -----------------------------" -ForegroundColor DarkGray
        }
        # Also drop a crash dump next to the script so it's easy to find.
        try {
            $dumpDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
            $dump = Join-Path $dumpDir "jpg2pdf-crash.log"
            $body = @(
                "jpg2pdf installer crash @ $(Get-Date -Format o)",
                ("PSVersion: " + $PSVersionTable.PSVersion),
                ("OS:        " + [Environment]::OSVersion.VersionString),
                "",
                "Message:",
                $err.Exception.Message,
                "",
                "Position:",
                ($err.InvocationInfo.PositionMessage),
                "",
                "Stack:",
                ($err.ScriptStackTrace),
                "",
                "Full log: $script:LogFile"
            ) -join "`r`n"
            Set-Content -LiteralPath $dump -Value $body -Encoding UTF8
            Write-Host "  Crash dump written to: $dump" -ForegroundColor Yellow
        } catch {}
    }
    Write-Host ("  " + ('=' * 60)) -ForegroundColor Red
    # Pause so a double-clicked window doesn't vanish.
    if ($Host.Name -eq 'ConsoleHost' -and -not $env:CI -and [Environment]::UserInteractive) {
        Write-Host ""
        Write-Host "  Press Enter to close..." -ForegroundColor Yellow
        try { [void](Read-Host) } catch {}
    }
    exit 1
}

Show-Banner -Version $RunPs1Version
Info "Log file: $script:LogFile"
if ($script:VerboseMode) { Info "Verbose mode ON" }

# Capture environment context up front - invaluable when debugging.
_Log "ENV " ("PSVersion={0} OS={1} User={2} CWD={3}" -f `
    $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, $env:USERNAME, (Get-Location).Path)

function Test-RealPython {
    param([string]$Path)
    if (-not $Path) { return $false }
    # Reject the Microsoft Store stub (returns exit 9009 and only opens the Store).
    if ($Path -match '\\WindowsApps\\') { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    # Probe: a real interpreter prints its version; the stub does not.
    try {
        $out = & $Path --version 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        return ($out -match '^Python\s+\d')
    } catch { return $false }
}

function Get-Python {
    # 1) py launcher (preferred - picks the latest installed real Python).
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        try {
            $real = & $pyLauncher.Source -3 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $real -and (Test-RealPython $real)) { return $real }
        } catch {}
    }

    # 2) Any python.exe on PATH that isn't the WindowsApps stub.
    $candidates = Get-Command python.exe -All -ErrorAction SilentlyContinue
    foreach ($c in $candidates) {
        if (Test-RealPython $c.Source) { return $c.Source }
    }

    # 3) Common install locations.
    $patterns = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "C:\Python3*\python.exe",
        "C:\Program Files\Python3*\python.exe",
        "C:\Program Files (x86)\Python3*\python.exe"
    )
    foreach ($pat in $patterns) {
        $hit = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit -and (Test-RealPython $hit.FullName)) { return $hit.FullName }
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

# ---------- Helpers: versions, build-stamp ----------
$script:BinDir   = Join-Path $HOME "Tools\bin"
$script:ExePath  = Join-Path $script:BinDir "jpg2pdf.exe"
$script:ShimPath = Join-Path $script:BinDir "jpg2pdf.cmd"
$script:StampPath= Join-Path $script:BinDir "jpg2pdf.buildstamp.json"

function Get-RepoVersion {
    param([string]$Root)
    $vf = Join-Path $Root "tools\jpg2pdf\VERSION"
    if (Test-Path -LiteralPath $vf) { return (Get-Content -LiteralPath $vf -Raw).Trim() }
    return "unknown"
}
function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Get-InstalledExeVersion {
    if (-not (Test-Path -LiteralPath $script:ExePath)) { return $null }
    try {
        $tmp = [IO.Path]::GetTempFileName()
        & $script:ExePath --version 2>&1 | Set-Content -LiteralPath $tmp
        $line = (Get-Content -LiteralPath $tmp -Raw).Trim()
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        return $line
    } catch { return "(failed to query exe: $_)" }
}
function Read-BuildStamp {
    if (-not (Test-Path -LiteralPath $script:StampPath)) { return $null }
    try { return Get-Content -LiteralPath $script:StampPath -Raw | ConvertFrom-Json } catch { return $null }
}
function Write-BuildStamp {
    param([hashtable]$Data)
    $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:StampPath -Encoding UTF8
}
function Compute-CurrentStamp {
    param([string]$Root)
    @{
        version    = Get-RepoVersion $Root
        srcSha256  = Get-FileSha256 (Join-Path $Root "tools\jpg2pdf\src\jpg2pdf.py")
        reqsSha256 = Get-FileSha256 (Join-Path $Root "tools\jpg2pdf\requirements.txt")
        builtAt    = (Get-Date).ToString("o")
        runPs1     = $RunPs1Version
    }
}

# ---------- -Version short-circuit ----------
if ($Version) {
    $repoVer = if ($localRepo) { Get-RepoVersion $localRepo } elseif (Test-Path $InstallDir) { Get-RepoVersion $InstallDir } else { "(no repo)" }
    Write-Host "run.ps1   : $RunPs1Version"
    Write-Host "repo      : $repoVer"
    $exeVer = Get-InstalledExeVersion
    Write-Host "installed : $(if ($exeVer) { $exeVer } else { '(not installed)' })"
    $stamp = Read-BuildStamp
    if ($stamp) {
        Write-Host "build     : $($stamp.version)  built $($stamp.builtAt)"
        Write-Host "src sha   : $($stamp.srcSha256)"
    }
    Write-Host "exe path  : $script:ExePath"
    exit 0
}

# ---------- -Unregister short-circuit ----------
if ($Unregister) {
    $unreg = Join-Path $InstallDir "tools\jpg2pdf\scripts\unregister-context-menu.ps1"
    if (-not (Test-Path $unreg)) { Die "Missing $unreg" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $unreg
    exit $LASTEXITCODE
}

Show-Section 1 7 "Python"
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

Show-Section 2 7 "Git"
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

Show-Section 3 7 "Pull / clone repo"
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

Show-Section 4 7 "Python dependencies"
Info "Installing Python dependencies..."
# Drop --quiet so log captures real pip output for troubleshooting.
$pipArgs = @("-m","pip","install","--user","--upgrade","--disable-pip-version-check","-r",$reqsFile)
if ($script:VerboseMode) { $pipArgs += "--verbose" }
Invoke-Logged -Label "pip install -r requirements.txt" -FilePath $py -ArgumentList $pipArgs

Show-Section 5 7 "Compile (PyInstaller) or shim"
$binDir = $script:BinDir
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$exePath  = $script:ExePath
$shimPath = $script:ShimPath
$entryPath = $null

# Compute current vs cached build stamp.
$currentStamp = Compute-CurrentStamp $InstallDir
$lastStamp    = Read-BuildStamp
$stampChanged = $true
if ($lastStamp) {
    $stampChanged = -not (
        $lastStamp.version    -eq $currentStamp.version    -and
        $lastStamp.srcSha256  -eq $currentStamp.srcSha256  -and
        $lastStamp.reqsSha256 -eq $currentStamp.reqsSha256
    )
}
Verb ("Stamp: repoVer={0} srcSha={1}... reqsSha={2}... cached={3}" -f `
      $currentStamp.version, $currentStamp.srcSha256.Substring(0,8),
      $currentStamp.reqsSha256.Substring(0,8),
      $(if ($lastStamp) { 'yes' } else { 'no' }))

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
    $needBuild = $Force -or (-not (Test-Path $exePath)) -or $stampChanged
    if (-not $needBuild) {
        Info ("jpg2pdf.exe up to date (v{0}). Use -Force to rebuild." -f $currentStamp.version)
    } else {
        if ($SelfUpdate -and $lastStamp) {
            Info ("Change detected ({0} -> {1}). Rebuilding..." -f $lastStamp.version, $currentStamp.version)
        }

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

        Write-BuildStamp $currentStamp
        Info ("Built: {0}  (v{1})" -f $exePath, $currentStamp.version)
    }
    $entryPath = $exePath
}

# When -SelfUpdate is used and nothing changed, skip context-menu re-registration.
if ($SelfUpdate -and -not $stampChanged -and -not $Force) {
    Verb "SelfUpdate: no changes - skipping PATH/context-menu steps."
    Info "Already up to date."
    Info "Full session log: $script:LogFile"
    exit 0
}

Show-Section 6 7 "Persist on User PATH"
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

Show-Section 7 7 "Explorer context menu"
if (-not $NoContextMenu) {
    if (-not (Test-Path $regScript)) {
        Warn "Missing $regScript - skipping context-menu registration."
    } else {
        Info "Registering Explorer context menu..."
        Invoke-Logged -Label "register context menu" -FilePath "powershell" `
            -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$regScript,"-ExePath",$entryPath)
    }
}

Show-Footer
Write-Host "  Try it:" -ForegroundColor Yellow
Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
Write-Host "    jpg2pdf . --size letter --fit cover --out album.pdf" -ForegroundColor Green
Write-Host "    jpg2pdf . --size legal --orientation landscape --recursive" -ForegroundColor Green
Write-Host ""
Write-Host "  Right-click a folder, folder background, or selected images:" -ForegroundColor Yellow
Write-Host "    Images to PDF  >  Convert All / Selected to A4 / Letter / Legal" -ForegroundColor Green
Write-Host ""
Write-Host ("  Full session log: {0}" -f $script:LogFile) -ForegroundColor DarkGray
Write-Host ""
