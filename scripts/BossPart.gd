extends Area2D
class_name BossPart
## A breakable piece of a boss: turret, armor plate, worm segment, egg sac...
## Child of a Boss. Joins &"enemies" (so Bullet, Beam, Missile, Torpedo and
## HitCheck hit it with no changes) and &"boss_parts" (ram damage and the
## missile boss multiplier treat it like the boss). NOT in &"bosses": the
## spawner counts the core only.
##
## A part either has its own HP (`hp`) or forwards hits to the core
## (`core_transfer` > 0, used by weak points and worm segments). When its HP
## runs out it becomes a scorched wreck (no collision) and tells the boss.

const EnemyExplosionScript := preload("res://scripts/EnemyExplosion.gd")
const PickupScript := preload("res://scripts/Pickup.gd")

enum Kind { TURRET, PLATE, SEGMENT, WEAKPOINT }

var boss: Node = null          ## Owning Boss (set before add_child)
var kind: int = Kind.TURRET
var part_id: StringName = &""
var max_hp: int = 60
var hp: int = 60
var armor: int = 2
var contact_damage: int = 14
var hit_half: Vector2 = Vector2(30, 30)   ## Read by HitCheck.half_extents
## While any part with shields_core lives, the core takes Boss.SHIELDED_CORE_MUL damage.
var shields_core: bool = false
## > 0: hits are passed to the boss core times this factor; the part has no HP of its own.
var core_transfer: float = 0.0
## Attack: Boss.part_fire(self) is called every `fire_cd` seconds (0 = never fires).
var pattern: StringName = &""
var fire_cd: float = 0.0
var fire_timer: float = 1.2
var reward_money: int = 60
var color: Color = Color(0.55, 0.55, 0.60)
var glow: Color = Color(0.55, 1.0, 0.35)
## Free-floating parts (worm segments) set top_level and are moved by the boss.
var follows_boss: bool = true

var alive: bool = true
## CO-OP: the server's id for this part (0 = local). On a phone the part's
## HP and its death come from the server; hits are reported.
var net_id: int = 0
var _flash: float = 0.0
var _t: float = 0.0
var _aim: float = PI * 0.5   ## Barrel angle, eased toward the player


func _ready() -> void:
	hp = max_hp
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hit_half * 2.0
	shape.shape = rect
	add_child(shape)
	add_to_group(&"enemies")
	add_to_group(&"boss_parts")
	fire_timer = randf_range(0.8, 1.6) if fire_cd > 0.0 else 0.0


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
	if alive and kind == Kind.TURRET:
		var p := HitCheck.player(get_tree())
		if p != null:
			var want: float = (p.global_position - global_position).angle()
			_aim = lerp_angle(_aim, want, clampf(delta * 4.0, 0.0, 1.0))
	if alive and fire_cd > 0.0 and boss != null and boss.has_method("part_fire") and boss.can_attack() and not _puppet():
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = fire_cd * boss.part_cd_mul()
			boss.part_fire(self)
	queue_redraw()


func aim_dir() -> Vector2:
	return Vector2.RIGHT.rotated(_aim)


## True on a phone in co-op: the owning boss is a server puppet.
func _puppet() -> bool:
	return boss != null and is_instance_valid(boss) and "net_puppet" in boss and boss.net_puppet


func take_damage(amount: int) -> void:
	if not alive:
		return
	_flash = 1.0
	if _puppet():
		Net.report_hit(net_id, amount)
		return
	if core_transfer > 0.0:
		if boss != null and is_instance_valid(boss):
			boss.take_part_hit(self, maxi(1, int(round(float(amount) * core_transfer))))
		return
	hp -= maxi(1, amount - armor)
	if hp <= 0:
		destroy()


## Break the part: explosion, money pop, wreck stays drawn, collision off.
func destroy(silent: bool = false) -> void:
	if not alive:
		return
	alive = false
	hp = 0
	remove_from_group(&"enemies")
	remove_from_group(&"boss_parts")
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	var parent: Node = get_tree().current_scene if boss == null else boss.get_parent()
	if parent != null:
		var burst: EnemyExplosion = EnemyExplosionScript.new()
		burst.position = global_position
		burst.burst_radius = maxf(hit_half.x, hit_half.y) * 1.6
		burst.spark_count = 14
		burst.debris_count = 8
		burst.smoke_count = 6
		burst.base_color = glow
		parent.add_child.call_deferred(burst)
		if not silent and reward_money > 0:
			var pk: Pickup = PickupScript.new()
			pk.type = Pickup.Type.MONEY
			pk.money_value = reward_money
			pk.position = global_position
			parent.add_child.call_deferred(pk)
	if not silent:
		EventBus.screen_shake_requested.emit(6.0, 0.25)
	if boss != null and is_instance_valid(boss) and boss.has_method("on_part_destroyed"):
		boss.on_part_destroyed(self)


func _draw() -> void:
	var fl: float = _flash
	match kind:
		Kind.TURRET:
			_draw_turret(fl)
		Kind.PLATE:
			_draw_plate(fl)
		Kind.SEGMENT:
			_draw_segment(fl)
		Kind.WEAKPOINT:
			_draw_weak(fl)
	if alive and core_transfer <= 0.0 and hp < max_hp:
		# Small HP ring so the player sees the part is about to pop
		var r: float = maxf(hit_half.x, hit_half.y) + 6.0
		var k: float = float(hp) / float(max_hp)
		draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * k, 28, Color(1.0, 0.85, 0.3, 0.85), 3.0, true)


