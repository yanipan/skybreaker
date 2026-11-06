extends Node
## Headless check: death sequence scene changes must not leave Main._process
## calling get_nodes_in_group on a null SceneTree.
## Parent this to the tree root; the DeathReloadTest scene is freed on load.

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("user_data=", OS.get_user_data_dir())
	var fails: int = 0
	fails += await _run_death_path(false)
	fails += await _run_death_path(true)
	# Still pumping frames after both scene changes.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS  process survived both death paths" if fails == 0 else "FAIL  a death path did not complete")
	print("DONE")
	get_tree().quit(fails)


## game_over_path: lives=1 so _finish_death_sequence change_scene's to StartScreen.
## otherwise lives>1 so it reload_current_scene's the stage.
func _run_death_path(game_over_path: bool) -> int:
	var label: String = "game over path" if game_over_path else "reload path"
	GameState.has_active_run = true
	GameState.current_level = 4
	GameState.intro_seen = true
	GameState.resume_pending = false
	GameState.pending_warp_entry = false
	GameState.lives = 1 if game_over_path else 3
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("_on_player_died"):
		print("FAIL  %s: Main.tscn did not become current_scene" % label)
		return 1
	var spawner: Node = main.get("_spawner")
	if spawner == null:
		print("FAIL  %s: no EnemySpawner on Main" % label)
		return 1
	spawner._mission_time = spawner.get_level_duration() + 10.0
	var fake_boss := Node2D.new()
	fake_boss.add_to_group(&"bosses")
	main.add_child(fake_boss)
	main._on_player_died()
	main._death_time_left = 0.05
	var frames: int = 180
	while is_instance_valid(main) and main.is_inside_tree() and frames > 0:
		await get_tree().process_frame
		frames -= 1
	# Reload/change_scene should have freed Main. If it is still the current
	# scene after 180 frames, the death sequence never finished.
	var still_same: bool = is_instance_valid(main) and main.is_inside_tree()
	if still_same:
		print("FAIL  %s: Main still in tree after death sequence" % label)
		return 1
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree() == null:
		print("FAIL  %s: SceneTree gone after death sequence" % label)
		return 1
	print("PASS  %s survived" % label)
	return 0
