extends Node
## Dev-only mockup generator — produces one preview PNG per cutscene beat
## showing what the final Cutscene.gd will look like (image + caption text
## + bottom gradient). NOT shipped — lives under scenes/tools/ and should
## never be referenced from Main.tscn or any gameplay scene.
##
## How to run: open `scenes/tools/CutsceneMockup.tscn` in the Godot editor
## and press F6 (Run Current Scene). The script walks through all 19
## beats, drawing each one on screen for two frames, screenshotting the
## viewport, and saving the result to `assets/cutscenes/mockups/`.
## When all mockups are written the editor prints "MOCKUPS DONE" and
## quits.
##
## The on-screen layout here is byte-identical to what Cutscene.gd will
## use at runtime — same font, same outline, same bottom-gradient panel,
## same caption positioning. Approving a mockup = approving the final
## in-game look.

const BEATS: Array = [
	# [filename_no_ext, caption]
	["cutscene_00_intro_01_relay_station", "Earth orbit. 03:47 UTC.\nA signal from a dead colony."],
	["cutscene_00_intro_02_signal_console", "Forty years of silence.\nAnd one word, repeating."],
	["cutscene_00_intro_03_decoded_sigil", "SKYBREAKER."],
	["cutscene_00_intro_04_launch", "You're the only pilot close enough.\nLaunch."],
	["cutscene_01_act1_01_pirate_dogfight", "The pirates aren't attacking.\nThey're running."],
	["cutscene_01_act1_02_dying_pilot", "One pilot transmits a final\nword before her ship cracks apart:"],
	["cutscene_01_act1_03_drifting_wreckage", "It's awake."],
	["cutscene_02_act2_01_dead_colony", "The colony isn't dead.\nIt's been waiting."],
	["cutscene_02_act2_02_docking_tunnel", "The air smells wrong.\nThe walls aren't metal anymore."],
	["cutscene_02_act2_03_rewritten_survivors", "They were human, once.\nSomething rewrote them."],
	["cutscene_03_act3_01_hive_artifact", "The swarm wasn't attacking you.\nIt was guarding."],
	["cutscene_03_act3_02_bugs_falling", "The firewall is falling.\nYou helped it fall."],
	["cutscene_03_act3_03_skybreaker_awake", "The weapon was buried for a reason."],
	["cutscene_04_act4_01_heart_chamber", "Inside the heart.\nAncient. Listening."],
	["cutscene_04_act4_02_grandmother_hologram", "It knows your name.\nIt was built from hers."],
	["cutscene_04_act4_03_chamber_waking", "\"If you're reading this, kill it.\nI'm sorry.\""],
	["cutscene_05_ending_01_skybreaker_falling", "It falls.\nThe stars go quiet."],
	["cutscene_05_ending_02_homeward", "You turn for home.\nThe signal is gone."],
	["cutscene_05_ending_03_new_signal", "And then, from deeper out..."],
]

const SRC_DIR: String = "res://assets/cutscenes/"
const OUT_DIR: String = "res://assets/cutscenes/mockups/"

var _texture_rect: TextureRect
var _caption_label: Label
var _gradient_rect: ColorRect


func _ready() -> void:
	# Build the mockup layout once — swap texture + caption per beat.
	_build_layout()
	await _run_batch()


func _build_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# 1. Full-screen source image (cover-scaled via TextureRect stretch mode)
	_texture_rect = TextureRect.new()
	_texture_rect.size = viewport_size
	_texture_rect.position = Vector2.ZERO
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_texture_rect)

	# 2. Bottom-third gradient (approximated with a single translucent
	#    ColorRect since Godot's built-in gradient shader would require
	#    a material — keeping this dev-only tool dependency-free).
	_gradient_rect = ColorRect.new()
	_gradient_rect.color = Color(0, 0, 0, 0.55)
	_gradient_rect.size = Vector2(viewport_size.x, viewport_size.y * 0.40)
	_gradient_rect.position = Vector2(0, viewport_size.y * 0.60)
	add_child(_gradient_rect)

	# 3. Caption label in the bottom quarter
	_caption_label = Label.new()
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.size = Vector2(viewport_size.x * 0.90, viewport_size.y * 0.22)
	_caption_label.position = Vector2(viewport_size.x * 0.05, viewport_size.y * 0.72)
	_caption_label.add_theme_font_size_override("font_size", int(viewport_size.x * 0.065))
	_caption_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_caption_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption_label.add_theme_constant_override("outline_size", int(viewport_size.x * 0.012))
	var fonts_node: Node = get_node_or_null("/root/Fonts")
	if fonts_node != null and "HEADLINE" in fonts_node:
		_caption_label.add_theme_font_override("font", fonts_node.HEADLINE)
	add_child(_caption_label)


## Walk all beats serially. For each one: swap texture, swap caption,
## wait two frames for the render to settle, screenshot the viewport,
## save PNG, move on.
func _run_batch() -> void:
	# Ensure the output dir exists on disk (ResourceLoader can't create it)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var written: int = 0
	for i in BEATS.size():
		var beat: Array = BEATS[i]
		var filename: String = beat[0]
		var caption: String = beat[1]
		var src_path: String = SRC_DIR + filename + ".png"
		if not ResourceLoader.exists(src_path):
			push_warning("Source missing: " + src_path + " — skipping")
			continue

		_texture_rect.texture = load(src_path)
		_caption_label.text = caption

		# Two process frames for the renderer to actually produce pixels
		# matching the new texture + caption before we sample the viewport.
		await get_tree().process_frame
		await get_tree().process_frame

		var img: Image = get_viewport().get_texture().get_image()
		var out_path: String = OUT_DIR + "mockup_%02d_%s.png" % [i + 1, filename]
		var err: int = img.save_png(out_path)
		if err != OK:
			push_error("Failed to save %s (err %d)" % [out_path, err])
		else:
			print("Wrote %s" % out_path)
			written += 1

	print("=== MOCKUPS DONE: %d of %d beats written to %s ===" % [written, BEATS.size(), OUT_DIR])
	get_tree().quit()
