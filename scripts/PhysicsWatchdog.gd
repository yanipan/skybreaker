extends Node
class_name PhysicsWatchdog
## Guards against "ship, enemies and shots stop colliding after a pause", seen
## on a real iPhone but never reproduced headless. Two off-screen Area2Ds on
## their own physics layer overlap once a second. If the overlap goes unseen
## for STALL_CYCLES tests, overlap detection is dead: first force the physics
## server back on, and if that does not help ask Main to reload the sector.
## Inherits pause from Main, so a paused tree is never counted as a stall.

signal unrecovered

const PROBE_LAYER: int = 1 << 19
const PROBE_HOME := Vector2(-20000.0, -20000.0)
const PROBE_AWAY := Vector2(-19000.0, -20000.0)
const HALF_CYCLE: float = 0.5
const STALL_CYCLES: int = 3

var _probe: Area2D
var _target: Area2D
var _on_target: bool = false
var _seen: bool = false
var _missed: int = 0
var _healed: bool = false
var _timer: float = 0.0
var _ticks: int = 0
var _tick_clock: float = 0.0
var ticks_per_second: float = 0.0
var overlap_ok: bool = true


func _ready() -> void:
	_probe = _make_area(0, PROBE_LAYER)
	_probe.position = PROBE_HOME
	_probe.monitorable = false
	_probe.area_entered.connect(func(_a: Area2D) -> void: _seen = true)
	_target = _make_area(PROBE_LAYER, 0)
	_target.position = PROBE_AWAY
	_target.monitoring = false


func _make_area(layer: int, mask: int) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = layer
	area.collision_mask = mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	return area


func _physics_process(_delta: float) -> void:
	_ticks += 1


func _process(delta: float) -> void:
	_tick_clock += delta
	if _tick_clock >= 1.0:
		ticks_per_second = _ticks / _tick_clock
		_ticks = 0
		_tick_clock = 0.0
	_timer += delta
	if _timer < HALF_CYCLE:
		return
	_timer = 0.0
	if _on_target:
		_target.position = PROBE_AWAY
		_check_result()
	else:
		_seen = false
		_target.position = PROBE_HOME
	_on_target = not _on_target


func _check_result() -> void:
	if _seen:
		_missed = 0
		_healed = false
		overlap_ok = true
		return
	_missed += 1
	if _missed < STALL_CYCLES:
		return
	_missed = 0
	overlap_ok = false
	GameState.physics_stalls += 1
	push_warning("PhysicsWatchdog: overlap detection stalled (%d)" % GameState.physics_stalls)
	if _healed:
		unrecovered.emit()
	else:
		_healed = true
		PhysicsServer2D.set_active(true)


## One line for the pause screen, so a device report can say what state the
## game was really in.
func diag_text() -> String:
	return "phys %s  stalls %d  ticks %d/s" % ["ok" if overlap_ok else "STALLED", GameState.physics_stalls, roundi(ticks_per_second)]
