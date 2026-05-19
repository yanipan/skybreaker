extends Node2D
class_name Starfield
## Procedural multi-layer parallax starfield. No assets required.
## Three layers of stars scroll downward at different speeds for depth.
## Far layer = many tiny dim stars (slow). Near layer = fewer big bright stars (fast).
## Wraps vertically so it's seamless and infinite.
##
## Each level picks a distinct palette + nebula colors so the sky visibly
## changes between sectors. Star positions are seeded by the level number
## so the same level always looks the same, but different levels differ.

@export var far_count: int = 120
@export var mid_count: int = 60
@export var near_count: int = 25

@export var far_speed: float = 18.0
@export var mid_speed: float = 45.0
@export var near_speed: float = 90.0

## Set by Main before adding to the tree. 1..20.
@export var level: int = 1

# Each star: x, y, size, brightness, twinkle_phase
var _far: Array = []
var _mid: Array = []
var _near: Array = []

# Per-level visual parameters, baked once in _ready
var _backdrop_color: Color = Color(0.03, 0.03, 0.08)
var _nebula_top: Color = Color(0.25, 0.10, 0.40, 0.025)
var _nebula_bottom: Color = Color(0.10, 0.05, 0.20, 0.015)
var _nebula_y_offset: float = 0.55
var _star_tint: Color = Color(1, 1, 1)

var _viewport_size: Vector2
var _time: float = 0.0

## Warp transition state. 0 = normal scroll, 1 = full warp (stars become long
## downward streaks and the layers race past). Driven from Main.gd between
## stages so the level handoff feels like a hyperjump rather than a snap.
var warp_factor: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_pick_palette_for_level()
	# Seed RNG with the level number so stars are consistent within a level
	# but each level is visibly different.
	seed(level * 9173 + 31)
	# Vary star density a touch per level so the sky's "thickness" changes
	var density_jitter: float = 0.85 + (float(level % 5)) * 0.075
	_seed_layer(_far, int(far_count * density_jitter), 0.6, 1.4, 0.25, 0.55)
	_seed_layer(_mid, int(mid_count * density_jitter), 1.0, 2.0, 0.45, 0.8)
	_seed_layer(_near, int(near_count * density_jitter), 1.6, 3.2, 0.7, 1.0)
	# Restore default randomness for the rest of the game
	randomize()
	queue_redraw()


## Hand-picked palette per act, with a per-level shift so neighbors differ.
## Acts mirror Levels.gd: 1-5 Earth, 6-10 Outer Colonies, 11-15 Insectoid,
## 16-19 Crystal, 20 Skybreaker.
func _pick_palette_for_level() -> void:
	var lvl: int = clamp(level, 1, 20)
	var act_palettes := [
		# Act 1: cool blue Earth defense
		{
			"backdrop": Color(0.03, 0.04, 0.10),
			"nebula_top": Color(0.20, 0.40, 0.85, 0.04),
			"nebula_bot": Color(0.10, 0.20, 0.55, 0.025),
			"star": Color(0.90, 0.95, 1.0),
		},
		# Act 2: rust/amber outer colonies
		{
			"backdrop": Color(0.08, 0.04, 0.04),
			"nebula_top": Color(0.85, 0.40, 0.20, 0.045),
			"nebula_bot": Color(0.55, 0.15, 0.08, 0.025),
			"star": Color(1.0, 0.92, 0.80),
		},
		# Act 3: bio green insectoid swarm
		{
			"backdrop": Color(0.03, 0.07, 0.04),
			"nebula_top": Color(0.30, 0.85, 0.40, 0.045),
			"nebula_bot": Color(0.10, 0.45, 0.15, 0.025),
			"star": Color(0.85, 1.0, 0.85),
		},
		# Act 4: violet crystal dominion
		{
			"backdrop": Color(0.05, 0.03, 0.10),
			"nebula_top": Color(0.65, 0.30, 1.0, 0.045),
			"nebula_bot": Color(0.30, 0.10, 0.55, 0.025),
			"star": Color(0.95, 0.85, 1.0),
		},
		# Act 5: blood-red final
		{
			"backdrop": Color(0.10, 0.02, 0.03),
			"nebula_top": Color(1.0, 0.20, 0.15, 0.06),
			"nebula_bot": Color(0.55, 0.05, 0.08, 0.035),
			"star": Color(1.0, 0.85, 0.80),
		},
	]
	var act: int
	if lvl <= 5:
		act = 0
	elif lvl <= 10:
		act = 1
	elif lvl <= 15:
		act = 2
	elif lvl <= 19:
		act = 3
	else:
		act = 4
	var p: Dictionary = act_palettes[act]
	_backdrop_color = p["backdrop"]
	_nebula_top = p["nebula_top"]
	_nebula_bottom = p["nebula_bot"]
	_star_tint = p["star"]
	# Within an act, shift the nebula band's vertical position so neighbors look different
	_nebula_y_offset = 0.40 + 0.10 * float(lvl % 5)


