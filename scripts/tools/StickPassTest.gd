extends Node
## Headless: in drag-to-move play, a steering finger that slides across the
## on-screen joystick keeps steering the ship (it can reach the corner under
## the stick), the stick stays idle, and lifting the finger over the stick
## still releases the ship. A finger that STARTS on the stick drives the stick.
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

func _ready() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var layer := CanvasLayer.new()
	add_child(layer)
	var stick: Control = load("res://scripts/MobileJoystick.gd").new()
	var hit: float = 150.0
	stick.size = Vector2(hit, hit) * 2.0
	var center := Vector2(vp.x - 200.0, vp.y - 200.0)
	stick.position = center - Vector2(hit, hit)
	stick.base_radius = 100.0
	layer.add_child(stick)
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = vp * 0.5
	add_child(p)
	for i in 2:
		await get_tree().process_frame

	# Finger starts mid-screen, slides into the stick.
	_touch(0, vp * 0.5, true)
	await get_tree().process_frame
	_check(p._touch_index == 0, "finger mid-screen steers the ship")
	var path: Array = [vp * 0.5 + Vector2(100, 100), center + Vector2(-60, 0), center, center + Vector2(40, 30)]
	for q in path:
		_drag(0, q)
		await get_tree().process_frame
	var want_x: float = clampf(center.x + 40.0, p.screen_padding, vp.x - p.screen_padding)
	_check(absf(p._target_position.x - want_x) < 1.0, "ship target follows the finger over the stick (x %.0f, want %.0f)" % [p._target_position.x, want_x])
	_check(not stick.is_active(), "the stick ignores a finger that started elsewhere")
	_touch(0, center + Vector2(40, 30), false)
	await get_tree().process_frame
	_check(p._touch_index == -1, "lifting the finger over the stick releases the ship")

	# Finger that starts ON the stick drives the stick, not the ship.
	_touch(1, center + Vector2(20, 0), true)
	await get_tree().process_frame
	_check(stick.is_active(), "finger that starts on the stick grabs it")
	_check(p._touch_index == -1, "and does not steer the ship by drag")
	_touch(1, center + Vector2(20, 0), false)
	await get_tree().process_frame
	_check(not stick.is_active(), "stick released")

	print("StickPassTest done, fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
