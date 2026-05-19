# Skybreaker — Launch Checklist (live, May 2026)

Working checklist for shipping Skybreaker to App Store + Play Store. Owner: Yaniv.
See `STORE_SUBMISSION.md` for deeper "why" context; this doc is the punch list.

---

## Phase 0 — Foundation (machine setup)

- [x] Git baseline committed (`2a98bc5`)
- [ ] **GitHub repo created** at https://github.com/new — Owner `yanipan`, Name `skybreaker`, **Public**, no README/gitignore/license
- [ ] Remote wired + pushed: `git remote add origin git@github.com:yanipan/skybreaker.git && git push -u origin master`
- [ ] **JDK 17 installed** — https://adoptium.net/temurin/releases/?version=17 (Windows x64 MSI)
- [ ] **Android Studio installed** + SDK downloaded — https://developer.android.com/studio
- [ ] **Godot 4.6.2 already installed** ✅ at `C:\Users\User\OneDrive\Desktop\`
- [ ] Godot export templates installed (see `scripts/build/2-install-export-templates.md`)

## Phase 1 — Privacy policy hosting

- [x] HTML version written at `docs/privacy.html`
- [ ] **GitHub Pages enabled** on `yanipan/skybreaker`: Settings → Pages → Source = "Deploy from a branch" → Branch = `master` → Folder = `/docs` → Save
- [ ] Verify live at: `https://yanipan.github.io/skybreaker/privacy.html`
- [ ] Update `docs/APP_STORE_COPY.md` (line 88) privacy URL to point at the live GitHub Pages URL

## Phase 2 — Store icon

- [ ] Generate 1024×1024 via ChatGPT (prompt is in session history)
- [ ] Save as `C:\Users\User\Skybreaker\assets\sprites\ui\store_icon_1024.png`
- [ ] Verify: square, no transparency, no rounded corners, full bleed

## Phase 3 — Android build path

- [ ] Run `scripts/build/1-generate-keystore.ps1` — generate `C:\Users\User\keys\skybreaker-release.keystore` (BACK IT UP IMMEDIATELY — offline, password manager, USB)
- [ ] Open Skybreaker in Godot (first open takes 5–10 min for import cache)
- [ ] Set Editor Settings → Export/Android paths (see `scripts/build/2-install-export-templates.md`)
- [ ] Add Android Release preset (see `scripts/build/3-configure-export-presets.md`)
- [ ] Add iOS Release preset (same doc)
- [ ] Run `scripts/build/4-build-android.ps1` — produces `builds/skybreaker.aab`
- [ ] Optional: validate AAB with `bundletool validate --bundle=builds/skybreaker.aab`

## Phase 4 — iOS Xcode project export

- [ ] Run `scripts/build/5-export-ios-xcodeproj.ps1` — produces `builds/ios/skybreaker.xcodeproj` + zip
- [ ] Transfer zip to Mac (USB or cloud)
- [ ] Open in Xcode → Signing & Capabilities → set Team
- [ ] Product → Archive → Distribute App → App Store Connect → Upload
- [ ] Wait for "processing complete" email from App Store Connect (~10 min)

## Phase 5 — Screenshots

- [ ] Open `scenes/tools/StoreScreenshots.tscn` in Godot
- [ ] Press F6 — generates 32 PNGs into `assets/store/screenshots/{ios_phone,ios_tablet,android_phone,android_tablet}/`
- [ ] Verify all 32 wrote successfully

## Phase 6 — Apple App Store Connect

- [ ] **Register Bundle ID** `com.origami.skybreaker` at https://developer.apple.com/account/resources/identifiers/list
- [ ] **Create app record** at https://appstoreconnect.apple.com — App name `Skybreaker`, SKU `skybreaker-ios`, Primary language English
- [ ] Note the ASC App ID from the URL — set env: `$env:SKYBREAKER_ASC_APP_ID = '<id>'`
- [ ] Fill **App Information**: name + subtitle + category (Action) + age rating (9+, mild cartoon violence)
- [ ] Fill **Pricing & Availability**: paid, territories
- [ ] Fill **App Privacy**: "Data Not Collected" — see `docs/PRIVACY_POLICY.md`
- [ ] Upload **screenshots** from `assets/store/screenshots/ios_phone/` + `ios_tablet/`
- [ ] Paste copy from `docs/APP_STORE_COPY.md` (name, subtitle, keywords, description, what's new, support URL)
- [ ] **Build** appears in App Store Connect ~10 min after Xcode upload; attach it to the version
- [ ] **Submit for Review** (24–48h wait)

## Phase 7 — Google Play Console

- [ ] **Create app** at https://play.google.com/console — name `Skybreaker`, default language English, free or paid
- [ ] Grant `google-play-service-account.json` access to the new app: Users and permissions → invite the service account email → grant `Release manager` role for this app
- [ ] Fill **Main store listing**: title + short desc + full desc + icon + feature graphic + screenshots
- [ ] Fill **App content** (this is the big one): privacy policy URL + ads declaration (No) + target audience (13+) + content rating questionnaire + data safety form (no data collected)
- [ ] Fill **Pricing & distribution**: paid, territories
- [ ] **Production track** → Create new release → upload `builds/skybreaker.aab` → add release notes from `docs/APP_STORE_COPY.md`
- [ ] **Submit for review** (~few hours)

## Phase 8 — Post-submission

- [ ] Bump `project.godot` `config/version` to `1.0.1` ready for first patch
- [ ] Confirm keystore + .p8 + service account JSON all backed up offline
- [ ] Tag git: `git tag v1.0.0 && git push --tags`
- [ ] Update memory: project state moves from "near-complete" to "submitted, awaiting review"
