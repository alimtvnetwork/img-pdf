<#
.SYNOPSIS
  One-liner installer for jpg2pdf on Windows (no clone, no Python required).

.USAGE
  irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

  # Pin a specific version:
  $env:JPG2PDF_VERSION = "v1.2.6"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

  # Skip Explorer context-menu registration:
  $env:JPG2PDF_NO_CONTEXT_MENU = "1"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

.WHAT IT DOES
  1. Resolves the latest GitHub Release (or $env:JPG2PDF_VERSION).
  2. If no release is available, falls back to the latest successful main-branch artifact.
  3. Downloads jpg2pdf-windows-x64.exe to $HOME\Tools\bin\jpg2pdf.exe.
  4. Adds that folder to your User PATH (persistent, no admin).
  5. Downloads + runs register-context-menu.ps1 from the same tag or main (unless disabled).
#>
$ErrorActionPreference = "Stop"

function Stop-Safely($Message) {
    try { Write-Host "[jpg2pdf] $Message" -ForegroundColor Red } catch { }
    exit 1
}

trap {
    try { Die "Installer failed safely before completion: $_" } catch { Stop-Safely "Installer failed safely before initialization: $_" }
}

try {
    $Repo = $null
    $Version = $null
    $NoContextMenu = $false
    $DebugLog = $false

    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = [string]$args[$i]
        switch -Regex ($arg) {
            '^(--repo|-Repo)$' {
                $i++
                if ($i -ge $args.Count) { throw "Missing value for $arg" }
                $Repo = [string]$args[$i]
                continue
            }
            '^(--version|-Version)$' {
                $i++
                if ($i -ge $args.Count) { throw "Missing value for $arg" }
                $Version = [string]$args[$i]
                continue
            }
            '^(--no-context-menu|-NoContextMenu)$' { $NoContextMenu = $true; continue }
            '^(--debug|--verbose|-DebugLog|-Verbose|-Verbose2|-d|-v)$' { $DebugLog = $true; continue }
            default { throw "Unknown installer option: $arg" }
        }
    }

$script:DebugMode = $false
if ($DebugLog) { $script:DebugMode = $true }
if ($env:JPG2PDF_DEBUG -eq "1") { $script:DebugMode = $true }

