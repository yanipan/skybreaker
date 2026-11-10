extends Node
## Headless: mid-sector mini-bosses (old bosses returning, Levels.gd mini_boss).
## Run: godot --headless --path . res://scenes/tools/MiniBossTest.tscn

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


func _bosses() -> Array:
	return get_tree().get_nodes_in_group(&"bosses")


func _clear(host: Node) -> void:
	for c in host.get_children():
		c.free()


func _run() -> void:
	var host := Node2D.new()
	add_child(host)
	var expect := {6: Boss.Type.BOSS1, 10: Boss.Type.BOSS2, 14: Boss.Type.BOSS3, 17: Boss.Type.BOSS4, 21: Boss.Type.BOSS5, 23: Boss.Type.ARCHON}
	var boss_sectors: Array = []
	for lv in range(1, GameState.MAX_LEVEL + 1):
		var d: Dictionary = Levels.get_level(lv)
		if bool(d.get("has_boss", false)):
			boss_sectors.append(lv)
			_check(not d.has("mini_boss"), "boss sector %d has no mini-boss" % lv)
		# A mini-boss is always a boss already beaten earlier in the run
		if d.has("mini_boss"):
			var t: int = int(d.mini_boss.type)
			var first: int = 99
			for lv2 in range(1, GameState.MAX_LEVEL + 1):
				var d2: Dictionary = Levels.get_level(lv2)
				if bool(d2.get("has_boss", false)) and int(d2.get("boss_type", -1)) == t:
					first = mini(first, lv2)
			_check(first < lv, "sector %d mini-boss type %d was beaten earlier (sector %d)" % [lv, t, first])

	for lv in expect:
		GameState.current_level = lv
		var sp: EnemySpawner = EnemySpawner.new()
		host.add_child(sp)
		sp.set_process(false)
		_check(not sp._mini_cfg.is_empty(), "sector %d has a mini-boss" % lv)
		_check(sp.boss_sequence_done(), "sector %d: timer may end the sector before the mini enters" % lv)
		sp._mission_time = sp._mini_time - 0.1
		sp._process(0.05)
		_check(_bosses().is_empty(), "sector %d: nothing before %.0f s" % [lv, sp._mini_time])
		sp._mission_time = sp._mini_time + 0.01
		sp._process(0.05)
		await get_tree().process_frame
		var bs: Array = _bosses()
		_check(bs.size() == 1, "sector %d: one mini-boss enters at mid-sector" % lv)
		if bs.size() != 1:
			_clear(host)
			continue
		var m: Boss = bs[0]
		_check(m.mini and m.type == expect[lv], "sector %d: mini is the right old boss (%s)" % [lv, m.boss_name])
		# Compare with the full boss at the same sector
		var full: Boss = Boss.new()
		full.type = m.type
		host.add_child(full)
		await get_tree().process_frame
		_check(m.max_hp < full.max_hp * 0.7 and m.boss_size < full.boss_size and m.reward < full.reward,
				"sector %d: mini smaller (hp %d vs %d, size %.0f vs %.0f, reward %d)" % [lv, m.max_hp, full.max_hp, m.boss_size, full.boss_size, m.reward])
		full.free()
		_check(sp._boss_phase(), "sector %d: waves thin while the mini lives" % lv)
		sp._mission_time = sp.get_level_duration() + 5.0
		_check(not sp.boss_sequence_done(), "sector %d: sector cannot end while the mini lives" % lv)
		var before: Array = get_tree().get_nodes_in_group(&"pickups")
		var pk0: int = before.size()
		m.take_damage(9999999)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(sp.boss_sequence_done() and not sp._boss_phase(), "sector %d: mini dead = sector may end, waves return" % lv)
		var pks: Array = get_tree().get_nodes_in_group(&"pickups")
		var power: int = 0
		for p in pks:
			if p in before:
				continue
			if not (p.type in [Pickup.Type.TORPEDO, Pickup.Type.MONEY, Pickup.Type.HEALTH_MEDIUM]):
				power += 1
		_check(pks.size() - pk0 == 3 and power == 0, "sector %d: mini drops torpedo + health + money only (%d drops)" % [lv, pks.size() - pk0])
		sp._process(0.05)
		await get_tree().process_frame
		_check(_bosses().is_empty(), "sector %d: the mini comes once" % lv)
		_clear(host)

	# A plain sector without mini_boss never spawns one
	GameState.current_level = 7
	var sp7: EnemySpawner = EnemySpawner.new()
	host.add_child(sp7)
	sp7.set_process(false)
	sp7._mission_time = 60.0
	sp7._process(0.05)
	await get_tree().process_frame
	_check(_bosses().is_empty() and sp7.boss_sequence_done(), "sector 7 has no mini-boss")

	print("MiniBossTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
