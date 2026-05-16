<#
.SYNOPSIS
  Register Windows Explorer context-menu entries for jpg2pdf.

.PARAMETER ExePath
  Full path to jpg2pdf.exe (or jpg2pdf.cmd shim) used by all menu entries.

.NOTES
  Writes only to HKCU - no admin required.
  Uses MultiSelectModel=Player so multi-select invokes the verb ONCE with
  all selected files as arguments (preserves selection order).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$ExePath
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ExePath)) { Write-Error "Not found: $ExePath"; exit 1 }
$exe = (Resolve-Path $ExePath).Path
$script:SelectedLauncherPath = Join-Path (Split-Path -Parent $exe) "jpg2pdf-selected-launcher.ps1"
$script:SelectedLauncherVbsPath = Join-Path (Split-Path -Parent $exe) "jpg2pdf-selected-launcher.vbs"

function Write-SelectedFilesLauncher {
    param([Parameter(Mandatory=$true)][string]$Path)

    $content = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExePath,
    [Parameter(Mandatory=$true)][ValidateSet("a4","letter","legal")][string]$Size,
    [string]$Style = "",
    [int]$Rotate = -1,
    [switch]$NoAutoRotate,
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)][string[]]$FilePath
)

$ErrorActionPreference = "Stop"

function Get-SafeHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function Quote-CmdArg([string]$Text) {
    return '"' + ($Text -replace '"','""') + '"'
}

$paths = @()
foreach ($raw in $FilePath) {
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try { $paths += (Resolve-Path -LiteralPath $raw).Path } catch { $paths += $raw }
    }
}
$paths = $paths | Select-Object -Unique
if (-not $paths -or -not (Test-Path -LiteralPath $ExePath)) { exit 1 }

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
# Group by the selected action, not by the first file path. Explorer can invoke
# legacy file verbs once per selected file, and mixed-folder selections otherwise
# split into several batches. The queue below coalesces those invocations into
# one visible terminal and one jpg2pdf run.
$keySource = "$sid|selected|$Size|$Style|$Rotate|$([bool]$NoAutoRotate)"
$key = Get-SafeHash $keySource
$queueRoot = Join-Path $env:TEMP "jpg2pdf-selected-queue"
New-Item -ItemType Directory -Force -Path $queueRoot | Out-Null

$stateFile = Join-Path $queueRoot "$key.state"
$queueFile = Join-Path $queueRoot "$key.queue"
$mutexName = "Local\jpg2pdf-selected-$key"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$leader = $false

try {
    [void]$mutex.WaitOne(10000)
    $stale = $true
    if (Test-Path -LiteralPath $stateFile) {
        $age = (Get-Date) - (Get-Item -LiteralPath $stateFile).LastWriteTime
        $stale = $age.TotalSeconds -gt 8
    }
    if ($stale) {
        Set-Content -LiteralPath $stateFile -Value ([Diagnostics.Process]::GetCurrentProcess().Id) -Encoding ASCII
        $leader = $true
    }
    Add-Content -LiteralPath $queueFile -Value $paths -Encoding UTF8
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}

if (-not $leader) { exit 0 }

$deadline = (Get-Date).AddSeconds(15)
$quietFor = [TimeSpan]::FromMilliseconds(1800)
do {
    Start-Sleep -Milliseconds 300
    $lastWrite = if (Test-Path -LiteralPath $queueFile) { (Get-Item -LiteralPath $queueFile).LastWriteTimeUtc } else { [DateTime]::UtcNow }
    $quiet = ([DateTime]::UtcNow - $lastWrite) -ge $quietFor
} while (-not $quiet -and (Get-Date) -lt $deadline)

$mutex = New-Object System.Threading.Mutex($false, $mutexName)
try {
    [void]$mutex.WaitOne(10000)
    $all = @()
    if (Test-Path -LiteralPath $queueFile) {
        $all = Get-Content -LiteralPath $queueFile -Encoding UTF8 | Where-Object { $_ } | Select-Object -Unique
    }
    Remove-Item -LiteralPath $stateFile,$queueFile -Force -ErrorAction SilentlyContinue
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}

if (-not $all -or $all.Count -eq 0) { exit 0 }

$firstDir = Split-Path -Parent $all[0]

$listFile = Join-Path $queueRoot ("files-" + $key + "-" + [Guid]::NewGuid().ToString("N") + ".txt")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($listFile, [string[]]$all, $utf8NoBom)

