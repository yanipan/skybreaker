extends Node
## Headless check: while a boss is alive, waves are <= 2 ships and spaced at
## max(_spawn_interval * 3, 9) s; after the boss dies the base cadence returns.
## Run: godot --headless --path . res://scenes/tools/BossPressureTest.tscn

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var fails: int = 0
	GameState.current_level = 4
	GameState.intro_seen = true

	var host := Node2D.new()
	add_child(host)

	var fake_boss := Node2D.new()
	fake_boss.add_to_group(&"bosses")
	host.add_child(fake_boss)

	var spawner: EnemySpawner = EnemySpawner.new()
	host.add_child(spawner)
	spawner.set_process(false)
	spawner._boss_spawned = true
	spawner._boss_enabled = false

	var boss_interval: float = max(spawner._spawn_interval * 3.0, 9.0)
	var cap: int = int(ceil(60.0 / boss_interval)) * 2
	print("BossPressure: spawn_interval=", spawner._spawn_interval,
			" boss_interval=", boss_interval, " cap=", cap)

	var dt: float = 0.05
	var t: float = 0.0
	var spawned_while_boss: int = 0
	var max_wave: int = 0
	while t < 60.0:
		var before: int = get_tree().get_nodes_in_group(&"enemies").size()
		spawner._process(dt)
		t += dt
		var n: int = get_tree().get_nodes_in_group(&"enemies").size() - before
		if n > 0:
			spawned_while_boss += n
			if n > max_wave:
				max_wave = n

	var r1: bool = spawned_while_boss <= cap
	var r2: bool = max_wave <= EnemySpawner.BOSS_WAVE_MAX
	print("%s  while boss alive: spawned=%d cap=%d" % ["PASS" if r1 else "FAIL", spawned_while_boss, cap])
	print("%s  while boss alive: max_wave=%d (limit %d)" % ["PASS" if r2 else "FAIL", max_wave, EnemySpawner.BOSS_WAVE_MAX])
	if not r1:
		fails += 1
	if not r2:
		fails += 1

	fake_boss.free()
	# Remaining boss-interval countdown may still be in flight; the spawn
	# AFTER that uses the base _spawn_interval.
	var gaps: Array[float] = []
	var last_wave_t: float = -1.0
	var t2: float = 0.0
	var max_wave_after: int = 0
	while t2 < 30.0:
		var before2: int = get_tree().get_nodes_in_group(&"enemies").size()
		spawner._process(dt)
		t2 += dt
		var n2: int = get_tree().get_nodes_in_group(&"enemies").size() - before2
		if n2 > 0:
			if n2 > max_wave_after:
				max_wave_after = n2
			if last_wave_t >= 0.0:
				gaps.append(t2 - last_wave_t)
			last_wave_t = t2

	var base: float = spawner._spawn_interval
	# First post-death gap can still be the leftover boss timer. Cadence is
	# back if any later gap matches the base interval.
	var cadence_back: bool = false
	for i in range(1, gaps.size()):
		if abs(gaps[i] - base) <= dt * 2.0:
			cadence_back = true
			break
	var r3: bool = cadence_back
	print("%s  after boss dies: cadence back (gaps=%s base=%.2f max_wave_after=%d)" % [
		"PASS" if r3 else "FAIL", str(gaps), base, max_wave_after])
	if not r3:
		fails += 1

	print("BOSS PRESSURE TEST DONE fails=%d" % fails)
	get_tree().quit(fails)
