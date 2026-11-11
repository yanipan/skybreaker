extends Node
## Headless: nearest-ship targeting for enemies, boss aim, and homing shots.
## Run: godot --headless --path . res://scenes/tools/TargetingTest.tscn

var _fails: int = 0
var _passes: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("PASS  ", what)
	else:
		_fails += 1
		print("FAIL  ", what)


func _ready() -> void:
	call_deferred("_run")


func _ship(host: Node, pos: Vector2) -> Area2D:
	var s := Area2D.new()
	s.monitoring = false
	s.monitorable = false
	s.position = pos
	s.add_to_group(&"player")
	host.add_child(s)
	Targeting.invalidate()
	return s


func _newest_bullet(host: Node) -> EnemyBullet:
	var b: EnemyBullet = null
	for c in host.get_children():
		if c is EnemyBullet:
			b = c
	if b != null:
		b.set_process(false)
	return b


func _clear(host: Node) -> void:
	for c in host.get_children():
		c.free()
	Targeting.invalidate()


func _run() -> void:
	var host := Node2D.new()
	add_child(host)
	GameState.current_level = 12
	var tree := get_tree()
	Targeting.invalidate()

	# 1. No ships
	_check(Targeting.nearest_ship(tree, Vector2.ZERO) == null, "1. no ships: nearest_ship is null")

	# 2. One ship at (400, 1000)
	var one := _ship(host, Vector2(400, 1000))
	_check(Targeting.nearest_ship(tree, Vector2(0, 0)) == one, "2. one ship returned from (0, 0)")
	_check(Targeting.nearest_ship(tree, Vector2(800, 1400)) == one, "2. one ship returned from (800, 1400)")
	_clear(host)

	# 3. Two ships: nearer A from the left, nearer B from the right
	var a := _ship(host, Vector2(100, 1000))
	var b := _ship(host, Vector2(700, 1000))
	_check(Targeting.nearest_ship(tree, Vector2(150, 200)) == a, "3. two ships: from (150, 200) is A")
	_check(Targeting.nearest_ship(tree, Vector2(650, 200)) == b, "3. two ships: from (650, 200) is B")

	# 4. B freed
	b.free()
	Targeting.invalidate()
	_check(Targeting.nearest_ship(tree, Vector2(650, 200)) == a, "4. B freed: from (650, 200) is A")

	# 5. A ship removed from the player group is not returned
	var extra := _ship(host, Vector2(650, 200))
	extra.remove_from_group(&"player")
	Targeting.invalidate()
	var picked: Node2D = Targeting.nearest_ship(tree, Vector2(650, 200))
	_check(picked != extra and picked == a, "5. remove_from_group: ship is not returned")
	_clear(host)

	# 6. Per-frame cache
	var _c1 := _ship(host, Vector2(100, 1000))
	_check(Targeting.ships(tree).size() == 1, "6. cache: one ship present")
	var _c2 := Area2D.new()
	_c2.monitoring = false
	_c2.monitorable = false
	_c2.position = Vector2(700, 1000)
	_c2.add_to_group(&"player")
	host.add_child(_c2)
	_check(Targeting.ships(tree).size() == 1, "6. cache: second ship hidden until invalidate")
	Targeting.invalidate()
	_check(Targeting.ships(tree).size() == 2, "6. cache: after invalidate size is 2")
	_clear(host)

	# 7. Aimed fire: DODGER snipes the nearer ship
	var sa := _ship(host, Vector2(100, 1200))
	var sb := _ship(host, Vector2(700, 1200))
	var dodger_b: Enemy = Enemy.new()
	dodger_b.type = Enemy.Type.DODGER
	dodger_b.position = Vector2(650, 300)
	host.add_child(dodger_b)
	dodger_b.set_process(false)
	dodger_b._fire_pattern(&"aimed")
	var bullet_b: EnemyBullet = _newest_bullet(host)
	var start_b: Vector2 = bullet_b.position if bullet_b != null else Vector2.ZERO
	var want_b: Vector2 = (sb.position - start_b).normalized()
	var dot_b: float = bullet_b.direction.dot(want_b) if bullet_b != null else -1.0
	_check(bullet_b != null and dot_b > 0.99, "7. aimed fire from (650, 300) points at B (dot=%.3f)" % dot_b)

	var dodger_a: Enemy = Enemy.new()
	dodger_a.type = Enemy.Type.DODGER
	dodger_a.position = Vector2(150, 300)
	host.add_child(dodger_a)
	dodger_a.set_process(false)
	dodger_a._fire_pattern(&"aimed")
	var bullet_a: EnemyBullet = _newest_bullet(host)
	var start_a: Vector2 = bullet_a.position if bullet_a != null else Vector2.ZERO
	var want_a: Vector2 = (sa.position - start_a).normalized()
	var dot_a: float = bullet_a.direction.dot(want_a) if bullet_a != null else -1.0
	_check(bullet_a != null and dot_a > 0.99, "7. aimed fire from (150, 300) points at A (dot=%.3f)" % dot_a)
	_clear(host)

	# 8. Chase: REAPER strafes toward the nearer ship
	var _ra := _ship(host, Vector2(100, 1200))
	var _rb := _ship(host, Vector2(760, 1200))
	var r1: Enemy = Enemy.new()
	r1.type = Enemy.Type.REAPER
	r1.position = Vector2(600, 200)
	host.add_child(r1)
	r1.set_process(false)
	r1._process(0.1)
	_check(r1.position.x > 600.0, "8. reaper at (600, 200) chases B (x=%.1f)" % r1.position.x)
	var r2: Enemy = Enemy.new()
	r2.type = Enemy.Type.REAPER
	r2.position = Vector2(200, 200)
	host.add_child(r2)
	r2.set_process(false)
	r2._process(0.1)
	_check(r2.position.x < 200.0, "8. reaper at (200, 200) chases A (x=%.1f)" % r2.position.x)
	_clear(host)

	# 9. Homing shot steers toward the nearer ship
	var _ha := _ship(host, Vector2(100, 900))
	var _hb := _ship(host, Vector2(760, 900))
	var m1: EnemyBullet = EnemyBullet.new()
	m1.position = Vector2(600, 300)
	m1.direction = Vector2.DOWN
	m1.homing_turn_rate = 3.0
	m1.homing_secs = 2.0
	host.add_child(m1)
	m1.set_process(false)
	for i in 5:
		m1._process_motion(0.1)
	_check(m1.direction.x > 0.0, "9. homing from (600, 300) turns toward B (dx=%.3f)" % m1.direction.x)
	var m2: EnemyBullet = EnemyBullet.new()
	m2.position = Vector2(200, 300)
	m2.direction = Vector2.DOWN
	m2.homing_turn_rate = 3.0
	m2.homing_secs = 2.0
	host.add_child(m2)
	m2.set_process(false)
	for i in 5:
		m2._process_motion(0.1)
	_check(m2.direction.x < 0.0, "9. homing from (200, 300) turns toward A (dx=%.3f)" % m2.direction.x)

	print("TargetingTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
