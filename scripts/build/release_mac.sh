#!/bin/bash
# Build both store binaries on the Mac. Run from the repo root AFTER bumping
# version/code (Android) and application/version (iOS) in export_presets.cfg.
#
#   scripts/build/release_mac.sh android        -> builds/skybreaker.aab
#   scripts/build/release_mac.sh ios            -> builds/ios-release/export/skybreaker.ipa
#   scripts/build/release_mac.sh ios upload     -> also uploads the ipa to App Store Connect (TestFlight)
#
# Android upload: python3 scripts/store/play_track.py internal builds/skybreaker.aab "notes"
# Needs: Godot 4.6.3 + export templates, Xcode, the signing keychain
# (~/Library/Keychains/skybreaker-signing.keychain-db, password in
# ~/keys/skybreaker-ios/keychain.password), ASC key A726RHWTX7 in
# ~/.appstoreconnect/private_keys. A new build never touches the App Store
# version or its review submission; attach it there separately when wanted.
set -euo pipefail
G=/Applications/Godot.app/Contents/MacOS/Godot
KC="$HOME/Library/Keychains/skybreaker-signing.keychain-db"
cd "$(dirname "$0")/../.."
"$G" --headless --path . --import >/dev/null 2>&1 || true
case "${1:-}" in
  android)
    "$G" --headless --path . --export-release "Android Release" builds/skybreaker.aab
    ls -la builds/skybreaker.aab ;;
  ios)
    "$G" --headless --path . --export-release "iOS Release" builds/ios-release/skybreaker.ipa
    security unlock-keychain -p "$(cat "$HOME/keys/skybreaker-ios/keychain.password")" "$KC"
    security set-keychain-settings -t 7200 -l "$KC"
    cd builds/ios-release
    rm -rf skybreaker.xcarchive export
    xcodebuild -project skybreaker.xcodeproj -scheme skybreaker -configuration Release \
      -archivePath skybreaker.xcarchive -destination generic/platform=iOS archive \
      CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=B6Z86P8XXQ "CODE_SIGN_IDENTITY=Apple Distribution" \
      "PROVISIONING_PROFILE_SPECIFIER=Skybreaker App Store" "OTHER_CODE_SIGN_FLAGS=--keychain $KC" > archive.log 2>&1
    xcodebuild -exportArchive -archivePath skybreaker.xcarchive -exportPath export \
      -exportOptionsPlist ExportOptions-appstore-manual.plist > exportipa.log 2>&1
    ls -la export/skybreaker.ipa
    if [ "${2:-}" = "upload" ]; then
      xcrun altool --upload-app -f export/skybreaker.ipa -t ios --apiKey A726RHWTX7 \
        --apiIssuer f2fcaeb1-4500-4e62-89bc-83d05e013db3
    fi ;;
  *) echo "usage: $0 android | ios [upload]"; exit 2 ;;
esac
