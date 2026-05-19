extends Area2D
class_name Missile
## Player missile. On launch it locks onto the nearest enemy in front of the
## player and bends toward THAT target. If the original target dies, the
## missile re-scans for a NEW target within `reacquire_radius` of itself —
## anything farther away is ignored, so the missile commits to the area it
## was launched at instead of chasing across the whole screen. Slower fire
## rate than the phaser, harder per-hit damage.
##
## Visuals are fully procedural: chrome body with rivet, animated flame plume,
## smoke trail puffs that detach behind the missile.

@export var speed: float = 520.0
@export var max_speed: float = 760.0
@export var turn_rate: float = 6.0       ## Radians/sec the missile can rotate toward its initial target
## When the locked target dies, the missile will scan for a NEW target this
## close to itself. Anything farther is ignored — keeps the missile committed
## to roughly the area it was launched at instead of zig-zagging across the
## whole screen forever.
@export var reacquire_radius: float = 260.0
@export var damage: int = 6
@export var direction: Vector2 = Vector2.UP
@export var bullet_color: Color = Color(1.0, 0.85, 0.55)  ## Drives flame tint

const TRAIL_PUFF_INTERVAL: float = 0.04
const MAX_TRAIL_PUFFS: int = 16

var _viewport_size: Vector2
var _time: float = 0.0
var _puff_timer: float = 0.0
# Smoke trail puffs left behind in WORLD space (so they don't drag with the missile)
var _trail: Array = []  ## Each puff: { pos, age, life, radius }
# Currently-tracked target. Set on _ready (initial lock) and re-acquired
# whenever it dies, but only to enemies within `reacquire_radius`.
var _target: Node2D = null
var _target_acquired: bool = false
const REACQUIRE_INTERVAL: float = 0.12   ## Throttle scans so we're not iterating every frame
var _reacquire_cooldown: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	add_to_group(&"player_bullets")
	_build_collision()
	area_entered.connect(_on_area_entered)
	# One-shot target lock — picked once, never updated.
	_target = _find_target()
	_target_acquired = true
	queue_redraw()


## Pick the closest enemy in our forward hemisphere at launch time.
func _find_target() -> Node2D:
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	var best: Node2D = null
	var best_score: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var to_e: Vector2 = e.global_position - global_position
		var dot: float = to_e.normalized().dot(direction)
		if dot < -0.10:
			continue
		var dist: float = to_e.length()
		var score: float = dist + (1.0 - dot) * 240.0
		if score < best_score:
			best_score = score
			best = e
	return best


