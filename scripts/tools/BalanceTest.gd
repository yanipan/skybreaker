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
	print("BALANCE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
