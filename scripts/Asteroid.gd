extends Area2D
class_name Asteroid
## Drifting space rock — environmental hazard. Damages the player on contact,
## takes hits from bullets/beams/missiles, and on destruction has a chance to
## spit out coins, health, or even a power-up. Adds passive variety to the
## starfield without leaning on the wave spawner.
##
## Joins the &"enemies" group so existing collision/damage code (Player, Bullet,
## Beam, Missile) treats it as a hostile target with zero plumbing.
##
## Three sizes (SMALL, MEDIUM, LARGE) drive HP, contact damage, drop chance,
## visual radius, and the post-destruction debris burst. Procedurally drawn as
## a rocky polygon with darker pits so each asteroid looks unique.

const PickupScript := preload("res://scripts/Pickup.gd")
const EnemyExplosionScript := preload("res://scripts/EnemyExplosion.gd")
const ScorePopupScript := preload("res://scripts/ScorePopup.gd")

enum Size { SMALL, MEDIUM, LARGE }

@export var size: Size = Size.MEDIUM
## Optional override; otherwise spin is randomized in _ready.
@export var spin_speed: float = 0.0
## Drift vector — set by spawner so we can have angled crossings, not just downward.
@export var drift: Vector2 = Vector2(0, 140)

var max_hp: int
var hp: int
var radius: float
var contact_damage: int
var reward: int
var money_value: int
var money_drop_chance: float
var power_drop_chance: float
var health_drop_chance: float

var _viewport_size: Vector2
var _time: float = 0.0
var _hit_flash: float = 0.0
var _shape_pts: PackedVector2Array        ## Cached jagged outline (local space)
var _crater_pts: Array = []               ## Each: {pos, r}
var _rock_color: Color = Color(0.55, 0.50, 0.45)
var _rock_dark: Color = Color(0.30, 0.27, 0.24)


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	_configure()
	_build_collision()
	_generate_shape()
	add_to_group(&"enemies")     # Reuses bullet/beam/contact pipelines
	add_to_group(&"asteroids")   # So future logic can find rocks specifically
	if spin_speed == 0.0:
		spin_speed = randf_range(-1.6, 1.6)
	queue_redraw()


func _configure() -> void:
	# Late-game asteroids hit harder and survive longer, mirroring Enemy scaling.
	var lvl: int = clamp(GameState.current_level, 1, GameState.MAX_LEVEL)
	var t: float = float(lvl - 1) / float(GameState.MAX_LEVEL - 1)
	var hp_mul: float = lerp(0.85, 1.80, t)
	match size:
		Size.SMALL:
			max_hp = max(2, int(round(4 * hp_mul)))
			radius = 22.0
			contact_damage = 6
			reward = 15
			money_value = 5
			money_drop_chance = 0.45
			power_drop_chance = 0.046   ## +15% — three weapon slots to feed
			health_drop_chance = 0.013  ## Halved — health was too common
		Size.MEDIUM:
			max_hp = max(5, int(round(10 * hp_mul)))
			radius = 38.0
			contact_damage = 12
			reward = 35
			money_value = 15
			money_drop_chance = 0.65
			power_drop_chance = 0.115   ## +15% — three weapon slots to feed
			health_drop_chance = 0.027  ## Halved
		Size.LARGE:
			max_hp = max(10, int(round(22 * hp_mul)))
			radius = 60.0
			contact_damage = 22
			reward = 80
			money_value = 35
			money_drop_chance = 0.90
			power_drop_chance = 0.23    ## +15% — three weapon slots to feed
			health_drop_chance = 0.045  ## Halved
	hp = max_hp


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius * 0.85
	shape.shape = circle
	add_child(shape)


