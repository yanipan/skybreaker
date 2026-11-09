extends Node2D
## Windowed look-check of the 9/11 expansion art in the real engine: every new
## enemy as the game draws it (rotation, scale, transparency), both new bosses,
## one beam charging and one firing. Saves user://art_check.png and quits.
## Run (needs a window, not --headless):
##   godot --path . res://scenes/tools/ArtCheckShot.tscn

const NAMES := {9: "SHADE", 10: "ARTILLERY", 11: "MINELAYER", 12: "SPLITTER", 13: "PULSAR", 14: "SHARD", 15: "HUNTER", 16: "BEAMER"}

func _ready() -> void:
	GameState.current_level = 24
	var vp: Vector2 = get_viewport_rect().size
	var sf: Node = load("res://scripts/Starfield.gd").new()
	sf.level = 21
	add_child(sf)
	var i: int = 0
	for t in NAMES:
		var e: Node = load("res://scripts/Enemy.gd").new()
		e.type = t
		e.position = Vector2(vp.x * (0.16 + 0.225 * (i % 4)), 560.0 + 230.0 * (i / 4))
		add_child(e)
		e.set_process(false)
		var lab := Label.new()
		lab.text = NAMES[t]
		lab.position = e.position + Vector2(-60, 86)
		lab.add_theme_font_size_override("font_size", 20)
		add_child(lab)
		i += 1
	var k: int = 0
	for bt in [6, 7]:
		var b: Node = load("res://scripts/Boss.gd").new()
		b.type = bt
		b.position = Vector2(vp.x * (0.27 + 0.46 * k), 210.0)
		add_child(b)
		b.set_process(false)
		b.scale = Vector2(0.8, 0.8)
		k += 1
	for j in 2:
		var beam: Node = load("res://scripts/EnemyBeam.gd").new()
		var anchor := Node2D.new()
		anchor.position = Vector2(vp.x * (0.30 + 0.40 * j), 1030.0)
		add_child(anchor)
		beam.emitter = anchor
		beam.beam_color = Color(0.45, 0.85, 1.0)
		beam.charge_secs = 0.3 if j == 1 else 5.0
		beam.fire_secs = 5.0
		add_child(beam)
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://art_check.png")
	print("saved ", ProjectSettings.globalize_path("user://art_check.png"), " ", img.get_size())
	get_tree().quit()
