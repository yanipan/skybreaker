extends Node
## See PerfProbe.gd.
var sectors: Array = [13, 20]
var secs: float = 40.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe_sectors="):
			sectors = []
			for s in a.trim_prefix("--probe_sectors=").split(","):
				sectors.append(int(s))
		elif a.begins_with("--probe_secs="):
			secs = float(a.trim_prefix("--probe_secs="))
	call_deferred("_run")


func _run() -> void:
	var backups: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak"]:
		if FileAccess.file_exists(f):
			backups[f] = FileAccess.get_file_as_bytes(f)
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
		for i in 60:
			await get_tree().process_frame
		var player = get_tree().get_first_node_in_group(&"player")
		# No frame cap and no vsync: the frame time IS the cost of a frame.
		if not OS.get_cmdline_user_args().has("--probe_capped"):   # capped = as shipped (60 fps), to read CPU use from outside
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var t: float = 0.0
		var times: Array = []
		var sum_nodes: float = 0.0
		var peak_nodes: float = 0.0
		var sum_draw: float = 0.0
		var peak_draw: float = 0.0
		var peak_enemies: int = 0
		var peak_bullets: int = 0
		var shot_done: bool = false
		var last: int = Time.get_ticks_usec()
		while t < secs:
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			var ms: float = float(now - last) / 1000.0
			last = now
			t += ms / 1000.0
			times.append(ms)
			if not is_instance_valid(player):
				player = get_tree().get_first_node_in_group(&"player")
			if is_instance_valid(player):
				if player.monitoring:
					player.set_deferred("monitoring", false)
				player.hp = player.max_hp
				if "_is_firing" in player:
					player._is_firing = true     # hold the trigger: bullets are part of the load
			var nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			sum_nodes += nodes
			peak_nodes = maxf(peak_nodes, nodes)
			var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			sum_draw += draws
			peak_draw = maxf(peak_draw, draws)
			peak_enemies = maxi(peak_enemies, get_tree().get_nodes_in_group(&"enemies").size())
			peak_bullets = maxi(peak_bullets, get_tree().get_nodes_in_group(&"enemy_bullets").size())
			if not shot_done and t > secs * 0.6 and DisplayServer.get_name() != "headless":
				shot_done = true
				get_viewport().get_texture().get_image().save_png("user://perf_probe_%d.png" % [int(sector)])
		times.sort()
		var n: int = times.size()
		var total: float = 0.0
		for x in times: total += float(x)
		print("PERF sector %d: frame ms avg %.2f, p99 %.2f, worst %.2f | nodes avg %.0f peak %.0f | draw calls avg %.0f peak %.0f | peak enemies %d, enemy shots %d" % [
			sector, total / n, float(times[int(n * 0.99)]), float(times[n - 1]), sum_nodes / n, peak_nodes, sum_draw / n, peak_draw, peak_enemies, peak_bullets])
	for f in backups:
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_buffer(backups[f])
		fa.close()
	get_tree().quit(0)
