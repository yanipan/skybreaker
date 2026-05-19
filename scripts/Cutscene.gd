extends CanvasLayer
class_name Cutscene
## Story cutscene playback overlay.
##
## Spawned by Main.gd at cutscene trigger points (sector-complete intercepts
## in `_check_level_complete` + intro in `_ready`). Plays a list of still
## beats (or MP4 clips if available) with a Ken Burns zoom, bottom-gradient
## + caption, crossfade between beats, tap-to-advance, and a SKIP button
## in the top corner.
##
## Playback contract:
##   1. Cutscene is a CanvasLayer at layer 150 (above pause at 110, below
##      modal alerts if we ever add them).
##   2. Pauses the tree (`get_tree().paused = true`) so enemies, spawner,
##      and physics all freeze behind the overlay. The cutscene itself runs
##      via process_mode = ALWAYS.
##   3. On dismissal (final beat consumed OR skip pressed), emits the
##      `finished` signal. Main connects to this and continues the original
##      transition (warp → next sector, or StartScreen transition for the
##      ending). Cutscene queue_free()s itself after emitting.
##
## Nano Banana MP4 support: if `res://assets/cutscenes/<image_file>.mp4`
## exists alongside the `.png`, the video plays instead of the still,
## looping for the beat's duration. Falls back transparently to the still
## when no clip is present — lets animation drops in without code changes.

signal finished

## Palette matches the rest of the HUD.
const COL_CYAN := Color(0.55, 0.95, 1.0)

const CUTSCENE_DIR: String = "res://assets/cutscenes/"
## Fade duration at the start of a cutscene (black→visible) and at the
## end (visible→black) so beats don't pop in/out jarringly.
const EDGE_FADE_SECONDS: float = 0.55
## Crossfade between beats. Short enough to not drag, long enough to read
## as intentional.
const BEAT_CROSSFADE_SECONDS: float = 0.7
## Ken Burns zoom range — 1.0 → 1.08 over each beat's duration.
const KB_SCALE_START: float = 1.0
const KB_SCALE_END: float = 1.08
## How far the image slides horizontally over a beat (in viewport pixels).
## Alternates sign each beat for organic variety.
const KB_PAN_PX: float = 40.0

var _beats: Array = []
var _current_index: int = -1
var _viewport_size: Vector2
## Two TextureRects are kept so we can crossfade — one holds the "current"
## beat, the other slides in on the next advance.
var _rect_a: TextureRect
var _rect_b: TextureRect
## Ditto for video, when a clip exists for that beat.
var _video_a: VideoStreamPlayer
var _video_b: VideoStreamPlayer
var _using_a: bool = true
var _gradient: ColorRect
var _caption: Label
var _edge_fade: ColorRect   ## Black curtain for intro/outro fade
var _skip_btn: Control
var _advance_timer: float = 0.0
var _beat_duration: float = 5.0
var _kb_tween: Tween
var _dismissing: bool = false


func play(beats: Array) -> void:
	_beats = beats
	if _beats.is_empty():
		# Nothing to show — emit done on the next frame and self-destruct.
		call_deferred("_finish")
		return
	_viewport_size = get_viewport().get_visible_rect().size
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# Freeze gameplay behind us while the cutscene plays.
	get_tree().paused = true
	# Start with a black curtain fading out to reveal beat 1.
	_edge_fade.color = Color.BLACK
	_advance_to_beat(0, true)
	set_process(true)


# --- UI construction ---

