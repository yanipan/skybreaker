# Skybreaker — Store submission runbook

**For:** the human running the final build and upload on their own machine.
**Why this exists:** Godot submissions can't be fully automated from Claude. This runbook walks through every step that has to happen in an editor or shell on your build machine. Tick each item off before submitting.

---

## 0. Prerequisites (one-time, per machine)

### Both platforms
- [ ] **Godot 4.6 Mono or standard**, matching the project's `config/features` list in `project.godot`. Download from godotengine.org.
- [ ] Open the Skybreaker project once in the Godot editor so all import caches are built (first open is slow; subsequent opens are fast).
- [ ] Confirm `project.godot` has `config/version="1.0.0"` — this is what both stores display.

### Android
- [ ] **Android Studio** + **Android SDK** + **Java JDK 17**. Godot calls into these to build APK/AAB.
- [ ] In Godot: *Editor → Editor Settings → Export/Android* — set the paths for `Android SDK Path` and `Debug Keystore`.
- [ ] **Release keystore** (NOT the debug one). Generate once and keep it safe:
  ```
  keytool -genkey -v -keystore skybreaker-release.keystore -alias skybreaker \
          -keyalg RSA -keysize 2048 -validity 10000
  ```
  Store the `.keystore` file **outside** the repo (e.g. `~/keys/skybreaker-release.keystore`). Back it up — losing it means you can never ship an update to the same Play Store listing.

### iOS
- [ ] **macOS + Xcode** (iOS builds cannot be produced on Windows or Linux).
- [ ] **Apple Developer Program membership** ($99/year).
- [ ] App ID registered at developer.apple.com as `com.origami.skybreaker` (or whatever bundle ID you want to use — match it below).
- [ ] **Provisioning profile** + **Distribution certificate** generated in Developer Portal, imported into Xcode.

---

## 1. Export presets (one-time, in Godot editor)

In Godot, open *Project → Export*.

### Android preset
- [ ] *Add… → Android*
- [ ] Name: `Android Release`
- [ ] `Export Path`: `builds/skybreaker.aab`
- [ ] *Options / Application*:
  - Package Unique Name: `com.origami.skybreaker`
  - Name: `Skybreaker`
  - Signed: ✅
  - Target SDK: 34 (or latest required by Play Store at submission time)
  - Min SDK: 24
- [ ] *Options / Architectures*: `arm64-v8a` ✅, `armeabi-v7a` ✅, others unchecked
- [ ] *Options / Keystore*: point `Release` at your release keystore, `Release User` = `skybreaker`, `Release Password` = (the password you set during keytool)
- [ ] *Options / Package Format*: Android App Bundle (`.aab`) — Play Store requires AAB for new listings
- [ ] *Options / Permissions*: leave all unchecked (app needs none beyond the defaults Godot injects)
- [ ] *Options / Gradle Build*: Use Gradle Build ✅ (gives you a proper signed AAB instead of the default APK)

### iOS preset
- [ ] *Add… → iOS*
- [ ] Name: `iOS Release`
- [ ] `Export Path`: `builds/skybreaker.xcodeproj`
- [ ] *Options / Application*:
  - App Store Team ID: `<your Team ID from developer.apple.com>`
  - Bundle Identifier: `com.origami.skybreaker`
  - Signature: `iPhone Distribution: <your name>`
  - Version: matches project.godot's `config/version`
  - Short Version: same
- [ ] *Options / Capabilities*: leave everything unchecked unless you add features later
- [ ] *Options / Orientation*: Portrait only (matches `project.godot`)
- [ ] *Options / Launch Screens*: point at `res://assets/sprites/ui/gamelogo.png` for all device sizes

Godot's iOS export produces an `.xcodeproj` that you then open in Xcode, archive, and upload. There's no one-click "submit" from Godot for iOS.

---

## 2. App icons

The project currently has:
- `icon.svg` (Godot editor icon — NOT a store icon)
- `assets/sprites/ui/gamelogo.png` (used for boot splash)

You need a **dedicated store icon**: square, 1024×1024, PNG, no transparency, no rounded corners (stores round them automatically).