func _draw_wreck(r: float) -> void:
	# Jagged scorched hole, smaller than the live part
	var hole := PackedVector2Array()
	for i in 9:
		var a: float = TAU / 9.0 * float(i)
		hole.append(Vector2(cos(a), sin(a)) * r * (0.55 + 0.22 * float((i * 7) % 3) / 2.0))
	draw_colored_polygon(hole, Color(0.06, 0.05, 0.05, 0.9))
	draw_circle(Vector2.ZERO, r * 0.42, Color(0.14, 0.10, 0.08, 0.95))
	var ember: float = 0.5 + 0.5 * sin(_t * 5.0 + r)
	draw_circle(Vector2(r * 0.2, -r * 0.1), r * 0.18, Color(1.0, 0.45, 0.15, 0.35 + 0.4 * ember))
	draw_circle(Vector2(-r * 0.25, r * 0.2), r * 0.12, Color(1.0, 0.65, 0.2, 0.25 + 0.35 * ember))


func _draw_turret(fl: float) -> void:
	var r: float = minf(hit_half.x, hit_half.y)
	if not alive:
		_draw_wreck(r)
		return
	var c: Color = color.lerp(Color.WHITE, fl)
	draw_circle(Vector2.ZERO, r, Color(0.08, 0.08, 0.10))
	draw_circle(Vector2.ZERO, r * 0.86, c.darkened(0.25))
	draw_circle(Vector2.ZERO, r * 0.70, c)
	# Barrel toward the player
	var d: Vector2 = aim_dir()
	draw_line(d * r * 0.3, d * r * 1.25, Color(0.10, 0.10, 0.12), r * 0.42)
	draw_line(d * r * 0.3, d * r * 1.20, c.lightened(0.15), r * 0.26)
	# Glowing eye, pulses before a shot
	var charge: float = 0.0
	if fire_cd > 0.0:
		charge = clampf(1.0 - fire_timer / 0.5, 0.0, 1.0)
	var g: Color = glow.lerp(Color.WHITE, charge * 0.6)
	draw_circle(Vector2.ZERO, r * (0.32 + 0.10 * charge), g)
	draw_circle(Vector2.ZERO, r * 0.15, Color(1, 1, 1, 0.9))


func _draw_plate(fl: float) -> void:
	var w: float = hit_half.x
	var h: float = hit_half.y
	if not alive:
		_draw_wreck(minf(w, h))
		return
	var c: Color = color.lerp(Color.WHITE, fl)
	var outer := PackedVector2Array([
		Vector2(-w, -h * 0.55), Vector2(-w * 0.55, -h), Vector2(w * 0.55, -h),
		Vector2(w, -h * 0.55), Vector2(w, h * 0.55), Vector2(w * 0.55, h),
		Vector2(-w * 0.55, h), Vector2(-w, h * 0.55)])
	draw_colored_polygon(outer, Color(0.07, 0.07, 0.09))
	var inner := PackedVector2Array()
	for p in outer:
		inner.append(p * 0.84)
	draw_colored_polygon(inner, Color(c.r, c.g, c.b, 0.93))
	# Top bevel highlight + lower shade so the plate reads as raised armor
	draw_polyline(PackedVector2Array([inner[7], inner[0], inner[1], inner[2], inner[3]]), c.lightened(0.35), 2.5, true)
	draw_polyline(PackedVector2Array([inner[4], inner[5], inner[6]]), c.darkened(0.5), 2.5, true)
	# Plate seams + rivets
	draw_line(Vector2(-w * 0.84, 0), Vector2(w * 0.84, 0), c.darkened(0.45), 3.0)
	for sx in [-0.6, 0.6]:
		for sy in [-0.6, 0.6]:
			draw_circle(Vector2(w * sx, h * sy), 3.5, Color(0.15, 0.15, 0.17))
	# Cracks grow with damage
	var dmg: float = 1.0 - float(hp) / float(max_hp)
	if dmg > 0.3:
		draw_line(Vector2(-w * 0.3, -h * 0.5), Vector2(w * 0.1, h * 0.1), Color(0, 0, 0, 0.8), 2.0)
	if dmg > 0.6:
		draw_line(Vector2(w * 0.4, -h * 0.3), Vector2(-w * 0.1, h * 0.6), Color(1.0, 0.5, 0.2, 0.8), 2.0)
	# Shield shimmer edge: this plate protects the core
	if shields_core:
		var a: float = 0.45 + 0.30 * sin(_t * 4.0)
		draw_polyline(outer + PackedVector2Array([outer[0]]), Color(glow.r, glow.g, glow.b, a), 2.5, true)


func _draw_segment(fl: float) -> void:
	var r: float = minf(hit_half.x, hit_half.y)
	if not alive:
		return
	var c: Color = color.lerp(Color.WHITE, fl)
	draw_circle(Vector2.ZERO, r, Color(0.06, 0.05, 0.08))
	draw_circle(Vector2.ZERO, r * 0.86, c.darkened(0.2))
	draw_circle(Vector2(0, -r * 0.15), r * 0.62, c)
	# Bony ridge
	draw_line(Vector2(-r * 0.7, 0), Vector2(r * 0.7, 0), c.darkened(0.5), 3.0)
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.0 + position.x * 0.02)
	draw_circle(Vector2(0, r * 0.35), r * 0.16, Color(glow.r, glow.g, glow.b, 0.5 + 0.5 * pulse))


func _draw_weak(fl: float) -> void:
	var r: float = minf(hit_half.x, hit_half.y)
	if not alive:
		_draw_wreck(r)
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 6.0)
	draw_circle(Vector2.ZERO, r * (1.15 + 0.1 * pulse), Color(glow.r, glow.g, glow.b, 0.25))
	draw_circle(Vector2.ZERO, r, color.lerp(Color.WHITE, fl))
	draw_circle(Vector2.ZERO, r * 0.6, glow)
	draw_circle(Vector2.ZERO, r * 0.28, Color(1, 1, 1, 0.95))
