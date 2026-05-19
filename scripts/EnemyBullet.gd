extends Area2D
class_name EnemyBullet
## Projectile fired by enemies. Travels in any direction. Damages player on contact.
## Visuals are procedural — pick a `style` to get a distinct shape/size/color
## per enemy type. Each style has its own draw routine so they read at a glance.

## Visual styles. Each enemy type uses a different one for instant readability.
##   ORB        — default round glowing orb (was the only style)
##   PELLET     — small fast yellow tracer (Grunt)
##   DART       — long thin magenta needle (Dodger sniper)
##   SHELL      — chunky red-orange shell with hot core (Tank spread)
##   SPARK      — tiny cyan electric spark with cross-flare (Strafer)
##   PLASMA     — fat slow purple plasma blob with crackle (Bomber fan)
##   ACID       — slow lumpy bioluminescent green acid blob with dripping
##                tendrils (Brooder spit) — biological, ugly, hard to dodge
enum Style { ORB, PELLET, DART, SHELL, SPARK, PLASMA, ACID }

@export var speed: float = 550.0
@export var direction: Vector2 = Vector2.DOWN
@export var damage: int = 1
@export var style: Style = Style.ORB
@export var bullet_radius: float = 7.0
@export var bullet_color: Color = Color(1.0, 0.45, 0.25)
## Marks bullets that come from a boss. The player's beam refuses to vaporize
## boss fire, so the encounter still requires real dodging — set to true in
## Boss._spawn_bullet.
@export var from_boss: bool = false

const TRAIL_LEN: int = 10

var _viewport_size: Vector2
var _time: float = 0.0
var _trail: Array = []  ## Recent local-space offsets for the tail


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	add_to_group(&"enemy_bullets")
	_apply_style_defaults()
	_build_collision()
	queue_redraw()


## Apply per-style defaults. Enemy.gd sets `style` before adding the bullet —
## anything left as the export defaults gets overwritten here so each shot type
## has the correct size/color/speed without callers needing to know the details.
func _apply_style_defaults() -> void:
	match style:
		Style.PELLET:
			bullet_radius = 5.0
			bullet_color = Color(1.0, 0.95, 0.30)   # bright yellow tracer
			speed = 540.0
		Style.DART:
			bullet_radius = 5.0
			bullet_color = Color(1.0, 0.40, 1.0)    # magenta
			speed = 720.0
		Style.SHELL:
			bullet_radius = 11.0
			bullet_color = Color(1.0, 0.35, 0.15)   # heavy red-orange
			speed = 460.0
		Style.SPARK:
			bullet_radius = 6.0
			bullet_color = Color(0.30, 0.95, 1.0)   # electric cyan
			speed = 640.0
		Style.PLASMA:
			bullet_radius = 13.0
			bullet_color = Color(0.65, 0.30, 1.0)   # purple plasma
			speed = 380.0
		Style.ACID:
			bullet_radius = 12.0
			bullet_color = Color(0.55, 1.0, 0.35)   # bioluminescent acid green
			speed = 300.0                            # Slowest projectile in the game
		_:
			pass  # ORB keeps caller-set defaults


func _draw() -> void:
	match style:
		Style.PELLET:
			_draw_pellet()
		Style.DART:
			_draw_dart()
		Style.SHELL:
			_draw_shell()
		Style.SPARK:
			_draw_spark()
		Style.PLASMA:
			_draw_plasma()
		Style.ACID:
			_draw_acid()
		_:
			_draw_orb()


# --- Style draw routines ---

func _draw_pellet() -> void:
	# Small fast tracer with a short bright tail.
	_draw_simple_trail(0.4)
	var rr: float = bullet_radius
	draw_circle(Vector2.ZERO, rr * 1.8, Color(1.0, 0.95, 0.3, 0.30))
	draw_circle(Vector2.ZERO, rr, bullet_color)
	draw_circle(Vector2.ZERO, rr * 0.4, Color(1, 1, 1, 0.95))