- [ ] Create `assets/sprites/ui/store_icon_1024.png` (1024×1024)
- [ ] For Android, use Godot's *Project → Export → Android → Options / Launcher Icons* section to generate the mipmap set from that single 1024 image. Godot handles the 48/72/96/144/192 dpi sizes automatically.
- [ ] For iOS, create an `AppIcon.appiconset` via Xcode's Asset Catalog after the `.xcodeproj` is exported. Drag the 1024×1024 into the `App Store` slot and Xcode generates the rest.

---

## 3. Privacy policy hosting

Both stores require a publicly accessible URL for the privacy policy at submission time.

- [ ] Publish `docs/PRIVACY_POLICY.md` (or a styled HTML version) to a public URL. GitHub Pages works fine — push the docs folder to a `gh-pages` branch and the policy is at `https://<user>.github.io/skybreaker/PRIVACY_POLICY.html`.
- [ ] Copy that URL into both store listings (App Store Connect → App Information → Privacy Policy URL, and Play Console → App content → Privacy policy).

---

## 4. App Store Connect / Play Console listings

Use the copy in `docs/APP_STORE_COPY.md` verbatim — already sized for both stores.

### Apple App Store
- [ ] Create app record in App Store Connect (App ID `com.origami.skybreaker`, SKU `skybreaker-ios`, primary language English)
- [ ] Fill in App Information (name, subtitle, category, age rating)
- [ ] Fill in Pricing & Availability (one-time purchase price, territories)
- [ ] Fill in App Privacy (declare "Data Not Collected" per the privacy policy)
- [ ] Upload screenshots (at least one set per device size — 6.7", 6.5", 5.5" required; iPad if you support tablet)
- [ ] Upload preview video (optional but boosts conversion)
- [ ] Submit for review

### Google Play
- [ ] Create app in Play Console (package name `com.origami.skybreaker`, default language English)
- [ ] Fill in Main store listing (title, short description, full description, icon, feature graphic, screenshots)
- [ ] Fill in App content (privacy policy URL, ads declaration = "No", target audience = 13+, content rating questionnaire)
- [ ] Fill in Pricing & distribution (paid, territories)
- [ ] Upload AAB to Production track
- [ ] Submit for review

---

## 5. Build commands (copy-paste)

Once presets exist and icons/signing are in place, these are the one-line exports:

### Android (AAB for Play Store)
```
godot --headless --export-release "Android Release" builds/skybreaker.aab
```

### iOS (Xcode project — you then archive + upload in Xcode)
```
godot --headless --export-release "iOS Release" builds/skybreaker.xcodeproj
open builds/skybreaker.xcodeproj
```
Then in Xcode: *Product → Archive → Distribute App → App Store Connect*.

### Verifying the AAB (optional but recommended)
```
bundletool validate --bundle=builds/skybreaker.aab
bundletool build-apks --bundle=builds/skybreaker.aab --output=builds/skybreaker.apks
bundletool install-apks --apks=builds/skybreaker.apks  # install on a connected test device
```

---

## 6. Pre-submission smoke test

**DO NOT SKIP.** The stores will happily accept a broken build and deploy it to your players.

- [ ] Install the release build on a real device (not the editor, not an emulator).
- [ ] Run through the 6 save-system scenarios in `docs/SAVE_SCHEMA.md` — confirm all pass.
- [ ] Play at least 2 sectors with beam, phaser, and missile loadouts. Confirm no crashes, 60 FPS on a mid-tier phone.
- [ ] Test each of the 6 cutscenes (fresh save → intro; force current_level via a debug build; after sector 5/10/15/19/20).
- [ ] Confirm the pause button on mobile opens the pause overlay.
- [ ] Confirm rotate lock (device should NOT rotate to landscape).
- [ ] Confirm the app handles home-swipe → relaunch without data loss.

---

## 7. Post-submission

- [ ] **Apple:** typically 24-48h review. May get rejected for minor compliance issues; iterate.
- [ ] **Google:** typically a few hours on first submission, can be same-day on updates. May require additional declarations (ads, data safety) on first listing.
- [ ] Once live, bump `config/version` to `1.0.1` for the next build.
- [ ] Keep the keystore + signing certs backed up offline. **Losing them is irrecoverable.**
