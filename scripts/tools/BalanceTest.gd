extends Node
## Headless check of missile homing scaling and first-boss firepower.
## Run: godot --headless --path . res://scenes/tools/BalanceTest.tscn

var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _missile_at(p: Node, lvl: int) -> Missile:
	p.power_level = lvl
	p._spawn_missile(Vector2.ZERO, Vector2.UP, 10)
	return get_child(get_child_count() - 1) as Missile

func _boss(t: int) -> Node:
	var b: Node = load("res://scripts/Boss.gd").new()
	b.type = t
	add_child(b)
	return b

func _ready() -> void:
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(360, 1000)
	add_child(p)
	await get_tree().process_frame
	var low := _missile_at(p, 1)
	var mid := _missile_at(p, 13)
	var top := _missile_at(p, 25)
	print("turn rates L1=%.2f L13=%.2f L25=%.2f" % [low.turn_rate, mid.turn_rate, top.turn_rate])
	_check(is_equal_approx(low.turn_rate, 1.2), "L1 turn rate is the weak floor")
	_check(low.turn_rate < mid.turn_rate and mid.turn_rate < top.turn_rate, "turn rate rises with level")
	_check(is_equal_approx(top.turn_rate, 6.0), "L25 turn rate equals the old homing")
	_check(low.reacquire_radius < top.reacquire_radius, "re-lock range rises with level")
	var b1 := _boss(0)
	var b2 := _boss(1)
	await get_tree().process_frame
	_check(b1.fire_cd_mul > 1.0 and b1.bullet_dmg_mul < 1.0, "boss 1 fires slower and hits softer")
	_check(is_equal_approx(b2.fire_cd_mul, 1.0) and is_equal_approx(b2.bullet_dmg_mul, 1.0), "boss 2 unchanged")
	# --- Beam burn: heat, not instant ---
	var EB = load("res://scripts/EnemyBullet.gd")
	var survived_frame := 0
	var max_t := 0.0
	for i in 40:
		var eb: Node = EB.new()
		add_child(eb)
		if not eb.beam_burn(1.0 / 60.0):
			survived_frame += 1
		var tt := 1.0 / 60.0
		while not eb.beam_burn(1.0 / 60.0):
			tt += 1.0 / 60.0
		max_t = max(max_t, tt)
	print("beam: %d/40 survive one frame, slowest pop %.2fs" % [survived_frame, max_t])
	_check(survived_frame == 40, "no normal bullet pops on its first beam frame")
	_check(max_t <= 0.47, "every normal bullet pops within ~0.45s of beam")
	var shell: Node = EB.new()
	shell.style = 3  # SHELL
	add_child(shell)
	_check(shell.beam_resist >= 0.12 * 1.6 - 0.001, "heavy rounds resist longer")
	var bb: Node = EB.new()
	bb.from_boss = true
	add_child(bb)
	var popped := false
	for i in 120:
		popped = popped or bb.beam_burn(1.0 / 60.0)
	_check(not popped, "boss bullets stay beam-immune")
	# --- Early sector fire rate ---
	var EN = load("res://scripts/Enemy.gd")
	var saved_lvl: int = GameState.current_level
	GameState.current_level = 1
	var g1: Node = EN.new(); g1.type = 0; add_child(g1)
	GameState.current_level = 20
	var g20: Node = EN.new(); g20.type = 0; add_child(g20)
	await get_tree().process_frame
	print("grunt fire interval S1=%.2f S20=%.2f first shot S1=%.2f" % [g1.fire_interval, g20.fire_interval, g1._fire_timer])
	_check(g1.fire_interval >= 2.8 * 2.4 - 0.01, "sector 1 grunt fires 2.4x slower than base")
	_check(is_equal_approx(g20.fire_interval, 2.8 * 0.45), "sector 20 fire rate unchanged")
	_check(g1._fire_timer >= 0.9, "no instant first shot")
	GameState.current_level = 1
	_check(g1._light_volley(), "sector 1 uses light volleys")
	GameState.current_level = 5
	_check(not g1._light_volley(), "sector 5 back to full volleys")
	GameState.current_level = saved_lvl
	print("BALANCE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
