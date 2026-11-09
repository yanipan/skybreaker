extends Node
## See ShopExitTest.gd.

var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var backups: Dictionary = {}
	for f in ["user://savegame.dat", "user://savegame.bak"]:
		if FileAccess.file_exists(f):
			backups[f] = FileAccess.get_file_as_bytes(f)
	GameState.begin_run(99)
	GameState.current_level = 6
	GameState.intro_seen = true
	GameState.has_active_run = true
	GameState.pending_warp_entry = false
	GameState.pending_story_key = &""
	GameState.resume_pending = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var main: Node = get_tree().current_scene
	var player := get_tree().get_first_node_in_group(&"player")
	var base: Node = load("res://scripts/Starbase.gd").new()
	base.position = Vector2(400, 400)
	main.add_child(base)
	await get_tree().process_frame
	base._open_shop(player)
	await get_tree().process_frame
	var shop: Node = null
	for c in get_tree().root.get_children():
		if c.get_script() == load("res://scripts/StarbaseShop.gd"):
			shop = c
	_check(shop != null and get_tree().paused, "shop open pauses the game")
	if shop != null:
		shop._on_leave()
	await get_tree().process_frame
	_check(get_tree().paused, "still paused right after LEAVE")
	_check(main._resume_countdown_active, "GET READY countdown is running")
	_check(not main._can_open_pause(), "pause menu refused during the countdown")
	var t0: int = Time.get_ticks_msec()
	while get_tree().paused and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	var waited: float = float(Time.get_ticks_msec() - t0) / 1000.0
	_check(not get_tree().paused and not main._resume_countdown_active, "game resumes after the countdown")
	_check(waited > 2.5 and waited < 4.5, "breather is about 3 seconds (%.1f s)" % waited)
	print("ShopExitTest: %d failure(s)" % _fails)
	for f in backups:
		var w := FileAccess.open(f, FileAccess.WRITE)
		w.store_buffer(backups[f])
		w.close()
	get_tree().quit(1 if _fails > 0 else 0)
