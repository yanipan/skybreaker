extends Node
## Dev-only store screenshot generator — produces 32 promotional PNGs
## (8 per device × 4 devices) composited from the painted cutscene art
## + promotional captions + a Skybreaker brand badge.
##
## Why not "real gameplay" screenshots? Two reasons:
##   1. Automating real gameplay (spawn enemies, fire weapons, catch the
##      perfect frame) is fragile and produces inconsistent framing
##      between runs. Screenshots need to be PERFECTLY cropped for the
##      stores to accept them.
##   2. Narrative-driven shmups (Steredenn, Phoenix 2, Bullet Soul) all
##      use promotional art + copy for their store listings, not raw
##      gameplay. Copy sells more than a cluttered gameplay frame at
##      thumbnail size on a crowded store grid.
##
## The generator walks 8 beats × 4 device resolutions and writes PNGs
## to `assets/store/screenshots/<device>/<nn>_<slug>.png`. The App Store
## and Google Play will accept these directly.
##
## How to run: open `scenes/tools/StoreScreenshots.tscn` in the editor
## and press F6. Watch the Output panel; when it prints
## "=== STORE SCREENSHOTS DONE ===" the batch is complete.

class_name StoreScreenshotsGen

## A single screenshot beat. `bg_image` is the filename (no extension)
## inside `res://assets/cutscenes/`; `headline` is the top banner caption
## (short — readable at thumbnail size); `subline` is the optional smaller
## copy underneath.
const BEATS: Array = [
	{
		"slug": "01_hand_painted_shmup",
		"bg_image": "cutscene_01_act1_01_pirate_dogfight",
		"headline": "A HAND-PAINTED SHMUP",
		"subline": "Every frame. Every sector. Every enemy.",
	},
	{
		"slug": "02_one_pilot",
		"bg_image": "cutscene_00_intro_04_launch",
		"headline": "ONE PILOT.\nFORTY YEARS SILENT.",
		"subline": "Answer the signal.",
	},
	{
		"slug": "03_story_that_matters",
		"bg_image": "cutscene_04_act4_02_grandmother_hologram",
		"headline": "A STORY\nTHAT MATTERS",
		"subline": "Six painted cutscenes. One ending you'll remember.",
	},
	{
		"slug": "04_twenty_sectors",
		"bg_image": "cutscene_03_act3_03_skybreaker_awake",
		"headline": "20 SECTORS\n5 BOSSES\n1 ENDING",
		"subline": "Every sector escalates. Every boss means something.",
	},
	{
		"slug": "05_answer_the_signal",
		"bg_image": "cutscene_00_intro_01_relay_station",
		"headline": "ANSWER\nTHE SIGNAL",
		"subline": "A distress call from a colony that went dark 40 years ago.",
	},
	{
		"slug": "06_built_for_one_hand",
		"bg_image": "cutscene_05_ending_02_homeward",
		"headline": "BUILT FOR\nONE HAND",
		"subline": "Drag to fly. Tap to fire. Works anywhere.",
	},
	{
		"slug": "07_no_ads_no_iap",
		"bg_image": "cutscene_00_intro_03_decoded_sigil",
		"headline": "NO ADS. NO IAP.\nJUST A GAME.",
		"subline": "Buy once. Play forever. Your data stays yours.",
	},
	{
		"slug": "08_deeper_out",
		"bg_image": "cutscene_05_ending_03_new_signal",
		"headline": "AND THEN,\nFROM DEEPER OUT...",
		"subline": "",
	},
]

## Device targets and their required output resolutions.
## Apple requires EXACT sizes for iPhone 6.7" and iPad 13"; Google Play
## accepts any portrait 9:16 in [320..3840] px range, so we pick a
## modern-flagship phone res and a 10" tablet res.
const DEVICES: Array = [
	{"folder": "ios_phone", "w": 1290, "h": 2796, "label": "iPhone 6.7\""},
	{"folder": "ios_tablet", "w": 2048, "h": 2732, "label": "iPad Pro 13\""},
	{"folder": "android_phone", "w": 1080, "h": 2340, "label": "Android phone"},
	{"folder": "android_tablet", "w": 1600, "h": 2560, "label": "Android 10\" tablet"},
]

const SRC_DIR: String = "res://assets/cutscenes/"
const OUT_DIR: String = "res://assets/store/screenshots/"

## Palette — matches the in-game HUD.
const COL_CYAN := Color(0.55, 0.95, 1.00)
const COL_GOLD := Color(1.00, 0.85, 0.40)


func _ready() -> void:
	await _run_all()


