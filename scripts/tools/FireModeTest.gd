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

func _ready() -> void:
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(360, 1000)
	add_child(p)
	await get_tree().process_frame
	# --- AUTO ---
	GameState.fire_mode = GameState.FireMode.AUTO
	_touch(0, true); await _expect(p, true, "AUTO steer finger down")
	_touch(1, true); await _expect(p, false, "AUTO 2nd finger held -> cease fire")
	_touch(2, true); await _expect(p, false, "AUTO 3rd finger ignored")
	_touch(2, false); await _expect(p, false, "AUTO 3rd finger up ignored")
	_touch(1, false); await _expect(p, true, "AUTO 2nd finger up -> resume")
	_touch(0, false); await _expect(p, true, "AUTO steer finger up -> still firing")
	_touch(1, true); await _expect(p, true, "AUTO lone finger becomes steer, fires")
	_touch(1, false); await _expect(p, true, "AUTO released")
	# --- HOLD ---
	GameState.fire_mode = GameState.FireMode.HOLD
	p._refresh_touch_firing()
	await _expect(p, false, "HOLD idle -> no fire")
	_touch(0, true); await _expect(p, false, "HOLD steer finger down -> no fire")
	_touch(1, true); await _expect(p, true, "HOLD 2nd finger down -> fire")
	_touch(1, false); await _expect(p, false, "HOLD 2nd finger up -> stop")
	_touch(1, true); await _expect(p, true, "HOLD 2nd finger again -> fire")
	_touch(0, false); await _expect(p, true, "HOLD steer up, fire finger still down -> fire")
	_touch(1, false); await _expect(p, false, "HOLD all up")
	# pause notification resets
	_touch(0, true); _touch(1, true); await _expect(p, true, "HOLD both down")
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _expect(p, false, "HOLD focus-out resets")
	GameState.fire_mode = GameState.FireMode.AUTO
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _expect(p, true, "AUTO focus-out resets to firing")
	# settings persistence
	GameState.set_fire_mode(GameState.FireMode.HOLD)
	GameState.fire_mode = GameState.FireMode.AUTO
	GameState.load_settings()
	print("%s  settings round-trip: %s" % ["PASS" if GameState.fire_mode == GameState.FireMode.HOLD else "FAIL", GameState.fire_mode])
	if GameState.fire_mode != GameState.FireMode.HOLD: _fails += 1
	GameState.set_fire_mode(GameState.FireMode.AUTO)
	print("FIRE MODE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
