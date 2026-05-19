extends Node
## Persistent save/load system. JSON to user://savegame.dat.
## Versioned so future schema changes can migrate old saves.
##
## HISTORY: v1 was Phase-0 scaffolding that only saved a handful of fields
## (money, high_score, plus some legacy ship/weapon IDs that the current
## gameplay code doesn't even use). That left the Continue button broken
## (`has_active_run` not persisted), dropped the player back to sector 1
## on every relaunch (`current_level` not persisted), and wiped shop
## purchases / carry state / lives / respawn state on quit.
##
## v2 persists the actual gameplay state the game uses today. Every run-
## affecting field is captured so quit-and-relaunch genuinely resumes a
## run where the player left off. Called from GameState.save_run_state()
## at every state-change checkpoint (level complete, shop purchase, death
## respawn stash, pause open, scene change).
##
## v1 saves load with default values for the new fields — no migration
## UI needed, the player just loses their in-progress run once. That's
## acceptable because v1 was Phase-0 and no real players have shipped
## saves with it.

const SAVE_PATH: String = "user://savegame.dat"
const SAVE_VERSION: int = 2

var _save_data: Dictionary = {}


func _ready() -> void:
	load_game()


## Write the current GameState to disk. Cheap (JSON < 1KB, single file
## write) — safe to call on every state change rather than batching.
func save_game() -> void:
	_save_data = {
		"version": SAVE_VERSION,
		# --- Meta / progression ---
		"has_active_run": GameState.has_active_run,
		"current_level": GameState.current_level,
		"lives": GameState.lives,
		"money": GameState.money,
		"total_score": GameState.total_score,
		"high_score": GameState.high_score,
		# --- Story / cutscene state ---
		"intro_seen": GameState.intro_seen,
		# --- Carry slot (persists between sectors) ---
		"carry_active": GameState.carry_active,
		"carry_hp": GameState.carry_hp,
		"carry_shield": GameState.carry_shield,
		"carry_power_level": GameState.carry_power_level,
		"carry_weapon_levels": GameState.carry_weapon_levels,
		"carry_torpedo_count": GameState.carry_torpedo_count,
		"carry_weapon_type": GameState.carry_weapon_type,
		"carry_max_shield": GameState.carry_max_shield,
		"carry_max_torpedoes": GameState.carry_max_torpedoes,
		"carry_speed_tier": GameState.carry_speed_tier,
		"carry_energy_cells": GameState.carry_energy_cells,
		"carry_sidekick": GameState.carry_sidekick,
		# --- Respawn slot (persists across one death per level) ---
		"respawn_pending": GameState.respawn_pending,
		"respawn_hp": GameState.respawn_hp,
		"respawn_shield": GameState.respawn_shield,
		"respawn_power_level": GameState.respawn_power_level,
		"respawn_weapon_levels": GameState.respawn_weapon_levels,
		"respawn_torpedo_count": GameState.respawn_torpedo_count,
		"respawn_weapon_type": GameState.respawn_weapon_type,
		"respawn_max_shield": GameState.respawn_max_shield,
		"respawn_max_torpedoes": GameState.respawn_max_torpedoes,
		"respawn_speed_tier": GameState.respawn_speed_tier,
		"respawn_energy_cells": GameState.respawn_energy_cells,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: failed to open save file for writing")
		return
	file.store_string(JSON.stringify(_save_data))
	file.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: failed to open save file for reading")
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: save file malformed")
		return
	_save_data = parsed as Dictionary
	_apply_save_data()


## Apply loaded dict to GameState. All fields use `.get(key, default)` so a
## v1 save (missing most of today's fields) loads cleanly with defaults —
## the in-progress run is lost but money/high_score carry over.
func _apply_save_data() -> void:
	# --- Meta ---
	GameState.has_active_run = bool(_save_data.get("has_active_run", false))
	GameState.current_level = int(_save_data.get("current_level", 1))
	GameState.lives = int(_save_data.get("lives", GameState.STARTING_LIVES))
	GameState.money = int(_save_data.get("money", 0))
	GameState.total_score = int(_save_data.get("total_score", 0))
	GameState.high_score = int(_save_data.get("high_score", 0))
	# --- Story ---
	GameState.intro_seen = bool(_save_data.get("intro_seen", false))
	# --- Carry slot ---
	GameState.carry_active = bool(_save_data.get("carry_active", false))
	GameState.carry_hp = int(_save_data.get("carry_hp", 0))
	GameState.carry_shield = float(_save_data.get("carry_shield", 0.0))
	GameState.carry_power_level = int(_save_data.get("carry_power_level", 1))
	GameState.carry_weapon_levels = _to_int_key_dict(_save_data.get("carry_weapon_levels", {}))
	GameState.carry_torpedo_count = int(_save_data.get("carry_torpedo_count", 0))
	GameState.carry_weapon_type = int(_save_data.get("carry_weapon_type", 0))
	GameState.carry_max_shield = int(_save_data.get("carry_max_shield", 1))
	GameState.carry_max_torpedoes = int(_save_data.get("carry_max_torpedoes", 2))
	GameState.carry_speed_tier = int(_save_data.get("carry_speed_tier", 0))
	GameState.carry_energy_cells = int(_save_data.get("carry_energy_cells", 0))
	GameState.carry_sidekick = bool(_save_data.get("carry_sidekick", false))
	# --- Respawn slot ---
	GameState.respawn_pending = bool(_save_data.get("respawn_pending", false))
	GameState.respawn_hp = int(_save_data.get("respawn_hp", 0))
	GameState.respawn_shield = float(_save_data.get("respawn_shield", 0.0))
	GameState.respawn_power_level = int(_save_data.get("respawn_power_level", 1))
	GameState.respawn_weapon_levels = _to_int_key_dict(_save_data.get("respawn_weapon_levels", {}))
	GameState.respawn_torpedo_count = int(_save_data.get("respawn_torpedo_count", 0))
	GameState.respawn_weapon_type = int(_save_data.get("respawn_weapon_type", 0))
	GameState.respawn_max_shield = int(_save_data.get("respawn_max_shield", 1))
	GameState.respawn_max_torpedoes = int(_save_data.get("respawn_max_torpedoes", 2))
	GameState.respawn_speed_tier = int(_save_data.get("respawn_speed_tier", 0))
	GameState.respawn_energy_cells = int(_save_data.get("respawn_energy_cells", 0))


## JSON parses numeric keys as strings ("0": 3) instead of ints (0: 3), so
## weapon_levels (keyed by WeaponType enum ints) needs a conversion pass on
## load. Anything non-numeric is dropped silently.
func _to_int_key_dict(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k in (raw as Dictionary).keys():
		var ki: int = int(k) if typeof(k) == TYPE_STRING or typeof(k) == TYPE_INT or typeof(k) == TYPE_FLOAT else -1
		if ki >= 0:
			out[ki] = int(raw[k])
	return out


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_save_data.clear()