func _run_all() -> void:
	var fonts_node: Node = get_node_or_null("/root/Fonts")
	var total: int = 0

	for device_idx in DEVICES.size():
		var device: Dictionary = DEVICES[device_idx]
		print("=== Rendering %s (%dx%d) ===" % [device.label, device.w, device.h])

		# Make the output folder on disk (ResourceLoader can't create dirs)
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUT_DIR + device.folder + "/"))

		for beat_idx in BEATS.size():
			var beat: Dictionary = BEATS[beat_idx]
			var ok: bool = await _render_one(beat, device, fonts_node)
			if ok:
				total += 1

	print("=== STORE SCREENSHOTS DONE: %d / %d written ===" % [total, DEVICES.size() * BEATS.size()])
	get_tree().quit()


## Render one beat at one device size. Everything lives inside a SubViewport
## sized to the target device so the output pixels are exactly right
## regardless of what the main viewport is configured for. Screenshot,
## save, tear down, move on.
func _render_one(beat: Dictionary, device: Dictionary, fonts_node) -> bool:
	var src_path: String = SRC_DIR + String(beat.bg_image) + ".png"
	if not ResourceLoader.exists(src_path):
		push_warning("Source missing: " + src_path)
		return false

	var vp := SubViewport.new()
	vp.size = Vector2i(int(device.w), int(device.h))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)

	var root := Control.new()
	root.size = Vector2(device.w, device.h)
	root.position = Vector2.ZERO
	vp.add_child(root)

	# --- Background image (cover-scaled) ---
	var tex := TextureRect.new()
	tex.size = root.size
	tex.position = Vector2.ZERO
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.texture = load(src_path)
	root.add_child(tex)

	# --- Top dark banner (gradient-ish — one translucent rect) for headline ---
	var top_band := ColorRect.new()
	top_band.size = Vector2(device.w, device.h * 0.38)
	top_band.position = Vector2.ZERO
	top_band.color = Color(0, 0, 0, 0.55)
	root.add_child(top_band)

	# --- Bottom dark band for subline + brand ---
	var bot_band := ColorRect.new()
	bot_band.size = Vector2(device.w, device.h * 0.18)
	bot_band.position = Vector2(0, device.h - bot_band.size.y)
	bot_band.color = Color(0, 0, 0, 0.55)
	root.add_child(bot_band)

	# --- Headline ---
	var head := Label.new()
	head.text = String(beat.headline)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.size = Vector2(device.w * 0.90, device.h * 0.30)
	head.position = Vector2(device.w * 0.05, device.h * 0.04)
	# Font size scales with viewport width so the look stays consistent
	# across all four device resolutions.
	head.add_theme_font_size_override("font_size", int(device.w * 0.10))
	head.add_theme_color_override("font_color", COL_CYAN)
	head.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_theme_constant_override("outline_size", int(device.w * 0.012))
	head.add_theme_constant_override("line_spacing", int(device.w * 0.015))
	if fonts_node != null and "HEADLINE" in fonts_node:
		head.add_theme_font_override("font", fonts_node.HEADLINE)
	root.add_child(head)

	# --- Subline ---
	if String(beat.subline) != "":
		var sub := Label.new()
		sub.text = String(beat.subline)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.size = Vector2(device.w * 0.90, device.h * 0.10)
		sub.position = Vector2(device.w * 0.05, device.h - bot_band.size.y + device.h * 0.02)
		sub.add_theme_font_size_override("font_size", int(device.w * 0.035))
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		sub.add_theme_color_override("font_outline_color", Color.BLACK)
		sub.add_theme_constant_override("outline_size", int(device.w * 0.005))
		root.add_child(sub)

	# --- Skybreaker brand badge — small gold text at bottom center ---
	var brand := Label.new()
	brand.text = "SKYBREAKER"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.size = Vector2(device.w, device.h * 0.06)
	brand.position = Vector2(0, device.h - device.h * 0.065)
	brand.add_theme_font_size_override("font_size", int(device.w * 0.040))
	brand.add_theme_color_override("font_color", COL_GOLD)
	brand.add_theme_color_override("font_outline_color", Color.BLACK)
	brand.add_theme_constant_override("outline_size", int(device.w * 0.006))
	if fonts_node != null and "HEADLINE" in fonts_node:
		brand.add_theme_font_override("font", fonts_node.HEADLINE)
	root.add_child(brand)

	# Let the viewport paint its contents — UPDATE_ALWAYS means every tick,
	# so two frames is plenty.
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = vp.get_texture().get_image()
	var out_path: String = "%s%s/%s.png" % [OUT_DIR, device.folder, beat.slug]
	var err: int = img.save_png(out_path)
	if err == OK:
		print("  wrote %s" % out_path)
	else:
		push_error("Failed to save %s (err %d)" % [out_path, err])

	vp.queue_free()
	return err == OK
