# Headless Android AAB build for Skybreaker.
# Run after: keystore generated, export templates installed, Android preset configured.

$ErrorActionPreference = 'Stop'

$Godot     = 'C:\Users\User\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe'
$ProjectDir = 'C:\Users\User\Skybreaker'
$Preset    = 'Android Release'
$Output    = Join-Path $ProjectDir 'builds\skybreaker.aab'

if (-not (Test-Path $Godot)) { Write-Host "Godot not at $Godot" -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $ProjectDir 'export_presets.cfg'))) {
  Write-Host "export_presets.cfg missing. Configure presets first (see 3-configure-export-presets.md)." -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path $Output) | Out-Null

Write-Host "Building $Preset -> $Output"
Push-Location $ProjectDir
try {
  & $Godot --headless --export-release $Preset $Output
  if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }
} finally {
  Pop-Location
}

if (Test-Path $Output) {
  $size = [math]::Round((Get-Item $Output).Length / 1MB, 2)
  Write-Host ""
  Write-Host "OK — $Output ($size MB)" -ForegroundColor Green
  Write-Host "Upload to Play Console Production track."
} else {
  Write-Host "Build did not produce $Output" -ForegroundColor Red
  exit 1
}