func _build_ui() -> void:
	# Fullscreen background so no gameplay leaks through where textures
	# don't cover (wrong aspect, letterbox, etc.)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = _viewport_size
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bg)

	# Two image slots for crossfading. Stretch_mode covers the viewport
	# keeping aspect — same behavior as the mockup generator uses.
	_rect_a = _make_image_rect()
	_rect_b = _make_image_rect()
	_rect_b.modulate.a = 0.0
	add_child(_rect_a)
	add_child(_rect_b)

	_video_a = _make_video_player()
	_video_b = _make_video_player()
	_video_b.modulate.a = 0.0
	add_child(_video_a)
	add_child(_video_b)

	# Bottom-third gradient for caption legibility. Same as the mockup.
	_gradient = ColorRect.new()
	_gradient.color = Color(0, 0, 0, 0.55)
	_gradient.size = Vector2(_viewport_size.x, _viewport_size.y * 0.40)
	_gradient.position = Vector2(0, _viewport_size.y * 0.60)
	_gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gradient)

	# Caption label in the bottom quarter. Font + outline size scale with
	# viewport width so it reads the same on a tablet and a phone.
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.size = Vector2(_viewport_size.x * 0.90, _viewport_size.y * 0.22)
	_caption.position = Vector2(_viewport_size.x * 0.05, _viewport_size.y * 0.72)
	_caption.add_theme_font_size_override("font_size", int(_viewport_size.x * 0.065))
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", int(_viewport_size.x * 0.012))
	var fonts_node: Node = get_node_or_null("/root/Fonts")
	if fonts_node != null and "HEADLINE" in fonts_node:
		_caption.add_theme_font_override("font", fonts_node.HEADLINE)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	# SKIP button in the top-right. Small, unobtrusive, cyan outline so it
	# matches HUD chrome. Real Control with STOP filter so its tap doesn't
	# also count as the "tap-anywhere-to-advance" gesture.
	_skip_btn = _make_skip_button()
	add_child(_skip_btn)

	# Fullscreen transparent overlay catches taps anywhere else on screen
	# to trigger _advance. Sits above images + gradient + caption but
	# below the SKIP button so SKIP stays hittable.
	var tap_catcher := Control.new()
	tap_catcher.size = _viewport_size
	tap_catcher.position = Vector2.ZERO
	tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	tap_catcher.gui_input.connect(_on_tap_catcher_input)
	add_child(tap_catcher)
	# Re-add SKIP button after tap_catcher so it draws ABOVE the catcher
	# and its own gui_input wins over the catcher's.
	move_child(_skip_btn, get_child_count() - 1)

	# Edge fade curtain — topmost, driven by opacity tweens at start / end.
	_edge_fade = ColorRect.new()
	_edge_fade.color = Color.BLACK
	_edge_fade.size = _viewport_size
	_edge_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edge_fade)


func _make_image_rect() -> TextureRect:
	var r := TextureRect.new()
	r.size = _viewport_size
	r.position = Vector2.ZERO
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.pivot_offset = _viewport_size * 0.5
	return r


func _make_video_player() -> VideoStreamPlayer:
	var v := VideoStreamPlayer.new()
	v.size = _viewport_size
	v.position = Vector2.ZERO
	v.expand = true
	v.loop = true
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.visible = false
	return v


func _make_skip_button() -> Control:
	var btn := Control.new()
	var w: float = _viewport_size.x * 0.22
	var h: float = _viewport_size.y * 0.055
	btn.size = Vector2(w, h)
	btn.position = Vector2(_viewport_size.x - w - 20, 20)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.gui_input.connect(_on_skip_input)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = btn.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bg)

	var label := Label.new()
	label.text = "SKIP  >>"
	label.size = btn.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(h * 0.50))
	label.add_theme_color_override("font_color", COL_CYAN)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)
	return btn


# --- Beat advance / crossfade / Ken Burns ---