$cmdFile = Join-Path $queueRoot ("run-" + $key + "-" + [Guid]::NewGuid().ToString("N") + ".cmd")
$args = @("--size", $Size)
if ($Rotate -ge 0) { $args += @("--rotate", [string]$Rotate) }
if ($NoAutoRotate) { $args += "--no-auto-rotate" }
if ($Style) { $args += @("--style", $Style) }
if ($Style -eq "pencil") { $args += "--ask-strength" }
$args += @("--files-from", $listFile)
$quotedArgs = ($args | ForEach-Object { Quote-CmdArg ([string]$_) }) -join " "

$cmd = @(
    "@echo off",
    "title jpg2pdf selected files",
    "echo [jpg2pdf] Combining $($all.Count) selected image(s)...",
    "echo [jpg2pdf] Output will be written next to the first selected image.",
    ((Quote-CmdArg $ExePath) + " " + $quotedArgs),
    'set "code=%ERRORLEVEL%"',
    'if not "%code%"=="0" (',
    '  echo.',
    '  echo [jpg2pdf] Failed with exit code %code%.',
    '  pause',
    ')',
    ('del /q ' + (Quote-CmdArg $listFile) + ' >nul 2>nul'),
    'del /q "%~f0" >nul 2>nul',
    'exit /b %code%'
)
$cmd | Set-Content -LiteralPath $cmdFile -Encoding ASCII
Start-Process -FilePath $cmdFile -WorkingDirectory $firstDir
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Write-SelectedFilesVbsLauncher {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$PowerShellLauncherPath
    )

    $escapedLauncher = $PowerShellLauncherPath.Replace('"', '""')
    $content = @"
Dim shell, i, cmd
Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$escapedLauncher"""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & " " & QuoteArg(WScript.Arguments(i))
Next
shell.Run cmd, 0, False

Function QuoteArg(value)
  QuoteArg = """" & Replace(value, """", """""") & """"
End Function
"@
    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function New-Key($path) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
}
function Set-Val($path, $name, $value, $type = "String") {
    New-Key $path
    if ($name -eq "(Default)" -or $name -eq "") {
        Set-ItemProperty -Path $path -Name "(default)" -Value $value
    } else {
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
    }
}

# ---------------------------------------------------------------
# Helper: register a parent "Combine into PDF" entry with a submenu
# at the given root (Directory, Directory\Background, or per-ext).
# ---------------------------------------------------------------
function Register-Parent {
    param(
        [string]$Root,                # e.g. HKCU:\Software\Classes\Directory\shell
        [string]$Mode,                # 'Folder' | 'Files'
        [string]$Ext = $null          # only used when targeting a file class
    )

    $parent = "$Root\Jpg2PdfMenu"
    Set-Val $parent "(Default)" "Combine into PDF"
    Set-Val $parent "MUIVerb"    "Combine into PDF"
    Set-Val $parent "Icon"       $exe
    Set-Val $parent "SubCommands" ""   # required when using ExtendedSubCommandsKey
    # Use ExtendedSubCommandsKey so children live in a clean subtree:
    New-ItemProperty -Path $parent -Name "ExtendedSubCommandsKey" `
        -Value "Jpg2Pdf.Menu" -PropertyType String -Force | Out-Null
}

# Build the shared submenu under HKCU\Software\Classes\Jpg2Pdf.Menu\shell\*
function Register-SubItems {
    param([string]$Mode)  # 'Folder' or 'Files'

    $base = "HKCU:\Software\Classes\Jpg2Pdf.Menu\shell"
    New-Key $base

    function Add-Item {
        param([string]$Id, [string]$Label, [string]$Args, [int]$Pos)
        $k = "$base\$Id"
        Set-Val $k "(Default)" $Label
        Set-Val $k "MUIVerb"   $Label
        Set-Val $k "Icon"      $exe
        Set-Val $k "Position"  "Bottom"
        $cmd = "$k\command"
        New-Key $cmd
        Set-ItemProperty -Path $cmd -Name "(default)" `
            -Value ('"' + $exe + '" ' + $Args)
    }

    if ($Mode -eq 'Folder') {
        Add-Item "01_A4"        "Convert All to A4"               '--size a4 "%V"'      1
        Add-Item "02_Letter"    "Convert All to Letter"           '--size letter "%V"'  2
        Add-Item "03_Legal"     "Convert All to Legal"            '--size legal "%V"'   3
        Add-Item "04_A4_R"      "Convert All to A4 (recursive)"   '--size a4 --recursive "%V"' 4
    }
    elseif ($Mode -eq 'Files') {
        # MultiSelectModel=Player -> %* expands to ALL selected file paths.
        Add-Item "11_A4"     "Convert Selected to A4"     '--size a4 --files %*'     1
        Add-Item "12_Letter" "Convert Selected to Letter" '--size letter --files %*' 2
        Add-Item "13_Legal"  "Convert Selected to Legal"  '--size legal --files %*'  3
    }
}

