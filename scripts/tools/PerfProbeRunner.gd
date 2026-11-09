extends Node
## See PerfProbe.gd.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _arg(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return int(a.split("=")[1])
	return fallback

func _run() -> void:
	var sector: int = _arg("sector", 24)
	var frames: int = _arg("frames", 2400)
	var warmup: int = 600
	var backups: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak"]:
		if FileAccess.file_exists(f):
			backups[f] = FileAccess.get_file_as_bytes(f)
	Engine.max_fps = 0
	GameState.begin_run(777)
	GameState.current_level = sector
	GameState.lives = 5
	GameState.intro_seen = true
	GameState.has_active_run = true
	GameState.pending_warp_entry = false
	GameState.pending_story_key = &""
	GameState.resume_pending = false
	get_tree().paused = false
	seed(12345)
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group(&"player")
	if is_instance_valid(player):
		player.power_level = 22
		if "weapon_levels" in player and player.weapon_levels is Dictionary:
			for k in player.weapon_levels.keys():
				player.weapon_levels[k] = 22
	# Ablation switches for finding the next hot spot (not for comparisons).
	if _arg("nostars", 0) == 1:
		for n in get_tree().current_scene.get_children():
			if n is Starfield or n.get_script() == load("res://scripts/ParallaxBg.gd"):
				n.set_process(false)
	var hold_fire: bool = _arg("nofire", 0) == 0
	var samples: PackedFloat32Array = []
	var sum_enemies: float = 0.0
	var sum_ebul: float = 0.0
	var sum_pbul: float = 0.0
	var peak_ebul: int = 0
	var last: int = Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		if not is_instance_valid(player):
			player = get_tree().get_first_node_in_group(&"player")
		if is_instance_valid(player):
			if player.monitoring:
				player.set_deferred("monitoring", false)
			player.hp = player.max_hp
			player._is_firing = hold_fire
			player._current_charge = player.max_charge
		if i >= warmup:
			samples.append(float(now - last) / 1000.0)
			var eb: int = get_tree().get_nodes_in_group(&"enemy_bullets").size()
			sum_enemies += get_tree().get_nodes_in_group(&"enemies").size()
			sum_ebul += eb
			sum_pbul += get_tree().get_nodes_in_group(&"player_bullets").size()
			peak_ebul = maxi(peak_ebul, eb)
		last = Time.get_ticks_usec()
	var n: int = samples.size()
	samples.sort()
	var total: float = 0.0
	for s in samples:
		total += s
	print("PERF sector=%d frames=%d  avg=%.3f ms  p50=%.3f  p95=%.3f  max=%.3f  | avg enemies=%.1f enemy_shots=%.1f (peak %d) player_shots=%.1f" % [
		sector, n, total / n, samples[n / 2], samples[int(n * 0.95)], samples[n - 1],
		sum_enemies / n, sum_ebul / n, peak_ebul, sum_pbul / n])
	for f in backups:
		var w := FileAccess.open(f, FileAccess.WRITE)
		w.store_buffer(backups[f])
		w.close()
	get_tree().quit(0)
