extends Node2D
## Windowed look-check of a boss as the game draws it, with parts.
## Three copies of the IRON TORTOISE: intact, turrets damaged/one dead,
## shell cracked. Saves user://boss_shot.png and quits.
## Run (needs a window): godot --path . res://scenes/tools/BossShot.tscn

func _ready() -> void:
	GameState.current_level = 8
	var vp: Vector2 = get_viewport_rect().size
	var sf: Node = load("res://scripts/Starfield.gd").new()
	sf.level = 8
	add_child(sf)
	for k in 3:
		var b: Boss = Boss.new()
		b.type = Boss.Type.BOSS2
		b.position = Vector2(vp.x * 0.5, 250.0 + 420.0 * k)
		add_child(b)
		b._entry_done = true
		b._target_y = b.position.y
		b._drift_speed = 0.0
		await get_tree().process_frame
		var parts: Array = b.live_parts()
		if k == 1:
			parts[3].take_damage(9999)
			parts[4].take_damage(30)
			parts[0].take_damage(40)
		elif k == 2:
			for p in parts:
				if p.shields_core:
					p.take_damage(9999)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://boss_shot.png")
	print("saved ", ProjectSettings.globalize_path("user://boss_shot.png"), " ", img.get_size())
	get_tree().quit()
