# Skybreaker

Mobile vertical shoot-'em-up, Godot 4.3+, GDScript. iOS + Android, portrait, 60fps.
Solo project by Yaniv. Nearly complete — bug fix + fire-balance pass remaining.

**GitHub:** https://github.com/yanipan/skybreaker (remote not yet wired — set up when repo is created)

## Architecture

### Autoloads (always in scope, no `get_node` needed)
| Singleton | File | Purpose |
|-----------|------|---------|
| `GameState` | `scripts/autoloads/GameState.gd` | All runtime state: money, score, lives, weapon/shield/carry slots |
| `SaveSystem` | `scripts/autoloads/SaveSystem.gd` | JSON save/load. Call `GameState.save_run_state()` — don't call SaveSystem directly |
| `EventBus` | `scripts/autoloads/EventBus.gd` | All cross-system signals. Emit here instead of coupling nodes |
| `AudioManager` | `scripts/autoloads/AudioManager.gd` | SFX + music |
| `Fonts` | `scripts/autoloads/Fonts.gd` | Font resources |

### Scene Tree
```
Boot.tscn → StartScreen.tscn → Main.tscn (gameplay)
```
- `scenes/main/` — Boot.tscn, Main.tscn, StartScreen.tscn
- `scenes/player/` — (player scene dir)

### Key Scripts (`scripts/`)
| Script | extends | Role |
|--------|---------|------|
| `Player.gd` | Area2D | Drag-to-move, auto-fire, weapon/shield/torpedo/energy logic. Self-constructs collision on `_ready` — no .tscn needed |
| `Main.gd` | Node | Game loop, wave orchestration, level transitions |
| `Levels.gd` | Resource | Level/wave definitions |
| `Enemy.gd` | Node2D | Base enemy logic |
| `Boss.gd` | Node2D | Boss phases and patterns |
| `EnemySpawner.gd` | Node | Spawns waves from Levels data |
| `StarbaseShop.gd` | Node | Between-level shop (upgrade purchases) |
| `Starbase.gd` | Node | Starbase scene controller |
| `Cutscene.gd` | Node | Cutscene player; `CutsceneData.gd` holds data |
| `Sidekick.gd` | Node2D | Companion ship, persists across levels if alive |
| `Bullet.gd` | Area2D | Player bullet (pooled) |
| `EnemyBullet.gd` | Area2D | Enemy bullet |
| `Torpedo.gd` | Area2D | Player torpedo (secondary) |
| `Missile.gd` | Area2D | Homing missile secondary |
| `Beam.gd` | Node2D | Continuous beam weapon |
| `Pickup.gd` | Area2D | Money, health, power-up drops |
| `Explosion.gd` / `EnemyExplosion.gd` | Node2D | Particle FX |
| `WeaponMeters.gd` | Control | HUD weapon charge display |
| `MobileControls.gd` | Control | Touch input layer |
| `ParallaxBg.gd` | Node2D | Scrolling background |
| `Starfield.gd` | Node2D | Star particle layer |
| `ScorePopup.gd` | Node2D | Floating score text |
| `StartScreen.gd` | Node | Main menu |

## GameState Quick Reference

```gdscript
GameState.money          # int — current run money
GameState.lives          # int — 3 to start, max 5
GameState.current_level  # int 1..20
GameState.mission_score  # int — this mission only

# Weapon IDs (StringName)
GameState.current_primary_weapon_id   # &"vulcan" | &"phaser" | &"beam" | &"missile"
GameState.current_secondary_weapon_id # &"bomb" | &"emp" | &"shield" | &"drone" | &"nuke"

# Save — always through GameState, not SaveSystem directly
GameState.save_run_state()

# EventBus — use signals for cross-system comms
EventBus.screen_shake_requested.emit(intensity, duration)
EventBus.money_changed.emit(GameState.money)
```

## Coding Conventions

- **Godot 4 syntax throughout:** `@export`, `@onready`, `signal foo(x: int)`, `StringName` with `&""` literals
- **class_name** on all major scripts
- **`##` doc comments** on exports and non-obvious vars
- **No coupling through scene tree** for cross-system events — use EventBus signals
- **Save at every checkpoint:** level complete, death, shop purchase, pause open, cutscene dismiss
- Weapon type stored as `int` in carry slots (0=vulcan, 1=phaser, etc.) but as `StringName` in current_*_weapon_id — be careful with conversions

## Assets

```
assets/sprites/
  playership.png + banking variants (left/right)
  sidekickship.png + banking variants
  enemy_grunt/dodger/bomber/brooder/lancer/reaper/strafer/swarmer/tank.png
  boss1..boss5.png + finalboss.png
  starbase.png
  bg/          — background tiles
  shop/        — shop UI assets
  ui/          — HUD / menu assets

assets/audio/
  music/       — sector tracks
  sfx/         — sound effects

assets/fonts/
```

## Weapons (Player)

**Primary** — auto-fire, power levels 1–25 per weapon, charge drain/recharge system. Three types, cycled in flight (`Player.WeaponType`):
- Phaser (`PHASER`) — bullets, baseline rate (6.9 base shots/sec, +0.49/level)
- Plasma Beam (`BEAM`) — continuous laser, drains charge ~3x faster, boss killer
- Homing Missiles (`MISSILE`) — slower fire, homing
(`GameState.current_primary_weapon_id` still defaults to `&"vulcan"` and `current_secondary_weapon_id` to `&"bomb"`; both are legacy fields, there is no vulcan cannon, smart bomb, EMP, drone or nuke weapon in the game. Store copy must say THREE weapon systems plus torpedoes.)

**Torpedoes** — separate button, limited ammo, max 2 base (refill in shop)

**Upgrades (Starbase Shop):**
- Hull repair, Shield (regen buffer), Engine (speed tier 0–3), Cargo (money ×), Magnet (pickup radius), Energy Cells (extend charge pool, max 4), per-weapon power ups, torpedo refill, sidekick

## Balance Notes (current tuning)
- Fast fire rate: 6.9 shots/sec base (raised from 5.4 → 6.4 → 6.9 for phaser feel)
- Fire rate bonus per level: 0.49/level (dropped from 0.62 to make L25 ≈ old L20)
- Max power level: 25 (raised from 20; per-level formulas rescaled to match old L20 ceiling)
- Max charge: 100 base, +50% per energy cell, max 4 cells (300 total)
- Death penalty: lose 1 weapon power level on the active slot, keep everything else

## Store / Release
- `docs/STORE_SUBMISSION.md` — submission runbook
- `docs/APP_STORE_COPY.md` — store listing copy
- `docs/PRIVACY_POLICY.md` — privacy policy
- `docs/SAVE_SCHEMA.md` — save file schema reference
- Target: iOS + Android via Godot export (not EAS — native Godot export)

## Source of Truth Docs
- `GAME_DESIGN_DOC.md` — full design doc
- `ROADMAP.md` — phase checklist (NOTE: shows Phase 0 but project is nearly complete)
- `TASKS.md` — active task list (stale — update when working)