$script:LogFile = $null
try {
    $logBase = if ($env:JPG2PDF_LOG) { $env:JPG2PDF_LOG } else {
        $tmp = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        Join-Path $tmp ("jpg2pdf-install-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
    }
    New-Item -ItemType File -Force -Path $logBase | Out-Null
    $script:LogFile = $logBase
} catch { $script:LogFile = $null }

function Write-Log($Level, $Message) {
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value ("{0} {1} {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message) -ErrorAction SilentlyContinue } catch { }
    }
}
function Info($m)  { Write-Log "INFO " $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Cyan }
function Warn($m)  { Write-Log "WARN " $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Yellow }
function Debug2($m){ Write-Log "DEBUG" $m; if ($script:DebugMode) { Write-Host "[jpg2pdf:debug] $m" -ForegroundColor Magenta } }
function Die ($m)  {
    Write-Log "ERROR" $m
    Write-Host "[jpg2pdf] $m" -ForegroundColor Red
    if ($script:LogFile) { Write-Host "[jpg2pdf] Full log: $script:LogFile" -ForegroundColor Red }
    exit 1
}

    if (-not $Repo) { $Repo = $(if ($env:JPG2PDF_REPO) { $env:JPG2PDF_REPO } else { "alimtvnetwork/img-pdf" }) }
    if (-not $Version) { $Version = $(if ($env:JPG2PDF_VERSION) { $env:JPG2PDF_VERSION } else { "" }) }
    if ($env:JPG2PDF_NO_CONTEXT_MENU -eq "1") { $NoContextMenu = $true }
    if (-not $Repo) {
        Die "Set the repo: `$env:JPG2PDF_REPO = 'your-user/your-repo'  (or pass -Repo)."
    }

    if ($script:DebugMode) {
        Info "Debug mode enabled. Log: $(if ($script:LogFile) { $script:LogFile } else { '<unavailable>' })"
        Debug2 "PSVersion: $($PSVersionTable.PSVersion)  OS: $($PSVersionTable.OS)"
        Debug2 "Repo=$Repo  Version=$Version  NoContextMenu=$NoContextMenu"
        Debug2 "USERPROFILE=$env:USERPROFILE  TEMP=$env:TEMP"
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "jpg2pdf-installer"; "Accept" = "application/vnd.github+json" }
    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

    function Get-GitHubJson($Uri, $Description) {
        Debug2 "GET $Uri ($Description)"
        try {
            return Invoke-RestMethod -Headers $headers -Uri $Uri -UseBasicParsing
        } catch {
            Warn "$Description failed: $_"
            Debug2 "Exception: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
            return $null
        }
    }

    function Download-ReleaseAsset($Repo, $Version, $Asset, $OutFile) {
        $dlUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
        Info "Downloading $dlUrl"
        try {
            Invoke-WebRequest -Headers $headers -Uri $dlUrl -OutFile $OutFile -UseBasicParsing
            return $true
        } catch {
            Warn "Release download failed: $_"
            return $false
        }
    }

    function Get-SafeTempDir() {
        if ($env:TEMP) { return $env:TEMP }
        try {
            $tmp = [System.IO.Path]::GetTempPath()
            if ($tmp) { return $tmp }
        } catch { }
        return (Get-Location).Path
    }

    function Download-MainArtifact($Repo, $Asset, $OutFile) {
        Info "Looking for latest main-branch artifact named $Asset ..."
        $runsUrl = "https://api.github.com/repos/$Repo/actions/workflows/release.yml/runs?branch=main&status=success&per_page=10"
        $runs = Get-GitHubJson $runsUrl "Main-branch workflow lookup"
        if (-not $runs -or -not $runs.workflow_runs) { return $false }

        foreach ($run in $runs.workflow_runs) {
            $artifacts = Get-GitHubJson $run.artifacts_url "Artifact lookup for run $($run.id)"
            if (-not $artifacts -or -not $artifacts.artifacts) { continue }
            $artifact = $artifacts.artifacts | Where-Object { $_.name -eq $Asset -and -not $_.expired } | Select-Object -First 1
            if (-not $artifact) { continue }

            $tmpRoot = $null
            try {
                $tempBase = Get-SafeTempDir
                $tmpRoot = Join-Path $tempBase ("jpg2pdf-artifact-" + [guid]::NewGuid().ToString("N"))
                $zipFile = Join-Path $tmpRoot "artifact.zip"
                $extractDir = Join-Path $tmpRoot "unzipped"
                New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
                Info "Downloading main-branch artifact from run $($run.id)"
                Invoke-WebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile $zipFile -UseBasicParsing
                Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
                $candidate = Join-Path $extractDir $Asset
                if (-not (Test-Path -LiteralPath $candidate)) {
                    $candidate = Get-ChildItem -LiteralPath $extractDir -Recurse -File | Where-Object { $_.Name -eq $Asset } | Select-Object -First 1
                    if ($candidate) { $candidate = $candidate.FullName }
                }
                if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) {
                    Warn "Artifact archive did not contain $Asset."
                    continue
                }
                Copy-Item -LiteralPath $candidate -Destination $OutFile -Force
                return $true
            } catch {
                Warn "Main-branch artifact download failed: $_"
            } finally {
                if ($tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        return $false
    }

    $asset = "jpg2pdf-windows-x64.exe"
    $homeDir = $(if ($HOME) { $HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { (Get-Location).Path })
    $binDir  = Join-Path $homeDir "Tools\bin"
    $exePath = Join-Path $binDir "jpg2pdf.exe"
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    $installedFrom = $null
    if ($Version) {
        Info "Installing jpg2pdf $Version"
        if (Download-ReleaseAsset $Repo $Version $asset $exePath) { $installedFrom = "release $Version" }
        if (-not $installedFrom) {
            Warn "Release asset was not available. Falling back to the latest successful main-branch artifact."
            if (Download-MainArtifact $Repo $asset $exePath) {
                $installedFrom = "latest main-branch artifact"
                $Version = ""
            }
        }
    } else {
        Info "Resolving latest release of $Repo ..."
        $rel = Get-GitHubJson "https://api.github.com/repos/$Repo/releases/latest" "Latest release lookup"
        if ($rel -and $rel.tag_name) {
            $Version = $rel.tag_name
            Info "Installing jpg2pdf $Version"
            if (Download-ReleaseAsset $Repo $Version $asset $exePath) { $installedFrom = "release $Version" }
        } else {
            Warn "No GitHub Release found. Falling back to the latest successful main-branch artifact."
        }

        if (-not $installedFrom) {
            if (Download-MainArtifact $Repo $asset $exePath) {
                $installedFrom = "latest main-branch artifact"
            }
        }
    }

    if (-not $installedFrom) {
        Die "Could not install jpg2pdf. Publish a release, run the main-branch build, or set GITHUB_TOKEN if artifact access requires it."
    }

    try {
        $verLine = & $exePath --version 2>&1
        Info "Installed from ${installedFrom}: $verLine -> $exePath"
    } catch {
        Warn "Binary downloaded from $installedFrom but --version failed: $_"
    }

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
    $sessionPath = $(if ($env:Path) { $env:Path } else { "" })
    if (($sessionPath.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') }) -notcontains $resolved) {
        $env:Path = $(if ($sessionPath) { "$($sessionPath.TrimEnd(';'));$resolved" } else { $resolved })
    }

    if (-not $NoContextMenu) {
        $ctxRef = $(if ($Version) { $Version } else { "main" })
        $ctxUrl  = "https://raw.githubusercontent.com/$Repo/$ctxRef/tools/jpg2pdf/scripts/register-context-menu.ps1"
        $ctxFile = Join-Path (Get-SafeTempDir) "jpg2pdf-register-context-menu.ps1"
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
} catch {
    Die "Installer failed safely: $_"
}
