extends Node
## Headless: act story slides play AFTER the warp, on arrival in the next
## sector, before it starts: Main loads with the entry fly-in under the
## cutscene, spawns stay frozen while the slides are up, and the fly-in then
## finishes and starts the sector. Sector-5 completion no longer opens a
## cutscene before the warp; it only queues the story key.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	GameState.intro_seen = true
	GameState.resume_pending = false
	GameState.current_level = 6
	GameState.pending_warp_entry = true
	GameState.pending_story_key = CutsceneData.TRIGGERS[5]
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	var cs: Node = null
	for c in main.get_children():
		if c is Cutscene:
			cs = c
	_check(cs != null, "act cutscene opens on arrival in sector 6")
	_check(main._cutscene_active and main._entry_active, "fly-in is waiting under the slides")
	_check(GameState.pending_story_key == &"", "story key consumed (plays once)")
	_check(main._spawner != null and not main._spawner.is_processing(), "no spawns while the slides are up")
	if cs != null:
		cs.finished.emit()
		cs.queue_free()
		get_tree().paused = false
	await get_tree().process_frame
	_check(not main._cutscene_active, "slides dismissed")
	_check(main._entry_active and not main._spawner.is_processing(), "fly-in still owns the spawner after the slides")
	await get_tree().create_timer(main._entry_total + 0.5).timeout
	_check(not main._entry_active and main._spawner.is_processing(), "fly-in done, sector running")
	print("StoryAfterWarpTest done, fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
