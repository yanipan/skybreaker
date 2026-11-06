extends Node
## Windowed capture of the start screen Settings overlay.
func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(720, 1560)
	var ss: Node = load("res://scenes/main/StartScreen.tscn").instantiate()
	add_child(ss)
	for i in 30:
		await get_tree().process_frame
	ss._open_settings()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/settings.png")
	get_tree().quit()
