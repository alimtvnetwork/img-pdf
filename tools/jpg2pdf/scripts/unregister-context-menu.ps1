<#
.SYNOPSIS
  Remove jpg2pdf Explorer context-menu entries (HKCU only).
#>
$ErrorActionPreference = "SilentlyContinue"

$paths = @(
    "HKCU:\Software\Classes\Directory\shell\Jpg2PdfMenu",
    "HKCU:\Software\Classes\Directory\Background\shell\Jpg2PdfMenu",
    "HKCU:\Software\Classes\Jpg2Pdf.FolderMenu",
    "HKCU:\Software\Classes\Jpg2Pdf.FilesMenu"
)

$exts = @(".jpg",".jpeg",".png",".webp",".bmp",".tif",".tiff")
foreach ($ext in $exts) {
    $paths += "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\Jpg2PdfMenu"
    $progId = (Get-ItemProperty -Path "HKCU:\Software\Classes\$ext")."(default)"
    if ($progId) {
        $paths += "HKCU:\Software\Classes\$progId\shell\Jpg2PdfMenu"
    }
}

foreach ($p in $paths) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force
        Write-Host "Removed: $p" -ForegroundColor Yellow
    }
}
Write-Host "Unregister complete." -ForegroundColor Green
