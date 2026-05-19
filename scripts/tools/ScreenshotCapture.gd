extends Node
## Dev-only keyboard screenshot capture.
##
## Press F12 during gameplay to save:
##   * A master PNG at the current viewport resolution
##   * 4 device-sized variants (iPhone 6.7", iPad 13", Android phone,
##     Android 10" tablet), each letterboxed to preserve the 9:16
##     gameplay framing on wider or taller target aspects
##
## Output lands in `assets/store/screenshots/<device>/gameplay_NNN_<ts>.png`
## with the master at `assets/store/screenshots/master/shot_NNN_<ts>.png`.
##
## Registered as an autoload — see project.godot `[autoload]` section.
## For production builds you should REMOVE the autoload line (or wrap
## this script's key handler in an `if OS.is_debug_build():` guard) so
## shipping users don't have a hidden screenshot key active.
##
## Why not just capture at whatever the viewport happens to be? Because
## the editor runs at the project viewport size (816×1452 by default),
## and the stores need 1290×2796 / 2048×2732 / etc. Taking one capture
## and producing all four variants means one keypress gives you a full
## store-ready set of a single gameplay moment.

## Per-device output configuration. Keep these in sync with
## StoreScreenshotsGen.gd's DEVICES array — stores reject mis-sized images.
const DEVICES: Array = [
	{"folder": "ios_phone", "w": 1290, "h": 2796},
	{"folder": "ios_tablet", "w": 2048, "h": 2732},
	{"folder": "android_phone", "w": 1080, "h": 2340},
	{"folder": "android_tablet", "w": 1600, "h": 2560},
]

const OUT_DIR: String = "res://assets/store/screenshots/"

var _shot_counter: int = 0
var _flash_layer: CanvasLayer = null


func _ready() -> void:
	# Runs even while the game is paused (pause menu, cutscene overlay)
	# so F12 always works.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_capture()
			get_viewport().set_input_as_handled()


## Capture current viewport → master PNG + 4 device variants.
## Runs in the current frame so the texture grab matches what the player
## just saw on screen.
func _capture() -> void:
	var src: Image = get_viewport().get_texture().get_image()
	if src == null or src.get_width() == 0:
		push_warning("ScreenshotCapture: viewport texture is empty")
		return
	_shot_counter += 1
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")

	# Ensure all output folders exist on disk (ResourceLoader can't mkdir)
	var master_dir: String = OUT_DIR + "master/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(master_dir))
	for device in DEVICES:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUT_DIR + String(device.folder) + "/"))

	# Save the raw master capture — useful for later re-processing if you
	# want to tweak crop/letterbox strategy without re-capturing.
	var master_path: String = "%sshot_%03d_%s.png" % [master_dir, _shot_counter, ts]
	src.save_png(master_path)

	# Produce one variant per device, letterboxed to preserve 9:16 framing.
	for device in DEVICES:
		var variant: Image = _fit_to_device(src, int(device.w), int(device.h))
		var out_path: String = "%s%s/gameplay_%03d_%s.png" % [
			OUT_DIR, String(device.folder), _shot_counter, ts]
		variant.save_png(out_path)

	# Visible feedback — brief white flash + text confirmation so the
	# player knows the capture fired even without watching the Output panel.
	_flash_and_toast("F12 — shot %03d saved (%d variants)" % [_shot_counter, DEVICES.size()])
	print("=== F12 capture #%03d → master + %d device variants ===" % [_shot_counter, DEVICES.size()])


## Letterbox the source into a target device canvas. We scale-to-fit
## (preserve aspect, add black bars where the aspect doesn't match) so
## gameplay framing is never cropped — especially important for boss
## encounters where the top/bottom of the screen carries action.
func _fit_to_device(src: Image, tw: int, th: int) -> Image:
	var sw: int = src.get_width()
	var sh: int = src.get_height()
	var scale: float = min(float(tw) / float(sw), float(th) / float(sh))
	var new_w: int = int(sw * scale)
	var new_h: int = int(sh * scale)
	var resized: Image = src.duplicate()
	resized.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	var canvas: Image = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.BLACK)
	var ox: int = (tw - new_w) / 2
	var oy: int = (th - new_h) / 2
	canvas.blit_rect(resized, Rect2i(0, 0, new_w, new_h), Vector2i(ox, oy))
	return canvas


## Full-screen white flash + toast label for 0.8s so the user sees the
## shot fired. Uses a temporary CanvasLayer at layer 200 (above cutscenes,
## pause menus, everything) so even mid-cutscene captures get feedback.
func _flash_and_toast(text: String) -> void:
	if _flash_layer != null and is_instance_valid(_flash_layer):
		_flash_layer.queue_free()
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 200
	_flash_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_flash_layer)

	var vp: Vector2 = get_viewport().get_visible_rect().size

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.size = vp
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(flash)

	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.size = Vector2(vp.x * 0.80, vp.y * 0.06)
	toast.position = Vector2(vp.x * 0.10, vp.y * 0.08)
	toast.add_theme_font_size_override("font_size", int(vp.x * 0.028))
	toast.add_theme_color_override("font_color", Color.BLACK)
	toast.add_theme_color_override("font_outline_color", Color.WHITE)
	toast.add_theme_constant_override("outline_size", 4)
	_flash_layer.add_child(toast)

	# Fade: flash quickly, keep toast visible longer, then kill the layer.
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.tween_property(flash, "modulate:a", 0.0, 0.25)
	tw.tween_interval(0.55)
	tw.tween_callback(func() -> void:
		if _flash_layer != null and is_instance_valid(_flash_layer):
			_flash_layer.queue_free()
			_flash_layer = null
	)
