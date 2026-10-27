extends Node2D
class_name ParallaxBg
## Multi-depth parallax background — drifts stylised celestial art (planets,
## wreckage, asteroids, nebulae) down the screen at three different depth
## bands so the world feels like the player is moving THROUGH space, not just
## past two huge billboards.
##
## How it works:
##   * Every PNG ships with its background already keyed out to alpha
##     (baked offline by scripts/tools/strip_backgrounds.gd), so _ready just
##     load()s them; Godot's resource cache shares them across instances.
##   * Bodies are spawned across THREE depth bands (FAR / MID / NEAR), each
##     with its own scale range, drift speed, alpha, and target on-screen
##     count. Far bodies are tiny, faded, drifting at 6 px/sec; near bodies
##     are big, bright, and drifting at 28 px/sec.
##   * On every frame any band that's below its target on-screen count gets
##     a fresh body spawned just above the top edge — there's no cooldown,
##     the band keeps itself populated. Off-screen bodies are culled and
##     freed.

const PLANET_TEXTURES: Array = [
	"res://assets/sprites/bg/ringed_gas_giant.png",
	"res://assets/sprites/bg/cracked_red_dwarf.png",
	"res://assets/sprites/bg/ice_moon_aurora.png",
	"res://assets/sprites/bg/shattered_moon.png",
	"res://assets/sprites/bg/derelict_cruiser.png",
	"res://assets/sprites/bg/asteroid_cluster.png",
	"res://assets/sprites/bg/crystalline_shard_cluster.png",
	"res://assets/sprites/bg/bioluminescent_jellyfish.png",
	"res://assets/sprites/bg/warp_gate_ruins.png",
	# Crystalline alien sentinel hovering over a vortex portal — an enigmatic
	# ancient artifact channeling a wormhole, with floating shards drifting
	# around it. Reads as "you flew past something you shouldn't have seen."
	"res://assets/sprites/bg/crystal_sentinel_vortex.png",
]
const NEBULA_TEXTURES: Array = [
	"res://assets/sprites/bg/nebula_cyan_magenta.png",
	"res://assets/sprites/bg/dust_pillars.png",
]

# --- Depth bands. Each band has its own visual + motion tuning so the eye
# reads three distinct distances. Tuned so the cumulative on-screen count
# stays around 6-8 bodies — busy enough to feel populated, sparse enough
# to never crowd combat.
const BAND_FAR: int = 0
const BAND_MID: int = 1
const BAND_NEAR: int = 2

# Per-band: scale_min, scale_max, speed_min, speed_max, alpha, target_count
## Speeds are deliberately BELOW the matching starfield layer (far stars
## scroll at 18, mid at 45, near at 90) — planets and wreckage are massive
## distant objects, so they should drift past slower than the stars around
## them, not race them. Targets are tuned low so the sky never feels cluttered.
## Wide scale + speed ranges per band so two bodies in the same band still
## look distinct. Targets are deliberately tiny (1 per band, 3 total on
## screen) and speeds are fast enough that any single body crosses the
## screen in 15-25 seconds — sparse, transient, never lingering.
const BANDS: Array = [
	{ "scale_min": 0.06, "scale_max": 0.22, "speed_min": 12.0, "speed_max": 22.0, "alpha": 0.55, "target": 1 },  # FAR
	{ "scale_min": 0.18, "scale_max": 0.42, "speed_min": 26.0, "speed_max": 42.0, "alpha": 0.78, "target": 1 },  # MID
	{ "scale_min": 0.40, "scale_max": 0.85, "speed_min": 48.0, "speed_max": 70.0, "alpha": 0.95, "target": 1 },  # NEAR
]

var _viewport_size: Vector2
# Per-body: { sprite, speed, spin, band }
var _bodies: Array = []
# Loaded (pre-stripped) textures.
var _planet_textures: Array = []
var _nebula_textures: Array = []
# Nebula has its own slow cadence — they're huge and atmospheric, not part
# of the depth-band rotation.
var _nebula_cooldown: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	# Missing files get silently skipped so the scene still runs during
	# asset churn.
	for path in PLANET_TEXTURES:
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_planet_textures.append(tex)
	for path in NEBULA_TEXTURES:
		var tex2: Texture2D = load(path) as Texture2D
		if tex2 != null:
			_nebula_textures.append(tex2)
	# Pre-populate every depth band with bodies already spread vertically
	# down the screen so the first frame isn't an empty void.
	if _planet_textures.size() > 0:
		for band in [BAND_FAR, BAND_MID, BAND_NEAR]:
			var target: int = int(BANDS[band]["target"])
			for i in target:
				_spawn_body(band, true)
	_nebula_cooldown = randf_range(8.0, 16.0)


