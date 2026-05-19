extends Node2D
class_name Explosion
## Procedural torpedo explosion. Bigger, longer, and louder than EnemyExplosion.
## Layered: huge white flash → expanding fire ball → fast shockwave ring →
## inner secondary ring → many sparks with trails → thick smoke cloud →
## chunky rotating debris. Damage is handled by whatever spawns it.

@export var radius: float = 220.0
@export var lifetime: float = 0.85
@export var spark_count: int = 28
@export var smoke_count: int = 10
@export var debris_count: int = 12

var _time: float = 0.0

# Per-instance randomness — gives every detonation its own personality
var _size_jitter: float = 1.0
var _life_jitter: float = 1.0
var _color_shift: float = 0.0
var _ring_speed_mul: float = 1.0
var _rotation_offset: float = 0.0
var _asymmetry: Vector2 = Vector2.ZERO

var _spark_dirs: Array[Vector2] = []
var _spark_speeds: Array[float] = []

var _smoke_dirs: Array[Vector2] = []
var _smoke_speeds: Array[float] = []
var _smoke_sizes: Array[float] = []
var _smoke_phase: Array[float] = []

var _debris_dirs: Array[Vector2] = []
var _debris_speeds: Array[float] = []
var _debris_sizes: Array[float] = []
var _debris_rot: Array[float] = []
var _debris_spin: Array[float] = []


