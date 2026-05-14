<#
.SYNOPSIS
  Register Windows Explorer context-menu entries for jpg2pdf.

.PARAMETER ExePath
  Full path to jpg2pdf.exe (or jpg2pdf.cmd shim) used by all menu entries.

.NOTES
  Writes only to HKCU — no admin required.
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
# Helper: register a parent "Images to PDF" entry with a submenu
# at the given root (Directory, Directory\Background, or per-ext).
# ---------------------------------------------------------------
function Register-Parent {
    param(
        [string]$Root,                # e.g. HKCU:\Software\Classes\Directory\shell
        [string]$Mode,                # 'Folder' | 'Files'
        [string]$Ext = $null          # only used when targeting a file class
    )

    $parent = "$Root\Jpg2PdfMenu"
    Set-Val $parent "(Default)" "Images to PDF"
    Set-Val $parent "MUIVerb"    "Images to PDF"
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
        # MultiSelectModel=Player → %* expands to ALL selected file paths.
        Add-Item "11_A4"     "Convert Selected to A4"     '--size a4 --files %*'     1
        Add-Item "12_Letter" "Convert Selected to Letter" '--size letter --files %*' 2
        Add-Item "13_Legal"  "Convert Selected to Legal"  '--size legal --files %*'  3
    }
}

Write-Host "[ctx] Registering context menu (HKCU)..." -ForegroundColor Cyan

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

    function _add($Id, $Label, $ArgsLine, [switch]$MultiSelect) {
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
        Set-ItemProperty -Path "$k\command" -Name "(default)" `
            -Value ('"' + $exe + '" ' + $ArgsLine)
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
        _add "09_A4_PENCIL" "Convert All to A4 (pencil / paper look)" '--size a4 --style pencil "%V"'
    } else {
        # Explorer (with MultiSelectModel=Player) invokes the verb ONCE and
        # appends every selected path as a separate quoted argument after %1.
        # %* is a cmd.exe-only token and is passed literally here — never use it.
        _add "11_A4"        "Convert Selected to A4"                       '--size a4 --files "%1"'                       -MultiSelect
        _add "12_Letter"    "Convert Selected to Letter"                   '--size letter --files "%1"'                   -MultiSelect
        _add "13_Legal"     "Convert Selected to Legal"                    '--size legal --files "%1"'                    -MultiSelect
        _add "15_A4_CW"     "Convert Selected to A4 (rotate 90 CW)"        '--size a4 --rotate 270 --files "%1"'          -MultiSelect
        _add "16_A4_CCW"    "Convert Selected to A4 (rotate 90 CCW)"       '--size a4 --rotate 90  --files "%1"'          -MultiSelect
        _add "17_A4_180"    "Convert Selected to A4 (rotate 180)"          '--size a4 --rotate 180 --files "%1"'          -MultiSelect
        _add "18_A4_NOAR"   "Convert Selected to A4 (no auto-rotate)"      '--size a4 --no-auto-rotate --files "%1"'      -MultiSelect
        _add "19_A4_PENCIL" "Convert Selected to A4 (pencil / paper look)" '--size a4 --style pencil --files "%1"'        -MultiSelect
    }
}

# Override the earlier helper that referenced a single shared key:
function Register-ParentV2 {
    param([string]$Root, [string]$ClassName)
    $parent = "$Root\Jpg2PdfMenu"
    if (Test-Path $parent) { Remove-Item $parent -Recurse -Force }
    New-Key $parent
    Set-ItemProperty -Path $parent -Name "(default)" -Value "Images to PDF"
    New-ItemProperty -Path $parent -Name "MUIVerb"  -Value "Images to PDF" -PropertyType String -Force | Out-Null
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
$exts = @(".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff")
foreach ($ext in $exts) {
    # Resolve the ProgID for this extension; fall back to SystemFileAssociations
    $progId = (Get-ItemProperty -Path "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue)."(default)"
    if (-not $progId) {
        $progId = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$ext" -ErrorAction SilentlyContinue)."(default)"
    }
    $targets = @("HKCU:\Software\Classes\SystemFileAssociations\$ext\shell")
    if ($progId) { $targets += "HKCU:\Software\Classes\$progId\shell" }

    foreach ($root in $targets) {
        Register-ParentV2 $root "Jpg2Pdf.FilesMenu"
        # MultiSelectModel is set on each LEAF verb inside Build-Submenu —
        # setting it here on the parent has no effect when ExtendedSubCommandsKey is used.
    }
}

Write-Host "[ctx] Done. Right-click any folder, folder background, or image file." -ForegroundColor Green
Write-Host "[ctx] If entries don't appear immediately, restart Explorer:" -ForegroundColor Yellow
Write-Host "      Stop-Process -Name explorer -Force; Start-Process explorer" -ForegroundColor Yellow
