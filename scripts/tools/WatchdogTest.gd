extends Node
## Headless check of PhysicsWatchdog (dev-only, excluded from exports).
## Run: godot --headless --path . res://scenes/tools/WatchdogTest.tscn
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])

func _bullet_hits() -> bool:
	var enemy: Area2D = load("res://scripts/Enemy.gd").new()
	enemy.position = Vector2(300, 300)
	add_child(enemy)
	var hp0: int = enemy.hp
	var bullet: Area2D = load("res://scripts/Bullet.gd").new()
	bullet.position = Vector2(300, 400)
	add_child(bullet)
	await get_tree().create_timer(0.35).timeout
	var hit: bool = not is_instance_valid(bullet) or not is_instance_valid(enemy) or enemy.hp < hp0
	if is_instance_valid(bullet): bullet.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()
	return hit

func _ready() -> void:
	await _bullet_hits()  # warm-up: first Enemy load hitches and the fast bullet tunnels past it
	var wd := PhysicsWatchdog.new()
	var fired := [0]
	wd.unrecovered.connect(func() -> void: fired[0] += 1)
	add_child(wd)
	await get_tree().create_timer(4.0).timeout
	_check(wd.overlap_ok and GameState.physics_stalls == 0, "healthy physics: no stall, no false positive")
	_check(await _bullet_hits(), "baseline: bullet hits enemy")
	# A real pause must never count as a stall.
	get_tree().paused = true
	await get_tree().create_timer(5.0, true).timeout
	get_tree().paused = false
	await get_tree().create_timer(2.0).timeout
	_check(GameState.physics_stalls == 0, "5 s pause is not a stall")
	# Kill overlap detection with the tree unpaused: the reported symptom.
	PhysicsServer2D.set_active(false)
	_check(not await _bullet_hits(), "server off: bullet passes through (symptom reproduced)")
	await get_tree().create_timer(5.0).timeout
	_check(GameState.physics_stalls >= 1, "watchdog noticed the stall (%d)" % GameState.physics_stalls)
	_check(await _bullet_hits(), "watchdog healed: bullet hits enemy again")
	_check(fired[0] == 0, "no reload needed when set_active heals it")
	# Second stall with the heal already spent asks Main to reload.
	PhysicsServer2D.set_active(false)
	await get_tree().create_timer(1.6).timeout  # past any test still reporting a pre-kill overlap
	wd._healed = true
	await get_tree().create_timer(5.0).timeout
	_check(fired[0] >= 1, "unhealed stall emits unrecovered (%d)" % fired[0])
	PhysicsServer2D.set_active(true)
	wd.queue_free()
	var runner: Node = load("res://scripts/tools/WatchdogMainRunner.gd").new()
	runner.prior_fails = _fails
	get_tree().root.add_child.call_deferred(runner)
