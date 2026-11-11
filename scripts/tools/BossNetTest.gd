extends Node
## Headless, no network: feeds NetClient the server's boss messages directly.
## The phone's Iron Tortoise is a puppet — snapshots own its HP and its
## parts, hits are reported, and it dies only on KILL.
## Run: godot --headless --path . res://scenes/tools/BossNetTest.tscn
## (the runner must also see no "SCRIPT ERROR" in the output)

var _fails: int = 0
var _passes: int = 0
var _n: int = 0
var _part_keys: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_n += 1
	if ok:
		_passes += 1
		print("PASS  %d. %s" % [_n, what])
	else:
		_fails += 1
		print("FAIL  %d. %s" % [_n, what])


func _ready() -> void:
	call_deferred("_run")


func _silence(boss: Boss) -> void:
	boss.set_process(false)
	for p in boss._parts:
		(p as Node).set_process(false)


func _bullet_count(world: Node) -> int:
	var n: int = 0
	for c in world.get_children():
		if c is EnemyBullet:
			n += 1
	return n


## Part ids in _parts order, the same order a SPAWN "parts" map is applied in.
func _learn_part_ids() -> void:
	var holder := Node.new()
	add_child(holder)
	var probe := Boss.new()
	probe.type = Boss.Type.BOSS2
	probe.set_process(false)
	holder.add_child(probe)
	_part_keys.clear()
	for p in probe._parts:
		p.set_process(false)
		_part_keys.append(String(p.part_id))
	probe.free()
	holder.free()


func _part_map(start_id: int) -> Dictionary:
	var parts := {}
	var id := start_id
	for key in _part_keys:
		parts[key] = id
		id += 1
	return parts


func _spawn_tortoise(nc: NetClient, id: int, pos: Vector2, mini: bool, mh: int, part_start: int) -> Boss:
	nc._on_msg(0, [Net.M.SPAWN, id, "boss", {
		"p": pos,
		"t": Boss.Type.BOSS2,
		"mi": mini,
		"hs": 1.0,
		"nm": "",
		"mh": mh,
		"parts": _part_map(part_start),
	}])
	var boss: Boss = nc.puppets[id]
	_silence(boss)
	return boss


func _snap(nc: NetClient, t: float, rows: Array) -> void:
	var ids := PackedInt32Array()
	var xy := PackedFloat32Array()
	var fl := PackedByteArray()
	var hp := PackedByteArray()
	for row in rows:
		ids.append(int(row[0]))
		xy.append(float(row[1]))
		xy.append(float(row[2]))
		fl.append(int(row[3]))
		hp.append(int(row[4]))
	nc._on_msg(0, [Net.M.SNAP, t, ids, xy, fl, hp])


