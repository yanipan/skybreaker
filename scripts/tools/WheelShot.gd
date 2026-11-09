extends Node2D
## Windowed look-check of the fire wheel: idle on the left side, then with the
## beam wedge held. Saves user://wheel_idle.png and user://wheel_held.png.
## Run (needs a window): godot --path . res://scenes/tools/WheelShot.tscn

func _ready() -> void:
	GameState.controls_side = 0
	GameState.joystick_enabled = true
	GameState.current_level = 8
	var sf: Node = load("res://scripts/Starfield.gd").new()
	sf.level = 8
	add_child(sf)
	var p: Node = load("res://scripts/Player.gd").new()
	var vp: Vector2 = get_viewport_rect().size
	p.position = Vector2(vp.x * 0.5, vp.y * 0.55)
	add_child(p)
	var mc: CanvasLayer = load("res://scripts/MobileControls.gd").new()
	mc.force_visible = true
	add_child(mc)
	await get_tree().create_timer(0.6).timeout
	p.weapon_levels = {0: 7, 1: 12, 2: 4}
	p.torpedo_count = 3
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://wheel_idle.png")
	var wheel: Control = mc._pad
	mc._pad_press(-100, mc._pad_centers[1] - wheel.position)
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://wheel_held.png")
	print("saved ", ProjectSettings.globalize_path("user://wheel_held.png"))
	get_tree().quit()
