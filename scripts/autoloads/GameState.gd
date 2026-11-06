extends Node
## Global game state singleton.
## Holds runtime data for the current player session.
## Persistent data is loaded/saved via SaveSystem.

# True once the player has started a run from the start screen. Powers the
# Continue button — if false, the start screen disables it.
var has_active_run: bool = false

# Set by the start screen's CONTINUE button, consumed by Main._ready: skip
# the intro cutscene and show a 3-2-1 countdown instead. Never persisted.
var resume_pending: bool = false

# --- Player settings ---
# Kept in their own file (not the run save) so NEW GAME / delete_save never
# resets them. Loaded once at autoload time.
const SETTINGS_PATH: String = "user://settings.cfg"
## Touch fire scheme. AUTO: the ship fires on its own; holding the FIRE
## button ceases fire (lets the charge refill). HOLD: the ship only
## fires while the FIRE button is held. Desktop mouse play is unaffected.
enum FireMode { AUTO, HOLD }
var fire_mode: int = FireMode.HOLD
## Which bottom corner holds the weapon + torpedo buttons. The other thumb
## steers. Default LEFT matches where the old FIRE button sat.
enum ControlsSide { LEFT, RIGHT }
var controls_side: int = ControlsSide.LEFT
## On-screen joystick in the corner opposite the weapon buttons.
var joystick_enabled: bool = true
## Session counters for PhysicsWatchdog; survive scene reloads, not relaunch.
var physics_stalls: int = 0
var physics_reloads: int = 0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# 6/11: the fire-mode setting is gone (per-weapon buttons are hold-to-
	# fire), so a saved AUTO from an older build is ignored.
	fire_mode = FireMode.HOLD
	controls_side = clampi(int(cfg.get_value("controls", "side", ControlsSide.LEFT)), ControlsSide.LEFT, ControlsSide.RIGHT)
	joystick_enabled = bool(cfg.get_value("controls", "joystick", true))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "fire_mode_v2", fire_mode)
	cfg.set_value("controls", "side", controls_side)
	cfg.set_value("controls", "joystick", joystick_enabled)
	var err: int = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("GameState: settings save failed (%d)" % err)


func set_controls_side(side: int) -> void:
	controls_side = clampi(side, ControlsSide.LEFT, ControlsSide.RIGHT)
	save_settings()


func set_joystick_enabled(on: bool) -> void:
	joystick_enabled = on
	save_settings()


func set_fire_mode(mode: int) -> void:
	fire_mode = clampi(mode, FireMode.AUTO, FireMode.HOLD)
	save_settings()
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


## Stash the player's current loadout, unreduced, for respawn after
## a non-fatal death. Half phasers, half torpedoes, etc — losing a life still
## stings but the player isn't reset to bare baseline.
func stash_respawn(p: Node) -> void:
	respawn_pending = true
	# No weapon penalty on death: dying already costs a life and restarts the
	# sector. HP/shields refill on respawn.
	respawn_hp = int(p.max_hp) if "max_hp" in p else 100
	respawn_shield = float(int(p.max_shield) if "max_shield" in p else 1)
	respawn_power_level = max(1, int(p.power_level) if "power_level" in p else 1)
	respawn_weapon_levels = {}
	if "weapon_levels" in p and p.weapon_levels is Dictionary:
		respawn_weapon_levels = p.weapon_levels.duplicate()
	respawn_torpedo_count = int(p.torpedo_count) if "torpedo_count" in p else 0
	respawn_weapon_type = int(p.weapon_type) if "weapon_type" in p else 0
	respawn_max_shield = int(p.max_shield) if "max_shield" in p else 1
	respawn_max_torpedoes = int(p.max_torpedoes) if "max_torpedoes" in p else 2
	respawn_speed_tier = int(p.speed_tier) if "speed_tier" in p else 0
	respawn_energy_cells = int(p.energy_cells_bought) if "energy_cells_bought" in p else 0


## No-penalty snapshot of the live player into the carry slot. Used by the
## level-complete warp AND by every mid-level save (pause, shop purchase,
## main menu, app focus-out). Player._ready consumes the carry/respawn slots
## on spawn, so without this a mid-level save would serialise an empty slot
## and Continue after an OS kill would boot with default gear.
## Unlike stash_respawn, nothing is lost: hp/shield/weapon levels are kept as-is.
func snapshot_player(p: Node) -> void:
	if p == null or not is_instance_valid(p):
		return
	carry_active = true
	carry_hp = int(p.hp) if "hp" in p else 0
	carry_shield = float(p.shield) if "shield" in p else 0.0
	carry_power_level = int(p.power_level) if "power_level" in p else 1
	# Full per-weapon slot dict so all three weapons survive.
	if "weapon_levels" in p and p.weapon_levels is Dictionary:
		carry_weapon_levels = p.weapon_levels.duplicate()
	else:
		carry_weapon_levels = {}
	carry_torpedo_count = int(p.torpedo_count) if "torpedo_count" in p else 0
	carry_weapon_type = int(p.weapon_type) if "weapon_type" in p else 0
	carry_max_shield = int(p.max_shield) if "max_shield" in p else 1
	carry_max_torpedoes = int(p.max_torpedoes) if "max_torpedoes" in p else 2
	carry_speed_tier = int(p.speed_tier) if "speed_tier" in p else 0
	carry_energy_cells = int(p.energy_cells_bought) if "energy_cells_bought" in p else 0
	# Sidekick (incl. one hired at the starbase) survives if currently in the field.
	carry_sidekick = p.get_tree().get_first_node_in_group(&"sidekick") != null


# --- Online run (leaderboard / challenges) ---
## Wave seed for the whole run (GameRng). Challenges reuse the challenger's.
var run_seed: int = 0
## Score for the whole run (mission_score resets every sector, total_score
## never resets). This is what the leaderboard ranks.
var run_score: int = 0
## Server-issued, single-use token; "" when the run started offline (unranked).
var run_token: String = ""
## Per cleared sector: {sector, score, t}. Sent with the final score so the
## server can sanity-check it.
var run_sectors: Array = []
var challenge_code: String = ""
var challenge_target: int = 0
var challenge_name: String = ""
## Result of the last finished run, shown on the start screen.
var last_run: Dictionary = {}


func begin_run(seed: int, code: String = "", target: int = 0, who: String = "") -> void:
	reset_mission_stats()
	run_score = 0
	run_seed = seed
	run_token = ""
	run_sectors = []
	challenge_code = code
	challenge_target = target
	challenge_name = who


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
	run_score += amount
	EventBus.score_changed.emit(total_score)


## Call when a run ends. If this run beat the high score, persist it.
func commit_high_score() -> void:
	if run_score > high_score:
		high_score = run_score
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