func _advance_to_beat(idx: int, is_first: bool) -> void:
	if idx < 0 or idx >= _beats.size():
		_dismiss()
		return
	var beat: Dictionary = _beats[idx]
	_current_index = idx
	_beat_duration = float(beat.get("duration", 5.0))
	_advance_timer = 0.0
	_caption.text = String(beat.get("caption", ""))

	var image_file: String = String(beat.get("image_file", ""))
	var mp4_path: String = CUTSCENE_DIR + image_file + ".mp4"
	var png_path: String = CUTSCENE_DIR + image_file + ".png"

	# Pick target slot (the one that's currently invisible).
	var target_rect: TextureRect = _rect_b if _using_a else _rect_a
	var target_video: VideoStreamPlayer = _video_b if _using_a else _video_a
	var outgoing_rect: TextureRect = _rect_a if _using_a else _rect_b
	var outgoing_video: VideoStreamPlayer = _video_a if _using_a else _video_b
	_using_a = not _using_a

	# Reset Ken Burns transform on the incoming slot
	target_rect.scale = Vector2(KB_SCALE_START, KB_SCALE_START)
	target_rect.position = Vector2.ZERO
	target_rect.pivot_offset = _viewport_size * 0.5

	# Load video if available, otherwise still image.
	var use_video: bool = ResourceLoader.exists(mp4_path)
	if use_video:
		var stream: VideoStream = load(mp4_path) as VideoStream
		target_video.stream = stream
		target_video.visible = true
		target_video.modulate.a = 0.0
		target_video.play()
		target_rect.visible = false
	else:
		target_video.visible = false
		target_video.stop()
		if ResourceLoader.exists(png_path):
			target_rect.texture = load(png_path)
		target_rect.visible = true
		target_rect.modulate.a = 0.0

	# Kick off Ken Burns on the still. Pan direction alternates per beat.
	_kb_tween = create_tween()
	_kb_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	var pan_dir: float = 1.0 if (idx % 2 == 0) else -1.0
	_kb_tween.parallel().tween_property(target_rect, "scale",
		Vector2(KB_SCALE_END, KB_SCALE_END), _beat_duration)
	_kb_tween.parallel().tween_property(target_rect, "position",
		Vector2(KB_PAN_PX * pan_dir * -0.5, 0), _beat_duration)
	# Start off-center opposite direction so the pan spans the full width.
	target_rect.position = Vector2(KB_PAN_PX * pan_dir * 0.5, 0)

	# Crossfade or hard-fade from black on the first beat.
	var fade_dur: float = EDGE_FADE_SECONDS if is_first else BEAT_CROSSFADE_SECONDS
	var fade_tw := create_tween()
	fade_tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	if is_first:
		# Black curtain fades out to reveal the image already at full opacity.
		target_rect.modulate.a = 1.0
		if use_video:
			target_video.modulate.a = 1.0
		fade_tw.tween_property(_edge_fade, "color",
			Color(0, 0, 0, 0), fade_dur)
	else:
		# Crossfade between outgoing and incoming.
		if use_video:
			fade_tw.parallel().tween_property(target_video, "modulate:a", 1.0, fade_dur)
		else:
			fade_tw.parallel().tween_property(target_rect, "modulate:a", 1.0, fade_dur)
		fade_tw.parallel().tween_property(outgoing_rect, "modulate:a", 0.0, fade_dur)
		fade_tw.parallel().tween_property(outgoing_video, "modulate:a", 0.0, fade_dur)
		fade_tw.tween_callback(func() -> void:
			outgoing_video.stop()
			outgoing_video.visible = false
		)


func _process(delta: float) -> void:
	if _dismissing:
		return
	_advance_timer += delta
	if _advance_timer >= _beat_duration:
		_on_advance_requested()


# --- Input handlers ---

func _on_tap_catcher_input(event: InputEvent) -> void:
	if _dismissing:
		return
	# Accept any press — touch on mobile, left-click on desktop testing.
	var pressed: bool = false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	if pressed:
		_on_advance_requested()
		get_viewport().set_input_as_handled()


func _on_skip_input(event: InputEvent) -> void:
	if _dismissing:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	if pressed:
		var am: Node = get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("haptic_light"):
			am.haptic_light()
		_dismiss()
		get_viewport().set_input_as_handled()


func _on_advance_requested() -> void:
	var next: int = _current_index + 1
	if next >= _beats.size():
		_dismiss()
	else:
		_advance_to_beat(next, false)


# --- Dismiss / finish ---

## Fade to black then emit `finished`. Caller (Main) handles what happens
## next — usually a warp transition or a StartScreen switch.
func _dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	set_process(false)
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.tween_property(_edge_fade, "color", Color(0, 0, 0, 1), EDGE_FADE_SECONDS)
	tw.tween_callback(_finish)


func _finish() -> void:
	get_tree().paused = false
	finished.emit()
	queue_free()