func _process(delta: float) -> void:
	# --- Drift + cull ---
	var still_alive: Array = []
	for b in _bodies:
		var sprite: Sprite2D = b["sprite"]
		if not is_instance_valid(sprite):
			continue
		sprite.position.y += b["speed"] * delta
		sprite.rotation += b["spin"] * delta
		var half_h: float = sprite.texture.get_height() * sprite.scale.y * 0.5
		if sprite.position.y - half_h > _viewport_size.y + 60.0:
			sprite.queue_free()
			continue
		still_alive.append(b)
	_bodies = still_alive

	# --- Refill bands ---
	# Count how many bodies each band currently has and spawn fresh ones to
	# cover any deficit. New bodies enter from just above the top edge.
	if _planet_textures.size() > 0:
		var counts: Array = [0, 0, 0]
		for b in _bodies:
			var bd: int = int(b.get("band", -1))
			if bd >= 0 and bd < counts.size():
				counts[bd] += 1
		for band in [BAND_FAR, BAND_MID, BAND_NEAR]:
			var target: int = int(BANDS[band]["target"])
			if counts[band] < target:
				_spawn_body(band, false)

	# --- Nebula sheets — slow standalone cadence ---
	_nebula_cooldown -= delta
	if _nebula_cooldown <= 0.0 and _nebula_textures.size() > 0:
		_spawn_nebula()
		_nebula_cooldown = randf_range(35.0, 70.0)


# Spawn one planet/wreckage body in the given depth band. If [start_onscreen]
# is true the body is placed at a random Y inside the viewport so the field
# is already populated when the scene starts; otherwise it appears just
# above the top edge and drifts in.
func _spawn_body(band: int, start_onscreen: bool) -> void:
	var cfg: Dictionary = BANDS[band]
	var tex: Texture2D = _planet_textures[randi() % _planet_textures.size()]
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	# Per-band scale, applied as a fraction of "fit texture to viewport width".
	var fit_w: float = _viewport_size.x
	var fit_scale: float = fit_w / max(1.0, float(tex.get_width()))
	var s: float = fit_scale * randf_range(cfg["scale_min"], cfg["scale_max"])
	sprite.scale = Vector2(s, s)
	# Random horizontal — anywhere across the screen with a small overshoot
	# margin so partially off-screen bodies are allowed (looks more natural).
	sprite.position.x = randf_range(-40.0, _viewport_size.x + 40.0)
	# Y start
	var half_h: float = tex.get_height() * s * 0.5
	if start_onscreen:
		sprite.position.y = randf_range(-half_h * 0.5, _viewport_size.y - half_h * 0.5)
	else:
		sprite.position.y = -half_h - 20.0
	sprite.rotation = randf_range(0.0, TAU)
	# Cooler / fainter the further away. Far bodies tint toward indigo and
	# near bodies stay close to neutral so the color shift sells the depth.
	var tint_r: float = lerp(0.55, 0.95, float(band) / 2.0)
	var tint_g: float = lerp(0.62, 1.00, float(band) / 2.0)
	var tint_b: float = lerp(0.85, 1.05, float(band) / 2.0)
	sprite.modulate = Color(tint_r, tint_g, tint_b, cfg["alpha"])
	add_child(sprite)
	# Speed scales with band. Spin is gentle on far bodies, more visible
	# on near bodies (so the foreground reads as actually spinning).
	var speed: float = randf_range(cfg["speed_min"], cfg["speed_max"])
	var spin_max: float = lerp(1.5, 6.0, float(band) / 2.0)
	var spin: float = deg_to_rad(randf_range(-spin_max, spin_max))
	_bodies.append({"sprite": sprite, "speed": speed, "spin": spin, "band": band})


# Giant nebula sheet — overlays the depth field, doesn't participate in the
# band rotation. Drifts much slower than even the FAR band so it reads as
# the deepest possible layer.
func _spawn_nebula() -> void:
	var tex: Texture2D = _nebula_textures[randi() % _nebula_textures.size()]
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	var base_w: float = _viewport_size.x * randf_range(1.10, 1.50)
	var s: float = base_w / max(1.0, float(tex.get_width()))
	sprite.scale = Vector2(s, s)
	sprite.position.x = _viewport_size.x * 0.5 + randf_range(-100.0, 100.0)
	var half_h: float = tex.get_height() * s * 0.5
	sprite.position.y = -half_h - 40.0
	sprite.rotation = randf_range(0.0, TAU)
	var tint: float = randf_range(0.55, 0.75)
	sprite.modulate = Color(tint, tint * 0.98, tint * 1.05, 0.32)
	add_child(sprite)
	# Slower than even the FAR planet band — the deepest layer.
	var speed: float = randf_range(2.0, 5.0)
	var spin: float = deg_to_rad(randf_range(-0.6, 0.6))
	_bodies.append({"sprite": sprite, "speed": speed, "spin": spin, "band": -1})