func _ready() -> void:
	# Roll personality for this specific blast
	_size_jitter = randf_range(0.85, 1.20)
	_life_jitter = randf_range(0.88, 1.15)
	_color_shift = randf_range(-0.07, 0.07)
	_ring_speed_mul = randf_range(0.85, 1.20)
	_rotation_offset = randf() * TAU
	_asymmetry = Vector2(randf_range(-0.10, 0.10), randf_range(-0.10, 0.10)) * radius
	radius *= _size_jitter
	lifetime *= _life_jitter
	spark_count = max(8, int(spark_count * randf_range(0.80, 1.25)))
	debris_count = max(4, int(debris_count * randf_range(0.80, 1.25)))
	smoke_count = max(4, int(smoke_count * randf_range(0.80, 1.25)))

	_spark_dirs.resize(spark_count)
	_spark_speeds.resize(spark_count)
	for i in spark_count:
		var a: float = _rotation_offset + randf() * TAU
		_spark_dirs[i] = Vector2(cos(a), sin(a))
		_spark_speeds[i] = randf_range(radius * 1.2, radius * 2.9)

	_smoke_dirs.resize(smoke_count)
	_smoke_speeds.resize(smoke_count)
	_smoke_sizes.resize(smoke_count)
	_smoke_phase.resize(smoke_count)
	for i in smoke_count:
		var a2: float = _rotation_offset + randf() * TAU
		_smoke_dirs[i] = Vector2(cos(a2), sin(a2))
		_smoke_speeds[i] = randf_range(radius * 0.25, radius * 0.95)
		_smoke_sizes[i] = randf_range(radius * 0.25, radius * 0.65)
		_smoke_phase[i] = randf() * TAU

	_debris_dirs.resize(debris_count)
	_debris_speeds.resize(debris_count)
	_debris_sizes.resize(debris_count)
	_debris_rot.resize(debris_count)
	_debris_spin.resize(debris_count)
	for i in debris_count:
		var a3: float = _rotation_offset + randf() * TAU
		_debris_dirs[i] = Vector2(cos(a3), sin(a3))
		_debris_speeds[i] = randf_range(radius * 0.7, radius * 2.1)
		_debris_sizes[i] = randf_range(radius * 0.03, radius * 0.11)
		_debris_rot[i] = randf() * TAU
		_debris_spin[i] = randf_range(-12.0, 12.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if _time >= lifetime:
		queue_free()


func _draw() -> void:
	var t: float = clamp(_time / lifetime, 0.0, 1.0)
	var inv: float = 1.0 - t

	# Center offset so the burst isn't perfectly symmetrical
	var oc: Vector2 = _asymmetry

	# 1. Massive white-hot flash — first ~10% of life
	var flash_t: float = clamp(_time / (lifetime * 0.10), 0.0, 1.0)
	var flash_alpha: float = (1.0 - flash_t) * 1.0
	if flash_alpha > 0.01:
		var flash_r: float = radius * (0.5 + flash_t * 1.0)
		draw_circle(oc, flash_r * 1.6, Color(1, 1, 1, flash_alpha * 0.4))
		draw_circle(oc, flash_r, Color(1, 1, 1, flash_alpha))

	# 2. Fire ball — expands outward then collapses, color shifts white → red
	var ball_r: float = radius * (0.55 + ease(t, 0.35) * 0.65) * (1.0 - t * 0.25)
	var fc: Color = _fire_color(t)
	# Per-instance hue jitter — pushes the whole fireball slightly redder or yellower
	fc.r = clamp(fc.r + _color_shift, 0.0, 1.0)
	fc.g = clamp(fc.g - _color_shift * 0.5, 0.0, 1.0)
	# Outer halo
	draw_circle(oc, ball_r * 1.45, Color(fc.r, fc.g, fc.b, inv * 0.30))
	# Mid body
	draw_circle(oc, ball_r, Color(fc.r, fc.g, fc.b, inv * 0.75))
	# Bright inner core (lighter than fc)
	var core := Color(clamp(fc.r + 0.3, 0.0, 1.0), clamp(fc.g + 0.3, 0.0, 1.0), clamp(fc.b + 0.2, 0.0, 1.0), inv * 0.9)
	draw_circle(oc, ball_r * 0.55, core)

	# 3. Primary shockwave — fast outer ring
	var ring_r: float = radius * (0.4 + ease(t, 0.2) * 1.7) * _ring_speed_mul
	var ring_alpha: float = inv * 0.85
	draw_arc(oc, ring_r, 0.0, TAU, 48, Color(1.0, 0.95, 0.7, ring_alpha), 3.5, true)
	# Faint trailing inner ring
	var ring2_r: float = radius * (0.3 + ease(t, 0.35) * 1.2) * _ring_speed_mul
	draw_arc(oc, ring2_r, 0.0, TAU, 48, Color(1.0, 0.7, 0.3, ring_alpha * 0.5), 2.0, true)

	# 4. Sparks — bright streaks with motion trails
	for i in spark_count:
		var dir: Vector2 = _spark_dirs[i]
		var dist: float = _spark_speeds[i] * ease(t, 0.5)
		var pos: Vector2 = dir * dist
		var trail_len: float = radius * 0.18 * (1.0 - t)
		var tail: Vector2 = pos - dir * trail_len
		var sc := Color(1.0, lerp(0.95, 0.5, t), lerp(0.6, 0.1, t), inv)
		draw_line(tail, pos, sc, 2.5)
		draw_circle(pos, 2.2 * inv + 0.6, Color(1, 1, 1, inv))

	# 5. Smoke cloud — thick dark puffs that drift outward, linger, and grow
	# Smoke uses a longer fade so it persists past the fire
	for i in smoke_count:
		var dir2: Vector2 = _smoke_dirs[i]
		var dist2: float = _smoke_speeds[i] * t
		var pos2: Vector2 = dir2 * dist2
		var size2: float = _smoke_sizes[i] * (0.6 + t * 0.8)
		var smoke_alpha: float = pow(inv, 0.6) * 0.55
		var gray: float = lerp(0.45, 0.20, t) + 0.05 * sin(_smoke_phase[i] + _time * 6.0)
		var sc2 := Color(gray, gray * 0.9, gray * 0.85, smoke_alpha)
		draw_circle(pos2, size2, sc2)

	# 6. Debris chunks — chunky rotating squares with fire-lit color
	for i in debris_count:
		var dir3: Vector2 = _debris_dirs[i]
		var dist3: float = _debris_speeds[i] * ease(t, 0.6)
		var pos3: Vector2 = dir3 * dist3
		var size3: float = _debris_sizes[i] * (1.0 - t * 0.4)
		var rot: float = _debris_rot[i] + _debris_spin[i] * _time
		var dc := Color(lerp(1.0, 0.35, t), lerp(0.8, 0.20, t), lerp(0.3, 0.12, t), inv)
		_draw_rotated_square(pos3, size3, rot, dc)


## Color shift for the fire ball through the explosion's life.
func _fire_color(t: float) -> Color:
	if t < 0.20:
		var k: float = t / 0.20
		return Color(1.0, lerp(1.0, 0.92, k), lerp(0.9, 0.35, k))      # white → yellow
	elif t < 0.55:
		var k2: float = (t - 0.20) / 0.35
		return Color(1.0, lerp(0.92, 0.50, k2), lerp(0.35, 0.12, k2))  # yellow → orange
	else:
		var k3: float = (t - 0.55) / 0.45
		return Color(lerp(1.0, 0.5, k3), lerp(0.5, 0.12, k3), lerp(0.12, 0.05, k3))  # orange → dark red


## Draws a square rotated around its center.
func _draw_rotated_square(center: Vector2, half_size: float, rot: float, color: Color) -> void:
	var c: float = cos(rot)
	var s: float = sin(rot)
	var p: PackedVector2Array = PackedVector2Array([
		center + Vector2( half_size * c - half_size * s,  half_size * s + half_size * c),
		center + Vector2(-half_size * c - half_size * s, -half_size * s + half_size * c),
		center + Vector2(-half_size * c + half_size * s, -half_size * s - half_size * c),
		center + Vector2( half_size * c + half_size * s,  half_size * s - half_size * c),
	])
	draw_colored_polygon(p, color)
