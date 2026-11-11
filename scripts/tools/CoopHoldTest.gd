extends Node
## Headless: the co-op hold keeps solo progress safe. Nothing a co-op session
## does to GameState reaches the save file, and ending the session puts every
## saved field back. Uses its own copy of the save files and restores them.
## Run: godot --headless --path . res://scenes/tools/CoopHoldTest.tscn

var _fails: int = 0
var _passes: int = 0

func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("PASS  ", what)
	else:
		_fails += 1
		print("FAIL  ", what)


func _ready() -> void:
	call_deferred("_run")


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _run() -> void:
	# Park whatever save this machine has; put it back at the end.
	var parked: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak", "user://savegame.tmp"]:
		if FileAccess.file_exists(f):
			parked[f] = FileAccess.get_file_as_bytes(f)

	# A known solo state on disk
	GameState.begin_run(4242)
	GameState.has_active_run = true
	GameState.current_level = 9
	GameState.lives = 2
	GameState.money = 1234
	GameState.run_score = 5555
	GameState.carry_active = true
	GameState.carry_weapon_levels = {0: 7, 1: 4, 2: 5}
	GameState.carry_max_shield = 3
	SaveSystem.save_game()
	var disk0: PackedByteArray = _bytes("user://savegame.dat")
	_check(disk0.size() > 0, "solo save written")

	SaveSystem.begin_coop_hold()
	_check(SaveSystem.coop_hold_active(), "hold is on")
	_check(_bytes("user://savegame.dat") == disk0, "starting the hold does not touch the file")

	# A co-op run tramples everything
	GameState.begin_run(1)
	GameState.current_level = 1
	GameState.lives = 0
	GameState.money = 7
	GameState.run_score = 99999
	GameState.has_active_run = false
	GameState.carry_weapon_levels = {0: 30, 1: 30, 2: 30}
	GameState.carry_max_shield = 6
	GameState.clear_carry()
	GameState.save_run_state()
	GameState.commit_high_score()
	SaveSystem.save_game()
	_check(_bytes("user://savegame.dat") == disk0, "saves during co-op never reach the file")

	SaveSystem.end_coop_hold()
	_check(not SaveSystem.coop_hold_active(), "hold is off")
	_check(GameState.current_level == 9 and GameState.lives == 2 and GameState.money == 1234, "level, lives, money are back (%d / %d / %d)" % [GameState.current_level, GameState.lives, GameState.money])
	_check(GameState.run_score == 5555 and GameState.run_seed == 4242 and GameState.has_active_run, "run score, seed and the active run are back")
	_check(GameState.carry_active and int(GameState.carry_weapon_levels.get(0, 0)) == 7 and int(GameState.carry_weapon_levels.get(2, 0)) == 5 and GameState.carry_max_shield == 3, "carried gear is back (%s, shield %d)" % [GameState.carry_weapon_levels, GameState.carry_max_shield])
	SaveSystem.save_game()
	var j0: Variant = JSON.parse_string(disk0.get_string_from_utf8())
	var j1: Variant = JSON.parse_string(_bytes("user://savegame.dat").get_string_from_utf8())
	_check(j0 is Dictionary and j1 is Dictionary and j0 == j1, "saving after co-op writes the same solo state as before")
	GameState.money = 1300
	SaveSystem.save_game()
	_check(_bytes("user://savegame.dat") != disk0, "after the hold, saving works again")

	# Net.leave_coop() without a session must not disturb anything
	GameState.money = 1400
	Net.leave_coop()
	_check(GameState.money == 1400, "leave_coop with no session changes nothing")

	# Put this machine's own save back exactly
	for f in ["user://savegame.dat", "user://savegame.bak", "user://savegame.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if parked.has(f):
			var w := FileAccess.open(f, FileAccess.WRITE)
			w.store_buffer(parked[f])
			w.close()
	SaveSystem.load_game()
	print("CoopHoldTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