func _seed_layer(arr: Array, count: int, min_size: float, max_size: float, min_bright: float, max_bright: float) -> void:
	arr.clear()
	for i in count:
		arr.append({
			"x": randf() * _viewport_size.x,
			"y": randf() * _viewport_size.y,
			"size": randf_range(min_size, max_size),
			"bright": randf_range(min_bright, max_bright),
			"phase": randf() * TAU,
		})


func _process(delta: float) -> void:
	_time += delta
	# Warp ramps the per-layer scroll speed up dramatically. Near layer races
	# the most so the parallax depth-cue stays correct.
	var warp_mul: float = 1.0 + warp_factor * 22.0
	_advance_layer(_far, far_speed * warp_mul * delta)
	_advance_layer(_mid, mid_speed * warp_mul * delta)
	_advance_layer(_near, near_speed * warp_mul * delta)
	queue_redraw()


func _advance_layer(arr: Array, dy: float) -> void:
	for s in arr:
		s["y"] += dy
		if s["y"] > _viewport_size.y:
			s["y"] -= _viewport_size.y
			s["x"] = randf() * _viewport_size.x


func _draw() -> void:
	# Backdrop — deep space gradient feel via the per-level base color
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), _backdrop_color, true)
	# Per-level nebula bands. Top band uses the top color, lower bands fade to bottom.
	for i in 8:
		var k: float = float(i) / 7.0
		var y: float = _viewport_size.y * (_nebula_y_offset + k * 0.08)
		var h: float = _viewport_size.y * 0.09
		var c: Color = _nebula_top.lerp(_nebula_bottom, k)
		# Fade alpha along the band so it doesn't read as hard rectangles
		c.a *= (1.0 - k * 0.6)
		draw_rect(Rect2(0.0, y, _viewport_size.x, h), c, true)

	_draw_layer(_far, _star_tint.lerp(Color(0.75, 0.80, 1.0), 0.35))
	_draw_layer(_mid, _star_tint.lerp(Color(0.85, 0.90, 1.0), 0.20))
	_draw_layer(_near, _star_tint)


func _draw_layer(arr: Array, tint: Color) -> void:
	# When warping, draw each star as a downward streak whose length scales with
	# the layer's scroll speed * warp_factor — produces the classic hyperspace
	# look without needing extra particles.
	var streaking: bool = warp_factor > 0.02
	for s in arr:
		var twinkle: float = 0.85 + 0.15 * sin(_time * 3.0 + s["phase"])
		var alpha: float = s["bright"] * twinkle
		var c := Color(tint.r, tint.g, tint.b, alpha)
		var pos := Vector2(s["x"], s["y"])
		if streaking:
			# Streak length depends on size (proxy for layer depth) and warp factor.
			# Bigger/closer stars get the longest streaks, sells the parallax.
			var streak_len: float = s["size"] * 8.0 * warp_factor + 18.0 * warp_factor
			var width: float = max(1.0, s["size"] * 0.9)
			draw_line(pos, pos + Vector2(0, streak_len), c, width)
			# Hot leading head — bright cap on the streak's bottom end
			draw_circle(pos + Vector2(0, streak_len), s["size"] * (0.6 + 0.6 * warp_factor), Color(1, 1, 1, alpha))
		else:
			draw_circle(pos, s["size"], c)
			if s["size"] > 2.0:
				var glow := Color(tint.r, tint.g, tint.b, alpha * 0.35)
				var r: float = s["size"] * 2.2
				draw_line(pos + Vector2(-r, 0), pos + Vector2(r, 0), glow, 1.0)
				draw_line(pos + Vector2(0, -r), pos + Vector2(0, r), glow, 1.0)
