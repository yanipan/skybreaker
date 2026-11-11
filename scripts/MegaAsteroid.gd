extends Asteroid
class_name MegaAsteroid
## MEGA ASTEROID (11/11): a huge, slow rock that drifts down the field. It is a
## wall: player shots stop on it (it sits in &"enemies", so bullets, beam,
## missiles and torpedoes all hit it) and enemy fire that reaches it pops
## harmlessly, so it is cover as well as an obstacle. Ramming it hurts every
## RAM_REPEAT seconds while the ship stays inside. Destroying it ALWAYS drops a
## weapon upgrade (weakest weapon below the hard cap, ignoring the per-sector
## soft cap) plus a ring of coins. Let it drift past and the upgrade is gone.
## Scheduled per sector by Levels.MEGA_ASTEROIDS. Test: MeteorTest.tscn.

## Live megas, read by every EnemyBullet each frame (empty almost always, so
## the check costs one array size test).
static var live: Array = []

const RAM_REPEAT: float = 0.9
## Ram damage the rock itself takes per touch (boss rule: no instant kill).
var ram_damage: int = 25
## Box read by HitCheck's safety net.
var hit_half: Vector2 = Vector2.ZERO
## Extra half-width the beam adds to its column test (the beam looks at
## centres, a 260 px rock must stop it at its edge too).
var beam_half_w: float = 0.0

var _ram_cd: float = 0.0
var _vein_pts: Array = []


func _ready() -> void:
	size = Size.LARGE   # base fields, overwritten in _configure
	super._ready()
	add_to_group(&"mega_asteroids")
	live.append(self)
	spin_speed = randf_range(-0.25, 0.25)


func _exit_tree() -> void:
	live.erase(self)


func _configure() -> void:
	var lvl: int = clamp(GameState.current_level, 1, GameState.MAX_LEVEL)
	var t: float = float(lvl - 1) / float(GameState.MAX_LEVEL - 1)
	max_hp = int(round(lerp(150.0, 650.0, t)))
	hp = max_hp
	radius = 130.0
	contact_damage = 14
	reward = 600
	money_value = 20
	money_drop_chance = 1.0
	power_drop_chance = 1.0
	health_drop_chance = 0.0
	hit_half = Vector2.ONE * radius * 0.72
	beam_half_w = radius * 0.75


func _generate_shape() -> void:
	_shape_pts = PackedVector2Array()
	var verts: int = 28
	for i in verts:
		var ang: float = TAU * float(i) / float(verts)
		var jitter: float = randf_range(0.86, 1.06)
		_shape_pts.append(Vector2(cos(ang), sin(ang)) * radius * jitter)
	for i in randi_range(6, 9):
		var p := Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)) * radius
		_crater_pts.append({"pos": p, "r": randf_range(radius * 0.07, radius * 0.18)})
	# Glowing ore veins: the "this one is worth it" tell
	for i in 4:
		var a: float = randf() * TAU
		var p0 := Vector2(cos(a), sin(a)) * radius * randf_range(0.1, 0.3)
		var p1 := p0 + Vector2(cos(a + 0.6), sin(a + 0.6)) * radius * randf_range(0.35, 0.55)
		_vein_pts.append([p0, p1])
	_rock_color = Color(0.46, 0.40, 0.36)
	_rock_dark = Color(0.24, 0.21, 0.19)


func _process(delta: float) -> void:
	super._process(delta)
	if is_queued_for_deletion():
		return
	if Engine.get_process_frames() % 3 == 0:
		queue_redraw()   # vein pulse (one rock on screen, cheap)
	# Ship sitting inside the rock keeps getting hurt (area_entered fires once).
	_ram_cd = max(0.0, _ram_cd - delta)
	if _ram_cd <= 0.0:
		var p: Node2D = HitCheck.player(get_tree())
		if p != null and p.monitoring and p.global_position.distance_to(global_position) < radius * 0.85 + 18.0:
			_ram_cd = RAM_REPEAT
			if p.has_method("_on_area_entered"):
				p._on_area_entered(self)


func _draw() -> void:
	super._draw()
	var pulse: float = 0.55 + 0.35 * sin(_time * 3.0)
	for v in _vein_pts:
		draw_line(v[0], v[1], Color(1.0, 0.62, 0.20, 0.35 * pulse), 9.0, true)
		draw_line(v[0], v[1], Color(1.0, 0.85, 0.45, 0.9 * pulse), 3.0, true)
	# Damage bar on the rock itself, so the player can see the wall giving way
	var w: float = radius * 1.2
	var frac: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	draw_rect(Rect2(-w * 0.5, radius + 10.0, w, 8.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w * 0.5, radius + 10.0, w * frac, 8.0), Color(1.0, 0.7, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Enemy fire that reaches the rock stops here (EnemyBullet asks every frame).
static func blocks(pos: Vector2) -> bool:
	for m in live:
		if is_instance_valid(m) and not m.is_queued_for_deletion() \
				and pos.distance_squared_to(m.global_position) < pow(m.radius * 0.85, 2):
			return true
	return false


## Always a weapon upgrade, then a ring of coins.
func _maybe_drop_pickup() -> void:
	var pwr: int = mega_power_drop(get_tree())
	_drop(pwr if pwr >= 0 else Pickup.Type.MONEY, 0 if pwr >= 0 else money_value * 4)
	for i in 8:
		var pickup: Pickup = PickupScript.new()
		pickup.type = Pickup.Type.MONEY
		pickup.money_value = money_value
		pickup.position = global_position + Vector2.RIGHT.rotated(TAU * i / 8.0) * radius * 0.5
		get_parent().add_child.call_deferred(pickup)


## Weakest weapon still below the hard cap (Player.max_power_level). Unlike
## Pickup.boss_power_drop this ignores the per-sector soft cap: the mega is
## the promise of an upgrade. -1 only when all three weapons are maxed.
static func mega_power_drop(tree: SceneTree) -> int:
	var player: Node = tree.get_first_node_in_group(&"player") if tree != null else null
	if player == null or not "weapon_levels" in player:
		return Pickup.Type.POWER_PHASER
	var cap: int = int(player.max_power_level) if "max_power_level" in player else 30
	var best: int = -1
	var best_lvl: int = 1 << 20
	for wt in 3:
		var lvl: int = int(player.weapon_levels.get(wt, 1))
		if lvl < cap and lvl < best_lvl:
			best = wt
			best_lvl = lvl
	return -1 if best < 0 else Pickup.power_type_for(best)
