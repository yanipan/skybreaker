extends Node
## Headless check of the multi-part boss framework on the IRON TORTOISE.
## Run: godot --headless --path . res://scenes/tools/BossPartsTest.tscn

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


func _bullets() -> int:
	return get_tree().get_nodes_in_group(&"enemy_bullets").size()


func _run() -> void:
	GameState.current_level = 8
	var host := Node2D.new()
	add_child(host)
	var boss: Boss = Boss.new()
	boss.type = Boss.Type.BOSS2
	boss.position = Vector2(360, 300)
	host.add_child(boss)
	await get_tree().process_frame

	var parts: Array = boss.live_parts()
	var plates: Array = parts.filter(func(p): return p.shields_core)
	var turrets: Array = parts.filter(func(p): return p.kind == BossPart.Kind.TURRET)
	_check(parts.size() == 7, "tortoise has 7 parts (got %d)" % parts.size())
	_check(plates.size() == 3 and turrets.size() == 4, "3 shell plates + 4 turrets")
	_check(not boss.is_in_group(&"boss_parts") and parts[0].is_in_group(&"enemies") and parts[0].is_in_group(&"boss_parts") and not parts[0].is_in_group(&"bosses"),
			"parts are enemies + boss_parts, not bosses")
	_check(HitCheck.half_extents(parts[0]) == parts[0].hit_half, "HitCheck uses the part box")
	_check(HitCheck.half_extents(boss) == boss.hit_half and boss.hit_half.x < boss.boss_size * 0.3, "core box is small on the tortoise")
	_check(boss.core_shielded(), "core shielded while plates stand")

	# Shielded core: 100 hits of 20 dmg ~ 15% of (20 - armor 4) each
	var hp0: int = boss.hp
	for i in 100:
		boss.take_damage(20)
	var lost: int = hp0 - boss.hp
	_check(lost > 150 and lost < 330, "shielded core takes ~15%% (lost %d of %d raw)" % [lost, 1600])

	# Missile + ram multipliers treat parts like the boss
	var m: Missile = preload("res://scripts/Missile.gd").new()
	m.damage = 20
	_check(m.damage_against(parts[0]) == 18, "missile does 90% to a part")
	m.free()

	# Turrets fire once the boss is in position
	boss._entry_done = true
	var b0: int = _bullets()
	for i in 240:
		for t in turrets:
			t._process(1.0 / 60.0)
	_check(_bullets() > b0, "turrets fire on their own (%d bullets)" % (_bullets() - b0))
	_check(boss.part_cd_mul() == 1.0 * boss.fire_cd_mul, "phase 0 part cadence")

	# Kill one turret: wreck stays, out of the enemy group, money drops
	var money_before: int = get_tree().get_nodes_in_group(&"pickups").size()
	turrets[0].take_damage(9999)
	await get_tree().process_frame
	_check(not turrets[0].alive and not turrets[0].is_in_group(&"enemies") and is_instance_valid(turrets[0]), "dead turret becomes a wreck")
	_check(get_tree().get_nodes_in_group(&"pickups").size() > money_before, "dead turret drops money")
	var tb: int = _bullets()
	for i in 300:
		turrets[0]._process(1.0 / 60.0)
	_check(_bullets() == tb, "wrecked turret no longer fires")

	# Crack the shell
	var armor_before: int = boss.armor
	var speed_before: float = boss._drift_speed
	for p in plates:
		p.take_damage(9999)
	_check(boss.shell_broken and not boss.core_shielded(), "all plates down = shell cracked")
	_check(boss.armor < armor_before and boss._drift_speed > speed_before, "cracked shell: less armor, faster")
	var hp1: int = boss.hp
	boss.take_damage(20)
	_check(hp1 - boss.hp == 20 - boss.armor, "exposed core takes full damage")

	# Death clears the remaining parts
	var live_turrets: Array = boss.live_parts()
	boss.take_damage(99999)
	await get_tree().process_frame
	var all_gone: bool = true
	for p in live_turrets:
		if is_instance_valid(p) and p.alive:
			all_gone = false
	_check(all_gone, "boss death destroys the remaining parts")
	_check(get_tree().get_nodes_in_group(&"boss_parts").is_empty(), "no boss_parts left after death")

	# Single-body bosses are unchanged
	var hq: Boss = Boss.new()
	hq.type = Boss.Type.BOSS1
	host.add_child(hq)
	await get_tree().process_frame
	_check(hq.live_parts().is_empty() and not hq.core_shielded(), "hornet queen has no parts")
	_check(HitCheck.half_extents(hq) == Vector2(hq.boss_size * 0.425, hq.boss_size * 0.375), "old bosses keep their box")

	print("BossPartsTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
