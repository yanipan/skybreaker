# Skybreaker — Roadmap

**Source of truth for project phases.** Updated by the PM agent.

---

## Phase 0 — Foundation (Current)
**Goal:** Project exists, team aligned, tooling ready.

- [x] Project folder created
- [x] Git initialized
- [x] Agent team defined (.claude/agents/)
- [x] Game Design Document v0.1 written
- [x] Godot project skeleton scaffolded
- [ ] Install Godot 4.3+ and open project
- [ ] First commit pushed to remote repo
- [ ] Balance doc v0.1 (Game Expert)
- [ ] Art style guide v0.1 (Graphics)
- [ ] UX flows v0.1 (UI/UX)

**Exit criteria:** Godot opens the project, all agents have posted their v0.1 docs.

---

## Phase 1 — MVP Playable
**Goal:** One sector is fully playable end-to-end on a device.

### Gameplay
- [ ] Player ship moves via drag input
- [ ] Auto-firing primary weapon (Vulcan Cannon)
- [ ] Bullet pooling system
- [ ] Enemy spawner with timeline/wave system
- [ ] 5 enemy types for Sector 1 (Grunt, Gunner, Dodger, Tank, Swarmer)
- [ ] Collision detection (player vs enemy, bullets vs entities)
- [ ] Pickups (money, health, power-up)
- [ ] Sector 1 boss
- [ ] Player death + game over flow

### Systems
- [ ] GameState autoload
- [ ] SaveSystem autoload (JSON, versioned)
- [ ] EventBus autoload
- [ ] AudioManager autoload (SFX + music)
- [ ] Object pooling for bullets and particles

### UI
- [ ] Splash → Main Menu
- [ ] Mission Select (Sector 1 only)
- [ ] Pre-mission briefing
- [ ] Gameplay HUD (score, money, health, secondary)
- [ ] Pause menu
- [ ] Mission results screen
- [ ] Hangar (basic: weapons + upgrades tabs)
- [ ] Options screen

### Content
- [ ] 1 ship (Scout)
- [ ] 2 primary weapons (Vulcan, Spread)
- [ ] 3 upgrade tiers per weapon
- [ ] 5 missions + 1 boss mission for Sector 1
- [ ] Basic SFX library
- [ ] 1 placeholder music track

### Polish
- [ ] Screen shake on hit/explosion
- [ ] Hit flash on damage
- [ ] Particle explosions
- [ ] Haptic feedback
- [ ] 60 FPS on mid-tier Android test device

**Exit criteria:** A new player can install, open, play through 5 missions + boss, upgrade their ship, and come back for more. Runs at 60 FPS on a Pixel 5 or equivalent.

---

## Phase 2 — Content Expansion
**Goal:** Sectors 2 and 3 complete. Polish pass on Sector 1.

- [ ] Sector 2 (Lunar Defense) — 10 missions + boss
- [ ] Sector 3 (Asteroid Belt) — 10 missions + boss
- [ ] 3 more weapons (Plasma, Homing, Rail)
- [ ] 1 more ship unlock (Striker)
- [ ] Secondary weapons system (bombs, EMP, drones)
- [ ] Star objectives (3 stars per mission)
- [ ] Mission replay & branching
- [ ] Polish pass on Sector 1 based on playtest feedback

**Exit criteria:** 28 missions playable, 5 weapons, 2 ships, full secondary weapon system.

---

## Phase 3 — Full Campaign
**Goal:** All 5 sectors complete. Game is "content complete."

- [ ] Sector 4 (Alien Frontier) — 10 missions + boss
- [ ] Sector 5 (Mothership) — 10 missions + final boss
- [ ] Remaining ships (Fortress, Phantom, Titan)
- [ ] Complete upgrade tree (all tiers for all weapons)
- [ ] End-to-end balance pass
- [ ] Full soundtrack (5 sector tracks + boss theme + menu)
- [ ] Credits sequence

**Exit criteria:** Full 48+ mission campaign playable start to finish, all content present, feels balanced.

---

## Phase 4 — Launch Prep
**Goal:** Ship it.

- [ ] Rewarded ads integration (AdMob)
- [ ] Cosmetic IAP (ship skins, trails)
- [ ] Tutorial/onboarding polish
- [ ] Accessibility features (colorblind, haptics, motion)
- [ ] Localization pass (start with English, plan for 5+ languages)
- [ ] App Store assets (icon, screenshots, trailer, description)
- [ ] Privacy policy, terms
- [ ] Beta test (TestFlight / Play Console closed testing)
- [ ] Bug triage and fixes
- [ ] Store submission

**Exit criteria:** Live on App Store and Google Play.

---

## Phase 5 — Post-launch
**Goal:** Live game, happy players.

- [ ] Analytics & crash reporting
- [ ] Weekly events / daily missions
- [ ] Community feedback loop
- [ ] Patches and balance updates
- [ ] New content (bonus sector, new ships, new weapons)
- [ ] Seasonal events

---

## Risk Watchlist
See `docs/RISKS.md` for details.

- **Scope creep** — full 5-sector vision is ambitious. PM must defend phase boundaries.
- **Custom art cost** — start with free assets, budget custom art only for bosses & hero pieces.
- **Mobile performance** — profile early, profile often. Pool everything.
- **iOS signing complexity** — first iOS export is always painful. Budget extra time.
- **Ad SDK integration** — AdMob setup + Play Store policies can block release.

---

*Updated by: PM agent. Next review: end of Phase 0.*