func _draw_dart() -> void:
	# Long thin needle along the travel direction. Magenta sniper round.
	# Drawn as a stretched diamond + glow halo.
	var ang: float = direction.angle()
	var fwd := Vector2.RIGHT.rotated(ang) * (bullet_radius * 3.2)
	var side := Vector2.RIGHT.rotated(ang + PI * 0.5) * (bullet_radius * 0.7)
	var pts := PackedVector2Array([fwd, side, -fwd, -side])
	# Outer halo (fatter diamond)
	var halo_fwd := fwd * 1.2
	var halo_side := side * 1.8
	var halo := PackedVector2Array([halo_fwd, halo_side, -halo_fwd, -halo_side])
	draw_colored_polygon(halo, Color(1.0, 0.50, 1.0, 0.30))
	draw_colored_polygon(pts, bullet_color)
	# White-hot core line
	var core_fwd := fwd * 0.85
	var core_side := side * 0.30
	var core := PackedVector2Array([core_fwd, core_side, -core_fwd, -core_side])
	draw_colored_polygon(core, Color(1, 1, 1, 0.95))


func _draw_shell() -> void:
	# Chunky red-orange tank shell. Layered concentric rings + a leading bright cap.
	_draw_simple_trail(0.35)
	var rr: float = bullet_radius * (0.92 + 0.08 * sin(_time * 18.0))
	# Outer halo
	draw_circle(Vector2.ZERO, rr * 2.0, Color(1.0, 0.30, 0.10, 0.30))
	draw_circle(Vector2.ZERO, rr * 1.4, Color(1.0, 0.45, 0.15, 0.55))
	draw_circle(Vector2.ZERO, rr, bullet_color)
	# Hot core offset slightly toward travel direction
	var lead: Vector2 = direction.normalized() * rr * 0.35
	draw_circle(lead, rr * 0.55, Color(1.0, 0.85, 0.55, 0.95))
	draw_circle(lead, rr * 0.25, Color(1, 1, 1, 1))


func _draw_spark() -> void:
	# Small cyan electric spark with a 4-point cross flare.
	var rr: float = bullet_radius * (0.85 + 0.30 * sin(_time * 30.0))
	# Cross flare
	var flare_len: float = rr * 3.2
	var flare_color := Color(0.55, 0.95, 1.0, 0.55)
	draw_line(Vector2(-flare_len, 0), Vector2(flare_len, 0), flare_color, 1.5)
	draw_line(Vector2(0, -flare_len), Vector2(0, flare_len), flare_color, 1.5)
	draw_line(Vector2(-flare_len * 0.7, -flare_len * 0.7), Vector2(flare_len * 0.7, flare_len * 0.7), flare_color, 1.0)
	draw_line(Vector2(-flare_len * 0.7, flare_len * 0.7), Vector2(flare_len * 0.7, -flare_len * 0.7), flare_color, 1.0)
	# Core
	draw_circle(Vector2.ZERO, rr * 1.6, Color(0.40, 0.90, 1.0, 0.45))
	draw_circle(Vector2.ZERO, rr, bullet_color)
	draw_circle(Vector2.ZERO, rr * 0.45, Color(1, 1, 1, 1))


func _draw_plasma() -> void:
	# Fat slow purple plasma blob with crackling outer ring.
	var rr: float = bullet_radius * (0.92 + 0.10 * sin(_time * 14.0))
	# Wide outer halo
	draw_circle(Vector2.ZERO, rr * 2.4, Color(0.55, 0.20, 0.95, 0.22))
	draw_circle(Vector2.ZERO, rr * 1.6, Color(0.65, 0.30, 1.0, 0.45))
	draw_circle(Vector2.ZERO, rr, bullet_color)
	# Crackle: small jittered points around the rim
	for i in 6:
		var ang: float = (TAU / 6.0) * float(i) + _time * 6.0
		var p := Vector2(cos(ang), sin(ang)) * rr * 1.15
		draw_circle(p, rr * 0.18, Color(0.95, 0.75, 1.0, 0.85))
	# Lavender core
	draw_circle(Vector2.ZERO, rr * 0.55, Color(0.95, 0.80, 1.0, 0.95))
	draw_circle(Vector2.ZERO, rr * 0.25, Color(1, 1, 1, 1))


