extends Node
## Headless: meteor showers + mega asteroid (11/11).
## Run: godot --headless --path . res://scenes/tools/MeteorTest.tscn

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


func _rocks(host: Node, mega: bool) -> Array:
	var out: Array = []
	for c in host.get_children():
		if c is MegaAsteroid:
			if mega: out.append(c)
		elif c is Asteroid and not mega:
			out.append(c)
	return out


func _clear(host: Node) -> void:
	for c in host.get_children():
		c.free()


func _run() -> void:
	# Schedule sanity
	for lv in Levels.METEOR_SHOWERS:
		var d: Dictionary = Levels.get_level(lv)
		_check(not bool(d.get("has_boss", false)), "shower sector %d is not a boss sector" % lv)
		for at in Levels.METEOR_SHOWERS[lv]:
			_check(absf(float(at) - 0.5) > 0.12 or not d.has("mini_boss"), "sector %d shower at %.2f clear of the mini-boss" % [lv, at])
	for lv in Levels.MEGA_ASTEROIDS:
		_check(not bool(Levels.get_level(lv).get("has_boss", false)), "mega sector %d is not a boss sector" % lv)

	var host := Node2D.new()
	add_child(host)

	# --- Shower on sector 7 ---
	GameState.current_level = 7
	var sp: EnemySpawner = EnemySpawner.new()
	host.add_child(sp)
	sp.set_process(false)
	_check(sp._shower_times.size() == 2, "sector 7 has two showers")
	var t0: float = float(sp._shower_times[0])
	sp._mission_time = t0 - 0.5
	sp._process(0.05)
	_check(not sp.shower_active(), "no shower before its time")
	sp._mission_time = t0 + 0.01
	sp._process(0.05)
	_check(sp.shower_active() and sp._shower_warn > 0.0, "warning starts at %.1f s" % t0)
	_check(_rocks(host, false).is_empty(), "no rocks during the warning")
	# Run the shower through
	var steps: int = int((EnemySpawner.SHOWER_WARN_SECS + Levels.SHOWER_SECS) / 0.05) + 4
	var max_rocks: int = 0
	sp._timer = 0.0   # a wave is due: it must be skipped while raining
	var enemies_before: int = get_tree().get_nodes_in_group(&"enemies").size()
	for i in steps:
		sp._mission_time += 0.05
		sp._process(0.05)
		max_rocks = maxi(max_rocks, _rocks(host, false).size())
	var rocks: Array = _rocks(host, false)
	_check(rocks.size() >= 25, "shower threw %d rocks (>= 25)" % rocks.size())
	_check(not sp.shower_active(), "shower ended")
	var all_shower: bool = true
	var no_gear: bool = true
	var dir_ok: bool = true
	var d0: Vector2 = rocks[0].drift.normalized()
	for r in rocks:
		all_shower = all_shower and r.shower
		no_gear = no_gear and r.power_drop_chance == 0.0 and r.health_drop_chance == 0.0
		dir_ok = dir_ok and r.drift.normalized().angle_to(d0) < deg_to_rad(13.0) and r.drift.y > 250.0
	_check(all_shower, "every rock is a shower rock")
	_check(no_gear, "shower rocks drop no power or health")
	_check(dir_ok, "rain falls one way (spread <= 12 deg), fast")
	var enemy_nodes: int = 0
	for c in host.get_children():
		if c is Enemy:
			enemy_nodes += 1
	_check(enemy_nodes == 0, "no enemy wave spawned during the shower")
	_clear(host)

	# --- Mega asteroid on sector 5 ---
	GameState.current_level = 5
	var player := Area2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	host.add_child(player)
	player.position = Vector2(400, 1300)
	sp = EnemySpawner.new()
	host.add_child(sp)
	sp.set_process(false)
	_check(sp._mega_time > 0.0, "sector 5 has a mega asteroid")
	sp._mission_time = sp._mega_time + 0.01
	sp._process(0.05)
	var megas: Array = _rocks(host, true)
	_check(megas.size() == 1, "mega spawned once")
	sp._mission_time += 1.0
	sp._process(0.05)
	_check(_rocks(host, true).size() == 1, "still only one mega")
	var m: MegaAsteroid = megas[0]
	_check(m.max_hp >= 220 and m.radius >= 190.0, "mega is big (hp %d, r %.0f)" % [m.max_hp, m.radius])
	_check(m.drift.y < 60.0, "mega drifts slowly")
	_check(MegaAsteroid.live.has(m), "mega registered as cover")
	# Enemy bullet into the rock pops
	m.position = Vector2(400, 500)
	var eb: EnemyBullet = EnemyBullet.new()
	eb.position = m.position + Vector2(0, 60)
	eb.direction = Vector2.DOWN
	host.add_child(eb)
	eb._process_motion(0.016)
	_check(eb.is_queued_for_deletion(), "enemy bullet stops on the mega")
	var eb2: EnemyBullet = EnemyBullet.new()
	eb2.position = Vector2(30, 500)
	eb2.direction = Vector2.DOWN
	host.add_child(eb2)
	eb2._process_motion(0.016)
	_check(not eb2.is_queued_for_deletion(), "enemy bullet beside it flies on")
	# Ram does not one-shot it
	var hp0: int = m.hp
	player._on_area_entered(m)
	_check(m.hp == hp0 - m.ram_damage and not m.is_queued_for_deletion(), "ram costs it %d, not an instant kill" % m.ram_damage)
	# Always an upgrade: even when the soft cap is hit on two weapons
	player.weapon_levels = {0: 30, 1: 29, 2: 30}
	_check(MegaAsteroid.mega_power_drop(get_tree()) == Pickup.power_type_for(1), "drop goes to the weakest weapon below 30")
	player.weapon_levels = {0: 1 + Pickup.power_soft_cap(5), 1: 1 + Pickup.power_soft_cap(5), 2: 1 + Pickup.power_soft_cap(5)}
	_check(Pickup.boss_power_drop(get_tree()) == -1 and MegaAsteroid.mega_power_drop(get_tree()) >= 0, "mega ignores the soft cap (boss drop would not)")
	player.weapon_levels = {0: 3, 1: 3, 2: 3}
	m.take_damage(m.hp)
	await get_tree().process_frame
	var powers: int = 0
	var coins: int = 0
	for c in host.get_children():
		if c is Pickup:
			if c.type == Pickup.Type.MONEY:
				coins += 1
			elif c.type in [Pickup.Type.POWER_PHASER, Pickup.Type.POWER_BEAM, Pickup.Type.POWER_MISSILE]:
				powers += 1
	_check(powers == 1, "destroyed mega drops exactly one weapon upgrade")
	_check(coins >= 8, "plus a coin ring (%d)" % coins)
	await get_tree().process_frame
	_check(MegaAsteroid.live.is_empty(), "cover list empty after it dies")

	# Boss sectors: nothing
	for lv in [4, 8, 24]:
		GameState.current_level = lv
		var bs: EnemySpawner = EnemySpawner.new()
		host.add_child(bs)
		_check(bs._shower_times.is_empty() and bs._mega_time < 0.0, "boss sector %d: no shower, no mega" % lv)
		bs.free()

	print("MeteorTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
