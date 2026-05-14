<#
.SYNOPSIS
  One-liner installer for jpg2pdf on Windows (no clone, no Python required).

.USAGE
  irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex

  # Pin a specific version:
  $env:JPG2PDF_VERSION = "v0.5.0"; irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex

  # Skip Explorer context-menu registration:
  $env:JPG2PDF_NO_CONTEXT_MENU = "1"; irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex

.WHAT IT DOES
  1. Resolves the latest GitHub Release (or $env:JPG2PDF_VERSION).
  2. Downloads jpg2pdf-windows-x64.exe to $HOME\Tools\bin\jpg2pdf.exe.
  3. Adds that folder to your User PATH (persistent, no admin).
  4. Downloads + runs register-context-menu.ps1 from the same tag (unless disabled).
#>
[CmdletBinding()]
param(
    [string]$Repo    = $(if ($env:JPG2PDF_REPO)    { $env:JPG2PDF_REPO }    else { "OWNER/REPO" }),
    [string]$Version = $(if ($env:JPG2PDF_VERSION) { $env:JPG2PDF_VERSION } else { "" }),
    [switch]$NoContextMenu
)

$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "[jpg2pdf] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[jpg2pdf] $m" -ForegroundColor Yellow }
function Die ($m) { Write-Host "[jpg2pdf] $m" -ForegroundColor Red; exit 1 }

if ($env:JPG2PDF_NO_CONTEXT_MENU -eq "1") { $NoContextMenu = $true }
if ($Repo -eq "OWNER/REPO") {
    Die "Set the repo: `$env:JPG2PDF_REPO = 'your-user/your-repo'  (or edit install.ps1)."
}

# Resolve tag (latest release if none specified).
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ "User-Agent" = "jpg2pdf-installer" }
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

if (-not $Version) {
    Info "Resolving latest release of $Repo ..."
    try {
        $rel = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/latest"
        $Version = $rel.tag_name
    } catch {
        Die "Could not query GitHub releases for $Repo : $_"
    }
}
Info "Installing jpg2pdf $Version"

$asset   = "jpg2pdf-windows-x64.exe"
$dlUrl   = "https://github.com/$Repo/releases/download/$Version/$asset"
$binDir  = Join-Path $HOME "Tools\bin"
$exePath = Join-Path $binDir "jpg2pdf.exe"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Info "Downloading $dlUrl"
try {
    Invoke-WebRequest -Headers $headers -Uri $dlUrl -OutFile $exePath -UseBasicParsing
} catch {
    Die "Download failed: $_"
}

# Sanity check
try {
    $verLine = & $exePath --version 2>&1
    Info "Installed: $verLine -> $exePath"
} catch {
    Warn "Binary downloaded but --version failed: $_"
}

# Persist on User PATH
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $current) { $current = "" }
$entries = $current.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ }
$resolved = (Resolve-Path $binDir).Path.TrimEnd('\')
if ($entries -notcontains $resolved) {
    [Environment]::SetEnvironmentVariable("Path", (($entries + $resolved) -join ';'), "User")
    Info "Added $resolved to User PATH (open a new terminal to pick it up)."
} else {
    Info "$resolved already on User PATH."
}
if (($env:Path.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') }) -notcontains $resolved) {
    $env:Path = "$($env:Path.TrimEnd(';'));$resolved"
}

# Optional: Explorer context menu (download + run the script from the same tag)
if (-not $NoContextMenu) {
    $ctxUrl  = "https://raw.githubusercontent.com/$Repo/$Version/tools/jpg2pdf/scripts/register-context-menu.ps1"
    $ctxFile = Join-Path $env:TEMP "jpg2pdf-register-context-menu.ps1"
    try {
        Info "Fetching context-menu registrar from $ctxUrl"
        Invoke-WebRequest -Headers $headers -Uri $ctxUrl -OutFile $ctxFile -UseBasicParsing
        & powershell -NoProfile -ExecutionPolicy Bypass -File $ctxFile -ExePath $exePath
    } catch {
        Warn "Skipped context-menu registration: $_"
    }
}

Info "Done. Open a NEW terminal and try:"
Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
Write-Host "    jpg2pdf . --size a4 --style pencil" -ForegroundColor Green
