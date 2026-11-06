extends Node
## Headless: mini-screen stick: mapping, straight-line flight, instant
## direction change, tier speed, release, layout.
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
	var sz: Vector2 = p.get_viewport_rect().size
	# Map corners land on the padded play field corners.
	_check(p.stick_to_screen(Vector2.ZERO).is_equal_approx(Vector2(p.screen_padding, p.screen_padding)), "map top-left = field top-left")
	_check(p.stick_to_screen(Vector2.ONE).is_equal_approx(sz - Vector2(p.screen_padding, p.screen_padding)), "map bottom-right = field bottom-right")
	_check(p.stick_position().distance_to(Vector2(inverse_lerp(p.screen_padding, sz.x - p.screen_padding, 360.0), inverse_lerp(p.screen_padding, sz.y - p.screen_padding, 1000.0))) < 0.001, "ship dot matches the ship position")
	# Thumb top-right: the ship flies there in a straight line.
	var start: Vector2 = p.position
	var goal: Vector2 = p.stick_to_screen(Vector2(0.9, 0.2))
	p.set_stick_target(Vector2(0.9, 0.2), true)
	await get_tree().process_frame
	await get_tree().process_frame
	var dir0: Vector2 = (goal - start).normalized()
	var moved: Vector2 = p.position - start
	_check(moved.length() > 5.0 and moved.normalized().dot(dir0) > 0.99, "ship heads straight for the thumb's spot")
	# Instant reversal: thumb jumps to bottom-left, next frames head there.
	p.set_stick_target(Vector2(0.1, 0.9), true)
	var at: Vector2 = p.position
	await get_tree().process_frame
	await get_tree().process_frame
	var goal2: Vector2 = p.stick_to_screen(Vector2(0.1, 0.9))
	_check((p.position - at).normalized().dot((goal2 - at).normalized()) > 0.99, "direction change is immediate")
	# Speed cap, tier scaling.
	var cap0: float = p.stick_max_speed()
	p.speed_tier = 2
	_check(p.stick_max_speed() > cap0 * 1.5, "thruster tier raises stick speed")
	p.speed_tier = 0
	var t0: int = Time.get_ticks_msec()
	for i in 240:
		await get_tree().process_frame
		if p.position.distance_to(goal2) < 4.0:
			break
	_check(p.position.distance_to(goal2) < 4.0, "ship arrives at the spot")
	# Release: ship stays put.
	p.set_stick_target(Vector2.ZERO, false)
	var rest: Vector2 = p.position
	for i in 20:
		await get_tree().process_frame
	_check(p.position.distance_to(rest) < 0.5, "release: ship stays where it is")
	p.set_stick_target(Vector2(1, 0), true)
	p.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not p._stick_active, "focus loss drops the stick")
	# Stick control: map is portrait with the screen aspect, thumb maps 0..1.
	var st: Control = load("res://scripts/MobileJoystick.gd").new()
	st.size = Vector2(290, 290)
	st.screen_aspect = 816.0 / 1452.0
	add_child(st)
	var r: Rect2 = st.map_rect()
	_check(absf(r.size.x / r.size.y - st.screen_aspect) < 0.01 and r.size.y > 250.0, "map is a portrait mini-screen (%.0fx%.0f)" % [r.size.x, r.size.y])
	_check(st.to_map(r.position).is_equal_approx(Vector2.ZERO) and st.to_map(r.end).is_equal_approx(Vector2.ONE), "map corners -> 0..1")
	_check(st.to_map(Vector2(-50, 400)) == Vector2(0, 1), "thumb off the map clamps to its edge")
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
