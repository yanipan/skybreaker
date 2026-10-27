# Save schema (v2)

**File:** `user://savegame.dat` (JSON, single file). Written atomically: `SaveSystem.save_game()` writes `user://savegame.tmp`, closes it, rotates the previous `savegame.dat` to `user://savegame.bak`, then renames the `.tmp` over `savegame.dat`. A failed temp write keeps the previous save untouched.
**Version:** `2` — bumped from v1. v1 saves load with defaults for missing fields.

## Why v2 exists

The audit that precedes this document found that **v1 was effectively broken** for a shipping game:

- `has_active_run` was in-memory only → Continue button always disabled after relaunch.
- `current_level` wasn't persisted → every relaunch dropped the player back to Sector 1.
- `lives` wasn't persisted → quit mid-run reset to 3 lives on relaunch.
- All `carry_*` state (HP, shield, weapon levels, torpedoes, max shield, max torpedoes, speed tier, energy cells, sidekick) wasn't persisted → every quit wiped shop upgrades and in-progress gear.
- All `respawn_*` state wasn't persisted → quit during the death-respawn window lost the respawn stash.
- v1 also stored `current_sector`, `current_mission`, `ship_id`, `primary_weapon_id`, `secondary_weapon_id` — fields the game does not actually read. Legacy Phase-0 scaffolding.

v2 drops the dead v1 fields and persists the fields the live gameplay actually uses.

## Fields persisted

| Key | Type | Default on load | Written from | Purpose |
|---|---|---|---|---|
| `version` | int | — | SaveSystem | Schema version (2). |
| `has_active_run` | bool | false | StartScreen / Main | Continue button enable. |
| `current_level` | int | 1 | Main warp-transition | Which sector to reload into. |
| `lives` | int | `STARTING_LIVES` (3) | Main death flow | Lives remaining. |
| `money` | int | 0 | GameState.add_money | Persistent funds. |
| `total_score` | int | 0 | GameState.add_score | Cumulative across runs. |
| `high_score` | int | 0 | GameState.commit_high_score | Best mission score. |
| `intro_seen` | bool | false | Main cutscene `finished` callback (on intro dismiss) | Stops the intro replaying on Continue / respawn within the run. New Game resets it to false (`StartScreen._on_new_game`), so every New Game replays the intro; SKIP dismisses it. |
| `carry_active` | bool | false | Main._finish_warp_transition | Carry slot populated. |
| `carry_hp` | int | 0 | same | HP snapshot at warp. |
| `carry_shield` | float | 0.0 | same | Shield snapshot. |
| `carry_power_level` | int | 1 | same | Legacy power level. |
| `carry_weapon_levels` | Dictionary[int,int] | {} | same | Per-weapon slot levels. Keys are WeaponType enum ints. |
| `carry_torpedo_count` | int | 0 | same | Torpedoes in tube. |
| `carry_weapon_type` | int | 0 | same | Active weapon (Phaser/Beam/Missile). |
| `carry_max_shield` | int | 1 | same | Shop-bought shield cap. |
| `carry_max_torpedoes` | int | 2 | same | Shop-bought torpedo cap. |
| `carry_speed_tier` | int | 0 | same | Shop-bought speed tier (0..3). |
| `carry_energy_cells` | int | 0 | same | Shop-bought energy cells (0..4). |
| `carry_sidekick` | bool | false | same | Whether a sidekick was alive at warp. |
| `respawn_pending` | bool | false | Main death handler | Respawn slot populated. |
| `respawn_hp` | int | 0 | same | HP to restore on respawn. |
| `respawn_shield` | float | 0.0 | same | |
| `respawn_power_level` | int | 1 | same | |
| `respawn_weapon_levels` | Dictionary[int,int] | {} | same | |
| `respawn_torpedo_count` | int | 0 | same | |
| `respawn_weapon_type` | int | 0 | same | |
| `respawn_max_shield` | int | 1 | same | |
| `respawn_max_torpedoes` | int | 2 | same | |
| `respawn_speed_tier` | int | 0 | same | |
| `respawn_energy_cells` | int | 0 | same | |

**Fields deliberately NOT persisted:**

