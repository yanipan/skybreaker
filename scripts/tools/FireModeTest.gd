extends Node
## Headless check of the touch fire scheme (dev-only, excluded from exports).
## Run: godot --headless --path . res://scenes/tools/FireModeTest.tscn

var _fails: int = 0

func _touch(idx: int, pressed: bool, pos: Vector2 = Vector2(300, 900)) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.pressed = pressed
	ev.position = pos
	Input.parse_input_event(ev)

func _expect(p: Node, want: bool, label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var got: bool = p._is_firing
	if got != want:
		_fails += 1
	print("%s  %s: firing=%s (want %s)" % ["PASS" if got == want else "FAIL", label, got, want])

func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])

func _bullet_count() -> int:
	return get_tree().get_nodes_in_group(&"player_bullets").size()

func _clear_bullets() -> void:
	for n in get_tree().get_nodes_in_group(&"player_bullets"):
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(360, 1000)
	add_child(p)
	await get_tree().process_frame

	# --- HOLD ---
	GameState.fire_mode = GameState.FireMode.HOLD
	p._refresh_touch_firing()
	await _expect(p, false, "HOLD idle -> no fire")
	_touch(0, true)
	await _expect(p, false, "HOLD steering finger down -> no fire")
	_check(p._touch_index == 0, "HOLD steer assigns _touch_index=0 (got %s)" % p._touch_index)
	p.set_fire_button(true)
	await _expect(p, true, "HOLD set_fire_button(true) fires")
	p.set_fire_button(false)
	await _expect(p, false, "HOLD set_fire_button(false) stops")
	_touch(1, true, Vector2(500, 900))
	await _expect(p, false, "HOLD 2nd free finger does not fire")
	_check(p._touch_index == 0, "HOLD 2nd finger does not steal steering (index=%s)" % p._touch_index)
	_touch(2, true, Vector2(200, 800))
	await _expect(p, false, "HOLD 3rd free finger does not fire")
	_check(p._touch_index == 0, "HOLD 3rd finger does not steal steering (index=%s)" % p._touch_index)
	_touch(2, false, Vector2(200, 800))
	_touch(1, false, Vector2(500, 900))
	_touch(0, false)

	# --- AUTO ---
	GameState.fire_mode = GameState.FireMode.AUTO
	p.set_fire_button(false)
	await _expect(p, true, "AUTO idle -> fires")
	p.set_fire_button(true)
	await _expect(p, false, "AUTO set_fire_button(true) stops")
	p.set_fire_button(false)
	await _expect(p, true, "AUTO set_fire_button(false) resumes")

	# pause / focus-out notification resets the FIRE button
	GameState.fire_mode = GameState.FireMode.HOLD
	p.set_fire_button(true)
	await _expect(p, true, "HOLD fire held before focus-out")
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _expect(p, false, "HOLD focus-out resets")
	GameState.fire_mode = GameState.FireMode.AUTO
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _expect(p, true, "AUTO focus-out resets to firing")

	# --- Per-weapon buttons (6/11): select + fire, no double-tap switch ---
	GameState.fire_mode = GameState.FireMode.HOLD
	p.set_fire_button(false)
	p.weapon_type = 0
	p._refresh_derived_power()
	p.set_weapon_button(2, true)
	await _expect(p, true, "HOLD missile button fires")
	_check(p.weapon_type == 2, "missile button selects missile (wt=%s)" % p.weapon_type)
	p.set_weapon_button(1, true)
	_check(p.weapon_type == 1, "second button pressed wins the slot (wt=%s)" % p.weapon_type)
	p.set_weapon_button(2, false)
	await _expect(p, true, "still firing while beam button is down")
	p.set_weapon_button(1, false)
	await _expect(p, false, "all weapon buttons up stops fire")
	GameState.fire_mode = GameState.FireMode.AUTO
	p._refresh_touch_firing()
	p.set_weapon_button(0, true)
	await _expect(p, false, "AUTO weapon button held pauses fire")
	_check(p.weapon_type == 0, "AUTO tap selects phaser")
	p.set_weapon_button(0, false)
	await _expect(p, true, "AUTO release resumes fire")
	GameState.fire_mode = GameState.FireMode.HOLD
	p._refresh_touch_firing()
	p.weapon_type = 0
	p._touch_index = -1
	p._is_dragging = false
	var tap := Vector2(300, 900)
	_touch(0, true, tap)
	_touch(1, true, tap)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(p.weapon_type == 0, "double tap on the field no longer switches (wt=%s)" % p.weapon_type)
	_touch(1, false, tap)
	_touch(0, false, tap)
	# Cluster layout: no overlaps, inside the safe area, mirrored by side
	var safe := Rect2(0, 0, 720, 1560)
	var MC = load("res://scripts/MobileControls.gd")
	for side in [0, 1]:
		var cs: Array = MC.cluster_centers(safe, 106.0, side)
		var ok_gap := true
		var inside := true
		for a in cs.size():
			if not safe.grow(-53.0).has_point(cs[a]):
				inside = false
			for b in range(a + 1, cs.size()):
				if cs[a].distance_to(cs[b]) < 106.0 * 1.05:
					ok_gap = false
		_check(ok_gap, "side %d: buttons do not overlap" % side)
		_check(inside, "side %d: buttons fully on screen" % side)
		_check((cs[3].x < 360.0) == (side == 0), "side %d: cluster on the chosen side" % side)

	p.weapon_type = 0
	p._touch_index = -1
	p._is_dragging = false
	_touch(0, true, tap)
	_touch(0, false, tap)
	await get_tree().create_timer(0.40).timeout
	_touch(1, true, tap)
	_touch(1, false, tap)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(p.weapon_type == 0, "two presses 400ms apart do not switch (wt=%s)" % p.weapon_type)

	p.weapon_type = 0
	p._touch_index = -1
	p._is_dragging = false
	_touch(0, true, tap)
	_touch(1, true, tap)
	_touch(2, true, tap)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(p.weapon_type == 0, "triple tap on the field does not switch (wt=%s)" % p.weapon_type)
	_touch(2, false, tap)
	_touch(1, false, tap)
	_touch(0, false, tap)

	# --- Emulated mouse must not drive firing ---
	GameState.fire_mode = GameState.FireMode.HOLD
	p.set_fire_button(false)
	await _expect(p, false, "HOLD idle before emulated mouse")
	var mev := InputEventMouseButton.new()
	mev.device = InputEvent.DEVICE_ID_EMULATION
	mev.button_index = MOUSE_BUTTON_LEFT
	mev.pressed = true
	mev.position = Vector2(400, 900)
	Input.parse_input_event(mev)
	await _expect(p, false, "HOLD emulated mouse press does not fire")

	# --- firing_locked suppresses shots, then unlocks ---
	GameState.fire_mode = GameState.FireMode.HOLD
	p.weapon_type = 0
	p._fire_cooldown = 0.0
	p.firing_locked = true
	p._is_firing = true
	await _clear_bullets()
	await get_tree().create_timer(0.3).timeout
	_check(_bullet_count() == 0, "firing_locked=true spawns no player_bullets (n=%d)" % _bullet_count())
	p.firing_locked = false
	p._fire_cooldown = 0.0
	p._is_firing = true
	await get_tree().create_timer(0.25).timeout
	_check(_bullet_count() > 0, "firing_locked=false then spawns player_bullets (n=%d)" % _bullet_count())
	p._is_firing = false
	p.set_fire_button(false)

	# --- thumb offset: touch at (400,900) -> target y 750 ---
	# Drive the same _update_target the ScreenTouch path calls. parse_input_event
	# remaps coordinates through the window/stretch transform (and headless
	# mouse-motion then overwrites), so the 150px offset is asserted here.
	_check(p.thumb_offset == 150.0, "thumb_offset default is 150 (got %s)" % p.thumb_offset)
	p._update_target(Vector2(400, 900))
	_check(p._target_position.y == 750.0, "thumb offset: touch (400,900) -> y=%s (want 750)" % p._target_position.y)

	# --- settings round-trip with fire_mode_v2 ---
	GameState.set_fire_mode(GameState.FireMode.AUTO)
	var cfg := ConfigFile.new()
	var load_err: int = cfg.load(GameState.SETTINGS_PATH)
	var stored: int = int(cfg.get_value("controls", "fire_mode_v2", -1))
	_check(load_err == OK and stored == GameState.FireMode.AUTO, "settings wrote fire_mode_v2=%s" % stored)
	GameState.fire_mode = GameState.FireMode.HOLD
	GameState.load_settings()
	_check(GameState.fire_mode == GameState.FireMode.AUTO, "settings round-trip loaded AUTO from v2 (got %s)" % GameState.fire_mode)
	GameState.set_fire_mode(GameState.FireMode.HOLD)
	_check(GameState.fire_mode == GameState.FireMode.HOLD, "restored HOLD default")

	print("FIRE MODE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
