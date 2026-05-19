extends Node2D
class_name EnemyExplosion
## Procedural enemy death burst.
## Layered particle effect: white flash → color-shifting fire core → expanding
## shockwave ring → sparks with trails → drifting smoke puffs → spinning debris.
## All values scale from `burst_radius`, set by the spawner to match enemy size.

@export var burst_radius: float = 40.0
@export var lifetime: float = 0.7
@export var base_color: Color = Color(1.0, 0.6, 0.2)
@export var spark_count: int = 14
@export var smoke_count: int = 5
@export var debris_count: int = 6

var _time: float = 0.0

# Per-instance randomness — set in _ready so each explosion has its own personality
var _size_jitter: float = 1.0       ## Multiplier on burst_radius (0.85..1.20)
var _life_jitter: float = 1.0       ## Multiplier on lifetime (0.85..1.15)
var _color_shift: float = 0.0       ## Hue offset for the fire core (-0.06..0.06)
var _ring_speed_mul: float = 1.0    ## Shockwave expansion variation
var _rotation_offset: float = 0.0   ## Whole-burst rotation so silhouettes don't repeat
var _asymmetry: Vector2 = Vector2.ZERO  ## Slight directional bias (off-center pop)

# Sparks: bright streaks that fly out fast and fade
var _spark_dirs: Array[Vector2] = []
var _spark_speeds: Array[float] = []

# Smoke puffs: dark circles that drift slowly and linger
var _smoke_dirs: Array[Vector2] = []
var _smoke_speeds: Array[float] = []
var _smoke_sizes: Array[float] = []

# Debris chunks: rotating rectangles with their own velocity
var _debris_dirs: Array[Vector2] = []
var _debris_speeds: Array[float] = []
var _debris_sizes: Array[float] = []
var _debris_rot: Array[float] = []
var _debris_spin: Array[float] = []