- `pending_warp_entry` — one-frame signal, meaningless across sessions.
- Per-mission stats (`mission_score / mission_money / mission_kills / mission_damage_taken`) — reset at the start of every level; no value in persisting.

## When save is written

`GameState.save_run_state()` (thin wrapper over `SaveSystem.save_game()`) is called at every state-change checkpoint:

| Trigger | File / Location |
|---|---|
| New Game button | `StartScreen._on_new_game` (after clearing carry/respawn, setting `has_active_run = true`) |
| Level complete | `Main._finish_warp_transition` (AFTER all `carry_*` writes + `current_level++`) |
| High-score commit | `GameState.commit_high_score` (always saves, not conditional on new record) |
| Player death | `Main._on_player_died` (after `stash_respawn`) |
| Pause opened | `Main._open_pause` (mobile home-swipe risk) |
| App backgrounded / focus lost | `Main._notification` on `NOTIFICATION_APPLICATION_PAUSED` / `FOCUS_OUT` during an active run: snapshots the player, saves, pauses the tree, then opens the PAUSED overlay on the next idle frame. Returning (RESUMED / FOCUS_IN) never auto-resumes; the player taps RESUME. If the shop already holds the tree paused it only snapshots + saves. |
| Main Menu from pause | `Main._on_main_menu` (explicit quit-ish) |
| Shop purchase | `StarbaseShop._on_buy` (after applying purchase, deducting money) |
| Cutscene dismissed | `Main._begin_cutscene` finished callback (when `intro_seen` flips true) |

## When save is read

Exactly once, at autoload init: `SaveSystem._ready()` → `load_game()` → `_apply_save_data()`. No mid-session re-reads.

## Corruption handling

- Missing or unreadable `savegame.dat` → `load_game()` falls back to `savegame.bak` (covers a crash between the two renames).
- Missing file and no `.bak` → `load_game()` returns silently; fresh defaults.
- Malformed JSON in `savegame.dat` → treated like a missing file (`.bak` fallback). Only if both are bad does GameState stay at compile-time defaults and the player start fresh.
- Missing fields (v1 → v2 upgrade) → `_apply_save_data()` uses `.get(key, default)` on every field; any v1 save loads cleanly with money/high_score preserved and everything else defaulted.
- `carry_weapon_levels` / `respawn_weapon_levels` — JSON parses numeric keys as strings, so `_to_int_key_dict()` converts `{"0": 3, "1": 2}` back to `{0: 3, 1: 2}` on load. Non-numeric keys dropped.

## Manual test matrix

After this change lands, verify these end-to-end flows on a real mobile device (or Godot editor + delete save file between tests):

1. **Fresh install → new run → mid-sector quit → relaunch Continue.** Sector number preserved, HP/shield/weapon levels preserved.
2. **Sector warp → quit during warp cinematic → relaunch Continue.** Arrives in next sector with carry gear.
3. **Starbase shop purchase → quit from Starbase → relaunch Continue.** Money deducted persistently, upgrade applied to carry state.
4. **Die → hit pause during death cinematic → quit → relaunch Continue.** Respawn slot preserved, arrives in same sector with 50% gear.
5. **Finish sector 20 → game marks run complete → relaunch.** High score persisted, has_active_run=false so Continue is disabled, New Game starts fresh.
6. **New Game twice.** The intro plays on every New Game (SKIP works); Continue and respawns within the run never replay it.
7. **Mid-sector home swipe → return.** PAUSED overlay is showing, gameplay stays frozen until RESUME; killing the app while backgrounded and relaunching Continue restores the snapshot.

Bugs found during these tests go into a follow-up fix cycle — not part of this audit.

## Known limitations (deliberate)

- **No cloud sync.** Local-only save. Reinstalling the app or switching devices loses progress.
- **Single save slot.** No "save slot A/B/C" UI. One run at a time.
- **No integrity check.** A malicious user can edit `savegame.dat` to give themselves infinite money. Acceptable for a premium single-player game.
- **No periodic / timed auto-save.** Saves happen on state change only. A 10-minute session with no shop visit, no death, and no sector complete would lose its progress on a crash. Mitigation: saves fire on `_open_pause` and on app background / focus loss, which covers the most common "user is about to quit" case.
