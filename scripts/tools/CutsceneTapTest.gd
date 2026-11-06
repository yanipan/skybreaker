extends Node
## Dev-only. Intro timing and tap handling, on the real Cutscene.
## Run: godot --path . res://scenes/tools/CutsceneTapTest.tscn   (SHOT_DIR env = save frames)
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])

func _make() -> Cutscene:
	var cs: Cutscene = load("res://scripts/Cutscene.gd").new()
	add_child(cs)
	cs.play(CutsceneData.beats_for(CutsceneData.INTRO_KEY))
	return cs

func _tap() -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = Vector2(200, 400)
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = ev.position
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout

func _shown(cs: Cutscene) -> float:
	var r: TextureRect = cs._rect_b if not cs._using_a else cs._rect_a
	return r.modulate.a

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dir: String = OS.get_environment("SHOT_DIR")
	# --- No taps: every image stays up for its full beat ---
	var cs := _make()
	var entered: Array = [0.0, -1.0, -1.0, -1.0]
	var left: Array = [-1.0, -1.0, -1.0, -1.0]
	var t0: int = Time.get_ticks_msec()
	var prev: int = 0
	var saved: Dictionary = {}
	while is_instance_valid(cs) and not cs._dismissing:
		var now: float = (Time.get_ticks_msec() - t0) / 1000.0
		if cs._current_index != prev:
			left[prev] = now
			prev = cs._current_index
			entered[prev] = now
		if prev == 2 and dir != "":
			for mark in [1.0, 2.5, 3.5]:
				if now - entered[2] >= mark and not saved.has(mark):
					saved[mark] = true
					get_viewport().get_texture().get_image().save_png("%s/beat3_%.1f.png" % [dir, mark])
					print("beat3 t=%.1f alpha=%.2f" % [mark, _shown(cs)])
		await get_tree().process_frame
	left[prev] = (Time.get_ticks_msec() - t0) / 1000.0
	for i in 4:
		print("beat %d shown %.2f s" % [i, left[i] - entered[i]])
		_check(left[i] - entered[i] >= 3.5, "untapped beat %d stays up" % i)
	await _wait(1.0)
	# --- One tap advances exactly one image ---
	get_tree().paused = false
	cs = _make()
	await _wait(1.0)
	_check(cs._current_index == 0, "starts on image 1")
	await _tap()
	_check(cs._current_index == 1, "one tap on image 1 -> image 2 (at %d)" % (cs._current_index + 1))
	await _wait(1.0)
	await _tap()
	_check(cs._current_index == 2, "one tap on image 2 -> image 3 (at %d)" % (cs._current_index + 1))
	await _wait(1.0)
	_check(cs._current_index == 2 and _shown(cs) > 0.9, "image 3 visible a second later, alpha %.2f" % _shown(cs))
	# --- Tapping during a crossfade must still end fully visible ---
	cs.queue_free()
	await get_tree().process_frame
	cs = _make()
	await _wait(1.0)
	await _tap()
	await _wait(0.2)
	await _tap()
	await _wait(1.2)
	_check(cs._current_index == 2 and _shown(cs) > 0.9, "tap during crossfade: image 3 fully visible, alpha %.2f" % _shown(cs))
	# --- Death keeps every weapon slot ---
	var p: Node = load("res://scripts/Player.gd").new()
	p.weapon_levels = {0: 7, 1: 4, 2: 2}
	p.weapon_type = 0
	p._refresh_derived_power()
	GameState.stash_respawn(p)
	_check(GameState.respawn_weapon_levels == {0: 7, 1: 4, 2: 2}, "death keeps all weapon levels: %s" % GameState.respawn_weapon_levels)
	_check(GameState.respawn_power_level == 7, "death keeps power level: %d" % GameState.respawn_power_level)
	p.free()
	GameState.clear_respawn()
	cs.queue_free()
	get_tree().paused = false
	print("CUTSCENE TAP TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
