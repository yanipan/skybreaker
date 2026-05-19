# Configure Android + iOS export presets in Godot

After export templates are installed (`2-install-export-templates.md`).

Open Skybreaker in Godot, then **Project → Export…**

---

## Android preset

Click **Add… → Android**.

### Top of panel
- **Name:** `Android Release`
- **Runnable:** ☑ (checked)
- **Export Path:** `builds/skybreaker.aab`

### Options → Custom Template
- Leave all blank.

### Options → Gradle Build
- **Use Gradle Build:** ☑ (REQUIRED for AAB)
- **Export Format:** `AAB - Android App Bundle`

### Options → Architectures
- **armeabi-v7a:** ☑
- **arm64-v8a:** ☑
- everything else unchecked

### Options → Version
- **Code:** `1`
- **Name:** `1.0.0`

### Options → Package
- **Unique Name:** `com.origami.skybreaker`
- **Name:** `Skybreaker`
- **Signed:** ☑

### Options → Launcher Icons
- **Main 192x192:** `res://assets/sprites/ui/store_icon_1024.png` (Godot will downscale)
- (adaptive icon fields — leave blank for now, Godot auto-generates from the main icon)

### Options → Keystore
- **Release:** `C:/Users/User/keys/skybreaker-release.keystore`
- **Release User:** `skybreaker`
- **Release Password:** (paste the password you set when generating the keystore)

### Options → Screen
- **Immersive Mode:** ☑
- All "Support" sizes: ☑

Click **Close**. Godot writes `export_presets.cfg` in the project root.

---

## iOS preset

Click **Add… → iOS**.

### Top of panel
- **Name:** `iOS Release`
- **Runnable:** ☑
- **Export Path:** `builds/skybreaker.xcodeproj`

### Options → Application
- **App Store Team ID:** *(your Team ID from developer.apple.com — 10 chars, e.g. `A726RHWTX7` IS the API key id, NOT the team id; find Team ID in Apple Developer → Membership)*
- **Bundle Identifier:** `com.origami.skybreaker`
- **Signature:** `iPhone Distribution: <your name>` (leave blank — Xcode will set on archive)
- **Version:** `1.0.0`
- **Short Version:** `1.0.0`

### Options → Icons & Launch Screens
- **App Icon:** `res://assets/sprites/ui/store_icon_1024.png`
- **Launch Screen:** `res://assets/sprites/ui/gamelogo.png`

### Options → Capabilities
- All unchecked.

### Options → Orientation
- **Portrait** only (matches `project.godot`).

Click **Close**.

---

## After both presets exist

Verify `C:\Users\User\Skybreaker\export_presets.cfg` exists and contains both presets. From now on you can use the headless build scripts in this folder.
