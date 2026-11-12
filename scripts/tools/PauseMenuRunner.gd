extends Node
## See PauseMenuTest.gd. Lives on the root because change_scene frees the scene.
var _fails: int = 0
var _passes: int = 0


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if ok: _passes += 1
	else: _fails += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _find(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n
	return null


func _start_run() -> Node:
	GameState.begin_run(777)
	GameState.current_level = 1
	GameState.lives = 3
	GameState.intro_seen = true
	GameState.has_active_run = true
	GameState.pending_warp_entry = false
	GameState.pending_story_key = &""
	GameState.resume_pending = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	for i in 30:
		await get_tree().process_frame
	return get_tree().current_scene


func _run() -> void:
	# The real GameState saves: keep the developer's own save and put it back.
	var backups: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak"]:
		if FileAccess.file_exists(f):
			backups[f] = FileAccess.get_file_as_bytes(f)

	# --- A phone that cannot close the app (iOS) ---
	GameState.app_can_quit = false
	var main: Node = await _start_run()
	main._open_pause()
	await get_tree().process_frame
	_check(get_tree().paused, "single player: the pause menu freezes the game")
	_check(_find(main, "RESUME") != null and _find(main, "MAIN MENU") != null, "RESUME and MAIN MENU are there")
	_check(_find(main, "QUIT") == null, "no QUIT button where the app cannot close itself")
	_find(main, "MAIN MENU").pressed.emit()
	for i in 20:
		await get_tree().process_frame
	var cur: Node = get_tree().current_scene
	_check(cur != null and cur.scene_file_path.ends_with("StartScreen.tscn"), "MAIN MENU leaves the run for the start screen (%s)" % [cur.scene_file_path if cur != null else "none"])
	_check(not get_tree().paused, "and the game is not left paused")
	_check(cur != null and _find(cur, "EXIT") == null, "start screen: no EXIT button where the app cannot close itself")
	_check(cur != null and _find(cur, "NEW GAME") != null or cur != null and cur.find_children("*", "Button", true, false).size() >= 3, "start screen still has its other buttons")

	# A stray QUIT press there must not unpause the fight behind the menu.
	main = await _start_run()
	main._open_pause()
	await get_tree().process_frame
	main._on_quit_app()
	for i in 20:
		await get_tree().process_frame
	cur = get_tree().current_scene
	_check(cur != null and cur.scene_file_path.ends_with("StartScreen.tscn"), "a quit that cannot close the app leaves to the start screen instead")

	# --- Everywhere else the buttons stay ---
	GameState.app_can_quit = true
	main = await _start_run()
	main._open_pause()
	await get_tree().process_frame
	_check(_find(main, "QUIT") != null, "Android / desktop: QUIT is still on the pause menu")
	_find(main, "RESUME").pressed.emit()
	await get_tree().process_frame
	_check(not get_tree().paused, "RESUME unfreezes the game")
	_find_and_leave(main)
	for i in 20:
		await get_tree().process_frame
	cur = get_tree().current_scene
	_check(cur != null and _find(cur, "EXIT") != null, "Android / desktop: EXIT is still on the start screen")

	for f in backups:
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_buffer(backups[f])
		fa.close()
	print("PauseMenuTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _find_and_leave(main: Node) -> void:
	main._open_pause()
	await get_tree().process_frame
	_find(main, "MAIN MENU").pressed.emit()
