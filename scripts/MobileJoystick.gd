extends Control
## Mini-screen stick (6/11 v3). A small portrait map of the play field: the
## thumb's spot on the map is where the ship flies (Player.set_stick_target),
## and the cyan dot shows where the ship is now. A touch that starts anywhere
## in the hit square grabs it; dragging off the map clamps to its edge.
## Only a finger that STARTED here is ours: a steering finger sliding across
## passes through to the ship.

signal aimed(u: Vector2, active: bool)

var base_radius: float = 100.0    ## kept for layout compatibility (ring size)
var screen_aspect: float = 816.0 / 1452.0   ## play field width / height
var ship_u: Vector2 = Vector2(0.5, 0.8)     ## ship position on the map, set by MobileControls
var col_base: Color = Color(0.55, 0.95, 1.0, 0.85)
var _touch: int = -1
var _mouse: bool = false
var _thumb_u: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## The map rectangle inside the control, portrait, centered.
func map_rect() -> Rect2:
	var h: float = size.y * 0.92
	var w: float = minf(h * screen_aspect, size.x * 0.92)
	h = w / screen_aspect
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


## Local point -> map point (0..1), clamped.
func to_map(local_pos: Vector2) -> Vector2:
	var r: Rect2 = map_rect()
	return ((local_pos - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_aim(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_aim(event.position)
			accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse = event.pressed
		if event.pressed:
			_aim(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _mouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_aim(event.position)
		accept_event()


func _aim(local_pos: Vector2) -> void:
	_thumb_u = to_map(local_pos)
	aimed.emit(_thumb_u, true)
	queue_redraw()


func _release() -> void:
	_touch = -1
	_mouse = false
	_thumb_u = Vector2(-1, -1)
	aimed.emit(Vector2.ZERO, false)
	queue_redraw()


## Drop a stuck finger (pause / focus loss never delivers the release).
func reset() -> void:
	if _touch != -1 or _mouse:
		_release()


func is_active() -> bool:
	return _touch != -1 or _mouse


func set_ship_u(u: Vector2) -> void:
	if u.distance_squared_to(ship_u) > 0.00001:
		ship_u = u
		queue_redraw()


func _draw() -> void:
	var r: Rect2 = map_rect()
	var active: bool = is_active()
	draw_rect(r, Color(0.04, 0.08, 0.14, 0.45 if active else 0.30), true)
	draw_rect(r, Color(col_base, 0.80 if active else 0.45), false, 3.0)
	# Faint thirds grid so the map reads as a screen.
	for i in [1, 2]:
		var x: float = r.position.x + r.size.x * float(i) / 3.0
		var y: float = r.position.y + r.size.y * float(i) / 3.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(col_base, 0.12), 1.0)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(col_base, 0.12), 1.0)
	var ship_p: Vector2 = r.position + r.size * ship_u
	if active and _thumb_u.x >= 0.0:
		var tp: Vector2 = r.position + r.size * _thumb_u
		draw_line(ship_p, tp, Color(col_base, 0.35), 2.0, true)
		draw_circle(tp, 16.0, Color(0.10, 0.20, 0.30, 0.6))
		draw_arc(tp, 16.0, 0.0, TAU, 32, Color(col_base, 0.95), 3.0, true)
	draw_circle(ship_p, 7.0, Color(col_base, 0.95 if active else 0.7))
