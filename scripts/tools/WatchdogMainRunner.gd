extends Node
## Second half of WatchdogTest, on the real Main.tscn. Lives on root because a
## scene change frees the current scene.
var prior_fails: int = 0
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])

func _main() -> Node:
	return get_tree().current_scene

func _wait_main() -> void:
	for i in 30:
		await get_tree().process_frame

func _shots() -> int:
	return get_tree().get_nodes_in_group(&"player_bullets").size()

func _ready() -> void:
	GameState.intro_seen = true
	GameState.current_level = 1
	GameState.lives = 3
	GameState.has_active_run = true
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await _wait_main()
	# Reload path after an unrecoverable stall.
	var old: Node = _main()
	old._on_physics_unrecovered()
	await _wait_main()
	_check(_main() != old and is_instance_valid(_main()), "unrecovered stall reloads the sector")
	_check(GameState.physics_reloads == 1 and GameState.lives == 3, "reload is counted and costs no life")
	GameState.physics_reloads = 2
	var same: Node = _main()
	same._on_physics_unrecovered()
	await _wait_main()
	_check(_main() == same, "reload cap: never loops past 2 per launch")
	# Fire lock across a real warp.
	var p: Node = get_tree().get_first_node_in_group(&"player")
	p._grant_sidekick()
	await get_tree().process_frame
	await get_tree().process_frame
	p._is_firing = true
	await get_tree().create_timer(0.3).timeout
	_check(_shots() > 0, "firing before warp (%d shots)" % _shots())
	_main()._begin_warp_transition()
	await get_tree().process_frame
	await get_tree().process_frame
	var most: int = 0
	var level_before: int = GameState.current_level
	while GameState.current_level == level_before:
		most = maxi(most, _shots())
		await get_tree().process_frame
	_check(most == 0, "no shots during warp out, sidekick included (max %d)" % most)
	await get_tree().process_frame
	await get_tree().process_frame
	var np: Node = get_tree().get_first_node_in_group(&"player")
	np._is_firing = true
	most = 0
	while _main()._entry_active:
		most = maxi(most, _shots())
		await get_tree().process_frame
	_check(most == 0, "no shots during warp in (max %d)" % most)
	await get_tree().create_timer(0.3).timeout
	_check(_shots() > 0, "firing returns after warp in (%d shots)" % _shots())
	GameState.physics_reloads = 0
	GameState.physics_stalls = 0
	print("WATCHDOG TEST DONE fails=%d" % (_fails + prior_fails))
	get_tree().quit(_fails + prior_fails)
