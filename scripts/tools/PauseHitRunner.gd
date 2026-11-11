extends Node
## Headless check: after pause/resume, player/enemy/bullet Area2D overlaps still fire.
## Body of PauseHitTest; parented to the tree root by PauseHitTest.gd so
## change_scene_to_file() does not free it mid-await.

const EnemyScript := preload("res://scripts/Enemy.gd")
const BulletScript := preload("res://scripts/Bullet.gd")
const EnemyBulletScript := preload("res://scripts/EnemyBullet.gd")
const StarbaseScript := preload("res://scripts/Starbase.gd")

var _rows: Array = []
var _fails: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	print("=== PAUSE HIT TEST START ===")
	print("Godot %s" % Engine.get_version_info())
	await _boot_main({})
	await _run_probes("baseline", 0, "pre")
	await _flow1()
	await _flow2()
	await _flow3()
	await _flow4()
	await _flow5()
	await _flow6()
	await _flow7()
	await _flow8()
	await _flow9()
	await _flow10()
	# Up to 3 extra targeted interleavings — not new game systems.
	await _extra_pending_then_close()
	await _extra_open_under_cutscene_then_finish()
	await _extra_close_then_focus_out()
	_print_table()
	print("PAUSE HIT TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)


func _boot_main(opts: Dictionary) -> Node:
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.has_active_run = true
	GameState.current_level = 1
	GameState.intro_seen = true
	GameState.resume_pending = false
	GameState.pending_warp_entry = bool(opts.get("entry", false))
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var main: Node = get_tree().current_scene
	if main == null:
		print("FAIL  Main.tscn did not become current_scene")
		_fails += 1
		return null
	if main._spawner != null and not bool(opts.get("keep_spawner", false)):
		main._spawner.set_process(false)
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player != null and not bool(opts.get("entry", false)):
		player.set_process(false)
	return main


func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _flags(player: Node) -> Dictionary:
	var monitoring: Variant = null
	var monitorable: Variant = null
	if player != null and is_instance_valid(player):
		monitoring = player.monitoring
		monitorable = player.monitorable
	return {
		"paused": get_tree().paused,
		"time_scale": Engine.time_scale,
		"monitoring": monitoring,
		"monitorable": monitorable,
	}


func _print_flags(tag: String, player: Node) -> Dictionary:
	var f: Dictionary = _flags(player)
	print("FLAGS %s paused=%s time_scale=%s monitoring=%s monitorable=%s" % [
		tag, f["paused"], f["time_scale"], f["monitoring"], f["monitorable"]
	])
	return f


func _wait_physics(n: int) -> void:
	if get_tree().paused:
		print("WARN  physics wait skipped; tree is paused")
		return
	for _i in n:
		await get_tree().physics_frame


func _wait_always(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _wait_overlay(main: Node, frames: int = 12) -> bool:
	for _i in frames:
		if main != null and is_instance_valid(main) and main._pause_layer != null:
			return true
		await get_tree().process_frame
	return main != null and is_instance_valid(main) and main._pause_layer != null


func _cleanup_probes(nodes: Array) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame


func _probe_bullet(main: Node) -> bool:
	if main == null or get_tree().paused:
		print("PROBE bullet SKIP paused=%s" % get_tree().paused)
		return false
	var player: Node = _player()
	if player == null:
		print("PROBE bullet FAIL no player")
		return false
	var enemy: Area2D = EnemyScript.new()
	enemy.position = player.position + Vector2(0, -140)
	enemy.set_process(false)
	main.add_child(enemy)
	await get_tree().process_frame
	if not is_instance_valid(enemy):
		print("PROBE bullet FAIL enemy vanished")
		return false
	var hp0: int = int(enemy.hp)
	var bullet: Area2D = BulletScript.new()
	bullet.position = enemy.position
	bullet.direction = Vector2.UP
	bullet.speed = 1200.0
	main.add_child(bullet)
	var hit: bool = false
	for _i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(bullet):
			hit = true
			break
		if is_instance_valid(enemy) and int(enemy.hp) < hp0:
			hit = true
			break
	await _cleanup_probes([bullet, enemy])
	return hit


func _probe_enemy_bullet(main: Node) -> bool:
	if main == null or get_tree().paused:
		print("PROBE ebullet SKIP paused=%s" % get_tree().paused)
		return false
	var player: Node = _player()
	if player == null:
		print("PROBE ebullet FAIL no player")
		return false
	if "_i_frame_timer" in player:
		player._i_frame_timer = 0.0
	var pool0: float = float(player.hp) + float(player.shield)
	var eb: Area2D = EnemyBulletScript.new()
	eb.position = player.position
	eb.direction = Vector2.DOWN
	eb.speed = 0.0
	main.add_child(eb)
	var hit: bool = false
	for _i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(player):
			hit = true
			break
		var pool: float = float(player.hp) + float(player.shield)
		if pool < pool0 - 0.01:
			hit = true
			break
		if not is_instance_valid(eb):
			# Player frees the bullet on hit; also counts.
			hit = pool < pool0 - 0.01 or hit
			break
	if is_instance_valid(player):
		if "_i_frame_timer" in player:
			player._i_frame_timer = 0.0
		player.hp = player.max_hp
		player.shield = float(player.max_shield)
	await _cleanup_probes([eb])
	return hit


func _run_probes(flow: String, iter: int, sub: String) -> void:
	var main: Node = get_tree().current_scene
	var player: Node = _player()
	var f: Dictionary = _print_flags("%s/%d/%s" % [flow, iter, sub], player)
	var b: bool = await _probe_bullet(main)
	var e: bool = await _probe_enemy_bullet(main)
	var row := {
		"flow": flow,
		"iter": iter,
		"sub": sub,
		"bullet": b,
		"ebullet": e,
		"paused": f["paused"],
		"time_scale": f["time_scale"],
		"monitoring": f["monitoring"],
		"monitorable": f["monitorable"],
	}
	_rows.append(row)
	if not b:
		_fails += 1
	if not e:
		_fails += 1
	print("ROW flow=%s iter=%d sub=%s bullet=%s ebullet=%s paused=%s timescale=%s monitoring=%s monitorable=%s" % [
		flow, iter, sub,
		"PASS" if b else "FAIL",
		"PASS" if e else "FAIL",
		f["paused"], f["time_scale"], f["monitoring"], f["monitorable"]
	])


func _ensure_closed(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		get_tree().paused = false
		return
	if main._pause_layer != null:
		main._close_pause()
	get_tree().paused = false
	Engine.time_scale = 1.0
	await get_tree().process_frame


# --- flows -----------------------------------------------------------------

func _flow1() -> void:
	print("--- flow 1 toggle_pause open/wait/close ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main._toggle_pause()
		await _wait_overlay(main)
		await _wait_always(0.25)
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("1_toggle", i, "after")
		await _ensure_closed(main)


func _flow2() -> void:
	print("--- flow 2 focus-out / double / paused+focus_out ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		var got: bool = await _wait_overlay(main)
		print("flow2 overlay_after_focus_out=%s pending=%s" % [got, main._pause_pending])
		await _wait_always(0.15)
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("2_focus_out", i, "once")

		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _wait_overlay(main)
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("2_focus_out", i, "twice")

		main.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _wait_overlay(main)
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("2_focus_out", i, "paused_and_focus")
		await _ensure_closed(main)


func _flow3() -> void:
	print("--- flow 3 same-frame / next-frame / physics-callback ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main._open_pause()
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("3_timing", i, "same_frame")

		main._open_pause()
		await get_tree().process_frame
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("3_timing", i, "next_frame")

		var opened: Array = [false]
		get_tree().physics_frame.connect(func() -> void:
			if opened[0]:
				return
			opened[0] = true
			main._open_pause()
		, CONNECT_ONE_SHOT)
		for _j in 8:
			if opened[0] and main._pause_layer != null:
				break
			await get_tree().process_frame
		print("flow3 physics_open opened=%s layer=%s paused=%s" % [
			opened[0], main._pause_layer != null, get_tree().paused
		])
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("3_timing", i, "physics_cb")
		await _ensure_closed(main)


func _flow4() -> void:
	print("--- flow 4 deferred close + second focus-out ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main._open_pause()
		main._close_pause.call_deferred()
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await get_tree().process_frame
		await get_tree().process_frame
		if main._pause_layer != null:
			main._close_pause()
		await get_tree().process_frame
		await _run_probes("4_deferred_close", i, "after")
		await _ensure_closed(main)


func _flow5() -> void:
	print("--- flow 5 starbase shop open/closed path ---")
	for i in 3:
		var main: Node = await _boot_main({})
		var player: Node = _player()
		var sb: Node = StarbaseScript.new()
		sb.position = Vector2(80, 80)
		sb.set_process(false)
		main.add_child(sb)
		await get_tree().process_frame
		sb._open_shop(player)
		await get_tree().process_frame
		print("flow5 shop paused=%s" % get_tree().paused)
		var shop: Node = _find_by_script(get_tree().root, "StarbaseShop.gd")
		if shop != null and shop.has_method("_on_leave"):
			shop._on_leave()
		else:
			print("flow5 WARN no shop; forcing unpause")
			get_tree().paused = false
		# Since 9/11 leaving the shop starts the GET READY 3-2-1 countdown and
		# the tree stays paused for it: hits are checked once it has run out.
		await _wait_always(4.2)
		print("flow5 after countdown paused=%s" % get_tree().paused)
		await _run_probes("5_shop", i, "after")
		await _ensure_closed(main)


func _flow6() -> void:
	print("--- flow 6 resume countdown +/- focus-out ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main._begin_resume_countdown()
		await _wait_always(4.2)
		print("flow6 no_focus countdown_active=%s paused=%s" % [
			main._resume_countdown_active, get_tree().paused
		])
		if main._pause_layer != null:
			main._close_pause()
		await get_tree().process_frame
		await _run_probes("6_countdown", i, "no_focus")
		await _ensure_closed(main)

		main = await _boot_main({})
		main._begin_resume_countdown()
		await _wait_always(0.4)
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		print("flow6 mid_focus lost_flag=%s pending=%s layer=%s" % [
			main._focus_lost_in_countdown, main._pause_pending, main._pause_layer != null
		])
		await _wait_always(4.2)
		print("flow6 after_countdown active=%s paused=%s layer=%s" % [
			main._resume_countdown_active, get_tree().paused, main._pause_layer != null
		])
		if main._pause_layer != null:
			main._close_pause()
		get_tree().paused = false
		await get_tree().process_frame
		await _run_probes("6_countdown", i, "with_focus")
		await _ensure_closed(main)


func _flow7() -> void:
	print("--- flow 7 pause during Cutscene._finish ---")
	for i in 3:
		var main: Node = await _boot_main({})
		main._begin_cutscene(CutsceneData.INTRO_KEY, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var cs: Node = _find_by_script(main, "Cutscene.gd")
		print("flow7 cutscene=%s active=%s paused=%s" % [
			cs != null, main._cutscene_active, get_tree().paused
		])
		if cs != null:
			if not cs.finished.is_connected(main._open_pause):
				cs.finished.connect(main._open_pause, CONNECT_ONE_SHOT)
			if cs.has_method("_finish"):
				cs._finish()
			else:
				cs.finished.emit()
		else:
			main._cutscene_active = false
			main._open_pause()
		await _wait_overlay(main)
		print("flow7 after_finish cutscene_active=%s paused=%s layer=%s" % [
			main._cutscene_active, get_tree().paused, main._pause_layer != null
		])
		main._close_pause()
		await get_tree().process_frame
		await _run_probes("7_cutscene_finish", i, "after")
		await _ensure_closed(main)


func _flow8() -> void:
	print("--- flow 8 focus-out during warp entry ---")
	for i in 3:
		var main: Node = await _boot_main({"entry": true})
		print("flow8 entry_active=%s monitoring=%s" % [
			main._entry_active,
			_player().monitoring if _player() != null else null
		])
		main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await get_tree().process_frame
		print("flow8 after_focus layer=%s pending=%s paused=%s entry=%s" % [
			main._pause_layer != null, main._pause_pending, get_tree().paused, main._entry_active
		])
		# Headless idle frames are uncapped; wait on game time so _update_entry can finish.
		var guard: int = 0
		while main._entry_active and guard < 40:
			await _wait_always(0.1)
			guard += 1
		# Deferred monitoring restore from _finish_entry_sequence.
		await get_tree().process_frame
		await get_tree().process_frame
		var player: Node = _player()
		if player != null:
			player.set_process(false)
		print("flow8 entry_done active=%s monitoring=%s monitorable=%s" % [
			main._entry_active,
			player.monitoring if player != null else null,
			player.monitorable if player != null else null
		])
		if main._pause_layer != null:
			main._close_pause()
		get_tree().paused = false
		await _run_probes("8_entry_focus", i, "after")
		await _ensure_closed(main)


func _flow9() -> void:
	print("--- flow 9 overlap at the moment of pause ---")
	for i in 3:
		var main: Node = await _boot_main({})
		var player: Node = _player()
		var enemy: Area2D = EnemyScript.new()
		enemy.position = player.position + Vector2(0, -140)
		enemy.set_process(false)
		main.add_child(enemy)
		await get_tree().process_frame
		var hp0: int = int(enemy.hp)
		var bullet: Area2D = BulletScript.new()
		bullet.position = enemy.position
		bullet.direction = Vector2.UP
		bullet.speed = 0.0
		main.add_child(bullet)
		main._open_pause()
		await _wait_always(0.3)
		var hp_during: int = int(enemy.hp) if is_instance_valid(enemy) else -1
		var bullet_alive_during: bool = is_instance_valid(bullet)
		print("flow9 during_pause hp=%s->%s bullet_alive=%s paused=%s" % [
			hp0, hp_during, bullet_alive_during, get_tree().paused
		])
		main._close_pause()
		await get_tree().process_frame
		var hit: bool = false
		for _j in 30:
			await get_tree().physics_frame
			if not is_instance_valid(bullet):
				hit = true
				break
			if is_instance_valid(enemy) and int(enemy.hp) < hp0:
				hit = true
				break
		print("flow9 after_resume overlap_hit=%s" % hit)
		await _cleanup_probes([bullet, enemy])
		if not hit:
			_fails += 1
		var f: Dictionary = _print_flags("9_overlap/%d" % i, player)
		_rows.append({
			"flow": "9_overlap_at_pause",
			"iter": i,
			"sub": "resume_hit",
			"bullet": hit,
			"ebullet": hit,
			"paused": f["paused"],
			"time_scale": f["time_scale"],
			"monitoring": f["monitoring"],
			"monitorable": f["monitorable"],
		})
		print("ROW flow=%s iter=%d sub=%s bullet=%s ebullet=%s paused=%s timescale=%s monitoring=%s monitorable=%s" % [
			"9_overlap_at_pause", i, "resume_hit",
			"PASS" if hit else "FAIL",
			"PASS" if hit else "FAIL",
			f["paused"], f["time_scale"], f["monitoring"], f["monitorable"]
		])
		await _run_probes("9_overlap_at_pause", i, "fresh_after")
		await _ensure_closed(main)


func _flow10() -> void:
	print("--- flow 10 long pause 5s time_scale=0.35 bullets flying ---")
	for i in 3:
		var main: Node = await _boot_main({})
		var player: Node = _player()
		var flyers: Array = []
		for k in 3:
			var b: Area2D = BulletScript.new()
			b.position = player.position + Vector2(-40 + k * 40, -40)
			b.direction = Vector2.UP
			b.speed = 400.0
			main.add_child(b)
			flyers.append(b)
		await get_tree().process_frame
		var pos0: Array = []
		for b2 in flyers:
			pos0.append(b2.position if is_instance_valid(b2) else Vector2.ZERO)
		Engine.time_scale = 0.35
		main._open_pause()
		await _wait_always(5.0)
		var moved: float = 0.0
		for k in flyers.size():
			if is_instance_valid(flyers[k]):
				moved = max(moved, pos0[k].distance_to(flyers[k].position))
		print("flow10 during_pause bullet_move_px=%s paused=%s time_scale=%s" % [
			moved, get_tree().paused, Engine.time_scale
		])
		main._close_pause()
		Engine.time_scale = 1.0
		await get_tree().process_frame
		await _cleanup_probes(flyers)
		await _run_probes("10_long_pause", i, "after")
		await _ensure_closed(main)


func _extra_pending_then_close() -> void:
	print("--- extra A focus-out then close before deferred overlay ---")
	var main: Node = await _boot_main({})
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	print("extraA pending=%s layer=%s paused=%s" % [
		main._pause_pending, main._pause_layer != null, get_tree().paused
	])
	main._close_pause()
	await get_tree().process_frame
	await get_tree().process_frame
	print("extraA after_close pending=%s layer=%s paused=%s" % [
		main._pause_pending, main._pause_layer != null, get_tree().paused
	])
	if main._pause_layer != null:
		main._close_pause()
	get_tree().paused = false
	await get_tree().process_frame
	await _run_probes("X_pending_close", 0, "after")
	await _ensure_closed(main)


func _extra_open_under_cutscene_then_finish() -> void:
	print("--- extra B _open_pause while cutscene holds pause, then _finish ---")
	var main: Node = await _boot_main({})
	main._begin_cutscene(CutsceneData.INTRO_KEY, false)
	await get_tree().process_frame
	await get_tree().process_frame
	main._open_pause()
	print("extraB overlay_under_cutscene paused=%s layer=%s cutscene=%s" % [
		get_tree().paused, main._pause_layer != null, main._cutscene_active
	])
	var cs: Node = _find_by_script(main, "Cutscene.gd")
	if cs != null and cs.has_method("_finish"):
		cs._finish()
	print("extraB after_finish paused=%s layer=%s cutscene=%s" % [
		get_tree().paused, main._pause_layer != null, main._cutscene_active
	])
	main._close_pause()
	await get_tree().process_frame
	await _run_probes("X_open_under_cutscene", 0, "after")
	await _ensure_closed(main)


func _extra_close_then_focus_out() -> void:
	print("--- extra C close then immediate focus-out ---")
	var main: Node = await _boot_main({})
	main._open_pause()
	await get_tree().process_frame
	main._close_pause()
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait_overlay(main)
	print("extraC reopened layer=%s paused=%s" % [main._pause_layer != null, get_tree().paused])
	if main._pause_layer != null:
		main._close_pause()
	await get_tree().process_frame
	await _run_probes("X_close_then_focus", 0, "after")
	await _ensure_closed(main)


func _find_by_script(root: Node, filename: String) -> Node:
	if root == null:
		return null
	var scr: Script = root.get_script()
	if scr != null and str(scr.resource_path).ends_with(filename):
		return root
	for c in root.get_children():
		var found: Node = _find_by_script(c, filename)
		if found != null:
			return found
	return null


func _print_table() -> void:
	print("=== PAUSE HIT TABLE ===")
	print("flow\titer\tsub\tbullet\tebullet\tpaused\ttime_scale\tmonitoring\tmonitorable")
	for r in _rows:
		print("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % [
			r["flow"], r["iter"], r["sub"],
			"PASS" if r["bullet"] else "FAIL",
			"PASS" if r["ebullet"] else "FAIL",
			r["paused"], r["time_scale"], r["monitoring"], r["monitorable"]
		])
