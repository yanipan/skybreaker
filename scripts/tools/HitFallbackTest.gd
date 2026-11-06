extends Node
## Headless: with the physics server switched off, bullets still hit enemies
## and enemy shots still hit the ship (HitCheck safety net); with physics on,
## the safety net never fires (no double hits).
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _round(physics_on: bool) -> Dictionary:
	PhysicsServer2D.set_active(physics_on)
	GameState.hit_fallbacks = 0
	var arena := Node2D.new()
	add_child(arena)
	var e: Node = load("res://scripts/Enemy.gd").new()
	e.type = 2   # tank: plenty of HP, slow
	e.position = Vector2(360, 300)
	arena.add_child(e)
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(200, 1100)
	arena.add_child(p)
	await get_tree().process_frame
	e.set_process(false)   # hold still
	e.set_physics_process(false)
	var hp0: int = e.hp
	var b: Node = load("res://scripts/Bullet.gd").new()
	b.position = Vector2(360, 700)
	b.direction = Vector2.UP
	arena.add_child(b)
	var eb: Node = load("res://scripts/EnemyBullet.gd").new()
	eb.position = Vector2(200, 800)
	eb.direction = Vector2.DOWN
	arena.add_child(eb)
	var p_hp0: int = p.hp
	var p_sh0: float = p.shield
	for i in 90:
		await get_tree().physics_frame
	var res := {
		"enemy_hit": e.hp < hp0 if is_instance_valid(e) else true,
		"ship_hit": p.hp < p_hp0 or p.shield < p_sh0,
		"fallbacks": GameState.hit_fallbacks,
	}
	arena.queue_free()
	await get_tree().process_frame
	PhysicsServer2D.set_active(true)
	return res

func _ready() -> void:
	var on: Dictionary = await _round(true)
	print("physics ON: ", on)
	_check(on["enemy_hit"] and on["ship_hit"], "physics on: both hits land")
	_check(on["fallbacks"] == 0, "physics on: safety net never fires (no double hits)")
	var off: Dictionary = await _round(false)
	print("physics OFF: ", off)
	_check(off["enemy_hit"], "physics off: player shot still damages the enemy")
	_check(off["ship_hit"], "physics off: enemy shot still hits the ship")
	_check(off["fallbacks"] >= 2, "physics off: safety net counted %d hits" % off["fallbacks"])
	print("HIT FALLBACK TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
