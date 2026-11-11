extends Node2D
## Windowed look check: jinker mid-jink, beam tank, homing bomber, homing strafer.
## Saves user://evasion_shot.png and quits.
func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.02, 0.03, 0.08); bg.size = Vector2(816, 1452); add_child(bg)
	GameState.current_level = 16
	var specs := [[Enemy.Type.JINKER, Vector2(200, 300), &""], [Enemy.Type.JINKER, Vector2(600, 330), &""],
		[Enemy.Type.TANK, Vector2(220, 700), &"beam"], [Enemy.Type.BOMBER, Vector2(600, 720), &"homing"],
		[Enemy.Type.LANCER, Vector2(400, 1050), &"beam"], [Enemy.Type.TANK, Vector2(650, 1100), &""]]
	var first: Enemy = null
	for sp in specs:
		var e: Enemy = Enemy.new()
		e.type = sp[0]; e.position = sp[1]; e.alt_pattern = sp[2]
		add_child(e)
		e.set_process(false)
		if first == null: first = e
	var b := Node2D.new(); b.add_to_group(&"player_bullets"); b.position = Vector2(205, 480); add_child(b)
	for i in 30:
		await get_tree().process_frame
	first._process(0.016); first._process(0.016); first._process(0.016)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://evasion_shot.png")
	get_tree().quit()