## Re-acquire after the original target dies — only enemies within
## `reacquire_radius` are eligible. Picks the closest one. Returns null if
## nothing nearby qualifies, in which case the missile flies straight.
func _find_nearby_target() -> Node2D:
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	var best: Node2D = null
	var best_dist: float = reacquire_radius
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = (e.global_position - global_position).length()
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	# --- Steer toward the current target while it's alive. If it dies, scan
	# for a NEW target within reacquire_radius (throttled). If nothing nearby
	# qualifies, the missile keeps its current heading and flies straight. ---
	if _target == null or not is_instance_valid(_target):
		_target = null
		_reacquire_cooldown -= delta
		if _reacquire_cooldown <= 0.0:
			_reacquire_cooldown = REACQUIRE_INTERVAL
			_target = _find_nearby_target()
	if _target != null:
		var desired: Vector2 = (_target.global_position - global_position).normalized()
		var current_ang: float = direction.angle()
		var desired_ang: float = desired.angle()
		var diff: float = wrapf(desired_ang - current_ang, -PI, PI)
		var max_step: float = turn_rate * delta
		var step: float = clamp(diff, -max_step, max_step)
		direction = Vector2.RIGHT.rotated(current_ang + step)
	speed = min(max_speed, speed + 280.0 * delta)
	position += direction * speed * delta
	rotation = direction.angle() + PI * 0.5  # sprite/draw points "up"

	# --- Emit smoke trail puffs in world space at a fixed interval ---
	_puff_timer -= delta
	if _puff_timer <= 0.0:
		_puff_timer = TRAIL_PUFF_INTERVAL
		_trail.append({
			"pos": global_position - direction * 14.0,
			"age": 0.0,
			"life": randf_range(0.45, 0.70),
			"radius": randf_range(4.0, 6.5),
		})
		if _trail.size() > MAX_TRAIL_PUFFS:
			_trail.pop_front()
	# Tick existing puffs
	var alive: Array = []
	for puff in _trail:
		puff.age += delta
		if puff.age < puff.life:
			alive.append(puff)
	_trail = alive
	queue_redraw()

	# Despawn if it leaves the playfield
	var m: float = 100.0
	if position.y < -m or position.y > _viewport_size.y + m \
			or position.x < -m or position.x > _viewport_size.x + m:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group(&"enemies"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		# Bigger pop than a bullet, smaller than a torpedo
		EventBus.screen_shake_requested.emit(4.0, 0.10)
		queue_free()


# --- Drawing — local space, missile points "up" (angle handled by rotation) ---

func _draw() -> void:
	# Trail is in WORLD space — convert each puff to local for draw
	for puff in _trail:
		var k: float = 1.0 - (puff.age / puff.life)
		var local: Vector2 = to_local(puff.pos)
		var r: float = puff.radius * (0.7 + (1.0 - k) * 1.4)
		var a: float = clamp(k, 0.0, 1.0)
		draw_circle(local, r * 1.6, Color(0.85, 0.85, 0.90, a * 0.40))
		draw_circle(local, r, Color(0.95, 0.92, 0.92, a * 0.75))
		# Hot ember while fresh
		var ember: float = clamp(k * 1.4 - 0.2, 0.0, 1.0)
		if ember > 0.0:
			draw_circle(local, r * 0.45, Color(1.0, 0.55, 0.20, ember * 0.85))

	# --- Body: chrome capsule with rivet ---
	var body_w: float = 7.0
	var body_h: float = 18.0
	# Outer shadow
	draw_rect(Rect2(-body_w * 0.5 + 1, -body_h * 0.5 + 1, body_w, body_h), Color(0, 0, 0, 0.4), true)
	# Body
	draw_rect(Rect2(-body_w * 0.5, -body_h * 0.5, body_w, body_h), Color(0.78, 0.80, 0.85), true)
	# Highlight stripe (left side)
	draw_rect(Rect2(-body_w * 0.5, -body_h * 0.5, body_w * 0.35, body_h), Color(0.95, 0.97, 1.0, 0.65), true)
	# Nose cone
	var nose := PackedVector2Array([
		Vector2(-body_w * 0.5, -body_h * 0.5),
		Vector2(body_w * 0.5, -body_h * 0.5),
		Vector2(0, -body_h * 0.5 - 8),
	])
	draw_colored_polygon(nose, Color(1.0, 0.50, 0.20))
	# Nose tip highlight
	draw_circle(Vector2(0, -body_h * 0.5 - 5), 1.2, Color(1, 1, 1, 0.95))
	# Fins (back)
	var fin_y: float = body_h * 0.35
	var fin1 := PackedVector2Array([
		Vector2(-body_w * 0.5, fin_y),
		Vector2(-body_w * 0.5 - 4, body_h * 0.5 + 2),
		Vector2(-body_w * 0.5, body_h * 0.5),
	])
	var fin2 := PackedVector2Array([
		Vector2(body_w * 0.5, fin_y),
		Vector2(body_w * 0.5 + 4, body_h * 0.5 + 2),
		Vector2(body_w * 0.5, body_h * 0.5),
	])
	draw_colored_polygon(fin1, Color(0.55, 0.55, 0.62))
	draw_colored_polygon(fin2, Color(0.55, 0.55, 0.62))
	# Rivet detail
	draw_circle(Vector2(0, -body_h * 0.15), 1.4, Color(0.40, 0.40, 0.45))

	# --- Animated exhaust flame at the tail ---
	var flicker: float = 0.85 + 0.15 * sin(_time * 50.0)
	var flame_len: float = 12.0 * flicker
	var flame_w: float = body_w * 1.3
	# Outer orange flame
	var flame_outer := PackedVector2Array([
		Vector2(-flame_w * 0.5, body_h * 0.5),
		Vector2(flame_w * 0.5, body_h * 0.5),
		Vector2(flame_w * 0.25, body_h * 0.5 + flame_len),
		Vector2(0, body_h * 0.5 + flame_len * 1.2),
		Vector2(-flame_w * 0.25, body_h * 0.5 + flame_len),
	])
	draw_colored_polygon(flame_outer, Color(1.0, 0.45, 0.10, 0.85))
	# Inner yellow flame
	var inner_w: float = flame_w * 0.55
	var inner_len: float = flame_len * 0.7
	var flame_inner := PackedVector2Array([
		Vector2(-inner_w * 0.5, body_h * 0.5),
		Vector2(inner_w * 0.5, body_h * 0.5),
		Vector2(0, body_h * 0.5 + inner_len),
	])
	draw_colored_polygon(flame_inner, Color(1.0, 0.95, 0.45, 0.95))
	# White-hot core dot
	draw_circle(Vector2(0, body_h * 0.5 + 1.5), 1.5, Color(1, 1, 1, 1))
