extends Area2D
class_name Torpedo
## Heavy projectile fired by the player. Slower than bullets, bigger hitbox.
## Detonates on enemy contact (or off-screen edge), dealing splash damage in a radius.

const ExplosionScript := preload("res://scripts/Explosion.gd")

@export var speed: float = 520.0
@export var direction: Vector2 = Vector2.UP
@export var torpedo_size: Vector2 = Vector2(28, 48)
@export var torpedo_color: Color = Color(1.0, 0.85, 0.2)
@export var splash_radius: float = 360.0
@export var splash_damage: int = 24
## Warhead upgrade from the starbase shop (0 = stock, 3 = max). Set by
## Player before the torpedo enters the tree; _ready scales the body, the
## blast radius and the damage from the tables below.
@export var tier: int = 0
const TIER_MAX: int = 3
const TIER_RADIUS_MUL: Array = [1.0, 1.2, 1.4, 1.65]
const TIER_DAMAGE: Array = [24, 34, 46, 60]
const TIER_BODY_MUL: Array = [1.0, 1.2, 1.4, 1.65]
## Aura colour drawn around the orb, hotter per tier.
const TIER_AURA: Array = [Color(1.0, 0.6, 0.15), Color(1.0, 0.45, 0.25), Color(1.0, 0.45, 0.95), Color(0.55, 0.9, 1.0)]

var _viewport_size: Vector2
var _time: float = 0.0
var _detonated: bool = false  ## Guards against multiple area_entered detonations in one step


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	tier = clampi(tier, 0, TIER_MAX)
	splash_radius *= float(TIER_RADIUS_MUL[tier])
	splash_damage = int(TIER_DAMAGE[tier])
	torpedo_size *= float(TIER_BODY_MUL[tier])
	add_to_group(&"player_bullets")
	add_to_group(&"player_torpedoes")  ## So Player can find an in-flight torpedo to manually detonate
	_build_collision()
	area_entered.connect(_on_area_entered)
	queue_redraw()


## Public — called by Player on a second torpedo input while one is in the air.
func detonate_now() -> void:
	_detonate()


func _draw() -> void:
	# Photon-torpedo style: glowing red-orange orb with a long fading tail trail.
	# Orb travels at the front (top in local space), tail streams behind.
	var pulse: float = 0.85 + 0.15 * sin(_time * 18.0)
	var orb_r: float = torpedo_size.x * 0.55 * pulse
	var orb_pos := Vector2(0.0, -torpedo_size.y * 0.35)

	# --- Tail trail: a series of fading circles streaming behind the orb ---
	# Each segment is dimmer and slightly smaller than the previous.
	var tail_segments: int = 10
	var tail_length: float = torpedo_size.y * 1.4
	for i in tail_segments:
		var k: float = float(i) / float(tail_segments - 1)   # 0 at orb, 1 at tail end
		var seg_pos := orb_pos + Vector2(0.0, tail_length * k)
		var seg_r: float = orb_r * (1.0 - k * 0.75)
		var seg_alpha: float = (1.0 - k) * 0.55 * pulse
		# Color shifts orange → red along the tail
		var seg_color := Color(1.0, lerp(0.6, 0.15, k), lerp(0.2, 0.05, k), seg_alpha)
		draw_circle(seg_pos, seg_r * 1.4, Color(seg_color.r, seg_color.g, seg_color.b, seg_alpha * 0.4))
		draw_circle(seg_pos, seg_r, seg_color)

	# --- Orb: outer halo → mid red-orange body → bright white-hot core ---
	# Outer soft halo
	draw_circle(orb_pos, orb_r * 2.2, Color(1.0, 0.5, 0.1, 0.20 * pulse))
	draw_circle(orb_pos, orb_r * 1.6, Color(1.0, 0.6, 0.15, 0.40 * pulse))
	# Mid body (red-orange)
	draw_circle(orb_pos, orb_r * 1.1, Color(1.0, 0.55, 0.15, 0.85))
	# Inner bright orange
	draw_circle(orb_pos, orb_r * 0.75, Color(1.0, 0.85, 0.35, 0.95))
	# White-hot core
	draw_circle(orb_pos, orb_r * 0.40, Color(1.0, 1.0, 0.95, 1.0))
	# Tiny offset highlight for a sense of curvature
	draw_circle(orb_pos + Vector2(-orb_r * 0.2, -orb_r * 0.2), orb_r * 0.18, Color(1, 1, 1, 0.9))
	# Upgraded warheads: a coloured aura and one spinning energy arc per tier.
	if tier > 0:
		var aura: Color = TIER_AURA[tier]
		draw_circle(orb_pos, orb_r * (2.4 + 0.3 * tier), Color(aura.r, aura.g, aura.b, 0.14 * pulse))
		for i in tier:
			var a0: float = _time * (5.0 + i * 1.7) + TAU * float(i) / float(tier)
			draw_arc(orb_pos, orb_r * (1.75 + 0.28 * i), a0, a0 + 1.9, 14, Color(aura.r, aura.g, aura.b, 0.85), 2.5, true)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = torpedo_size
	shape.shape = rect
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	position += direction * speed * delta
	queue_redraw()
	var m: float = 32.0
	# Detonate at top edge so it doesn't waste; despawn off other edges
	if position.y < -m:
		_detonate()
		return
	if position.y > _viewport_size.y + m or position.x < -m or position.x > _viewport_size.x + m:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group(&"enemies"):
		_detonate()


