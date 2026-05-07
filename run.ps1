<#
.SYNOPSIS
  Local runner — calls src/jpg2pdf.py without installing anything globally.
  Use ..\install.ps1 if you want a global `jpg2pdf` command.

.EXAMPLE
  .\run.ps1 "C:\Photos" -a4
  .\run.ps1 . -letter -Landscape
  .\run.ps1 . -legal -Fit cover -Out scans.pdf -Recursive
#>
[CmdletBinding(DefaultParameterSetName='A4')]
param(
    [Parameter(Position=0)] [string]$Path = ".",
    [Parameter(ParameterSetName='A4')]     [switch]$a4,
    [Parameter(ParameterSetName='Letter')] [switch]$letter,
    [Parameter(ParameterSetName='Legal')]  [switch]$legal,
    [switch]$Landscape,
    [ValidateSet("contain","cover","stretch","original")]
    [string]$Fit = "contain",
    [string]$Out,
    [switch]$Recursive
)

$size = "a4"
if ($letter) { $size = "letter" } elseif ($legal) { $size = "legal" }

$repoRoot = $PSScriptRoot
$pyScript = Join-Path $repoRoot "tools\jpg2pdf\src\jpg2pdf.py"
$reqFile  = Join-Path $repoRoot "tools\jpg2pdf\requirements.txt"
if (-not (Test-Path $pyScript)) { Write-Error "Missing $pyScript"; exit 1 }

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Write-Error "Python not found. Run .\install.ps1 first."; exit 1 }

& $py.Source -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    & $py.Source -m pip install --user --quiet -r $reqFile
}

$argsList = @($pyScript, $Path, "--size", $size, "--fit", $Fit)
if ($Landscape) { $argsList += @("--orientation","landscape") }
if ($Recursive) { $argsList += "--recursive" }
if ($Out)       { $argsList += @("--out", $Out) }

& $py.Source @argsList
exit $LASTEXITCODE
