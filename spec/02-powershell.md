# 02 — PowerShell Spec (`install.ps1`, `uninstall.ps1`, `run.ps1`)

This is the spec that has been violated most often. Read it in full before
editing any `.ps1` file.

## Target runtime

- **Windows PowerShell 5.1** (default on Windows 10/11) AND **PowerShell 7+**.
- 5.1 has the most quirks — design for it, 7+ will keep working.

## Encoding rule (R4 from AI-INSTRUCTIONS)

ASCII only. No em-dashes (`—`), no smart quotes (`' '`), no arrows (`→`),
no emoji. If you must include UTF-8, save the file with a BOM — but
prefer ASCII.

## Bulletproof startup (CRITICAL — this is the bug we keep hitting)

The install script must NEVER crash before it can print a useful error.
The first ~30 lines of `install.ps1` MUST follow this template:

```powershell
[CmdletBinding()]
param(
  [string]$Version = $env:JPG2PDF_VERSION,
  [string]$Repo    = $env:JPG2PDF_REPO,
  [Alias('Verbose2','d')][switch]$DebugLog
)

# 1. Do NOT use Set-StrictMode here. It causes crashes on missing env vars.
# 2. Set ErrorActionPreference to Continue at the very top so a single
#    failure doesn't abort the script before the try/catch wraps it.
$ErrorActionPreference = 'Continue'

# 3. Wrap EVERYTHING that follows in a master try/catch so the user
#    always gets a friendly error + log path instead of a stack trace.
try {
  # 3a. Resolve safe paths with fallbacks. NEVER read $env:TEMP or $HOME
  #     directly without a fallback.
  function Get-SafeTempDir {
    foreach ($candidate in @($env:TEMP, $env:TMP, "$env:USERPROFILE\AppData\Local\Temp", (Get-Location).Path)) {
      if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return (Get-Location).Path
  }
  $tempDir = Get-SafeTempDir
  $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($HOME) { $HOME } else { (Get-Location).Path }

  # 3b. Now it is safe to set up logging, parse args, etc.
  # ... rest of installer ...
}
catch {
  Write-Host "jpg2pdf installer failed: $($_.Exception.Message)" -ForegroundColor Red
  if ($script:LogPath) { Write-Host "Full log: $script:LogPath" -ForegroundColor Yellow }
  exit 1
}
```

### Forbidden patterns

- `Set-StrictMode -Version Latest` at the top of the file.
- Reading `$env:TEMP`, `$env:Path`, `$HOME`, `$env:USERPROFILE` without a
  null-check or fallback.
- `throw` outside a try/catch in startup code.
- Any network call (`Invoke-RestMethod`, `Invoke-WebRequest`) outside a
  try/catch.

### Required patterns

- Master try/catch wrapping the whole script body.
- `Get-SafeTempDir` (or equivalent) helper.
- `Get-GitHubJson` helper that wraps `Invoke-RestMethod` in try/catch and
  returns `$null` on failure (not throw).
- Release lookup: `try { $release = Get-GitHubJson "$api/releases/latest" } catch { $release = $null }`,
  then `if (-not $release) { # fall back to main-branch artifact }`.

## Release → main-branch fallback (R2 from AI-INSTRUCTIONS)

Pseudo-code that MUST be present:

```powershell
$release = $null
try { $release = Get-GitHubJson "$api/releases/tags/$Version" } catch { }
if (-not $release) {
  try { $release = Get-GitHubJson "$api/releases/latest" } catch { }
}
if ($release) {
  $assetUrl = ($release.assets | Where-Object { $_.name -eq $assetName }).browser_download_url
}
if (-not $assetUrl) {
  Write-Host "No release found, falling back to main-branch artifact..." -ForegroundColor Yellow
  $assetUrl = Get-MainBranchArtifactUrl -Repo $Repo -AssetName $assetName
}
if (-not $assetUrl) { throw "Could not locate jpg2pdf binary in releases or main-branch artifacts." }
```

Removing or short-circuiting either fallback is a regression.

## Debug/verbose flag

`-DebugLog` (alias `-d`, `-Verbose2`) or `JPG2PDF_DEBUG=1` env var enables:
- Timestamped log file at `${tempDir}\jpg2pdf-install-YYYYMMDD-HHmmss-<pid>.log`
  (overridable via `$env:JPG2PDF_LOG`).
- `Write-Log` writes every info/warn/error/debug message to the log.
- `Debug2` for magenta verbose tracing of network calls.
- The path is printed in the final error message on crash.

## PATH updates

When adding the install dir to PATH:
```powershell
$currentPath = if ($env:Path) { $env:Path } else { '' }
if ($currentPath -notlike "*$installDir*") {
  [Environment]::SetEnvironmentVariable('Path', "$currentPath;$installDir", 'User')
}
```
Never assume `$env:Path` is non-null.

## Validation checklist

- [ ] File is ASCII (`file install.ps1` reports ASCII text, not UTF-8 with non-ASCII).
- [ ] `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('install.ps1', [ref]$null, [ref]$null)"` parses without errors (run on Linux with `pwsh` if available).
- [ ] `grep -n 'Set-StrictMode' install.ps1` returns nothing in startup region.
- [ ] Release-then-main fallback is present (grep for `main-branch`, `falling back`).
- [ ] Master try/catch wraps the script body.
- [ ] `JPG2PDF_VERSION` matches `tools/jpg2pdf/VERSION`.