func _detonate() -> void:
	# area_entered fires once per enemy overlapped in the same physics step and
	# queue_free doesn't stop them, so only the first call may detonate.
	if _detonated:
		return
	_detonated = true
	# Spawn the visual explosion
	var explosion: Node2D = ExplosionScript.new()
	explosion.position = position
	explosion.radius = splash_radius
	explosion.lifetime *= 1.0 + 0.12 * tier
	explosion.spark_count += 8 * tier
	explosion.debris_count += 4 * tier
	get_parent().add_child(explosion)
	# Upgraded warheads throw secondary fireballs through the blast area.
	for i in tier * 2:
		var sec: EnemyExplosion = preload("res://scripts/EnemyExplosion.gd").new()
		sec.position = position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(splash_radius * 0.2, splash_radius * 0.6)
		sec.burst_radius = splash_radius * randf_range(0.14, 0.22)
		sec.lifetime = 0.55 + 0.08 * tier
		sec.base_color = TIER_AURA[tier]
		get_parent().add_child.call_deferred(sec)

	# Apply splash damage to every enemy within radius
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var dist: float = position.distance_to(e.global_position)
		if dist <= splash_radius and e.has_method("take_damage"):
			e.take_damage(splash_damage)

	# Wipe enemy bullets caught in the blast — torpedoes are a rare, premium
	# weapon, so unlike the beam they DO clear boss fire too. This makes the
	# torpedo a real panic button against boss spread patterns and rewards
	# saving them for tight moments instead of spamming on fodder.
	var bullets := get_tree().get_nodes_in_group(&"enemy_bullets")
	for b in bullets:
		if not is_instance_valid(b):
			continue
		if position.distance_to(b.global_position) <= splash_radius:
			b.queue_free()

	# Louder and deeper per tier; from tier 2 a second, lower boom is layered in.
	AudioManager.play_sfx(AudioManager.SFX_TORPEDO_EXPLOSION, -2.0 + 1.5 * tier, 1.0 - 0.07 * tier)
	if tier >= 2:
		AudioManager.play_sfx(AudioManager.SFX_SPACESHIP_EXPLODING, -7.0 + 1.5 * (tier - 2), 0.72)
	AudioManager.haptic_heavy()
	EventBus.screen_shake_requested.emit(14.0 + 3.5 * tier, 0.35 + 0.07 * tier)
	queue_free()