func _draw_acid() -> void:
	# Lumpy bioluminescent acid blob with a glowing core and trailing slime
	# drips. Wobbles asymmetrically so it reads as organic, not mechanical.
	# A short greenish trail behind it sells the "leaking" feel.
	_draw_simple_trail(0.45)
	var rr: float = bullet_radius * (0.92 + 0.10 * sin(_time * 11.0))
	# Outer toxic halo
	draw_circle(Vector2.ZERO, rr * 2.6, Color(0.40, 0.95, 0.30, 0.18))
	draw_circle(Vector2.ZERO, rr * 1.8, Color(0.50, 1.0, 0.35, 0.38))
	# Lumpy main body — six off-center bulges around the core to break the
	# perfect circle and read as organic
	for i in 6:
		var ang: float = (TAU / 6.0) * float(i) + sin(_time * 3.0 + float(i)) * 0.4
		var dist: float = rr * (0.55 + 0.20 * sin(_time * 4.0 + float(i) * 1.7))
		var p := Vector2(cos(ang), sin(ang)) * dist
		draw_circle(p, rr * 0.55, bullet_color)
	# Bright slimy core
	draw_circle(Vector2.ZERO, rr * 0.95, Color(0.75, 1.0, 0.55, 0.95))
	draw_circle(Vector2.ZERO, rr * 0.50, Color(0.95, 1.0, 0.80, 1.0))
	# Two trailing slime drips dangling behind the blob along -direction
	var back: Vector2 = -direction.normalized()
	for i in 2:
		var drip_off: float = float(i + 1) * rr * 0.85
		var drip_pos: Vector2 = back * drip_off + Vector2(sin(_time * 6.0 + float(i) * 2.0) * rr * 0.25, 0)
		var drip_r: float = rr * (0.40 - float(i) * 0.10)
		draw_circle(drip_pos, drip_r, Color(0.55, 1.0, 0.35, 0.75))


func _draw_orb() -> void:
	_draw_simple_trail(0.55)
	var pulse: float = 0.85 + 0.15 * sin(_time * 22.0)
	var rr: float = bullet_radius * pulse
	draw_circle(Vector2.ZERO, rr * 2.2, Color(bullet_color.r, bullet_color.g * 0.4, 0.05, 0.25))
	draw_circle(Vector2.ZERO, rr * 1.5, Color(1.0, 0.55, 0.15, 0.55))
	draw_circle(Vector2.ZERO, rr, bullet_color)
	draw_circle(Vector2.ZERO, rr * 0.45, Color(1.0, 0.95, 0.75, 0.95))
	draw_circle(Vector2(-rr * 0.25, -rr * 0.25), rr * 0.20, Color(1, 1, 1, 0.9))


## Shared trail renderer for orb-style bullets. `peak_alpha` controls how bright
## the head of the trail draws.
func _draw_simple_trail(peak_alpha: float) -> void:
	var n: int = _trail.size()
	for i in n:
		var k: float = float(i) / float(max(1, n - 1))   # 0 = oldest, 1 = newest
		var r: float = bullet_radius * (0.35 + 0.65 * k)
		var a: float = peak_alpha * k
		var p: Vector2 = _trail[i]
		draw_circle(p, r * 1.6, Color(bullet_color.r, bullet_color.g * 0.7, bullet_color.b * 0.7, a * 0.4))
		draw_circle(p, r, Color(bullet_color.r, bullet_color.g, bullet_color.b, a))


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	# Slightly larger hit radius than the visual core so player feedback feels fair
	# (especially for darts/sparks that draw thinner than they hit)
	circle.radius = max(bullet_radius, 6.0)
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	position += direction * speed * delta

	# Trail samples are stored in local space behind the head along -direction.
	var step: Vector2 = -direction * speed * delta
	for i in _trail.size():
		_trail[i] += step
	_trail.append(Vector2.ZERO)
	if _trail.size() > TRAIL_LEN:
		_trail.pop_front()
	queue_redraw()

	var m: float = 64.0
	if position.y < -m or position.y > _viewport_size.y + m \
			or position.x < -m or position.x > _viewport_size.x + m:
		queue_free()
