extends Area2D
class_name EnemyBeam
## Enemy beam weapon (9/11 expansion): a thin flickering warning line for
## `charge_secs`, then a damaging column for `fire_secs`, straight down from
## its emitter to the bottom of the screen. It follows the emitter, so a
## drifting boss sweeps it across the field.
##
## It sits in the enemy_bullets group so the existing plumbing applies: the
## ship takes `damage` once and the beam ends (Player._on_area_entered frees
## the area), warps and deaths clear it with the other shots. The player's own
## beam cannot burn it (no beam_burn method). If the emitter dies while the
## beam is still charging, the beam is cancelled: killing the gunner in time
## is the counterplay.

@export var damage: int = 8
@export var charge_secs: float = 0.9
@export var fire_secs: float = 0.7
@export var width: float = 46.0
@export var beam_color: Color = Color(1.0, 0.30, 0.30)
@export var from_boss: bool = false

## Node the beam hangs under (position follows it every frame) + local offset.
var emitter: Node2D = null
var offset: Vector2 = Vector2.ZERO

var _time: float = 0.0
var _firing: bool = false
var _length: float = 1600.0
var _shape: CollisionShape2D


func _ready() -> void:
	add_to_group(&"enemy_bullets")
	z_index = 2
	_length = get_viewport().get_visible_rect().size.y + 200.0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width * 0.8, _length)
	_shape.shape = rect
	_shape.position = Vector2(0.0, _length * 0.5)
	add_child(_shape)
	# Harmless while it charges.
	monitorable = false
	_follow()


func is_firing() -> bool:
	return _firing


func _follow() -> void:
	if emitter != null and is_instance_valid(emitter):
		global_position = emitter.global_position + offset


func _process(delta: float) -> void:
	_time += delta
	var emitter_alive: bool = emitter != null and is_instance_valid(emitter) and not emitter.is_queued_for_deletion()
	if not emitter_alive and not _firing:
		queue_free()   # gunner killed during the wind-up: no beam
		return
	_follow()
	if not _firing and _time >= charge_secs:
		_firing = true
		set_deferred("monitorable", true)
		AudioManager.play_sfx(AudioManager.SFX_BEAM, -10.0)
		EventBus.screen_shake_requested.emit(3.0, 0.15)
	if _firing and _time >= charge_secs + fire_secs:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if not _firing:
		# Warning: a thin line that flickers faster as the shot gets closer,
		# plus a charge glow at the muzzle.
		var k: float = clampf(_time / maxf(charge_secs, 0.01), 0.0, 1.0)
		var flick: float = 0.45 + 0.55 * absf(sin(_time * lerpf(10.0, 34.0, k)))
		var c := Color(beam_color.r, beam_color.g, beam_color.b, 0.25 + 0.45 * k * flick)
		draw_line(Vector2.ZERO, Vector2(0.0, _length), c, lerpf(2.0, 5.0, k))
		draw_circle(Vector2.ZERO, lerpf(6.0, width * 0.45, k), Color(beam_color.r, beam_color.g, beam_color.b, 0.30 + 0.4 * k))
		draw_circle(Vector2.ZERO, lerpf(3.0, width * 0.22, k), Color(1, 1, 1, 0.55 * k))
		return
	# Firing: wide soft halo, coloured body, white-hot core; fades at the end.
	var t: float = (_time - charge_secs) / maxf(fire_secs, 0.01)
	var fade: float = 1.0 if t < 0.75 else clampf((1.0 - t) / 0.25, 0.0, 1.0)
	var pulse: float = 0.92 + 0.08 * sin(_time * 60.0)
	var w: float = width * pulse
	draw_rect(Rect2(-w * 0.9, 0.0, w * 1.8, _length), Color(beam_color.r, beam_color.g, beam_color.b, 0.16 * fade), true)
	draw_rect(Rect2(-w * 0.5, 0.0, w, _length), Color(beam_color.r, beam_color.g, beam_color.b, 0.80 * fade), true)
	draw_rect(Rect2(-w * 0.2, 0.0, w * 0.4, _length), Color(1.0, 1.0, 1.0, 0.95 * fade), true)
	draw_circle(Vector2.ZERO, w * 0.75, Color(1.0, 1.0, 1.0, 0.85 * fade))