func _ready() -> void:
	# Roll personality for this specific burst
	_size_jitter = randf_range(0.85, 1.20)
	_life_jitter = randf_range(0.85, 1.15)
	_color_shift = randf_range(-0.06, 0.06)
	_ring_speed_mul = randf_range(0.85, 1.20)
	_rotation_offset = randf() * TAU
	_asymmetry = Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15)) * burst_radius
	burst_radius *= _size_jitter
	lifetime *= _life_jitter
	# Particle counts also get a small ±25% jitter so density varies
	spark_count = max(4, int(spark_count * randf_range(0.75, 1.25)))
	debris_count = max(2, int(debris_count * randf_range(0.75, 1.25)))
	smoke_count = max(2, int(smoke_count * randf_range(0.75, 1.25)))

	_spark_dirs.resize(spark_count)
	_spark_speeds.resize(spark_count)
	for i in spark_count:
		var a: float = _rotation_offset + randf() * TAU
		_spark_dirs[i] = Vector2(cos(a), sin(a))
		_spark_speeds[i] = randf_range(burst_radius * 2.6, burst_radius * 6.0)

	_smoke_dirs.resize(smoke_count)
	_smoke_speeds.resize(smoke_count)
	_smoke_sizes.resize(smoke_count)
	for i in smoke_count:
		var a2: float = _rotation_offset + randf() * TAU
		_smoke_dirs[i] = Vector2(cos(a2), sin(a2))
		_smoke_speeds[i] = randf_range(burst_radius * 0.3, burst_radius * 1.1)
		_smoke_sizes[i] = randf_range(burst_radius * 0.40, burst_radius * 0.85)

	_debris_dirs.resize(debris_count)
	_debris_speeds.resize(debris_count)
	_debris_sizes.resize(debris_count)
	_debris_rot.resize(debris_count)
	_debris_spin.resize(debris_count)
	for i in debris_count:
		var a3: float = _rotation_offset + randf() * TAU
		_debris_dirs[i] = Vector2(cos(a3), sin(a3))
		_debris_speeds[i] = randf_range(burst_radius * 1.5, burst_radius * 3.8)
		_debris_sizes[i] = randf_range(burst_radius * 0.08, burst_radius * 0.22)
		_debris_rot[i] = randf() * TAU
		_debris_spin[i] = randf_range(-14.0, 14.0)


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

	# 1. Initial white-hot flash — peaks in the first ~10% of life, then dies fast
	var flash_t: float = clamp(_time / (lifetime * 0.12), 0.0, 1.0)
	var flash_alpha: float = (1.0 - flash_t) * 0.95
	if flash_alpha > 0.01:
		var flash_r: float = burst_radius * (0.4 + flash_t * 0.9)
		draw_circle(oc, flash_r * 1.4, Color(1, 1, 1, flash_alpha * 0.35))
		draw_circle(oc, flash_r, Color(1, 1, 1, flash_alpha))

	# 2. Fire core — color-shifts white → yellow → orange → red → dark, shrinking
	var core_r: float = burst_radius * (0.5 + ease(t, 0.4) * 0.9) * (1.0 - t * 0.4)
	var core_color: Color = _fire_color(t)
	# Apply per-instance hue jitter — pushes color slightly redder or yellower
	core_color.r = clamp(core_color.r + _color_shift, 0.0, 1.0)
	core_color.g = clamp(core_color.g - _color_shift * 0.5, 0.0, 1.0)
	draw_circle(oc, core_r * 1.35, Color(core_color.r, core_color.g, core_color.b, inv * 0.35))
	draw_circle(oc, core_r, Color(core_color.r, core_color.g, core_color.b, inv * 0.85))

	# 3. Expanding shockwave ring — thin bright arc that races outward
	var ring_r: float = burst_radius * (0.4 + ease(t, 0.25) * 1.6) * _ring_speed_mul
	var ring_alpha: float = inv * 0.7
	draw_arc(oc, ring_r, 0.0, TAU, 32, Color(1.0, 0.95, 0.7, ring_alpha), 2.5, true)

	# 4. Sparks — bright streaks with trails. Drawn as a line from past pos to current pos.
	for i in spark_count:
		var dir: Vector2 = _spark_dirs[i]
		var dist: float = _spark_speeds[i] * ease(t, 0.5)
		var pos: Vector2 = dir * dist
		var trail_len: float = burst_radius * 0.35 * (1.0 - t)
		var tail: Vector2 = pos - dir * trail_len
		var spark_color := Color(1.0, lerp(0.95, 0.5, t), lerp(0.6, 0.1, t), inv)
		draw_line(tail, pos, spark_color, 2.0)
		draw_circle(pos, 1.6 * inv + 0.4, Color(1, 1, 1, inv))

	# 5. Smoke puffs — dark drifting circles that linger and grow slightly
	for i in smoke_count:
		var dir2: Vector2 = _smoke_dirs[i]
		var dist2: float = _smoke_speeds[i] * t
		var pos2: Vector2 = dir2 * dist2
		var size2: float = _smoke_sizes[i] * (0.5 + t * 0.7)
		var smoke_alpha: float = inv * 0.45
		# Smoke fades from warm dark gray toward cold dark
		var sc := Color(lerp(0.35, 0.18, t), lerp(0.25, 0.18, t), lerp(0.18, 0.18, t), smoke_alpha)
		draw_circle(pos2, size2, sc)

	# 6. Debris chunks — small rectangles that fly out and spin, lit by remaining fire
	for i in debris_count:
		var dir3: Vector2 = _debris_dirs[i]
		var dist3: float = _debris_speeds[i] * ease(t, 0.6)
		var pos3: Vector2 = dir3 * dist3
		var size3: float = _debris_sizes[i] * (1.0 - t * 0.5)
		var rot: float = _debris_rot[i] + _debris_spin[i] * _time
		var dc := Color(lerp(1.0, 0.4, t), lerp(0.7, 0.25, t), lerp(0.3, 0.15, t), inv)
		_draw_rotated_square(pos3, size3, rot, dc)


## Color shift for the fire core through the explosion's life.
func _fire_color(t: float) -> Color:
	if t < 0.25:
		var k: float = t / 0.25
		return Color(1.0, lerp(1.0, 0.95, k), lerp(0.85, 0.4, k))     # white → yellow
	elif t < 0.55:
		var k2: float = (t - 0.25) / 0.30
		return Color(1.0, lerp(0.95, 0.55, k2), lerp(0.4, 0.15, k2))  # yellow → orange
	else:
		var k3: float = (t - 0.55) / 0.45
		return Color(lerp(1.0, 0.55, k3), lerp(0.55, 0.15, k3), lerp(0.15, 0.05, k3))  # orange → dark red


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
