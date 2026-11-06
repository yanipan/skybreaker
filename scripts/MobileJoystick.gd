extends Control
## Fixed on-screen joystick (6/11). Base ring + knob; the knob follows the
## finger clamped to the ring and reports a unit-circle vector. A touch that
## starts anywhere in the (larger) hit circle grabs the stick, and the drag
## keeps it even when the finger leaves the circle. Release = zero.

signal moved(v: Vector2)

var base_radius: float = 100.0
var col_base: Color = Color(0.55, 0.95, 1.0, 0.85)
var _touch: int = -1
var _knob: Vector2 = Vector2.ZERO   ## Offset from center, |_knob| <= base_radius
var _mouse: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center() -> Vector2:
	return size * 0.5


func _has_point(point: Vector2) -> bool:
	return point.distance_to(_center()) <= min(size.x, size.y) * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_set_knob(event.position)
		elif not event.pressed and event.index == _touch:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_set_knob(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse = event.pressed
		if event.pressed:
			_set_knob(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _mouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_set_knob(event.position)
		accept_event()


func _set_knob(local_pos: Vector2) -> void:
	_knob = (local_pos - _center()).limit_length(base_radius)
	moved.emit(_knob / base_radius)
	queue_redraw()


func _release() -> void:
	_touch = -1
	_mouse = false
	_knob = Vector2.ZERO
	moved.emit(Vector2.ZERO)
	queue_redraw()


## Drop a stuck finger (pause / focus loss never delivers the release).
func reset() -> void:
	if _touch != -1 or _mouse or _knob != Vector2.ZERO:
		_release()


func is_active() -> bool:
	return _touch != -1 or _mouse


func _draw() -> void:
	var c: Vector2 = _center()
	var active: bool = is_active()
	draw_circle(c, base_radius, Color(0.04, 0.08, 0.14, 0.45 if active else 0.30))
	draw_arc(c, base_radius, 0.0, TAU, 64, Color(col_base, 0.75 if active else 0.40), 3.0, true)
	draw_arc(c, base_radius * 0.12 + 0.0, 0.0, TAU, 24, Color(col_base, 0.25), 1.5, true)
	var kr: float = base_radius * 0.42
	var kc: Vector2 = c + _knob
	draw_circle(kc, kr, Color(0.10, 0.20, 0.30, 0.85 if active else 0.60))
	draw_arc(kc, kr, 0.0, TAU, 48, Color(col_base, 0.95 if active else 0.60), 3.0, true)