func _run() -> void:
	GameState.current_level = 8
	Net.mode = Net.Mode.CLIENT
	Net.my_peer = 1
	var world := Node2D.new()
	add_child(world)
	var nc := NetClient.new()
	nc.world = world
	nc.ship_state = func() -> Dictionary: return {}
	add_child(nc)
	nc.set_process(false)

	_learn_part_ids()
	var part_ids := _part_map(101)
	var boss := _spawn_tortoise(nc, 50, Vector2(400, 200), false, 999, 101)

	var spawn_ok := nc.puppets.has(50) and boss.net_puppet and boss.net_id == 50
	var part_bits := ""
	for p in boss._parts:
		var expect: int = int(part_ids.get(String(p.part_id), -1))
		if p.net_id != expect or not nc.puppets.has(p.net_id):
			spawn_ok = false
			part_bits += " %s net_id=%d expect=%d in_table=%s" % [String(p.part_id), p.net_id, expect, nc.puppets.has(p.net_id)]
	_check(spawn_ok and boss._parts.size() == _part_keys.size() and not _part_keys.is_empty(),
			"SPAWN 50 at (400, 200): puppet net_id 50, every part id is in the table%s" % part_bits)
	_check(boss.max_hp == 999 and boss.hp == 999, "SPAWN mh 999: max_hp=%d hp=%d" % [boss.max_hp, boss.hp])

	boss._entry_done = false
	var pos0: Vector2 = boss.position
	for _i in 4:
		boss._process(0.5)
	_check(boss.position == pos0, "puppet does not move itself (y %.1f -> %.1f)" % [pos0.y, boss.position.y])

	boss._entry_done = true
	var bullets0: int = _bullet_count(world)
	for _i in 10:
		boss._process(1.0)
	for p in boss._parts:
		for _j in 10:
			p._process(1.0)
	var bullets1: int = _bullet_count(world)
	_check(bullets1 == bullets0, "puppet and its parts fire nothing (%d -> %d EnemyBullet)" % [bullets0, bullets1])

	var hp_before: int = boss.hp
	boss.take_damage(50)
	_check(boss.hp == hp_before and int(Net._hits.get(50, 0)) == 50,
			"core hit is reported, hp stays %d (hits=%s)" % [boss.hp, str(Net._hits.get(50, 0))])

	var part0: BossPart = boss._parts[0]
	var part0_hp: int = part0.hp
	var part0_id: int = part0.net_id
	part0.take_damage(20)
	_check(part0.hp == part0_hp and int(Net._hits.get(part0_id, 0)) == 20,
			"first part hit is reported, hp stays %d (id %d hits=%s)" % [part0.hp, part0_id, str(Net._hits.get(part0_id, 0))])

	_snap(nc, 10.0, [[50, 400.0, 200.0, 0, 128]])
	_check(absf(float(boss.hp) - float(boss.max_hp) / 2.0) <= 4.0,
			"SNAP hp byte 128: hp %d within 4 of max/2 (%.1f)" % [boss.hp, float(boss.max_hp) / 2.0])

	var score_parts: int = GameState.run_score
	var broken: BossPart = null
	for p in boss._parts:
		if p.shields_core and p.alive:
			broken = p
			break
	if broken != null:
		_snap(nc, 20.0, [[broken.net_id, 0.0, 0.0, 2, 255]])
	var others_alive := true
	for p in boss._parts:
		if p == broken:
			continue
		if not p.alive:
			others_alive = false
	_check(broken != null and not broken.alive and not broken.is_in_group(&"enemies") and others_alive,
			"one shields_core part broken by SNAP flag 2 (alive=%s in enemies=%s)" % [
				str(broken.alive) if broken != null else "missing",
				str(broken.is_in_group(&"enemies")) if broken != null else "missing"])

	var shield_before := false
	for p in boss._parts:
		if p.shields_core and p.alive:
			shield_before = true
	shield_before = shield_before and boss.core_shielded()
	var break_rows: Array = []
	for p in boss._parts:
		if p.shields_core:
			break_rows.append([p.net_id, 0.0, 0.0, 2, 255])
	_snap(nc, 30.0, break_rows)
	_check(shield_before and not boss.core_shielded() and boss.shell_broken,
			"shell holds while a plate lives, then cracks (before=%s shielded=%s shell_broken=%s)" % [
				shield_before, boss.core_shielded(), boss.shell_broken])
	_check(GameState.run_score == score_parts,
			"parts broken on a puppet give no score (%d -> %d)" % [score_parts, GameState.run_score])

	var t0 := 100.0
	var t1 := 100.05
	_snap(nc, t0, [[50, 400.0, 200.0, 0, 255]])
	_snap(nc, t1, [[50, 400.0, 210.0, 0, 255]])
	nc._offset = t1 - nc._now() + NetClient.INTERP - 0.025
	nc._process(0.016)
	_check(absf(boss.position.y - 205.0) <= 1.5, "interpolated y=%.2f within 1.5 of 205" % boss.position.y)

	var reward: int = boss.reward
	var score_kill: int = GameState.run_score
	nc._on_msg(0, [Net.M.KILL, 50, 1, 500])
	_check(GameState.run_score == score_kill + reward and boss.is_queued_for_deletion() and not nc.puppets.has(50),
			"my KILL adds reward %d (score %d -> %d), queued=%s, table has 50=%s" % [
				reward, score_kill, GameState.run_score, boss.is_queued_for_deletion(), nc.puppets.has(50)])

	await get_tree().process_frame
	await get_tree().process_frame
	var parts_left := ""
	for key in _part_keys:
		var pid: int = int(part_ids[key])
		if nc.puppets.has(pid):
			parts_left += " %d" % pid
	_check(parts_left == "", "part ids leave the table after the boss frees%s" % parts_left)

	_spawn_tortoise(nc, 60, Vector2(400, 200), false, 999, 201)
	var score_partner: int = GameState.run_score
	nc._on_msg(0, [Net.M.KILL, 60, 2, 500])
	_check(GameState.run_score == score_partner,
			"partner KILL adds no score (%d -> %d)" % [score_partner, GameState.run_score])

	var mini := _spawn_tortoise(nc, 70, Vector2(300, 180), true, 999, 301)
	var full := _spawn_tortoise(nc, 71, Vector2(500, 180), false, 999, 401)
	_check(mini.mini == true and mini.boss_size < full.boss_size,
			"mini boss is smaller (mini=%s size %.1f < %.1f)" % [mini.mini, mini.boss_size, full.boss_size])

	Net.mode = Net.Mode.OFF
	print("BossNetTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
