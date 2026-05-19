# Generates the release keystore for Skybreaker Android signing.
# ONE-TIME — do not regenerate or you'll be unable to update the Play Store listing.
# Keep the keystore + password backed up offline (Google Drive, USB, password manager).

$ErrorActionPreference = 'Stop'

$KeystorePath = 'C:\Users\User\keys\skybreaker-release.keystore'
$Alias        = 'skybreaker'

if (Test-Path $KeystorePath) {
  Write-Host "Keystore already exists at $KeystorePath" -ForegroundColor Yellow
  Write-Host "Refusing to overwrite. If you really want a new one, delete the file first." -ForegroundColor Yellow
  exit 1
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  Write-Host "keytool not found on PATH. Install JDK 17 first (Temurin: https://adoptium.net/)." -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path $KeystorePath) | Out-Null

Write-Host "Generating release keystore. You'll be prompted for:"
Write-Host "  - keystore password (REMEMBER THIS — back it up)"
Write-Host "  - name / org / locality (any values are fine — Google doesn't display them)"
Write-Host ""

keytool -genkey -v `
  -keystore $KeystorePath `
  -alias $Alias `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000

if (Test-Path $KeystorePath) {
  Write-Host ""
  Write-Host "OK — keystore created at $KeystorePath" -ForegroundColor Green
  Write-Host "BACK IT UP NOW. Losing it = you can never update the Play Store listing." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Next: set the SKYBREAKER_KEYSTORE_PASSWORD env var so the build script can use it:"
  Write-Host "  `$env:SKYBREAKER_KEYSTORE_PASSWORD = 'your-password'"
}
