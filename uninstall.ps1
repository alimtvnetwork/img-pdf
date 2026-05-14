<#
.SYNOPSIS
  Uninstall jpg2pdf:
    - Unregisters Explorer context menu (HKCU)
    - Deletes jpg2pdf.exe / jpg2pdf.cmd from the bin folder
    - Removes the bin folder from User PATH (only if empty after cleanup)
    - Optionally removes the cloned repo (-RemoveRepo)

.USAGE
  .\uninstall.ps1
  .\uninstall.ps1 -RemoveRepo
  .\uninstall.ps1 -BinDir "$HOME\Tools\bin" -InstallDir "$HOME\Tools\jpg2pdf"

.NOTES
  Open a NEW terminal afterwards for PATH changes to take effect.
  A backup of the previous PATH (if any) is kept in env var PathBackup_jpg2pdf.
#>
[CmdletBinding()]
param(
    [string]$BinDir     = (Join-Path $HOME "Tools\bin"),
    [string]$InstallDir = (Join-Path $HOME "Tools\jpg2pdf"),
    [switch]$RemoveRepo
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[uninstall] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[uninstall] $m" -ForegroundColor Yellow }
function OK  ($m){ Write-Host "[uninstall] $m" -ForegroundColor Green }

# ---------- 1. Unregister Explorer context menu ----------
$unreg = Join-Path $InstallDir "tools\jpg2pdf\scripts\unregister-context-menu.ps1"
if (Test-Path $unreg) {
    Info "Removing Explorer context menu..."
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $unreg
    } catch { Warn "Context-menu cleanup failed: $_" }
} else {
    Warn "Unregister script not found ($unreg). Skipping context-menu cleanup."
}

# ---------- 2. Delete the exe / shim ----------
$targets = @(
    (Join-Path $BinDir "jpg2pdf.exe"),
    (Join-Path $BinDir "jpg2pdf.cmd")
)
foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) {
        try {
            Remove-Item -LiteralPath $t -Force
            OK "Deleted $t"
        } catch {
            Warn "Could not delete $t : $_  (is jpg2pdf still running?)"
        }
    }
}

# ---------- 3. PATH cleanup ----------
function Remove-FromUserPath {
    param([Parameter(Mandatory=$true)][string]$Dir)

    $resolved = $Dir.TrimEnd('\')
    $current  = [Environment]::GetEnvironmentVariable("Path","User")
    if (-not $current) { Info "User PATH is empty - nothing to clean."; return }

    $cmp = [System.StringComparer]::OrdinalIgnoreCase
    $seen    = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
    $cleaned = New-Object 'System.Collections.Generic.List[string]'
    $removed = $false

    foreach ($entry in $current.Split(';')) {
        $e = $entry.Trim().TrimEnd('\')
        if (-not $e) { continue }
        if ([string]::Equals($e, $resolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $removed = $true
            continue
        }
        if ($seen.Add($e)) { [void]$cleaned.Add($e) }
    }

    if (-not $removed) {
        Info "$resolved was not on User PATH."
        return
    }

    # Back up previous PATH before mutating.
    try {
        [Environment]::SetEnvironmentVariable("PathBackup_jpg2pdf", $current, "User")
    } catch { Warn "Could not write PATH backup: $_" }

    try {
        [Environment]::SetEnvironmentVariable("Path", ($cleaned -join ';'), "User")
        OK "Removed $resolved from User PATH (backup in env var 'PathBackup_jpg2pdf')."
    } catch {
        Warn "Failed to update User PATH: $_"
    }

    # Update current session too.
    $sess = $env:Path.Split(';') |
        Where-Object { $_.Trim() -and -not [string]::Equals($_.Trim().TrimEnd('\'), $resolved, [System.StringComparison]::OrdinalIgnoreCase) }
    $env:Path = ($sess -join ';')
}

# Only remove the bin folder from PATH if it no longer holds anything we care about.
# (User may have other tools in the same folder - don't yank PATH out from under them.)
$shouldRemove = $true
if (Test-Path -LiteralPath $BinDir) {
    $remaining = Get-ChildItem -LiteralPath $BinDir -File -ErrorAction SilentlyContinue
    if ($remaining -and $remaining.Count -gt 0) {
        Warn "Bin folder still contains other files - leaving it on PATH:"
        $remaining | ForEach-Object { Write-Host "    $($_.Name)" }
        $shouldRemove = $false
    }
}
if ($shouldRemove) {
    Remove-FromUserPath -Dir $BinDir
    if ((Test-Path -LiteralPath $BinDir) -and -not (Get-ChildItem -LiteralPath $BinDir -Force)) {
        try { Remove-Item -LiteralPath $BinDir -Force; OK "Removed empty bin folder $BinDir" }
        catch { Warn "Could not remove $BinDir : $_" }
    }
}

# ---------- 4. Optional: remove the cloned repo ----------
if ($RemoveRepo) {
    if (Test-Path -LiteralPath $InstallDir) {
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
            OK "Removed repo $InstallDir"
        } catch { Warn "Could not remove $InstallDir : $_" }
    } else {
        Info "Repo folder $InstallDir does not exist."
    }
} else {
    Info "Repo left in place at $InstallDir (use -RemoveRepo to delete)."
}

OK "Uninstall complete. Open a NEW terminal for PATH changes to take effect."
