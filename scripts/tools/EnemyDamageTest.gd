extends Node
## Headless: enemy fire damage grows gently by sector (x1.0 -> x1.35), heavy
## hits cost two shield pips, burst pellets are not scaled twice, and the
## difficulty hook multiplies everything.
## Run: godot --headless --path . res://scenes/tools/EnemyDamageTest.tscn

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


func _bullet(host: Node, dmg: int) -> EnemyBullet:
	var b: EnemyBullet = EnemyBullet.new()
	b.damage = dmg
	b.position = Vector2(-500, -500)
	b.direction = Vector2.DOWN
	host.add_child(b)
	return b


func _run() -> void:
	var host := Node2D.new()
	add_child(host)
	GameState.difficulty_damage_mul = 1.0

	GameState.current_level = 1
	_check(is_equal_approx(GameState.enemy_damage_mul(), 1.0), "sector 1 multiplier 1.0")
	_check(_bullet(host, 3).damage == 3 and _bullet(host, 9).damage == 9, "sector 1 shots unchanged (3, 9)")
	GameState.current_level = 4
	_check(_bullet(host, 3).damage == 3, "sector 4 grunt shot still 3 (gentle start)")
	GameState.current_level = 24
	_check(is_equal_approx(GameState.enemy_damage_mul(), 1.35), "sector 24 multiplier 1.35")
	_check(_bullet(host, 3).damage == 4 and _bullet(host, 6).damage == 8 and _bullet(host, 9).damage == 12,
			"sector 24: 3->4, 6->8, 9->12")
	GameState.current_level = 12
	var m12: float = GameState.enemy_damage_mul()
	_check(m12 > 1.1 and m12 < 1.25, "sector 12 in between (x%.2f)" % m12)

	# Fused shell: its burst pellets keep the scaled burst damage, no double scaling
	GameState.current_level = 24
	var shell: EnemyBullet = EnemyBullet.new()
	shell.damage = 6
	shell.burst_damage = 3
	shell.burst_count = 4
	shell.position = Vector2(-500, -500)
	host.add_child(shell)
	_check(shell.burst_damage == 4, "shell burst damage scaled once (3 -> 4)")
	shell._burst()
	await get_tree().process_frame
	var pellets: Array = host.get_children().filter(func(n): return n is EnemyBullet and n.style == EnemyBullet.Style.PELLET and n.damage_scaled and not n.is_queued_for_deletion())
	var ok_p: bool = pellets.size() >= 4
	for p in pellets:
		if p.damage != 4:
			ok_p = false
	_check(ok_p, "burst pellets do 4, not 5 (%d pellets)" % pellets.size())

	# Beam scales too
	var beam: EnemyBeam = EnemyBeam.new()
	beam.emitter = host
	beam.damage = 8
	host.add_child(beam)
	_check(beam.damage == 11, "sector 24 beam 8 -> 11 (got %d)" % beam.damage)
	beam.queue_free()

	# Heavy hits: same attacks heavy in every sector
	for lv in [1, 12, 24]:
		GameState.current_level = lv
		var lance: int = GameState.scale_enemy_damage(9)
		var beamd: int = GameState.scale_enemy_damage(8)
		var shellv: int = GameState.scale_enemy_damage(7)
		var tank: int = GameState.scale_enemy_damage(6)
		_check(GameState.is_heavy_hit(lance) and GameState.is_heavy_hit(beamd) and not GameState.is_heavy_hit(shellv) and not GameState.is_heavy_hit(tank),
				"sector %d: lance %d + beam %d heavy, shell %d + tank %d not" % [lv, lance, beamd, shellv, tank])

	# Shield pips on the real Player
	GameState.current_level = 24
	var pl: Player = Player.new()
	host.add_child(pl)
	await get_tree().process_frame
	pl.max_shield = 3
	pl.shield = 3.0
	var hp0: int = pl.hp
	pl._i_frame_timer = 0.0
	pl._take_damage(GameState.scale_enemy_damage(3))
	_check(is_equal_approx(pl.shield, 2.0) and pl.hp == hp0, "light hit: one pip, no hull")
	pl._i_frame_timer = 0.0
	pl._take_damage(GameState.scale_enemy_damage(9))
	_check(is_equal_approx(pl.shield, 0.0) and pl.hp == hp0, "heavy hit with 2 pips: both pips, no hull")
	pl.shield = 1.0
	pl._i_frame_timer = 0.0
	var lance24: int = GameState.scale_enemy_damage(9)
	pl._take_damage(lance24)
	_check(is_equal_approx(pl.shield, 0.0) and pl.hp == hp0 - int(ceil(lance24 * 0.5)), "heavy hit with 1 pip: half reaches the hull (%d)" % (hp0 - pl.hp))
	var hp1: int = pl.hp
	pl._i_frame_timer = 0.0
	pl._take_damage(lance24)
	_check(pl.hp == hp1 - lance24, "no shield: full hit")

	# Difficulty hook
	GameState.current_level = 1
	GameState.difficulty_damage_mul = 1.25
	_check(_bullet(host, 4).damage == 5, "difficulty x1.25 raises a 4 to 5")
	GameState.difficulty_damage_mul = 0.75
	_check(_bullet(host, 4).damage == 3, "difficulty x0.75 lowers a 4 to 3")
	GameState.difficulty_damage_mul = 1.0

	print("EnemyDamageTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
