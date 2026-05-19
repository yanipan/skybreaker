extends Node
## Global game state singleton.
## Holds runtime data for the current player session.
## Persistent data is loaded/saved via SaveSystem.

# True once the player has started a run from the start screen. Powers the
# Continue button — if false, the start screen disables it.
var has_active_run: bool = false
## True for one frame after a warp transition completes — Main reads this
## on _ready to play the "drop in from below" entry sequence with lingering
## warp streaks, then clears it.
var pending_warp_entry: bool = false

## True once the player has watched the intro cutscene at least once.
## Persisted so a returning player doesn't re-watch the 4-beat cold open
## every time they hit New Game on a fresh install. See Cutscene.gd.
var intro_seen: bool = false

# Player progression
var money: int = 0
var total_score: int = 0
var high_score: int = 0   ## Best mission_score ever achieved — persisted via SaveSystem
var current_sector: int = 1
var current_mission: int = 1

# --- Lives system ---
# Player starts a run with 3 lives. Dying decrements; reaching 0 ends the run
# and resets to Sector 1. Rare LIFE pickups can grant +1 mid-run.
const STARTING_LIVES: int = 3
const MAX_LIVES: int = 5
var lives: int = STARTING_LIVES

# After a non-fatal death, the next scene boots from these slots so the player
# resumes the same stage with HALF (rounded up) of their previous gear.
var respawn_pending: bool = false
var respawn_hp: int = 0
var respawn_shield: float = 0.0
var respawn_power_level: int = 1
var respawn_weapon_levels: Dictionary = {}   ## Per-weapon slot snapshot — supersedes respawn_power_level
var respawn_torpedo_count: int = 0
var respawn_weapon_type: int = 0
var respawn_max_shield: int = 1
var respawn_max_torpedoes: int = 2
var respawn_speed_tier: int = 0
var respawn_energy_cells: int = 0

# Level progression — 1..20. Drives wave library, background, difficulty.
var current_level: int = 1
const MAX_LEVEL: int = 20

# Current run state
var current_ship_id: StringName = &"scout"
var current_primary_weapon_id: StringName = &"vulcan"
var current_secondary_weapon_id: StringName = &"bomb"

# Run stats (reset each mission)
var mission_score: int = 0
var mission_money: int = 0
var mission_kills: int = 0
var mission_damage_taken: int = 0

# Carry-over slot — when a level completes successfully, the player's hp / shield /
# power_level / torpedo_count are stashed here so the next scene can restore them
# instead of resetting to defaults. Cleared on death.
var carry_active: bool = false
var carry_hp: int = 0
var carry_shield: float = 0.0
var carry_power_level: int = 1
var carry_weapon_levels: Dictionary = {}   ## Per-weapon slot snapshot — supersedes carry_power_level
var carry_torpedo_count: int = 0
var carry_weapon_type: int = 0   ## Persists Phaser/Beam/Missile choice across stages
# Starbase-shop upgrades — these are sticky for the run, also flow through carry slots.
var carry_max_shield: int = 1
var carry_max_torpedoes: int = 2
var carry_speed_tier: int = 0
var carry_energy_cells: int = 0
## True if a sidekick was alive at the end of the previous sector. The next
## scene re-spawns one (refilled to full HP/shield) on _ready.
var carry_sidekick: bool = false


func clear_carry() -> void:
	carry_active = false
	carry_hp = 0
	carry_shield = 0.0
	carry_power_level = 1
	carry_weapon_levels = {}
	carry_torpedo_count = 0
	carry_weapon_type = 0
	carry_max_shield = 1
	carry_max_torpedoes = 2
	carry_speed_tier = 0
	carry_energy_cells = 0
	carry_sidekick = false


func clear_respawn() -> void:
	respawn_pending = false
	respawn_hp = 0
	respawn_shield = 0.0
	respawn_power_level = 1
	respawn_weapon_levels = {}
	respawn_torpedo_count = 0
	respawn_weapon_type = 0
	respawn_max_shield = 1
	respawn_max_torpedoes = 2
	respawn_speed_tier = 0
	respawn_energy_cells = 0


## Stash 50% (rounded up) of the player's current loadout for respawn after
## a non-fatal death. Half phasers, half torpedoes, etc — losing a life still
## stings but the player isn't reset to bare baseline.
func stash_respawn(p: Node) -> void:
	respawn_pending = true
	# Death penalty is light: lose ONE weapon power level, keep everything
	# else intact. Otherwise dying in a late sector left the player with too
	# few power-ups to survive the rematch. HP/shields refill on respawn.
	respawn_hp = int(p.max_hp) if "max_hp" in p else 100
	respawn_shield = float(int(p.max_shield) if "max_shield" in p else 1)
	respawn_power_level = max(1, (int(p.power_level) if "power_level" in p else 1) - 1)
	# Snapshot the per-weapon slots, applying the same -1 penalty to whichever
	# slot was active when the player died. The other two slots carry forward
	# unchanged so a missile death doesn't punish the phaser progress you'd
	# already grinded for.
	respawn_weapon_levels = {}
	if "weapon_levels" in p and p.weapon_levels is Dictionary:
		var active_wt: int = int(p.weapon_type) if "weapon_type" in p else 0
		for k in p.weapon_levels.keys():
			var v: int = int(p.weapon_levels[k])
			if int(k) == active_wt:
				v = max(1, v - 1)
			respawn_weapon_levels[k] = v
	respawn_torpedo_count = int(p.torpedo_count) if "torpedo_count" in p else 0
	respawn_weapon_type = int(p.weapon_type) if "weapon_type" in p else 0
	respawn_max_shield = int(p.max_shield) if "max_shield" in p else 1
	respawn_max_torpedoes = int(p.max_torpedoes) if "max_torpedoes" in p else 2
	respawn_speed_tier = int(p.speed_tier) if "speed_tier" in p else 0
	respawn_energy_cells = int(p.energy_cells_bought) if "energy_cells_bought" in p else 0


func reset_mission_stats() -> void:
	mission_score = 0
	mission_money = 0
	mission_kills = 0
	mission_damage_taken = 0


func add_money(amount: int) -> void:
	money += amount
	mission_money += amount
	EventBus.money_changed.emit(money)


func add_score(amount: int) -> void:
	total_score += amount
	mission_score += amount
	EventBus.score_changed.emit(total_score)


## Call when a run ends. If this run beat the high score, persist it.
func commit_high_score() -> void:
	if mission_score > high_score:
		high_score = mission_score
		EventBus.high_score_changed.emit(high_score)
	# Save unconditionally — even if the score didn't beat the record, the
	# run state (current_level / carry_* / money / etc.) needs to persist
	# so quit-and-relaunch resumes correctly.
	SaveSystem.save_game()


## Write the full run state to disk. Call at every checkpoint that could
## be the last thing the player sees before the OS kills the app:
##   * Level complete (after carry snapshot)
##   * Respawn stash (after death)
##   * Shop purchase (money + upgrade committed)
##   * Pause menu opens (imminent quit is common on mobile)
##   * Cutscene dismissal (intro_seen flip)
##
## Thin wrapper so call sites don't need to know SaveSystem exists — they
## just say "state changed, save it."
func save_run_state() -> void:
	SaveSystem.save_game()
