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
	# --- Missile damage trimmed ~12% (7/11) ---
	p.power_level = 1
	var md1: int = p.missile_damage()
	p.power_level = 25
	var md25: int = p.missile_damage()
	print("missile damage L1=%d L25=%d" % [md1, md25])
	_check(md1 == 10, "L1 missile damage trimmed to 10 (was 11), got %d" % md1)
	_check(md25 == 36, "L25 missile damage trimmed to 36 (was 41), got %d" % md25)
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
	_check(max_t <= 0.14, "every normal bullet pops within ~0.12s of beam")
	var shell: Node = EB.new()
	shell.style = 3  # SHELL
	add_child(shell)
	_check(shell.beam_resist >= 0.03 * 1.4 - 0.001, "heavy rounds resist longer")
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
	GameState.current_level = 7
	_check(g1._light_volley(), "pirate sectors (through 7) keep light volleys")
	GameState.current_level = 8
	_check(not g1._light_volley(), "sector 8 back to full volleys")
	# --- Pirate sectors thinned (7/11) ---
	var s6: Dictionary = Levels.get_level(6)
	var s7: Dictionary = Levels.get_level(7)
	_check(int(s6["wave_size_max"]) <= 5 and float(s6["spawn_interval"]) >= 3.6, "sector 6 waves <=5 every >=3.6s")
	_check(int(s7["wave_size_max"]) <= 5 and float(s7["spawn_interval"]) >= 3.4, "sector 7 waves <=5 every >=3.4s")
	_check(float(Levels.get_level(5)["spawn_interval"]) >= float(s6["spawn_interval"]) and float(s6["spawn_interval"]) >= float(s7["spawn_interval"]), "cadence still tightens 5 -> 6 -> 7")
	# --- Drop economy + shop caps (6/11) ---
	GameState.current_level = 1
	p.weapon_levels = {0: 4, 1: 4, 2: 4}
	var capped := 0
	for i in 60:
		if Pickup.roll_power_drop(get_tree()) < 0:
			capped += 1
	_check(capped == 60, "sector 1: weapons at L4 get money, not power (%d/60)" % capped)
	p.weapon_levels = {0: 1, 1: 3, 2: 2}
	_check(Pickup.boss_power_drop(get_tree()) == Pickup.Type.POWER_PHASER, "boss drops power for the weakest weapon")
	p.weapon_levels = {0: 4, 1: 4, 2: 4}
	_check(Pickup.boss_power_drop(get_tree()) == -1, "boss drops no power when all are capped")
	GameState.current_level = 20
	_check(Pickup.roll_power_drop(get_tree()) >= 0, "sector 20 under cap still drops power")
	_check(Pickup.ENEMY_POWER_DROP_SCALE < 1.0 and Pickup.ASTEROID_POWER_DROP_SCALE < 1.0, "power drop rates scaled down")
	p.energy_cells_bought = 0
	var r0: float = p.regen_mul()
	for i in 6:
		_check(p.buy_energy_cell(), "energy cell %d buyable" % (i + 1))
	_check(not p.buy_energy_cell(), "7th energy cell refused")
	_check(p.regen_mul() > r0 + 0.8, "6 cells regen x%.2f" % p.regen_mul())
	_check(is_equal_approx(p.max_charge, 100.0 * 3.4), "6 cells capacity %.0f" % p.max_charge)
	_check(Player.TORPEDO_CAP == 8, "torpedo cap is 8")
	GameState.current_level = saved_lvl
	print("BALANCE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
