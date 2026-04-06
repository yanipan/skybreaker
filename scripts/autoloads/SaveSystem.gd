extends Node
## Persistent save/load system. JSON to user://savegame.dat.
## Versioned so future schema changes can migrate old saves.

const SAVE_PATH: String = "user://savegame.dat"
const SAVE_VERSION: int = 1

var _save_data: Dictionary = {}


func _ready() -> void:
	load_game()


func save_game() -> void:
	_save_data = {
		"version": SAVE_VERSION,
		"money": GameState.money,
		"total_score": GameState.total_score,
		"current_sector": GameState.current_sector,
		"current_mission": GameState.current_mission,
		"ship_id": String(GameState.current_ship_id),
		"primary_weapon_id": String(GameState.current_primary_weapon_id),
		"secondary_weapon_id": String(GameState.current_secondary_weapon_id),
		# TODO: weapons_owned, ships_owned, upgrade_tiers, stars_per_mission
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


func _apply_save_data() -> void:
	GameState.money = int(_save_data.get("money", 0))
	GameState.total_score = int(_save_data.get("total_score", 0))
	GameState.current_sector = int(_save_data.get("current_sector", 1))
	GameState.current_mission = int(_save_data.get("current_mission", 1))
	GameState.current_ship_id = StringName(_save_data.get("ship_id", "scout"))
	GameState.current_primary_weapon_id = StringName(_save_data.get("primary_weapon_id", "vulcan"))
	GameState.current_secondary_weapon_id = StringName(_save_data.get("secondary_weapon_id", "bomb"))


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_save_data.clear()
