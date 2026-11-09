extends Node
## Headless check of the one-button fire wheel (9/11): touch a wedge to fire
## that weapon, slide to another wedge to switch without lifting; the torpedo
## is its own corner button (a firing thumb can curl onto it: one torpedo per
## visit, gun keeps going); hub and border hysteresis, layout on both sides, torpedo warhead tiers and shop ladder.
## Run: godot --headless --path . res://scenes/tools/FireWheelTest.tscn

var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _w(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _w(pos)
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _w(pos)
	Input.parse_input_event(e)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	GameState.controls_side = 0
	GameState.joystick_enabled = true
	GameState.fire_mode = GameState.FireMode.HOLD
	var W = MobileFireWheel
	# --- geometry (static): three 120-degree wedges ---
	var r: float = 140.0
	var down_in := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 80.0
	var down_out := Vector2(-cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 80.0
	_check(W.SLOTS == 3, "three weapon wedges, no torpedo wedge")
	_check(W.slot_at(Vector2(0, -80), r, -1, false) == 0, "up = phaser")
	_check(W.slot_at(down_in, r, -1, false) == 1, "inward = beam")
	_check(W.slot_at(down_out, r, -1, false) == 2, "back toward the corner = missile")
	_check(W.slot_at(down_out, r, -1, true) == 1 and W.slot_at(down_in, r, -1, true) == 2, "mirrored on a right-side wheel")
	_check(W.slot_at(Vector2(5, 5), r, 0, false) == 0, "hub keeps the wedge the finger came from")
	var just_over := Vector2.UP.rotated(deg_to_rad(65.0)) * 90.0     # 5 deg past the P/B border
	var well_over := Vector2.UP.rotated(deg_to_rad(80.0)) * 90.0
	_check(W.slot_at(just_over, r, 0, false) == 0, "a few degrees past the border does not flicker")
	_check(W.slot_at(well_over, r, 0, false) == 1, "clearly past the border switches")
	_check(W.slot_at(just_over, r, -1, false) == 1, "a fresh touch has no hysteresis")
	# --- live wheel ---
	var p: Node = load("res://scripts/Player.gd").new()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	p.position = vp * 0.5
	add_child(p)
	var mc: CanvasLayer = load("res://scripts/MobileControls.gd").new()
	mc.force_visible = true
	add_child(mc)
	await _frames(3)
	var wheel: Control = mc._pad
	_check(wheel is MobileFireWheel, "one fire wheel replaces the three weapon buttons")
	_check(not mc._weapon_btns[0].visible and mc._torpedo_btn.visible, "weapon buttons hidden, torpedo keeps its own button")
	var cs: Array = mc._pad_centers
	var centre: Vector2 = wheel.position + wheel.size * 0.5
	var torp: Vector2 = cs[3]
	_check(centre.x - wheel.radius >= 0.0 and centre.y + wheel.radius <= vp.y, "wheel fully on screen")
	_check(torp.distance_to(centre) > wheel.radius + mc._torpedo_radius, "torpedo button sits outside the wheel")
	# touch P, slide to B, slide to M: weapon follows, fire never drops
	_touch(4, cs[0], true)
	await _frames(2)
	_check(p.weapon_type == 0 and p._fire_button_held, "touch the top wedge: phaser firing")
	_drag(4, cs[1])
	await _frames(2)
	_check(p.weapon_type == 1 and p._fire_button_held, "slide to the beam wedge: beam firing, no lift")
	_drag(4, cs[2])
	await _frames(2)
	_check(p.weapon_type == 2 and p._fire_button_held, "slide across to missiles: still firing")
	_check(p._weapon_buttons_down.size() == 1, "exactly one weapon is held after sliding (%d)" % p._weapon_buttons_down.size())
	# curl onto the torpedo button and back
	p.torpedo_count = 3
	_drag(4, centre + (torp - centre).normalized() * (wheel.radius + 4.0))
	await _frames(2)
	_check(p.torpedo_count == 3, "just past the rim toward the corner is not yet the torpedo")
	_drag(4, torp)
	await _frames(2)
	_check(p.torpedo_count == 2, "sliding onto the torpedo button fires one torpedo")
	_check(p.weapon_type == 2 and p._fire_button_held, "main gun keeps firing during the torpedo flick")
	for t in get_tree().get_nodes_in_group(&"player_torpedoes"):
		t.free()
	_drag(4, torp + Vector2(5, 3))
	await _frames(2)
	_check(p.torpedo_count == 2, "resting on the torpedo button does not fire again")
	_drag(4, cs[0])
	await _frames(2)
	_check(p.weapon_type == 0 and p._fire_button_held, "back up to phaser")
	# slide far past the rim: still ours, still switching
	_drag(4, centre + Vector2(wheel.radius * 2.2, wheel.radius * 0.6))
	await _frames(2)
	_check(p.weapon_type == 1 and p._fire_button_held, "finger past the rim still switches by direction")
	_touch(4, centre + Vector2(wheel.radius * 2.2, wheel.radius * 0.6), false)
	await _frames(2)
	_check(not p._fire_button_held and mc._pad_touch.is_empty(), "lifting anywhere stops the fire")
	# torpedo tap alone
	p.torpedo_count = 2
	p._torpedo_grace_timer = 0.0
	_touch(5, torp, true)
	await _frames(2)
	_touch(5, torp, false)
	await _frames(2)
	_check(p.torpedo_count == 1 and not p._fire_button_held, "tapping the torpedo button fires one torpedo and no gun")
	for t in get_tree().get_nodes_in_group(&"player_torpedoes"):
		t.free()
	# layout on both sides, clear of the joystick
	var MC = load("res://scripts/MobileControls.gd")
	var safe := Rect2(0, 0, 720, 1560)
	for side in [0, 1]:
		var wl: Array = MC.wheel_layout(safe, 106.0, side)
		var jl: Array = MC.joystick_layout(safe, 106.0, side)
		var c: Vector2 = wl[0]
		var tcn: Vector2 = wl[2]
		_check(c.x - wl[1] >= 0.0 and c.x + wl[1] <= 720.0 and c.y + wl[1] <= 1560.0, "side %d: wheel inside the safe area" % side)
		_check(tcn.x - wl[3] >= 0.0 and tcn.x + wl[3] <= 720.0 and tcn.y + wl[3] <= 1560.0, "side %d: torpedo button inside the safe area" % side)
		_check(c.distance_to(jl[0]) > MC.pad_reach(106.0) + jl[2], "side %d: wheel clear of the joystick" % side)

	# --- torpedo warhead upgrade ---
	var T = load("res://scripts/Torpedo.gd")
	var t0: Node = T.new(); add_child(t0)
	var t3: Node = T.new(); t3.tier = 3; add_child(t3)
	await _frames(1)
	_check(t0.splash_damage == 24 and is_equal_approx(t0.splash_radius, 360.0), "stock torpedo unchanged")
	_check(t3.splash_damage == 60 and is_equal_approx(t3.splash_radius, 360.0 * 1.65) and t3.torpedo_size.x > t0.torpedo_size.x * 1.5, "level 3 warhead: 60 damage, 65%% wider blast, bigger body")
	t0.free(); t3.free()
	p.torpedo_tier = 2
	p.torpedo_count = 1
	p._torpedo_grace_timer = 0.0
	p._try_fire_torpedo()
	var fired: Array = get_tree().get_nodes_in_group(&"player_torpedoes")
	_check(fired.size() == 1 and fired[0].tier == 2, "the ship fires its upgraded warhead")
	for t in fired:
		t.free()
	GameState.snapshot_player(p)
	_check(GameState.carry_torpedo_tier == 2, "warhead level is carried to the next sector")
	var shop: Node = load("res://scripts/StarbaseShop.gd").new()
	shop.player_ref = p
	p.torpedo_tier = 0
	_check(shop._price_for(&"torp_power") == 900, "warhead level 1 costs 900")
	p.torpedo_tier = 2
	_check(shop._price_for(&"torp_power") == 2800, "warhead level 3 costs 2800")
	p.torpedo_tier = 3
	_check(shop._price_for(&"torp_power") == -1, "three levels, then maxed")
	shop.free()
	print("FireWheelTest: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
