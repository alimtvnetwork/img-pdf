<#
.SYNOPSIS
  One-liner installer for jpg2pdf on Windows (no clone, no Python required).

.USAGE
  irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

  # Pin a specific version:
  $env:JPG2PDF_VERSION = "v1.3.4"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

  # Skip Explorer context-menu registration:
  $env:JPG2PDF_NO_CONTEXT_MENU = "1"; irm https://raw.githubusercontent.com/alimtvnetwork/img-pdf/main/install.ps1 | iex

.WHAT IT DOES
  1. Resolves the latest GitHub Release (or $env:JPG2PDF_VERSION).
  2. If no release is available, falls back to the latest successful main-branch artifact.
  3. Downloads jpg2pdf-windows-x64.exe to $HOME\Tools\bin\jpg2pdf.exe.
  4. Adds that folder to your User PATH (persistent, no admin).
  5. Downloads + runs register-context-menu.ps1 from the same tag or main (unless disabled).
#>
try { $ErrorActionPreference = "Continue" } catch { }

function Stop-Safely($Message) {
    try { Write-Host "[jpg2pdf] $Message" -ForegroundColor Red } catch { }
    try { exit 1 } catch { return }
}

trap {
    try {
        if (Get-Command Die -ErrorAction SilentlyContinue) { Die "Installer failed safely before completion: $_" }
        else { Stop-Safely "Installer failed safely before initialization: $_" }
    } catch { Stop-Safely "Installer failed safely (trap): $_" }
    continue
}

