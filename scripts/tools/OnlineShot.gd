extends Node
## Windowed captures of the online overlays (live data, test player id).
func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(720, 1560)
	Telemetry.player_id = "00000000-0000-4000-8000-000000000003"
	Online.allow_debug = true
	GameState.last_run = {"score": 12340, "sector": 6, "won": false, "ranked": true, "token": "x", "rank_all": 3, "rank_week": 1, "challenge_name": "GodotTest_3", "challenge_target": 9000}
	var ss: Node = load("res://scenes/main/StartScreen.tscn").instantiate()
	add_child(ss)
	await get_tree().create_timer(1.5).timeout
	await _shot(out + "/ui_lastrun.png")
	ss._online_ui.open_leaderboard()
	await get_tree().create_timer(3.0).timeout
	await _shot(out + "/ui_board.png")
	ss._online_ui.open_name_prompt()
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/ui_name.png")
	ss._online_ui.open_code_entry()
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/ui_code.png")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