Write-Host "[ctx] Registering context menu (HKCU)..." -ForegroundColor Cyan
Write-SelectedFilesLauncher -Path $script:SelectedLauncherPath
Write-SelectedFilesVbsLauncher -Path $script:SelectedLauncherVbsPath -PowerShellLauncherPath $script:SelectedLauncherPath

# Build BOTH submenus into the same shared key (folder + file items live
# together; harmless duplicates won't show because each parent links here).
# To keep folder vs file entries distinct, we use TWO shared submenu roots:
#   Jpg2Pdf.FolderMenu  and  Jpg2Pdf.FilesMenu
# Re-implement Register-SubItems to take a target key:

function Build-Submenu {
    param([string]$ClassName, [string]$Mode)
    $base = "HKCU:\Software\Classes\$ClassName\shell"
    # wipe & rebuild for idempotency
    if (Test-Path "HKCU:\Software\Classes\$ClassName") {
        Remove-Item "HKCU:\Software\Classes\$ClassName" -Recurse -Force
    }
    New-Key $base

    function _add($Id, $Label, $ArgsLine, [switch]$MultiSelect, [switch]$RawCommand) {
        $k = "$base\$Id"
        New-Key $k
        Set-ItemProperty -Path $k -Name "(default)" -Value $Label
        New-ItemProperty -Path $k -Name "MUIVerb" -Value $Label -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $k -Name "Icon"    -Value $exe   -PropertyType String -Force | Out-Null
        # CRITICAL: MultiSelectModel must live on each LEAF verb when using
        # ExtendedSubCommandsKey. Without it, Explorer invokes the verb once
        # PER selected file (N consoles, N broken commands).
        if ($MultiSelect) {
            New-ItemProperty -Path $k -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
        }
        New-Key "$k\command"
        $commandLine = if ($RawCommand) { $ArgsLine } else { ('"' + $exe + '" ' + $ArgsLine) }
        Set-ItemProperty -Path "$k\command" -Name "(default)" `
            -Value $commandLine
    }

    if ($Mode -eq 'Folder') {
        _add "01_A4"      "Convert All to A4"                       '--size a4 "%V"'
        _add "02_Letter"  "Convert All to Letter"                   '--size letter "%V"'
        _add "03_Legal"   "Convert All to Legal"                    '--size legal "%V"'
        _add "04_A4_R"    "Convert All to A4 (recursive)"           '--size a4 --recursive "%V"'
        _add "05_A4_CW"   "Convert All to A4 (rotate 90 CW)"        '--size a4 --rotate 270 "%V"'
        _add "06_A4_CCW"  "Convert All to A4 (rotate 90 CCW)"       '--size a4 --rotate 90  "%V"'
        _add "07_A4_180"  "Convert All to A4 (rotate 180)"          '--size a4 --rotate 180 "%V"'
        _add "08_A4_NOAR"   "Convert All to A4 (no auto-rotate)"      '--size a4 --no-auto-rotate "%V"'
        _add "09_A4_PENCIL" "Convert All to A4 (pencil / paper look)" '--size a4 --style pencil --ask-strength "%V"'
    } else {
        # Direct cmd.exe invocation: opens a visible console, runs jpg2pdf
        # once on all selected files (MultiSelectModel=Player on each leaf),
        # and pauses on non-zero exit so users can read errors. No VBS/launcher
        # indirection — that chain silently failed on some hosts (ExecutionPolicy
        # GPO, AV blocking temp .cmd, hidden Start-Process not surfacing a console)
        # which made "nothing happen" when clicking the menu.
        $prefix = 'cmd.exe /c "title jpg2pdf & "' + $exe + '"'
        $suffix = ' & if errorlevel 1 pause"'
        _add "11_A4"        "Combine into PDF (A4)"                         ($prefix + ' --size a4 --files %*' + $suffix)                             -MultiSelect -RawCommand
        _add "12_Letter"    "Combine into PDF (Letter)"                     ($prefix + ' --size letter --files %*' + $suffix)                         -MultiSelect -RawCommand
        _add "13_Legal"     "Combine into PDF (Legal)"                      ($prefix + ' --size legal --files %*' + $suffix)                          -MultiSelect -RawCommand
        _add "15_A4_CW"     "Combine into PDF (A4, rotate 90 CW)"           ($prefix + ' --size a4 --rotate 270 --files %*' + $suffix)                -MultiSelect -RawCommand
        _add "16_A4_CCW"    "Combine into PDF (A4, rotate 90 CCW)"          ($prefix + ' --size a4 --rotate 90 --files %*' + $suffix)                 -MultiSelect -RawCommand
        _add "17_A4_180"    "Combine into PDF (A4, rotate 180)"             ($prefix + ' --size a4 --rotate 180 --files %*' + $suffix)                -MultiSelect -RawCommand
        _add "18_A4_NOAR"   "Combine into PDF (A4, no auto-rotate)"         ($prefix + ' --size a4 --no-auto-rotate --files %*' + $suffix)            -MultiSelect -RawCommand
        _add "19_A4_PENCIL" "Combine into PDF (A4, pencil / paper look)"    ($prefix + ' --size a4 --style pencil --ask-strength --files %*' + $suffix) -MultiSelect -RawCommand
    }
}

# Override the earlier helper that referenced a single shared key:
function Register-ParentV2 {
    param([string]$Root, [string]$ClassName)
    $parent = "$Root\Jpg2PdfMenu"
    if (Test-Path $parent) { Remove-Item $parent -Recurse -Force }
    New-Key $parent
    Set-ItemProperty -Path $parent -Name "(default)" -Value "Combine into PDF"
    New-ItemProperty -Path $parent -Name "MUIVerb"  -Value "Combine into PDF" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $parent -Name "Icon"     -Value $exe            -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $parent -Name "SubCommands" -Value "" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $parent -Name "ExtendedSubCommandsKey" `
        -Value $ClassName -PropertyType String -Force | Out-Null
}

# ---- Build the two submenu trees ----
Build-Submenu -ClassName "Jpg2Pdf.FolderMenu" -Mode 'Folder'
Build-Submenu -ClassName "Jpg2Pdf.FilesMenu"  -Mode 'Files'

# ---- Hook them onto Explorer surfaces ----
# Folders (right-click ON a folder)
Register-ParentV2 "HKCU:\Software\Classes\Directory\shell" "Jpg2Pdf.FolderMenu"
# Folder background (right-click INSIDE a folder)
Register-ParentV2 "HKCU:\Software\Classes\Directory\Background\shell" "Jpg2Pdf.FolderMenu"

# Image file extensions (right-click ON selected images)
$exts = @(".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff",
          ".pdf", ".html", ".htm", ".docx", ".doc")
foreach ($ext in $exts) {
    # Remove older direct file verbs first. If left behind, Explorer may show
    # duplicate entries and run the old per-file command, which opens one
    # terminal per selected image.
    $legacyRoots = @("HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\Jpg2PdfMenu")
    $oldProgId = (Get-ItemProperty -Path "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue)."(default)"
    if (-not $oldProgId) {
        $oldProgId = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$ext" -ErrorAction SilentlyContinue)."(default)"
    }
    if ($oldProgId) { $legacyRoots += "HKCU:\Software\Classes\$oldProgId\shell\Jpg2PdfMenu" }
    foreach ($legacyRoot in $legacyRoots) {
        if (Test-Path $legacyRoot) { Remove-Item $legacyRoot -Recurse -Force }
    }

    # Resolve the ProgID for this extension; fall back to SystemFileAssociations
    $progId = (Get-ItemProperty -Path "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue)."(default)"
    if (-not $progId) {
        $progId = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$ext" -ErrorAction SilentlyContinue)."(default)"
    }
    $targets = @("HKCU:\Software\Classes\SystemFileAssociations\$ext\shell")
    if ($progId) { $targets += "HKCU:\Software\Classes\$progId\shell" }

    foreach ($root in $targets) {
        Register-ParentV2 $root "Jpg2Pdf.FilesMenu"
        # MultiSelectModel is set on each LEAF verb inside Build-Submenu -
        # setting it here on the parent has no effect when ExtendedSubCommandsKey is used.
    }
}

Write-Host "[ctx] Done. Right-click any folder, folder background, or image file." -ForegroundColor Green
Write-Host "[ctx] If entries don't appear immediately, restart Explorer:" -ForegroundColor Yellow
Write-Host "      Stop-Process -Name explorer -Force; Start-Process explorer" -ForegroundColor Yellow
