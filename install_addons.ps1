$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$config = Join-Path $here "portable_config"
$scripts = Join-Path $config "scripts"
$scriptOpts = Join-Path $config "script-opts"

New-Item -ItemType Directory -Force -Path $config, $scripts, $scriptOpts | Out-Null

Write-Host ""
Write-Host "Installing/updating uosc into portable_config..."
Write-Host ""

# Official uosc Windows installer.
Invoke-Expression (Invoke-RestMethod "https://raw.githubusercontent.com/tomasklaen/uosc/HEAD/installers/windows.ps1")

Write-Host ""
Write-Host "Installing/updating thumbfast..."
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua" `
  -OutFile (Join-Path $scripts "thumbfast.lua")

try {
    Invoke-WebRequest `
      -Uri "https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.conf" `
      -OutFile (Join-Path $scriptOpts "thumbfast.conf")
} catch {
    Write-Warning "thumbfast.conf could not be downloaded. thumbfast.lua will still work with defaults."
}

Write-Host ""
Write-Host "Done."
Write-Host "Start mpv.exe and open a video."
Write-Host ""
