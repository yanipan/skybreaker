extends Node
## Headless check: CONTINUE never replays the intro and runs the countdown.
## Body of ResumeTest; parented to the tree root by ResumeTest.gd so
## change_scene_to_file() does not free it mid-await.

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var fails: int = 0
	# Fresh level-1 run saved before the intro finished.
	GameState.has_active_run = true
	GameState.current_level = 1
	GameState.intro_seen = false
	GameState.resume_pending = true
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var main: Node = get_tree().current_scene
	var r1: bool = not main._cutscene_active
	var r2: bool = main._resume_countdown_active and get_tree().paused
	var r3: bool = GameState.intro_seen and not GameState.resume_pending
	for pair in [[r1, "no intro cutscene on continue"], [r2, "countdown active + tree paused"], [r3, "intro_seen set, resume flag consumed"]]:
		print("%s  %s" % ["PASS" if pair[0] else "FAIL", pair[1]])
		if not pair[0]: fails += 1
	await get_tree().create_timer(3.6, true).timeout
	var r4: bool = not main._resume_countdown_active and not get_tree().paused
	print("%s  countdown finished, tree running" % ["PASS" if r4 else "FAIL"])
	if not r4: fails += 1
	# Control: a brand-new game on level 1 still gets the intro.
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.intro_seen = false
	GameState.resume_pending = false
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var r5: bool = get_tree().current_scene._cutscene_active
	print("%s  new game still plays intro" % ["PASS" if r5 else "FAIL"])
	if not r5: fails += 1
	print("RESUME TEST DONE fails=%d" % fails)
	get_tree().quit(fails)
