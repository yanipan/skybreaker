extends Node
## See SectorSoakTest.gd.

var sectors: Array = []
var soak_seconds: float = 50.0
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	# The soak drives the real GameState, which saves: keep the developer's
	# own save files and put them back at the end.
	var backups: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak"]:
		if FileAccess.file_exists(f):
			backups[f] = FileAccess.get_file_as_bytes(f)
	var seen_types: Dictionary = {}
	var seen_boss_types: Dictionary = {}
	for sector in sectors:
		GameState.begin_run(4242 + int(sector))
		GameState.current_level = int(sector)
		GameState.lives = 5
		GameState.intro_seen = true
		GameState.has_active_run = true
		GameState.pending_warp_entry = false
		GameState.pending_story_key = &""
		GameState.resume_pending = false
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
		await get_tree().process_frame
		await get_tree().process_frame
		Engine.time_scale = 8.0
		var player := get_tree().get_first_node_in_group(&"player")
		var peak_enemies: int = 0
		var peak_bullets: int = 0
		var t: float = 0.0
		var frames: int = 0
		while t < soak_seconds and frames < 4000:
			await get_tree().process_frame
			frames += 1
			t += get_process_delta_time()   # already scaled by Engine.time_scale
			# Keep the ship alive: this soak is about the spawner and enemies.
			# With monitoring off nothing can hit it (bullets, rams and the
			# HitCheck safety net all respect it), so no death reload resets
			# the sector clock before the boss enters.
			if not is_instance_valid(player):
				player = get_tree().get_first_node_in_group(&"player")
			if is_instance_valid(player):
				if player.monitoring:
					player.set_deferred("monitoring", false)
				player.hp = player.max_hp
			var enemies := get_tree().get_nodes_in_group(&"enemies")
			peak_enemies = maxi(peak_enemies, enemies.size())
			peak_bullets = maxi(peak_bullets, get_tree().get_nodes_in_group(&"enemy_bullets").size())
			for e in enemies:
				if e.is_in_group(&"bosses"):
					seen_boss_types[int(e.type)] = true
				elif "type" in e:
					seen_types[int(e.type)] = true
		Engine.time_scale = 1.0
		var main_alive: bool = get_tree().current_scene != null and get_tree().current_scene.name != ""
		_check(main_alive and peak_enemies > 0, "sector %d soaked %.0fs game time: peak %d enemies, %d enemy bullets" % [sector, t, peak_enemies, peak_bullets])
	_check(seen_types.has(9), "SHADE spawned in real waves")
	_check(seen_types.has(10), "ARTILLERY spawned in real waves")
	_check(seen_boss_types.has(6), "NULL ARCHON entered in sector 22")
	_check(seen_boss_types.has(7), "THE HERALD entered in sector 24")
	print("SectorSoak: %d failure(s), enemy types seen %s, boss types seen %s" % [_fails, str(seen_types.keys()), str(seen_boss_types.keys())])
	for f in backups:
		var w := FileAccess.open(f, FileAccess.WRITE)
		w.store_buffer(backups[f])
		w.close()
	get_tree().quit(1 if _fails > 0 else 0)
