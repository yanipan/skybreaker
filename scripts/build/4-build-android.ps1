# Headless Android AAB build for Skybreaker.
# Run after: keystore generated (1-generate-keystore.ps1), export templates
# installed at %APPDATA%\Godot\export_templates\4.6.2.stable\, and
# export_presets.cfg present at project root.

$ErrorActionPreference = 'Stop'

# Godot 4.6.2 binary — the outer .exe is actually a folder; the real exe is inside.
$Godot      = 'C:\Users\User\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
$ProjectDir = 'C:\Users\User\Skybreaker'
$Preset     = 'Android Release'
$Output     = Join-Path $ProjectDir 'builds\skybreaker.aab'

if (-not (Test-Path $Godot)) { Write-Host "Godot not at $Godot" -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $ProjectDir 'export_presets.cfg'))) {
  Write-Host "export_presets.cfg missing. See scripts/build/3-configure-export-presets.md." -ForegroundColor Red
  exit 1
}
$Templates = "$env:APPDATA\Godot\export_templates\4.6.2.stable"
if (-not (Test-Path "$Templates\android_release.apk")) {
  Write-Host "Export templates not installed at $Templates" -ForegroundColor Red
  Write-Host "Wait for templates download to finish, or open Godot Editor > Manage Export Templates." -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path $Output) | Out-Null

Push-Location $ProjectDir
try {
  # First-time gradle source tree install (idempotent — Godot exits cleanly if already present).
  if (-not (Test-Path (Join-Path $ProjectDir 'android\build'))) {
    Write-Host "Installing Android gradle build template (one-time)..."
    & $Godot --headless --install-android-build-template
    if (-not (Test-Path (Join-Path $ProjectDir 'android\build'))) {
      Write-Host "Gradle template install did not produce android/build/. Open Godot Editor and run Project > Install Android Build Template." -ForegroundColor Red
      exit 1
    }
  }

  Write-Host "Building $Preset -> $Output"
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
