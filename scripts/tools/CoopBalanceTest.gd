extends Node
## Headless: co-op HP scaling. One ship = exactly the single-player numbers;
## two ships flying = enemies x1.5, bosses and their parts x1.7.
## Run: godot --headless --path . res://scenes/tools/CoopBalanceTest.tscn

var _fails: int = 0
var _passes: int = 0
var _n: int = 0


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


func _enemy_hp(type: int) -> int:
	var e := Enemy.new()
	e.type = type
	add_child(e)
	var hp: int = e.max_hp
	e.set_meta("silent", true)
	e.queue_free()
	return hp


func _boss(type: int) -> Array:
	var b := Boss.new()
	b.type = type
	add_child(b)
	b.set_process(false)
	var parts: int = 0
	for p in b._parts:
		(p as Node).set_process(false)
		parts += int(p.max_hp)
	var out: Array = [b.max_hp, parts]
	b.queue_free()
	return out


func _run() -> void:
	GameState.current_level = 10
	GameState.coop_players = 1
	_check(is_equal_approx(GameState.coop_enemy_hp_mul(), 1.0) and is_equal_approx(GameState.coop_boss_hp_mul(), 1.0), "one ship: no scaling at all (single-player untouched)")
	var solo: Array = []
	for t in [Enemy.Type.GRUNT, Enemy.Type.TANK, Enemy.Type.HUNTER]:
		solo.append(_enemy_hp(t))
	var boss_solo: Array = _boss(Boss.Type.BOSS2)
	GameState.coop_players = 2
	var duo: Array = []
	for t in [Enemy.Type.GRUNT, Enemy.Type.TANK, Enemy.Type.HUNTER]:
		duo.append(_enemy_hp(t))
	var boss_duo: Array = _boss(Boss.Type.BOSS2)
	for i in solo.size():
		var r: float = float(duo[i]) / float(solo[i])
		_check(absf(r - 1.5) < 0.13, "two ships: enemy %d has x1.5 HP (%d -> %d)" % [i, solo[i], duo[i]])
	_check(absf(float(boss_duo[0]) / float(boss_solo[0]) - 1.7) < 0.02, "two ships: boss core x1.7 HP (%d -> %d)" % [boss_solo[0], boss_duo[0]])
	_check(boss_solo[1] > 0 and absf(float(boss_duo[1]) / float(boss_solo[1]) - 1.7) < 0.05, "two ships: boss parts x1.7 HP (%d -> %d)" % [boss_solo[1], boss_duo[1]])
	GameState.coop_players = 1
	_check(_enemy_hp(Enemy.Type.TANK) == solo[1], "back to one ship (partner down): single-player HP again")
	print("CoopBalanceTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
