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
| `Levels.gd` | Resource | Level/wave definitions, 24 sectors in 6 acts (1-5, 6-10, 11-15, 16-19, 20-22, 23-24); bosses at 4, 8, 12, 16, 19, 22, 24 (pair); MINI-BOSSES (`mini_boss` key, an already-beaten boss returns at 50%, `Boss.mini` = 78% size, slower fire, 25% reward, torpedo + health + money drops, sector cannot end while it lives, no asteroids meanwhile) at 6 Hornet, 10 Tortoise, 14 Hive, 17 Prism, 21 Reaper, 23 Archon. Test `MiniBossTest.tscn` |
| `Enemy.gd` | Node2D | Base enemy logic. 16 pooled types + SHARD. Added 9/11: SHADE (cloaks, untouchable), ARTILLERY (holds, fused mortar), MINELAYER (sideways, fused mines), SPLITTER (dies into 2 SHARDs), PULSAR (ring volleys), HUNTER (homing missiles), BEAMER (holds, telegraphed `EnemyBeam`). Each loads `assets/sprites/enemy_<name>.png` if present, else a tinted stand-in. 11/11: JINKER (17, from sector 10) side-jinks out of incoming player shots (`_update_jink`, JINK_* consts; homing missiles + beam counter it). ARMED VARIANTS: `alt_pattern`/`alt_every` (set by EnemySpawner from `Enemy.ARMED_TABLE` via `roll_armed`): beam TANKs from 10, homing BOMBERs from 8, homing STRAFERs from 14, beam LANCERs from 16, marked by a cyan (beam) / orange (homing) ring. Test `EvasionTest.tscn`, look `EvasionShot.tscn` |
| `Boss.gd` | Node2D | Boss phases and patterns. 8 types: BOSS1-5, FINAL, ARCHON (sector 22, sweeping beam, `boss6.png`), HERALD (finale escort, homing volleys, `boss7.png`) |
| `BossPart.gd` | Area2D | Breakable boss part (turret, plate, segment, weak point): own HP or `core_transfer` to the core, in `enemies` + `boss_parts` (not `bosses`). Boss: `add_part`, `part_fire(part)` by `pattern`, `core_shielded()` (core takes 15% while a `shields_core` part lives), `hit_half` box read by HitCheck. IRON TORTOISE is multi-part (10/11). Designs + roadmap: `docs/BOSS_DESIGNS.md`. Tests: `BossPartsTest.tscn`, look check `BossShot.tscn` (windowed) |
| `EnemySpawner.gd` | Node | Spawns waves from Levels data; boss queue (`escort_boss` then `boss_type`), `boss_sequence_done()` / `ends_on_boss()` gate the stage end in Main |
| `StarbaseShop.gd` | Node | Between-level shop (upgrade purchases) |
| `Starbase.gd` | Node | Starbase scene controller |
| `Cutscene.gd` | Node | Cutscene player; `CutsceneData.gd` holds data. Plays `assets/audio/narration/<image_file>.mp3` per beat (made by `scripts/tools/narration_tts.mjs`, Inworld voice Eldrin) over `assets/audio/music/cutscene_mystery.mp3` (made by `scripts/tools/make_cutscene_music.py`) |
| `Sidekick.gd` | Node2D | Companion ship, persists across levels if alive; charged shield eats one whole hit |
| `Bullet.gd` | Area2D | Player bullet (pooled) |
| `EnemyBullet.gd` | Area2D | Enemy bullet. Style defaults OVERWRITE speed/radius/colour: set `speed_override` etc. for custom values. `burst_after`/`burst_count` = fused shell or mine, `homing_turn_rate`/`homing_secs` = homing missile. Redraws only while its trail grows, while steering, or every 3rd frame for animated styles |
| `EnemyBeam.gd` | Area2D | Enemy beam: warning line for `charge_secs`, then a damaging column for `fire_secs`; follows its emitter, cancelled if the emitter dies during the wind-up |
| `Torpedo.gd` | Area2D | Player torpedo (secondary). `tier` 0-3 = TORPEDO WARHEAD shop upgrade (`Player.torpedo_tier`, carried and saved): body x1.65, blast radius x1.65, damage 24 -> 60 at level 3, deeper and layered boom |
| `Missile.gd` | Area2D | Homing missile primary; 90% damage to bosses; small fireball on every impact |
| `Beam.gd` | Node2D | Continuous beam weapon |
| `Pickup.gd` | Area2D | Money, health, power-up drops |
| `Explosion.gd` / `EnemyExplosion.gd` | Node2D | Particle FX |
| `WeaponMeters.gd` | Control | HUD weapon charge display |
| `MobileControls.gd` | Control | Touch input layer. Since 9/11: ONE fire wheel (`MobileFireWheel.gd`, three 120-degree wedges P / B / M, touch or slide to switch without lifting) plus a separate red torpedo button in the corner pocket (a firing thumb can curl onto it: one torpedo per visit, gun keeps firing). A finger that starts on the wheel is tracked in `_input` until it lifts |
| `ParallaxBg.gd` | Node2D | Scrolling background |
| `Starfield.gd` | Node2D | Star particle layer |
| `ScorePopup.gd` | Node2D | Floating score text |
| `StartScreen.gd` | Node | Main menu |

## GameState Quick Reference

