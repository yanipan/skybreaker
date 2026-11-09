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
## Mortar fuse (9/11, ARTILLERY): after `burst_after` seconds the shell
## pops into `burst_count` pellets in a ring and frees itself. 0 = no fuse.
@export var burst_after: float = 0.0
@export var burst_count: int = 0
@export var burst_damage: int = 3
@export var burst_speed: float = 330.0
## _apply_style_defaults() rewrites speed / radius / colour for every style
## except ORB, so a caller that wants its own value must say so here
## (0 / transparent = keep the style default).
@export var speed_override: float = 0.0
@export var radius_override: float = 0.0
@export var color_override: Color = Color(0, 0, 0, 0)
## Homing missile (9/11): steers toward the ship at `homing_turn_rate`
## rad/s for the first `homing_secs`, then flies straight. 0 = dumb shot.
@export var homing_turn_rate: float = 0.0
@export var homing_secs: float = 0.0

## Beam burn: a non-boss bullet must sit in the beam for beam_resist seconds
## before it pops. Rolled per bullet, so some pop on contact and some take a
## couple of beam sweeps. Heavy rounds (shell/acid/plasma) resist longer.
## 6/11: 0.12-0.45 s x1.6 made the beam barely clear shots (angled shots cross
## the burn band in under 0.2 s); then 0.05-0.18 s x1.5. 7/11 playtest: still
## not quite enough, now 0.03-0.12 s x1.4: never on the first frame, but a
## held beam clears a stream in a few frames.
const BEAM_RESIST_MIN: float = 0.03
const BEAM_RESIST_MAX: float = 0.12
const BEAM_HEAVY_MUL: float = 1.4
var beam_resist: float = 0.0
var beam_heat: float = 0.0

static var _shape_cache: Dictionary = {}
const TRAIL_LEN: int = 10
const TRAIL_DT: float = 1.0 / 60.0   ## trail spacing = distance flown in one 60 fps frame
var _frames: int = 0
var _animated: bool = false           ## style whose body pulses / spins (needs periodic redraw)
var _stagger: int = 0                 ## spreads the every-3rd-frame redraws across shots

var _viewport_size: Vector2
var _time: float = 0.0
var _trail: Array = []  ## Recent local-space offsets for the tail


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	add_to_group(&"enemy_bullets")
	_apply_style_defaults()
	if speed_override > 0.0:
		speed = speed_override
	if radius_override > 0.0:
		bullet_radius = radius_override
	if color_override.a > 0.0:
		bullet_color = color_override
	_animated = style == Style.SPARK or style == Style.PLASMA or style == Style.ACID or style == Style.ORB
	_stagger = randi() % 3
	_roll_beam_resist()
	_build_collision()
	queue_redraw()


func _roll_beam_resist() -> void:
	beam_resist = randf_range(BEAM_RESIST_MIN, BEAM_RESIST_MAX)
	if style == Style.SHELL or style == Style.ACID or style == Style.PLASMA:
		beam_resist *= BEAM_HEAVY_MUL


## Called by Beam every frame this bullet sits in the burn band. Returns true
## (and frees the bullet) once enough heat has built up. Heat stays between
## sweeps, so a second pass finishes a bullet the first one softened.
func beam_burn(delta: float) -> bool:
	if from_boss:
		return false
	beam_heat += delta
	modulate = Color(1, 1, 1).lerp(Color(2.2, 2.2, 2.2), clamp(beam_heat / max(beam_resist, 0.001), 0.0, 1.0))
	if beam_heat >= beam_resist:
		queue_free()
		return true
	return false


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
	# Slightly larger hit radius than the visual core so player feedback feels fair
	# (especially for darts/sparks that draw thinner than they hit).
	# One shared CircleShape2D per radius instead of a new resource per shot.
	var radius: float = max(bullet_radius, 6.0)
	var key: int = int(round(radius * 10.0))
	var circle: CircleShape2D = _shape_cache.get(key)
	if circle == null:
		circle = CircleShape2D.new()
		circle.radius = radius
		_shape_cache[key] = circle
	shape.shape = circle
	add_child(shape)


var _stuck: Array = []

func _process(delta: float) -> void:
	_check_player_fallback()
	_process_motion(delta)


## Trail points in local space, oldest first, head (ZERO) last: what the old
## per-frame shifting produced at 60 fps.
func _rebuild_trail() -> void:
	var n: int = mini(_frames, TRAIL_LEN)
	var step: Vector2 = -direction * speed * TRAIL_DT
	_trail.resize(n)
	for i in n:
		_trail[i] = step * float(n - 1 - i)


## Mortar shell pops: a ring of pellets, then the shell is gone.
func _burst() -> void:
	var parent: Node = get_parent()
	for i in burst_count:
		var ang: float = TAU * float(i) / float(burst_count) + 0.3
		var p: EnemyBullet = get_script().new()
		p.position = global_position
		p.direction = Vector2.RIGHT.rotated(ang)
		p.damage = burst_damage
		p.style = Style.PELLET
		p.speed_override = burst_speed
		p.from_boss = from_boss
		if parent != null:
			parent.add_child.call_deferred(p)
	queue_free()


## Physics safety net for hits on the ship (HitCheck.gd).
func _check_player_fallback() -> void:
	var p: Node2D = HitCheck.player(get_tree())
	if p == null or is_queued_for_deletion() or not p.monitoring:
		_stuck.clear()
		return
	var r: float = max(bullet_radius, 6.0)
	if HitCheck.stuck(HitCheck.on_player(global_position, r), _stuck) and p.has_method("_on_area_entered"):
		HitCheck.note_fallback("enemy_bullet")
		p._on_area_entered(self)


func _process_motion(delta: float) -> void:
	_time += delta
	if burst_after > 0.0 and _time >= burst_after and not is_queued_for_deletion():
		_burst()
		return
	if homing_turn_rate > 0.0 and _time < homing_secs:
		var ship: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
		if ship != null:
			var want: float = (ship.global_position - global_position).angle()
			var cur: float = direction.angle()
			direction = Vector2.RIGHT.rotated(rotate_toward(cur, want, homing_turn_rate * delta))
	position += direction * speed * delta

	# Battery pass 9/11. A shot flying straight has a trail that never changes
	# in its own space (evenly spaced points behind the head), so it is built
	# from the frame count instead of being shifted and redrawn every frame.
	# Redraw happens: every frame while the tail is still growing or while a
	# missile is steering, every 3rd frame (staggered) for the styles whose
	# body animates, and never again for the static ones (pellet, dart, shell).
	_frames += 1
	var steering: bool = homing_turn_rate > 0.0 and _time < homing_secs
	if _frames <= TRAIL_LEN or steering:
		_rebuild_trail()
		queue_redraw()
	elif _animated and (_frames + _stagger) % 3 == 0:
		queue_redraw()

	var m: float = 64.0
	if position.y < -m or position.y > _viewport_size.y + m \
			or position.x < -m or position.x > _viewport_size.x + m:
		queue_free()
