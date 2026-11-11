extends Node2D
## Windowed look check: a mega asteroid mid-field inside a meteor shower.
## Saves user://alert_shot.png (red alert up) and user://meteor_shot.png, quits.
func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.02, 0.03, 0.08); bg.size = Vector2(816, 1452); add_child(bg)
	GameState.current_level = 7
	var sp: EnemySpawner = EnemySpawner.new()
	add_child(sp)
	sp._mission_time = float(sp._shower_times[0]) + 0.01
	var m := MegaAsteroid.new(); m.position = Vector2(408, 700); m.drift = Vector2.ZERO; add_child(m)
	m.take_damage(int(m.max_hp * 0.4))
	sp._show_warning("MEGA ASTEROID INBOUND")
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://alert_shot.png")
	for i in 110:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://meteor_shot.png")
	get_tree().quit()