```gdscript
GameState.money          # int — current run money
GameState.lives          # int — 3 to start, max 5
GameState.current_level  # int 1..24
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
  enemy_shade/artillery/minelayer/splitter/pulsar/hunter/beamer.png (9/11, generated; see docs/ART_PROMPTS_24.md)
  boss1..boss5.png + finalboss.png + boss6.png (Null Archon) + boss7.png (Herald)
  All in-play sprites are transparent cut-outs: scripts/tools/cutout_sprite.py
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

**Primary** — auto-fire, power levels 1–30 per weapon (26-30 added 9/11: 9-bullet phaser and 6-missile salvo at L27+, violet VOID tier dmg 4 at L28+), charge drain/recharge system. Three types, cycled in flight (`Player.WeaponType`):
- Phaser (`PHASER`) — bullets, baseline rate (6.9 base shots/sec, +0.49/level)
- Plasma Beam (`BEAM`) — continuous laser, drains charge ~3x faster, boss killer
- Homing Missiles (`MISSILE`) — slower fire, homing
(`GameState.current_primary_weapon_id` still defaults to `&"vulcan"` and `current_secondary_weapon_id` to `&"bomb"`; both are legacy fields, there is no vulcan cannon, smart bomb, EMP, drone or nuke weapon in the game. Store copy must say THREE weapon systems plus torpedoes.)

**Torpedoes** — separate button, limited ammo, max 2 base (refill in shop)

**Upgrades (Starbase Shop):**
- Hull repair, Shield (regen buffer, max 6), Engine (speed tier 0–3), Energy Cells (extend charge pool, max 8), per-weapon power ups, torpedo bay (max 10) + refill, sidekick

## Balance Notes (current tuning)
- Fast fire rate: 6.9 shots/sec base (raised from 5.4 → 6.4 → 6.9 for phaser feel)
- Fire rate bonus per level: 0.49/level (dropped from 0.62 to make L25 ≈ old L20)
- Max power level: 30 (20 → 25 → 30; levels 26-30 are real growth for the 24-sector ladder)
- Max charge: 100 base, +40% per energy cell, max 8 cells; shield max 6, torpedo bay max 10
- Death penalty: lose a life and restart the sector; weapons and gear are kept
- Enemy fire damage (10/11): base values 3-10 per attack (grunt 3, aimed 4, tank/hunter/mine/mortar 6, beamer 8, lancer 9, boss beam 10), scaled by `GameState.enemy_damage_mul()` = x1.0 sector 1 -> x1.35 sector 24, applied once in `EnemyBullet._ready` / `EnemyBeam._ready` (burst pellets carry `damage_scaled`). HEAVY hits (base >= 8, `GameState.is_heavy_hit`) cost 2 shield pips; with 1 pip left half the hit reaches the hull. `GameState.difficulty_damage_mul` is the hook for future difficulty levels (not saved yet). Test `EnemyDamageTest.tscn`

## Story clips
- A cutscene beat plays `assets/cutscenes/<image_file>.ogv` when it exists (one per cutscene: intro launch 10 s, acts 1-5 6 s each, ending 10 s). Godot plays only Ogg Theora: convert with `scripts/tools/clip_to_ogv.sh clip.mp4 out.ogv 5` (720 wide, quality 5, no audio, about 2 MB per 10 s).
- Clips are generated from the existing stills (image-to-video) with the translate skill's `art.mjs --engine grok --video --image still.png --duration 6|10`; see docs/ART_PROMPTS_24.md. Always check frames before installing.
- `scenes/tools/CutsceneVideoShot.tscn` (windowed) proves a clip plays, covers the screen and sets the beat length.

## Performance (measure, do not guess)
- `godot --headless --fixed-fps 60 --path . res://scenes/tools/PerfProbe.tscn` prints CPU ms per frame on a busy sector 24 (ship untouchable, firing). 9/11: 4.30 ms -> 2.26 ms on the M-series Mac after the shot pass.
- Rules that came out of it: never `queue_redraw()` every frame on anything that exists 100 times (shots draw once, pulse through `modulate`); flatten per-frame lookups (`HitCheck` caches enemies and the ship once per frame); share collision shapes; `run/max_fps=60`.
- Headless measures scripts + physics + draw-command building, not GPU fill. Phone heat still needs a device check.

## Co-op multiplayer (in progress, started 11/11; plan + protocol + phases in `docs/MULTIPLAYER_PLAN.md`)
- Server-authoritative: one headless Godot process per room runs `scenes/net/ServerWorld.tscn` (the real `EnemySpawner` + world objects, fixed 816x1800 field). Phones keep owning their own ship, shots, damage taken, money, shop and lives.
- `scripts/net/Net.gd` (autoload `Net`, raw ENet, inert while `mode == OFF`), `ServerWorld.gd`, `NetClient.gd` (puppets, interpolation 100 ms behind the server clock, local enemy shots, kills, pickup grants), `NetBot.gd` (headless bot).
- Puppet mode: `net_puppet` / `net_id` on `Enemy` and `Asteroid` (no AI, no self-despawn, `take_damage` -> `Net.report_hit`, death via `net_kill`); `Pickup.net_id` + claim in `Player._on_area_entered`; burst pellets carry meta `net_local` (each phone bursts its own shell).
- RULE: never read a node back from a net table into a TYPED variable (`var n: Node = d.get(id)`): a freed instance makes that assignment an error that aborts the caller. That froze a bot's whole update loop on 11/11.
- Tests: `scenes/tools/NetClientTest.tscn` (no network, 21 checks incl. the freed-object race) and `scripts/net/run_loop_test.sh [sector] [duration_mul] [lag_ms] [loss] [port]` (server + 2 bots as separate processes).
- Not built yet: Main/Player integration (nothing is playable), partner ship, bosses, starbase/shop, revive pods, lobby, GCP deploy, AI partners (phase 7).

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