try {
    # Guard $args access -- under `irm | iex` it may be $null in some hosts.
    $InstallerArgs = @()
    try { if ($null -ne $args) { $InstallerArgs = @($args) } } catch { $InstallerArgs = @() }

    $script:CrashReports = @()
    $script:CrashReportWritten = $false

    function Add-CrashReport($Variable, $Where, $Fallback, $ErrorText) {
        try {
            $script:CrashReports += [pscustomobject]@{
                Time = (Get-Date -Format 'HH:mm:ss')
                Variable = [string]$Variable
                Where = [string]$Where
                Fallback = [string]$Fallback
                Error = [string]$ErrorText
            }
        } catch { }
    }

    function Get-SafeEnv($Name, $Default = "") {
        try {
            $value = [Environment]::GetEnvironmentVariable($Name)
            if ($null -ne $value -and [string]$value -ne "") { return [string]$value }
        } catch { Add-CrashReport "env:$Name" "Get-SafeEnv" "default: $Default" $_ }
        return $Default
    }

    $Repo = $null
    $Version = $null
    $NoContextMenu = $false
    $DebugLog = $false

    try {
        for ($i = 0; $i -lt $InstallerArgs.Count; $i++) {
            $arg = [string]$InstallerArgs[$i]
            switch -Regex ($arg) {
                '^(--repo|-Repo)$' {
                    $i++
                    if ($i -ge $InstallerArgs.Count) { throw "Missing value for $arg" }
                    $Repo = [string]$InstallerArgs[$i]
                    continue
                }
                '^(--version|-Version)$' {
                    $i++
                    if ($i -ge $InstallerArgs.Count) { throw "Missing value for $arg" }
                    $Version = [string]$InstallerArgs[$i]
                    continue
                }
                '^(--no-context-menu|-NoContextMenu)$' { $NoContextMenu = $true; continue }
                '^(--debug|--verbose|-DebugLog|-Verbose|-Verbose2|-d|-v)$' { $DebugLog = $true; continue }
                default { throw "Unknown installer option: $arg" }
            }
        }
    } catch {
        try { Write-Host "[jpg2pdf] Argument parsing failed safely: $_" -ForegroundColor Yellow } catch { }
        Add-CrashReport "InstallerArgs" "argument parsing" "ignore invalid installer option" $_
    }


$script:DebugMode = $false
if ($DebugLog) { $script:DebugMode = $true }
if ((Get-SafeEnv "JPG2PDF_DEBUG") -eq "1") { $script:DebugMode = $true }

$script:LogFile = $null
try {
    $configuredLog = Get-SafeEnv "JPG2PDF_LOG"
    $logBase = if ($configuredLog) { $configuredLog } else {
        $tmp = Get-SafeEnv "TEMP"
        if (-not $tmp) { $tmp = [System.IO.Path]::GetTempPath() }
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
function Write-CrashReportSection($Reason) {
    if (-not $script:LogFile -or $script:CrashReportWritten) { return }
    try {
        $script:CrashReportWritten = $true
        Add-Content -LiteralPath $script:LogFile -Value "" -ErrorAction SilentlyContinue
        Add-Content -LiteralPath $script:LogFile -Value "===== Installer crash report =====" -ErrorAction SilentlyContinue
        Add-Content -LiteralPath $script:LogFile -Value ("Reason: {0}" -f $Reason) -ErrorAction SilentlyContinue
        if ($script:CrashReports -and $script:CrashReports.Count -gt 0) {
            foreach ($item in $script:CrashReports) {
                Add-Content -LiteralPath $script:LogFile -Value ("{0} variable={1} where={2} fallback={3} error={4}" -f $item.Time, $item.Variable, $item.Where, $item.Fallback, $item.Error) -ErrorAction SilentlyContinue
            }
        } else {
            Add-Content -LiteralPath $script:LogFile -Value "No guarded read failures were recorded before exit." -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $script:LogFile -Value "===== End installer crash report =====" -ErrorAction SilentlyContinue
    } catch { }
}
function Info($m)  { Write-Log "INFO " $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Cyan }
function Warn($m)  { Write-Log "WARN " $m; Write-Host "[jpg2pdf] $m" -ForegroundColor Yellow }
function Debug2($m){ Write-Log "DEBUG" $m; if ($script:DebugMode) { Write-Host "[jpg2pdf:debug] $m" -ForegroundColor Magenta } }
    function Die ($m)  {
    Write-CrashReportSection $m
    Write-Log "ERROR" $m
    Write-Host "[jpg2pdf] $m" -ForegroundColor Red
    if ($script:LogFile) { Write-Host "[jpg2pdf] Full log: $script:LogFile" -ForegroundColor Red }
    exit 1
}
    function Log-ExternalOutput($Level, $Lines) {
        try {
            foreach ($line in @($Lines)) {
                if ($null -ne $line -and [string]$line -ne "") { Write-Log $Level ([string]$line) }
            }
        } catch { }
    }

function Invoke-Safe($Description, [scriptblock]$Action, $Default = $null) {
    try { return & $Action } catch { Add-CrashReport $Description $Description "default: $Default" $_; Warn "$Description failed safely: $_"; return $Default }
}
function Invoke-SafeBool($Description, [scriptblock]$Action) {
    try { $null = & $Action; return $true } catch { Add-CrashReport $Description $Description "false" $_; Warn "$Description failed safely: $_"; return $false }
}
function Invoke-InstallerStep($StepName, [scriptblock]$Action, $Fallback = "continue safely", [switch]$Required) {
    try {
        Debug2 "STEP $StepName"
        return & $Action
    } catch {
        Add-CrashReport $StepName $StepName $Fallback $_
        if ($Required) { Die "$StepName failed safely: $_" }
        Warn "$StepName failed safely: $_"
        return $null
    }
}
function Join-SafePath($Base, $Child) {
    try { if ($Base) { return (Join-Path $Base $Child -ErrorAction Stop) } } catch { Add-CrashReport "path:$Base + $Child" "Join-SafePath" "child only: $Child" $_; Warn "Path join failed safely: $_" }
    return $Child
}
function Test-SafePath($Path) {
    try { return (Test-Path -LiteralPath $Path -ErrorAction Stop) } catch { Add-CrashReport "path:$Path" "Test-SafePath" "false" $_; Warn "Path test failed safely: $_"; return $false }
}
function Resolve-SafePath($Path) {
    try { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { Add-CrashReport "path:$Path" "Resolve-SafePath" "original path" $_; Warn "Path resolve failed safely: $_"; return $Path }
}
function Save-SafeUrl($Description, $Uri, $OutFile) {
    Debug2 "GET $Uri ($Description)"
    return Invoke-SafeBool $Description { Invoke-WebRequest -Headers $headers -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop }
}
function Convert-SafeJson($Description, $Raw) {
    try {
        if (-not $Raw) { return $null }
        return ($Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Add-CrashReport $Description "Convert-SafeJson" "null" $_
        Warn "$Description JSON parse failed safely: $_"
        return $null
    }
}

    Invoke-InstallerStep "Resolve installer settings" {
        if (-not $Repo) { $Repo = Get-SafeEnv "JPG2PDF_REPO" "alimtvnetwork/img-pdf" }
        if (-not $Version) { $Version = Get-SafeEnv "JPG2PDF_VERSION" }
        if ((Get-SafeEnv "JPG2PDF_NO_CONTEXT_MENU") -eq "1") { $NoContextMenu = $true }
        if (-not $Repo) {
            Die "Set the repo: `$env:JPG2PDF_REPO = 'your-user/your-repo'  (or pass -Repo)."
        }
    } "default repo and no pinned version" -Required | Out-Null

    Invoke-InstallerStep "Emit debug environment" {
        if ($script:DebugMode) {
            Info "Debug mode enabled. Log: $(if ($script:LogFile) { $script:LogFile } else { '<unavailable>' })"
            Debug2 "PSVersion: $($PSVersionTable.PSVersion)  OS: $($PSVersionTable.OS)"
            Debug2 "Repo=$Repo  Version=$Version  NoContextMenu=$NoContextMenu"
            Debug2 "USERPROFILE=$(Get-SafeEnv 'USERPROFILE')  TEMP=$(Get-SafeEnv 'TEMP')"
        }
    } "skip debug environment output" | Out-Null

    Invoke-InstallerStep "Configure GitHub HTTP headers" {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { Add-CrashReport "SecurityProtocol" "TLS setup" "continue with host default TLS" $_; Warn "Could not force TLS 1.2 safely: $_" }
        $headers = @{ "User-Agent" = "jpg2pdf-installer"; "Accept" = "application/vnd.github+json" }
        $token = Get-SafeEnv "GITHUB_TOKEN"
        if ($token) { $headers["Authorization"] = "Bearer $token" }
    } "anonymous GitHub requests" -Required | Out-Null

    function Get-GitHubJson($Uri, $Description) {
        Debug2 "GET $Uri ($Description)"
        $response = Invoke-Safe "$Description HTTP read" { Invoke-WebRequest -Headers $headers -Uri $Uri -UseBasicParsing -ErrorAction Stop } $null
        if (-not $response) { return $null }
        $content = Invoke-Safe "$Description response content read" { [string]$response.Content } ""
        if (-not $content) { Add-CrashReport "response.Content" $Description "null JSON result" "empty response content" }
        return Convert-SafeJson $Description $content
    }

    function Download-ReleaseAsset($Repo, $Version, $Asset, $OutFile) {
        $dlUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
        Info "Downloading $dlUrl"
        return Save-SafeUrl "Release download" $dlUrl $OutFile
    }

    function Get-SafeTempDir() {
        $safeTemp = Get-SafeEnv "TEMP"
        if ($safeTemp) { return $safeTemp }
        try {
            $tmp = [System.IO.Path]::GetTempPath()
            if ($tmp) { return $tmp }
        } catch { Add-CrashReport "temp path" "Get-SafeTempDir" "current directory" $_ }
        try { return (Get-Location).Path } catch { Add-CrashReport "Get-Location" "Get-SafeTempDir" "." $_; return "." }
    }

    function Download-MainArtifact($Repo, $Asset, $OutFile) {
        Info "Looking for latest main-branch artifact named $Asset ..."
        $runsUrl = "https://api.github.com/repos/$Repo/actions/workflows/release.yml/runs?branch=main&status=success&per_page=10"
        $runs = Get-GitHubJson $runsUrl "Main-branch workflow lookup"
        if (-not $runs -or -not $runs.workflow_runs) {
            Add-CrashReport "workflow_runs" "Download-MainArtifact" "artifact fallback unavailable" "no successful main-branch runs returned"
            return $false
        }

        foreach ($run in $runs.workflow_runs) {
            $artifacts = Get-GitHubJson $run.artifacts_url "Artifact lookup for run $($run.id)"
            if (-not $artifacts -or -not $artifacts.artifacts) {
                Add-CrashReport "artifacts" "Download-MainArtifact run $($run.id)" "try next workflow run" "no artifacts returned"
                continue
            }
            $artifact = $artifacts.artifacts | Where-Object { $_.name -eq $Asset -and -not $_.expired } | Select-Object -First 1
            if (-not $artifact) {
                Add-CrashReport "artifact:$Asset" "Download-MainArtifact run $($run.id)" "try next workflow run" "artifact missing or expired"
                continue
            }

            $tmpRoot = $null
            try {
                $tempBase = Get-SafeTempDir
                $tmpRoot = Join-SafePath $tempBase ("jpg2pdf-artifact-" + [guid]::NewGuid().ToString("N"))
                $zipFile = Join-SafePath $tmpRoot "artifact.zip"
                $extractDir = Join-SafePath $tmpRoot "unzipped"
                if (-not (Invoke-SafeBool "Temp directory creation" { New-Item -ItemType Directory -Force -Path $tmpRoot -ErrorAction Stop | Out-Null })) { continue }
                Info "Downloading main-branch artifact from run $($run.id)"
                if (-not (Save-SafeUrl "Main-branch artifact download" $artifact.archive_download_url $zipFile)) { continue }
                if (-not (Invoke-SafeBool "Main-branch artifact extraction" { Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop })) { continue }
                $candidate = Join-SafePath $extractDir $Asset
                if (-not (Test-SafePath $candidate)) {
                    $candidate = Invoke-Safe "Artifact file lookup" { Get-ChildItem -LiteralPath $extractDir -Recurse -File -ErrorAction Stop | Where-Object { $_.Name -eq $Asset } | Select-Object -First 1 } $null
                    if ($candidate) { $candidate = $candidate.FullName }
                }
                if (-not $candidate -or -not (Test-SafePath $candidate)) {
                    Warn "Artifact archive did not contain $Asset."
                    continue
                }
                if (-not (Invoke-SafeBool "Artifact copy" { Copy-Item -LiteralPath $candidate -Destination $OutFile -Force -ErrorAction Stop })) { continue }
                return $true
            } catch {
                Add-CrashReport "main artifact:$Asset" "Download-MainArtifact run $($run.id)" "try next workflow run" $_
                Warn "Main-branch artifact download failed: $_"
            } finally {
                if ($tmpRoot) { Invoke-SafeBool "Temp artifact cleanup" { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction Stop } | Out-Null }
            }
        }
        return $false
    }

    function Find-PythonCommand() {
        foreach ($name in @("py", "python", "python3")) {
            $cmd = Invoke-Safe "Python command lookup $name" { Get-Command $name -ErrorAction Stop } $null
            if ($cmd) { return $cmd.Source }
        }
        Add-CrashReport "python" "Find-PythonCommand" "binary-only install unavailable" "Python was not found on PATH"
        return $null
    }

    function Install-SourceFromRef($Repo, $Ref, $RefKind, $OutFile, $BinDir) {
        $python = Find-PythonCommand
        if (-not $python) { return $null }
        $tmpRoot = $null
        try {
            $tmpRoot = Join-SafePath (Get-SafeTempDir) ("jpg2pdf-source-" + [guid]::NewGuid().ToString("N"))
            $zipFile = Join-SafePath $tmpRoot "source.zip"
            $extractDir = Join-SafePath $tmpRoot "extracted"
            if (-not (Invoke-SafeBool "Source temp directory creation" { New-Item -ItemType Directory -Force -Path $extractDir -ErrorAction Stop | Out-Null })) { return $null }
            $sourceUrl = $(if ($RefKind -eq "tag") { "https://github.com/$Repo/archive/refs/tags/$Ref.zip" } else { "https://github.com/$Repo/archive/refs/heads/$Ref.zip" })
            Info "Downloading source fallback $sourceUrl"
            if (-not (Save-SafeUrl "Source fallback download" $sourceUrl $zipFile)) { return $null }
            if (-not (Invoke-SafeBool "Source fallback extraction" { Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop })) { return $null }
            $scriptFile = Invoke-Safe "Source fallback script lookup" { Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter "jpg2pdf.py" -ErrorAction Stop | Where-Object { $_.FullName -like "*tools*jpg2pdf*src*jpg2pdf.py" } | Select-Object -First 1 } $null
            if (-not $scriptFile) { Add-CrashReport "source tree" "Install-SourceFromRef" "try next fallback" "tools/jpg2pdf/src/jpg2pdf.py not found"; return $null }
            $sourceRoot = $scriptFile.FullName -replace "[\\/]tools[\\/]jpg2pdf[\\/]src[\\/]jpg2pdf\.py$", ""
            $installRoot = Join-SafePath $BinDir "jpg2pdf-source"
            Invoke-SafeBool "Existing source fallback cleanup" { Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction Stop } | Out-Null
            if (-not (Invoke-SafeBool "Source fallback copy" { Copy-Item -LiteralPath $sourceRoot -Destination $installRoot -Recurse -Force -ErrorAction Stop })) { return $null }
            $requirements = Join-SafePath $installRoot "tools\jpg2pdf\requirements.txt"
            if (Test-SafePath $requirements) {
                $pipOutput = Invoke-Safe "Source fallback dependency install" { & $python -m pip install --user -r $requirements 2>&1 } $null
                Log-ExternalOutput "PIP  " $pipOutput
            } else { Add-CrashReport "requirements.txt" "Install-SourceFromRef" "write wrapper without pip" "requirements file missing" }
            $installedScript = Join-SafePath $installRoot "tools\jpg2pdf\src\jpg2pdf.py"
            $wrapper = @("@echo off", "`"$python`" `"$installedScript`" %*")
            if (-not (Invoke-SafeBool "Source fallback wrapper write" { Set-Content -LiteralPath $OutFile -Value $wrapper -Encoding ASCII -ErrorAction Stop })) { return $null }
            return "source fallback $Ref"
        } catch {
            Add-CrashReport "source fallback:$Ref" "Install-SourceFromRef" "try next fallback" $_
            Warn "Source fallback failed safely: $_"
            return $null
        } finally {
            if ($tmpRoot) { Invoke-SafeBool "Source temp cleanup" { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction Stop } | Out-Null }
        }
    }

    function Install-SourceFallback($Repo, $Version, $OutFile, $BinDir) {
        if ($Version) {
            $from = Install-SourceFromRef $Repo $Version "tag" $OutFile $BinDir
            if ($from) { return $from }
            Warn "Pinned source fallback failed. Trying main branch source."
        }
        return (Install-SourceFromRef $Repo "main" "branch" $OutFile $BinDir)
    }

    Invoke-InstallerStep "Resolve install paths" {
        $asset = "jpg2pdf-windows-x64.exe"
        $homeDir = Get-SafeEnv "USERPROFILE"
        if (-not $homeDir) { try { if ($HOME) { $homeDir = [string]$HOME } } catch { Add-CrashReport "HOME" "Resolve install paths" "current directory" $_ } }
        if (-not $homeDir) { try { $homeDir = (Get-Location).Path } catch { Add-CrashReport "Get-Location" "Resolve install paths" "." $_; $homeDir = "." } }
        $binDir  = Join-SafePath $homeDir "Tools\bin"
        $exePath = Join-SafePath $binDir "jpg2pdf.exe"
    } "install under current directory" -Required | Out-Null

    Invoke-InstallerStep "Create install directory" {
        if (-not (Invoke-SafeBool "Install directory creation" { New-Item -ItemType Directory -Force -Path $binDir -ErrorAction Stop | Out-Null })) {
            Die "Could not create install directory safely."
        }
    } "abort install" -Required | Out-Null

    $installedFrom = $null
    Invoke-InstallerStep "Download installer binary" {
        if ($Version) {
            Info "Installing jpg2pdf $Version"
            if (Download-ReleaseAsset $Repo $Version $asset $exePath) { $installedFrom = "release $Version" }
            if (-not $installedFrom) {
                Add-CrashReport "release asset:$asset" "version-pinned install" "latest main-branch artifact" "release asset unavailable"
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
                if (-not $installedFrom) { Add-CrashReport "release asset:$asset" "latest-release install" "latest main-branch artifact" "release asset unavailable" }
            } else {
                Add-CrashReport "latest release" "release resolution" "latest main-branch artifact" "no GitHub Release found"
                Warn "No GitHub Release found. Falling back to the latest successful main-branch artifact."
            }

            if (-not $installedFrom) {
                if (Download-MainArtifact $Repo $asset $exePath) {
                    $installedFrom = "latest main-branch artifact"
                }
            }
        }
    } "release download -> latest main-branch artifact" | Out-Null

    if (-not $installedFrom) {
        Die "Could not install jpg2pdf. Publish a release, run the main-branch build, or set GITHUB_TOKEN if artifact access requires it."
    }

    Invoke-InstallerStep "Verify installed binary" {
        $verLine = & $exePath --version 2>&1
        Info "Installed from ${installedFrom}: $verLine -> $exePath"
    } "continue after successful download" | Out-Null

    Invoke-InstallerStep "Update PATH" {
        $current = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not $current) { $current = "" }
        $entries = $current.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ }
        $resolved = (Resolve-SafePath $binDir).TrimEnd('\')
        if ($entries -notcontains $resolved) {
            [Environment]::SetEnvironmentVariable("Path", (($entries + $resolved) -join ';'), "User")
            Info "Added $resolved to User PATH (open a new terminal to pick it up)."
        } else {
            Info "$resolved already on User PATH."
        }
        $sessionPath = Get-SafeEnv "Path"
        if (($sessionPath.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') }) -notcontains $resolved) {
            $env:Path = $(if ($sessionPath) { "$($sessionPath.TrimEnd(';'));$resolved" } else { $resolved })
        }
    } "binary installed; skip PATH update" | Out-Null

    Invoke-InstallerStep "Register context menu" {
        if (-not $NoContextMenu) {
            $ctxRef = $(if ($Version) { $Version } else { "main" })
            $ctxUrl  = "https://raw.githubusercontent.com/$Repo/$ctxRef/tools/jpg2pdf/scripts/register-context-menu.ps1"
            $ctxFile = Join-SafePath (Get-SafeTempDir) "jpg2pdf-register-context-menu.ps1"
            Info "Fetching context-menu registrar from $ctxUrl"
            if (Save-SafeUrl "Context-menu registrar download" $ctxUrl $ctxFile) {
                $null = Invoke-Safe "Context-menu registrar execution" { & powershell -NoProfile -ExecutionPolicy Bypass -File $ctxFile -ExePath $exePath } $null
            }
        }
    } "skip context-menu registration" | Out-Null

    Invoke-InstallerStep "Print completion instructions" {
        Info "Done. Open a NEW terminal and try:"
        Write-CrashReportSection "installer completed"
        Write-Host "    jpg2pdf `"C:\Photos`" --size a4" -ForegroundColor Green
        Write-Host "    jpg2pdf . --size a4 --style pencil" -ForegroundColor Green
    } "installer completed without final instructions" | Out-Null
} catch {
    try { Write-CrashReportSection "top-level catch: $_" } catch { }
    try { Die "Installer failed safely: $_" } catch { Stop-Safely "Installer failed safely before logging was initialized: $_" }
}
