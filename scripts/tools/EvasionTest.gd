extends Node
## Headless: JINKER evasion + armed variants (beam / homing) on regular ships.
## Run: godot --headless --path . res://scenes/tools/EvasionTest.tscn

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


func _shot(host: Node, pos: Vector2) -> Node2D:
	var b := Node2D.new()
	b.position = pos
	b.add_to_group(&"player_bullets")
	host.add_child(b)
	return b


func _jinker(host: Node, pos: Vector2) -> Enemy:
	var e: Enemy = Enemy.new()
	e.type = Enemy.Type.JINKER
	e.position = pos
	host.add_child(e)
	e.set_process(false)
	e._fire_timer = 999.0
	return e


func _step(e: Enemy, secs: float) -> void:
	var n: int = int(secs / 0.016)
	for i in n:
		e._process(0.016)


func _clear(host: Node) -> void:
	for c in host.get_children():
		c.free()


func _run() -> void:
	var host := Node2D.new()
	add_child(host)
	GameState.current_level = 12

	# 1. Shot in the lane below -> jinks sideways about JINK_DIST
	var e := _jinker(host, Vector2(400, 400))
	var s1 := _shot(host, Vector2(405, 600))
	_step(e, 0.3)
	_check(e.jinks == 1, "jinker jinks once at a shot in its lane (jinks=%d)" % e.jinks)
	_check(absf(e.position.x - 400.0) >= Enemy.JINK_DIST * 0.9, "moved %.0f px sideways" % absf(e.position.x - 400.0))
	_check(e.position.x < 400.0, "jinked AWAY from the shot (shot was right of centre)")
	# 2. Cooldown: a new shot right under it straight away -> no second jink
	s1.position = Vector2(e.position.x, e.position.y + 150)
	var x_before: float = e.position.x
	_step(e, 0.2)
	_check(e.jinks == 1 and absf(e.position.x - x_before) < 1.0, "cooldown: no second jink straight away")
	_step(e, 1.2)
	_check(e.jinks == 2, "after the cooldown it jinks again (jinks=%d)" % e.jinks)
	_clear(host)

	# 3. Shot outside the lane, or above the hull, or too far -> ignored
	e = _jinker(host, Vector2(400, 400))
	_shot(host, Vector2(560, 600))
	_shot(host, Vector2(400, 300))
	_shot(host, Vector2(400, 400 + Enemy.JINK_LOOK + 60))
	_step(e, 0.3)
	_check(e.jinks == 0, "ignores shots outside its lane, above it, or far below")
	_clear(host)

	# 4. Pinned at the left wall with the shot to its right -> jinks right anyway
	e = _jinker(host, Vector2(50, 400))
	_shot(host, Vector2(60, 600))
	_step(e, 0.3)
	_check(e.jinks == 1 and e.position.x > 50.0 + Enemy.JINK_DIST * 0.9, "pinned at the wall: jinks the open way (x=%.0f)" % e.position.x)
	_check(e.position.x <= 816.0, "stays on screen")
	_clear(host)

	# 5. Armed table
	_check(Enemy.roll_armed(Enemy.Type.TANK, 9, 0.0).is_empty(), "no beam tanks before sector 10")
	_check(Enemy.roll_armed(Enemy.Type.TANK, 10, 0.1).get("pattern") == &"beam", "sector 10 tank can carry a beam")
	_check(Enemy.roll_armed(Enemy.Type.TANK, 10, 0.9).is_empty(), "most tanks stay plain")
	_check(Enemy.roll_armed(Enemy.Type.BOMBER, 8, 0.1).get("pattern") == &"homing", "sector 8 bomber can carry homing missiles")
	_check(Enemy.roll_armed(Enemy.Type.GRUNT, 24, 0.0).is_empty(), "grunts never armed")

	# 6. Armed fire: tank beam every 3rd volley, bomber homing every 2nd
	GameState.current_level = 14
	var tank: Enemy = Enemy.new()
	tank.type = Enemy.Type.TANK
	tank.alt_pattern = &"beam"
	tank.alt_every = 3
	tank.position = Vector2(400, 300)
	host.add_child(tank)
	tank.set_process(false)
	for i in 3:
		tank._fire()
	var beams: int = 0
	for c in host.get_children():
		if c is EnemyBeam:
			beams += 1
	_check(beams == 1, "beam tank: 3 volleys -> exactly 1 beam (%d)" % beams)
	tank._volleys = 5
	tank._fire()
	beams = 0
	for c in host.get_children():
		if c is EnemyBeam:
			beams += 1
	_check(beams == 1, "no second beam while the first is still out")
	_clear(host)
	var bomber: Enemy = Enemy.new()
	bomber.type = Enemy.Type.BOMBER
	bomber.alt_pattern = &"homing"
	bomber.alt_every = 2
	bomber.position = Vector2(400, 300)
	host.add_child(bomber)
	bomber.set_process(false)
	bomber._fire()
	bomber._fire()
	var homing: int = 0
	var plain: int = 0
	for c in host.get_children():
		if c is EnemyBullet:
			if c.homing_turn_rate > 0.0:
				homing += 1
			else:
				plain += 1
	_check(homing >= 1 and plain >= 3, "homing bomber: one fan + homing missile(s) (fan %d, homing %d)" % [plain, homing])
	_clear(host)

	# 7. Spawner: armed ships and jinkers really show up in the late sectors
	var armed_seen: int = 0
	var jinkers_seen: int = 0
	for lv in range(10, GameState.MAX_LEVEL + 1):
		GameState.current_level = lv
		GameRng.seed_sector(777, lv)
		var sp: EnemySpawner = EnemySpawner.new()
		host.add_child(sp)
		sp.set_process(false)
		for w in 12:
			sp._spawn_wave()
		for c in host.get_children():
			if c is Enemy:
				if c.alt_pattern != &"":
					armed_seen += 1
				if c.type == Enemy.Type.JINKER:
					jinkers_seen += 1
		_clear(host)
	_check(armed_seen >= 10, "armed variants spawn in sectors 10-24 (%d seen)" % armed_seen)
	_check(jinkers_seen >= 10, "jinkers spawn in sectors 10-24 (%d seen)" % jinkers_seen)
	GameState.current_level = 9
	var sp9: EnemySpawner = EnemySpawner.new()
	host.add_child(sp9)
	sp9.set_process(false)
	for w in 12:
		sp9._spawn_wave()
	var j9: int = 0
	for c in host.get_children():
		if c is Enemy and c.type == Enemy.Type.JINKER:
			j9 += 1
	_check(j9 == 0, "no jinkers before sector 10")

	print("EvasionTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
