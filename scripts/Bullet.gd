extends Area2D
class_name Bullet
## Player projectile. Moves in a straight line and despawns off-screen.
## Drawn as a layered energy beam: outer glow → mid glow → bright core → front spark.
## Color is set by the player based on weapon tier; brighter/exotic colors mean more damage.

@export var speed: float = 1200.0           ## Pixels per second
@export var direction: Vector2 = Vector2.UP ## Travel direction (normalized)
@export var damage: int = 1   ## Per-hit damage. Set by Player from the current weapon tier.
@export var bullet_size: Vector2 = Vector2(9, 24)
@export var bullet_color: Color = Color(0.55, 0.95, 1.0)  ## Default cyan; Player overrides per tier

var _viewport_size: Vector2
var _time: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_build_collision()
	add_to_group(&"player_bullets")
	area_entered.connect(_on_area_entered)
	# Rotate the whole node so visuals (and collision) align with travel direction.
	rotation = direction.angle() + PI * 0.5
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group(&"enemies"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()


func _draw() -> void:
	var w: float = bullet_size.x
	var h: float = bullet_size.y
	# Subtle high-frequency pulse so the beam feels alive
	var pulse: float = 0.85 + 0.15 * sin(_time * 25.0)
	var c := bullet_color
	# Tinted glow layers (use the bullet color, modulated alpha)
	var glow_outer := Color(c.r, c.g, c.b, 0.18 * pulse)
	var glow_mid := Color(c.r, c.g, c.b, 0.40 * pulse)
	# White-hot core, pulled toward 1,1,1 from the base color
	var core := Color(
		clamp(c.r + 0.4, 0.0, 1.0),
		clamp(c.g + 0.4, 0.0, 1.0),
		clamp(c.b + 0.4, 0.0, 1.0),
		1.0
	)
	# Layered capsules → beam silhouette with soft halo
	_draw_capsule(Vector2.ZERO, w * 1.9, h * 1.25, glow_outer)
	_draw_capsule(Vector2.ZERO, w * 1.2, h * 1.10, glow_mid)
	_draw_capsule(Vector2.ZERO, w * 0.7,  h * 0.95, c)
	_draw_capsule(Vector2.ZERO, w * 0.3,  h * 0.85, core)
	# Bright front sparkle at the leading edge
	draw_circle(Vector2(0, -h * 0.5), w * 0.65, Color(1, 1, 1, 0.75 * pulse))


## Draws a vertical capsule (rounded rect) centered on `center`.
func _draw_capsule(center: Vector2, width: float, height: float, color: Color) -> void:
	var radius: float = width * 0.5
	var rect_h: float = max(0.0, height - width)
	if rect_h > 0.0:
		draw_rect(Rect2(center - Vector2(radius, rect_h * 0.5), Vector2(width, rect_h)), color, true)
	draw_circle(center + Vector2(0, -rect_h * 0.5), radius, color)
	draw_circle(center + Vector2(0,  rect_h * 0.5), radius, color)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = bullet_size
	shape.shape = rect
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	position += direction * speed * delta
	queue_redraw()
	# Despawn when fully off any edge (with a small margin)
	var m: float = 64.0
	if position.y < -m or position.y > _viewport_size.y + m \
			or position.x < -m or position.x > _viewport_size.x + m:
		queue_free()
