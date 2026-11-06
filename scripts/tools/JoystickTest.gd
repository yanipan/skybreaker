extends Node
## Headless: joystick speed curve, movement, clamping, release, layout.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(360, 1000)
	add_child(p)
	await get_tree().process_frame
	_check(p.joy_speed(0.05) == 0.0, "dead zone: tiny push does not move")
	_check(p.joy_speed(0.5) > 0.0 and p.joy_speed(0.5) < p.joy_speed(1.0) * 0.6, "half push is well under half of full speed (%.0f vs %.0f)" % [p.joy_speed(0.5), p.joy_speed(1.0)])
	_check(is_equal_approx(p.joy_speed(1.0), p.JOY_MAX_SPEED), "full push = max speed at tier 0")
	p.speed_tier = 2
	_check(p.joy_speed(1.0) > p.JOY_MAX_SPEED * 1.5, "thruster tier speeds up the stick")
	p.speed_tier = 0
	var start: Vector2 = p.position
	p.set_joystick(Vector2(1, 0))
	for i in 10:
		await get_tree().process_frame
	_check(p.position.x > start.x + 20.0 and absf(p.position.y - start.y) < 1.0, "stick right moves the ship right only (dx=%.0f)" % (p.position.x - start.x))
	p.set_joystick(Vector2(0, -0.3))
	var y0: float = p.position.y
	for i in 10:
		await get_tree().process_frame
	var slow_dy: float = y0 - p.position.y
	p.set_joystick(Vector2(0, -1))
	y0 = p.position.y
	for i in 10:
		await get_tree().process_frame
	var fast_dy: float = y0 - p.position.y
	_check(fast_dy > slow_dy * 2.0, "further from center = faster (%.0f vs %.0f px)" % [fast_dy, slow_dy])
	p.set_joystick(Vector2(-1, 0))
	for i in 240:
		await get_tree().process_frame
	_check(p.position.x >= p.screen_padding - 0.01, "clamped at the left edge (x=%.0f)" % p.position.x)
	p.set_joystick(Vector2.ZERO)
	var rest: Vector2 = p.position
	for i in 20:
		await get_tree().process_frame
	_check(p.position.distance_to(rest) < 0.5, "release: ship stays put (no snap back)")
	p.set_joystick(Vector2(1, 0))
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(p._joy_vec == Vector2.ZERO, "focus loss drops the stick")
	# Layout: stick on the side opposite the weapons, no overlap with them
	var MC = load("res://scripts/MobileControls.gd")
	var safe := Rect2(0, 0, 720, 1560)
	for side in [0, 1]:
		var lay: Array = MC.joystick_layout(safe, 106.0, side)
		var cs: Array = MC.cluster_centers(safe, 106.0, side)
		var c: Vector2 = lay[0]
		_check((c.x > 360.0) == (side == 0), "side %d: stick opposite the weapons" % side)
		_check(safe.grow(-lay[1]).has_point(c), "side %d: stick ring fully on screen" % side)
		var clear := true
		for b in cs:
			if c.distance_to(b) < lay[2] + 53.0:
				clear = false
		_check(clear, "side %d: stick hit area clear of weapon buttons" % side)
	print("JOYSTICK TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
