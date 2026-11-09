extends Node
## Headless: the corner pad. A tap that MISSES a round button but lands in its
## wedge still picks that weapon; the corner fires a torpedo; fingers can hold
## two slots at once; a steering finger sliding through the corner keeps
## steering; the pad never reaches the joystick on either side.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _w(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = _w(pos)
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = _w(pos)
	Input.parse_input_event(e)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	GameState.controls_side = 0
	GameState.joystick_enabled = true
	var p: Node = load("res://scripts/Player.gd").new()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	p.position = vp * 0.5
	add_child(p)
	var mc: CanvasLayer = load("res://scripts/MobileControls.gd").new()
	mc.force_visible = true
	add_child(mc)
	await _frames(3)
	var cs: Array = mc._pad_centers
	_check(cs.size() == 4 and mc._pad != null, "pad built over the cluster")
	var size: float = mc._button_size()
	var corner: Vector2 = cs[3]
	# Near-miss taps (fire wheel, 9/11): a tap in a wedge's direction just
	# PAST the drawn rim still picks that weapon.
	var centre: Vector2 = mc._pad.position + mc._pad.size * 0.5
	for wt in [1, 2, 0]:
		var c: Vector2 = cs[wt]
		var pos: Vector2 = centre + (c - centre).normalized() * mc._pad.radius * 1.1
		_touch(5, pos, true)
		await _frames(2)
		_check(p.weapon_type == wt, "near-miss tap off button %d still picks weapon %d (got %d)" % [wt, wt, p.weapon_type])
		_touch(5, pos, false)
		await _frames(2)
	# Two fingers: hold P, then also hold M -> M wins, firing held.
	_touch(6, cs[0], true)
	_touch(7, cs[2], true)
	await _frames(2)
	_check(p.weapon_type == 2 and p._fire_button_held, "two fingers: last weapon wins and fire is held")
	_touch(7, cs[2], false)
	await _frames(2)
	_check(p._fire_button_held, "lifting one finger keeps firing with the other")
	_touch(6, cs[0], false)
	await _frames(2)
	_check(not p._fire_button_held, "both lifted: fire released")
	# Torpedo from a tap near (not on) the corner button.
	p.torpedo_count = 2
	var t0: int = p.torpedo_count
	var tpos: Vector2 = corner + Vector2(size * 0.45, size * 0.10)
	_touch(8, tpos, true)
	await _frames(2)
	_touch(8, tpos, false)
	await _frames(2)
	_check(p.torpedo_count < t0, "tap near the corner fires a torpedo")
	# Steering finger slides through the corner.
	_touch(0, vp * 0.5, true)
	await _frames(1)
	_drag(0, corner + Vector2(size * 0.8, -size * 0.8))
	await _frames(1)
	_drag(0, corner + Vector2(size * 0.3, -size * 0.3))
	await _frames(1)
	_check(p._touch_index == 0 and absf(p._target_position.x - clampf(corner.x + size * 0.3, p.screen_padding, vp.x - p.screen_padding)) < 1.0, "steering finger keeps steering through the corner")
	_check(not p._fire_button_held, "and does not press any button")
	_touch(0, corner, false)
	await _frames(1)
	# Layout: pad clear of the joystick on both sides.
	var MC = load("res://scripts/MobileControls.gd")
	var safe := Rect2(0, 0, 720, 1560)
	for side in [0, 1]:
		var lay: Array = MC.joystick_layout(safe, 106.0, side)
		var c3: Vector2 = MC.cluster_centers(safe, 106.0, side)[3]
		_check(c3.distance_to(lay[0]) > MC.pad_reach(106.0) + lay[2], "side %d: pad clear of the joystick" % side)
	print("PadTest done, fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