## Build a jagged 14-vertex outline plus a few darker craters. Cached at spawn
## time so _draw stays cheap and the shape stays consistent across frames.
func _generate_shape() -> void:
	_shape_pts = PackedVector2Array()
	var verts: int = 14
	for i in verts:
		var ang: float = TAU * float(i) / float(verts)
		var jitter: float = randf_range(0.78, 1.12)
		_shape_pts.append(Vector2(cos(ang), sin(ang)) * radius * jitter)
	# Craters: 2-4 darker pits scattered across the face
	var n: int = randi_range(2, 4)
	for i in n:
		var p := Vector2(randf_range(-0.55, 0.55), randf_range(-0.55, 0.55)) * radius
		var cr: float = randf_range(radius * 0.10, radius * 0.22)
		_crater_pts.append({"pos": p, "r": cr})
	# Slight grey tint variation per rock
	var k: float = randf_range(0.85, 1.10)
	_rock_color = Color(0.55 * k, 0.50 * k, 0.45 * k)
	_rock_dark = Color(0.30 * k, 0.27 * k, 0.24 * k)


func _process(delta: float) -> void:
	_time += delta
	position += drift * delta
	rotation += spin_speed * delta
	if _hit_flash > 0.0:
		_hit_flash = max(0.0, _hit_flash - delta * 8.0)
		queue_redraw()
	# Despawn well off-screen on any side
	if position.y > _viewport_size.y + 200.0 \
			or position.y < -300.0 \
			or position.x < -300.0 \
			or position.x > _viewport_size.x + 300.0:
		queue_free()


func _draw() -> void:
	# Subtle outer glow so the rock reads against the busy starfield
	draw_circle(Vector2.ZERO, radius * 1.15, Color(0.20, 0.18, 0.15, 0.25))
	# Body — flash white briefly when hit
	var body: Color = _rock_color.lerp(Color(1, 1, 1), _hit_flash)
	draw_colored_polygon(_shape_pts, body)
	# Outline
	var outline := PackedVector2Array(_shape_pts)
	outline.append(_shape_pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.6), 2.0, true)
	# Craters
	for c in _crater_pts:
		draw_circle(c.pos, c.r, _rock_dark)
		draw_circle(c.pos + Vector2(-c.r * 0.25, -c.r * 0.25), c.r * 0.55, _rock_color * 0.8)


func take_damage(amount: int) -> void:
	hp -= amount
	_hit_flash = 1.0
	queue_redraw()
	if hp <= 0:
		GameState.add_score(reward)
		_spawn_burst()
		_maybe_drop_pickup()
		var shake: float = clamp(radius / 12.0, 2.0, 7.0)
		EventBus.screen_shake_requested.emit(shake, 0.18)
		queue_free()


func _spawn_burst() -> void:
	var burst: EnemyExplosion = EnemyExplosionScript.new()
	burst.position = global_position
	burst.burst_radius = radius * 0.95
	burst.spark_count = 12 + int(radius / 4.0)
	burst.debris_count = 8 + int(radius / 8.0)
	burst.smoke_count = 6 + int(radius / 10.0)
	burst.base_color = _rock_color
	get_parent().add_child(burst)
	# Score popup
	var popup: ScorePopup = ScorePopupScript.new()
	popup.amount = reward
	popup.position = global_position + Vector2(0, -radius * 0.4)
	get_parent().add_child(popup)


## Roll for drops independently — coins are common, power/health rare. Larger
## asteroids are juicier so the player has a real reason to focus them down.
func _maybe_drop_pickup() -> void:
	if randf() < money_drop_chance:
		_drop(Pickup.Type.MONEY, money_value)
	var roll: float = randf()
	if roll < power_drop_chance:
		# Randomized weapon-specific power — same equal-weight roll as enemies
		var v: int = randi() % 3
		var pwr: int = Pickup.Type.POWER_PHASER
		if v == 1:
			pwr = Pickup.Type.POWER_BEAM
		elif v == 2:
			pwr = Pickup.Type.POWER_MISSILE
		_drop(pwr, 0)
	elif roll < power_drop_chance + health_drop_chance:
		_drop(Pickup.Type.HEALTH_SMALL, 0)


func _drop(t: int, mv: int) -> void:
	var pickup: Pickup = PickupScript.new()
	pickup.type = t
	if mv > 0:
		pickup.money_value = mv
	pickup.position = global_position + Vector2(randf_range(-10, 10), 0)
	get_parent().add_child(pickup)
