# Exports the iOS Xcode project from Godot on Windows.
# The resulting .xcodeproj must be transferred to a Mac to Archive + upload.

$ErrorActionPreference = 'Stop'

$Godot     = 'C:\Users\User\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe'
$ProjectDir = 'C:\Users\User\Skybreaker'
$Preset    = 'iOS Release'
$Output    = Join-Path $ProjectDir 'builds\ios\skybreaker.xcodeproj'

if (-not (Test-Path $Godot)) { Write-Host "Godot not at $Godot" -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Force -Path (Split-Path $Output) | Out-Null

Write-Host "Exporting $Preset -> $Output"
Push-Location $ProjectDir
try {
  & $Godot --headless --export-release $Preset $Output
  if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }
} finally {
  Pop-Location
}

if (Test-Path $Output) {
  Write-Host ""
  Write-Host "OK — Xcode project at $(Split-Path $Output -Parent)" -ForegroundColor Green
  Write-Host ""
  Write-Host "Next steps (on Mac):"
  Write-Host "  1. Transfer the entire $(Split-Path $Output -Parent) folder to your Mac (zip + cloud, or scp)."
  Write-Host "  2. Open the .xcodeproj in Xcode."
  Write-Host "  3. Set the signing team in the Signing & Capabilities tab."
  Write-Host "  4. Product -> Archive."
  Write-Host "  5. Distribute App -> App Store Connect -> Upload."

  # Zip it for convenient transfer
  $ZipPath = Join-Path $ProjectDir 'builds\skybreaker-ios.zip'
  if (Test-Path $ZipPath) { Remove-Item $ZipPath }
  Compress-Archive -Path (Split-Path $Output -Parent) -DestinationPath $ZipPath
  $zipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
  Write-Host ""
  Write-Host "Zipped for transfer: $ZipPath ($zipSize MB)" -ForegroundColor Cyan
} else {
  Write-Host "Export did not produce $Output" -ForegroundColor Red
  exit 1
}
