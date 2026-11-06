extends Node
## Windowed capture of the touch overlay on both sides (needs a window).
## godot --path . res://scenes/tools/ControlsShot.tscn -- --out=/abs/dir
func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(720, 1560)
	for side in [0, 1]:
		GameState.controls_side = side
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.03, 0.08)
		bg.size = Vector2(720, 1560)
		add_child(bg)
		GameState.joystick_enabled = true
		var pl: Node = load("res://scripts/Player.gd").new()
		pl.position = Vector2(360, 1100)
		bg.add_child(pl)
		var mc: CanvasLayer = load("res://scripts/MobileControls.gd").new()
		mc.force_visible = true
		add_child(mc)
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/controls_side%d.png" % [out, side])
		mc.queue_free()
		bg.queue_free()
		await get_tree().process_frame
	get_tree().quit()
