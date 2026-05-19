# Install Godot Android + iOS export templates (one-time)

After JDK 17 and Android Studio are installed:

## 1. Set Godot editor settings (one-time)

Launch Godot: `C:\Users\User\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe`

Open Skybreaker project. **First open builds the import cache — be patient (~5–10 min).**

Then: **Editor → Editor Settings** (top menu)

Navigate to **Export → Android**:
- **Android SDK Path:** `C:\Users\User\AppData\Local\Android\Sdk`
- **Debug Keystore:** leave default (`<editor>/debug.keystore` — Godot ships one)

(If Android Studio installed the SDK somewhere else, find it: usually `%LOCALAPPDATA%\Android\Sdk`.)

## 2. Install export templates

**Project → Tools → Manage Export Templates → Download and Install**

This downloads ~700 MB of templates for all platforms (Android + iOS + Web + Linux + macOS + Windows). Takes 5–10 minutes.

When it finishes, you can close the dialog. Templates are at:
`C:\Users\User\AppData\Roaming\Godot\export_templates\4.6.2.stable\`

## 3. Verify with the project

**Project → Export…** should now show no warnings about missing templates.

Don't add presets in the UI — we'll do that via `export_presets.cfg` next.
