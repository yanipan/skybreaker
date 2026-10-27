extends Node2D
class_name Boot
## First scene the game opens to. Exists purely to kill the gray flash players
## see while StartScreen + its preloaded Main.tscn graph compile and import.
##
## Strategy:
##   * Boot.tscn is intentionally microscopic — one ColorRect, one title
##     Label, one "loading…" Label, a few drifting star ColorRects. No
##     preloads, no imported textures, no autoload work besides what
##     GameState already does. It mounts in <50 ms even on a cold launch.
##   * As soon as we're mounted we kick off ResourceLoader.load_threaded_request
##     for StartScreen.tscn. The request runs on Godot's worker pool so the
##     main thread keeps drawing the loader while the disk read + script
##     parse + texture imports happen in the background.
##   * _process polls the load status, advances a progress bar, and when
##     the resource is ready calls change_scene_to_packed() — which is
##     instant because the PackedScene is already in memory.
##
## Result: the player sees a styled "SKYBREAKER" + animated loading dots
## from the very first frame. No gray gap, no frozen window.
##
## Publisher splash ("Shimonster presents"): plays on top of the same dark
## background for SPLASH_SECONDS while the threaded load runs underneath.
## The loader UI lives under _loader_root (alpha 0 during the splash) and
## fades in as the splash fades out. Tap/click anywhere skips the splash.
## The scene switch waits for both the load AND the end of the splash.

const START_SCENE_PATH: String = "res://scenes/main/StartScreen.tscn"

# Game palette — matches StartScreen so the transition feels seamless.
const COL_BG := Color(0.02, 0.04, 0.10, 1.0)
const COL_CYAN := Color(0.55, 0.95, 1.0)
const COL_GOLD := Color(1.0, 0.85, 0.40)

var _viewport_size: Vector2
var _time: float = 0.0
var _dots_label: Label
var _progress_rect: ColorRect
var _progress_bg: ColorRect
var _stars: Array = []          ## Array of {rect, speed, base_alpha}
var _load_started: bool = false
var _switched: bool = false
## Minimum time we hold the loader on screen even if the threaded load
## finishes instantly — prevents an ugly one-frame flash on fast desktops
## while still feeling snappy on phones.
const MIN_HOLD_SECONDS: float = 0.45

# --- Publisher splash ---
const MASCOT_PATH: String = "res://assets/sprites/brand/shimmy_mascot.png"
const BRAND_FONT_PATH: String = "res://assets/fonts/Fredoka.ttf"
const BODY_FONT_PATH: String = "res://assets/fonts/Rajdhani-Medium.ttf"
## Total splash length, fade-out included. Max time the splash can add.
const SPLASH_SECONDS: float = 2.4
## Cross-fade from splash to the SKYBREAKER loader at the end of the splash.
const SPLASH_FADE_SECONDS: float = 0.35
## Faster cross-fade used when the player taps to skip.
const SPLASH_SKIP_FADE_SECONDS: float = 0.2
const COL_LAVENDER := Color(0.78, 0.62, 1.0)
const COL_PURPLE_GLOW := Color(0.55, 0.30, 0.95, 0.75)
const COL_MUTED := Color(0.78, 0.80, 0.92, 0.85)

## Holds every loader node (title, tagline, bar, dots). Hidden during the splash.
var _loader_root: Node2D
## Holds every splash node; freed once the splash has faded out.
var _splash_root: Node2D
var _mascot: Sprite2D
var _mascot_base_pos: Vector2
var _sparkles: Array = []       ## Array of {node, phase, speed, base_scale}
var _splash_time: float = 0.0
var _splash_ending: bool = false
## True once the splash has fully faded out (or there was none). Gates the switch.
var _splash_done: bool = false


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_build_ui()
	_spawn_stars()
	_build_splash()
	# Kick off the threaded load on the very next frame so the loader has
	# already drawn at least once before we start hammering the disk.
	call_deferred("_start_load")


func _start_load() -> void:
	_load_started = true
	ResourceLoader.load_threaded_request(START_SCENE_PATH)
	# Warm the audio cache in the background while the threaded scene load
	# is running. AudioManager defers all its MP3 decodes now, so this is
	# the right place to pay that cost — loader is already on screen, the
	# main thread is mostly idle waiting on the scene load.
	if Engine.has_singleton("AudioManager") or get_node_or_null("/root/AudioManager") != null:
		var am: Node = get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("warm_assets"):
			am.call_deferred("warm_assets")


# --- UI build ---

func _build_ui() -> void:
	var vw: float = _viewport_size.x
	var vh: float = _viewport_size.y

	# Solid background — guarantees the first frame is dark blue, never gray.
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.size = _viewport_size
	bg.position = Vector2.ZERO
	bg.z_index = -10
	add_child(bg)

	# Everything below belongs to the loader look and starts invisible while
	# the publisher splash plays; it fades in when the splash fades out.
	_loader_root = Node2D.new()
	_loader_root.modulate.a = 0.0
	add_child(_loader_root)

	# SKYBREAKER title
	var title := Label.new()
	title.text = "SKYBREAKER"
	title.add_theme_font_size_override("font_size", int(vw * 0.10))
	title.add_theme_color_override("font_color", COL_CYAN)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vw, vh * 0.15)
	title.position = Vector2(0, vh * 0.40)
	_loader_root.add_child(title)

	# Subtitle / tagline
	var sub := Label.new()
	sub.text = "DEEP SPACE CALL SIGN"
	sub.add_theme_font_size_override("font_size", int(vw * 0.030))
	sub.add_theme_color_override("font_color", COL_GOLD)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 3)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(vw, vh * 0.06)
	sub.position = Vector2(0, vh * 0.55)
	_loader_root.add_child(sub)

	# Progress bar — thin cyan strip under the title
	var bar_w: float = vw * 0.55
	var bar_h: float = max(4.0, vh * 0.006)
	var bar_x: float = (vw - bar_w) * 0.5
	var bar_y: float = vh * 0.66
	_progress_bg = ColorRect.new()
	_progress_bg.color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.18)
	_progress_bg.size = Vector2(bar_w, bar_h)
	_progress_bg.position = Vector2(bar_x, bar_y)
	_loader_root.add_child(_progress_bg)
	_progress_rect = ColorRect.new()
	_progress_rect.color = COL_CYAN
	_progress_rect.size = Vector2(0, bar_h)
	_progress_rect.position = Vector2(bar_x, bar_y)
	_loader_root.add_child(_progress_rect)

	# Animated "loading" label
	_dots_label = Label.new()
	_dots_label.text = "loading"
	_dots_label.add_theme_font_size_override("font_size", int(vw * 0.035))
	_dots_label.add_theme_color_override("font_color", Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.85))
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_label.size = Vector2(vw, vh * 0.05)
	_dots_label.position = Vector2(0, vh * 0.70)
	_loader_root.add_child(_dots_label)


# --- Publisher splash ("Shimonster presents") ---
# Beats (seconds from Boot mount):
#   0.00-0.70  mascot elastic pop, scale 0 -> 1 (then continuous bob/wobble)
#   0.30+      sparkles fade in and twinkle around the mascot
#   0.35-1.15  "SHIMONSTER" letters drop in, 0.05 s stagger, back ease
#   1.15-1.55  "presents" fades in
#   2.05-2.40  splash fades out, SKYBREAKER loader fades in
func _build_splash() -> void:
	var vw: float = _viewport_size.x
	var vh: float = _viewport_size.y
	_splash_root = Node2D.new()
	add_child(_splash_root)

	# Mascot — height ~32% of the viewport, centred a bit above the middle.
	var mascot_h: float = vh * 0.32
	var mascot_tex: Texture2D = load(MASCOT_PATH) as Texture2D
	_mascot_base_pos = Vector2(vw * 0.5, vh * 0.36)
	var target_scale := Vector2.ONE
	if mascot_tex != null:
		_mascot = Sprite2D.new()
		_mascot.texture = mascot_tex
		_mascot.centered = true
		var s: float = mascot_h / float(mascot_tex.get_height())
		target_scale = Vector2(s, s)
		_mascot.scale = Vector2.ZERO
		_mascot.position = _mascot_base_pos
		_splash_root.add_child(_mascot)
		var mt := _mascot.create_tween()
		mt.tween_property(_mascot, "scale", target_scale, 0.70) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	_spawn_sparkles(mascot_h)

	# Wordmark — one Label per letter so they can drop in with a stagger.
	var brand_font := _make_brand_font()
	var word: String = "SHIMONSTER"
	var font_size: int = int(vw * 0.13)
	var word_w: float = brand_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if word_w > vw * 0.84:
		font_size = int(font_size * (vw * 0.84) / word_w)
		word_w = brand_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var word_y: float = _mascot_base_pos.y + mascot_h * 0.5 + vh * 0.015
	var x: float = (vw - word_w) * 0.5
	var drop: float = vh * 0.05
	for i in word.length():
		var ch: String = word[i]
		var lbl := Label.new()
		lbl.text = ch
		lbl.add_theme_font_override("font", brand_font)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color(0.42, 0.22, 0.78))
		lbl.add_theme_constant_override("outline_size", max(2, int(font_size * 0.06)))
		lbl.add_theme_color_override("font_shadow_color", COL_PURPLE_GLOW)
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", max(2, int(font_size * 0.07)))
		lbl.add_theme_constant_override("shadow_outline_size", max(4, int(font_size * 0.16)))
		lbl.position = Vector2(x, word_y - drop)
		lbl.modulate.a = 0.0
		_splash_root.add_child(lbl)
		x += brand_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var delay: float = 0.35 + i * 0.05
		var lt := lbl.create_tween().set_parallel(true)
		lt.tween_property(lbl, "position:y", word_y, 0.35).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lt.tween_property(lbl, "modulate:a", 1.0, 0.18).set_delay(delay)

	# "presents" — small, muted, fades in after the wordmark lands.
	var presents := Label.new()
	presents.text = "presents"
	var body_font: Font = load(BODY_FONT_PATH) as Font
	if body_font != null:
		presents.add_theme_font_override("font", body_font)
	presents.add_theme_font_size_override("font_size", int(vw * 0.05))
	presents.add_theme_color_override("font_color", COL_MUTED)
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presents.size = Vector2(vw, vh * 0.05)
	presents.position = Vector2(0, word_y + font_size * 1.35)
	presents.modulate.a = 0.0
	_splash_root.add_child(presents)
	var pt := presents.create_tween()
	pt.tween_property(presents, "modulate:a", 1.0, 0.40).set_delay(1.15)


## Fredoka at weight 700 via FontVariation; falls back to the plain file.
func _make_brand_font() -> Font:
	var base: Font = load(BRAND_FONT_PATH) as Font
	if base == null:
		return ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	return fv


## Soft four-point sparkles orbiting the mascot; twinkled in _process.
func _spawn_sparkles(mascot_h: float) -> void:
	var count: int = 8
	for i in count:
		var p := Polygon2D.new()
		var r: float = mascot_h * randf_range(0.035, 0.06)
		var t: float = r * 0.28
		p.polygon = PackedVector2Array([
			Vector2(0, -r), Vector2(t, -t), Vector2(r, 0), Vector2(t, t),
			Vector2(0, r), Vector2(-t, t), Vector2(-r, 0), Vector2(-t, -t),
		])
		p.color = COL_LAVENDER.lerp(Color.WHITE, randf_range(0.3, 0.9))
		var ang: float = TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var dist: float = mascot_h * randf_range(0.55, 0.72)
		p.position = _mascot_base_pos + Vector2(cos(ang) * dist * 1.1, sin(ang) * dist * 0.85)
		p.scale = Vector2.ZERO
		_splash_root.add_child(p)
		_sparkles.append({"node": p, "phase": randf() * TAU, "speed": randf_range(3.0, 5.5)})


## Per-frame splash motion: mascot bob/wobble, sparkle twinkle, auto end.
func _process_splash(delta: float) -> void:
	if _splash_root == null:
		return
	_splash_time += delta
	if _mascot != null:
		_mascot.position = _mascot_base_pos + Vector2(0, sin(_splash_time * 3.2) * _viewport_size.y * 0.008)
		_mascot.rotation = sin(_splash_time * 2.1) * deg_to_rad(3.0)
	var sparkle_in: float = clamp((_splash_time - 0.3) / 0.4, 0.0, 1.0)
	for sp in _sparkles:
		var node: Polygon2D = sp["node"]
		var tw: float = 0.5 + 0.5 * sin(_splash_time * sp["speed"] + sp["phase"])
		node.scale = Vector2.ONE * (0.35 + 0.65 * tw) * sparkle_in
		node.rotation += delta * 0.8
		node.modulate.a = (0.35 + 0.65 * tw) * sparkle_in
	if not _splash_ending and _splash_time >= SPLASH_SECONDS - SPLASH_FADE_SECONDS:
		_end_splash(SPLASH_FADE_SECONDS)


## Cross-fade splash -> loader. Safe to call more than once.
func _end_splash(fade: float) -> void:
	if _splash_ending:
		return
	_splash_ending = true
	var t := create_tween().set_parallel(true)
	if _splash_root != null:
		t.tween_property(_splash_root, "modulate:a", 0.0, fade)
	# Loader starts in the second half so the two layouts don't overlap.
	t.tween_property(_loader_root, "modulate:a", 1.0, fade * 0.5).set_delay(fade * 0.5)
	t.chain().tween_callback(_on_splash_faded)


func _on_splash_faded() -> void:
	_splash_done = true
	_sparkles.clear()
	_mascot = null
	if _splash_root != null:
		_splash_root.queue_free()
		_splash_root = null


## Tap or click anywhere skips the splash. _input (not _unhandled_input)
## because the full-screen background ColorRect stops GUI mouse events.
func _input(event: InputEvent) -> void:
	if _splash_ending:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		_end_splash(SPLASH_SKIP_FADE_SECONDS)


# --- Tiny background star layer ---
# We can't use Starfield.gd here because that would defeat the whole point
# (it pulls in textures). A handful of slowly-drifting ColorRects is enough
# to make the loader feel like part of the game and not a static splash.
func _spawn_stars() -> void:
	for i in 40:
		var r := ColorRect.new()
		var s: float = randf_range(1.0, 3.0)
		r.size = Vector2(s, s)
		r.position = Vector2(randf() * _viewport_size.x, randf() * _viewport_size.y)
		var a: float = randf_range(0.25, 0.85)
		r.color = Color(0.85, 0.95, 1.0, a)
		add_child(r)
		_stars.append({"rect": r, "speed": randf_range(12.0, 60.0), "base_alpha": a})


func _process(delta: float) -> void:
	_time += delta
	_process_splash(delta)

	# Drift stars downward, wrap at bottom — same direction as in-game so the
	# transition into StartScreen reads as one continuous starfield.
	for s in _stars:
		var r: ColorRect = s["rect"]
		r.position.y += s["speed"] * delta
		if r.position.y > _viewport_size.y:
			r.position.y = -4.0
			r.position.x = randf() * _viewport_size.x
		# Subtle twinkle so the field doesn't feel dead
		var ba: float = s["base_alpha"]
		var twinkle: float = 0.85 + 0.15 * sin(_time * 3.0 + r.position.x * 0.1)
		r.color.a = ba * twinkle

	# Animated dots after "loading"
	if _dots_label != null:
		var n: int = int(_time * 2.4) % 4
		_dots_label.text = "loading" + ".".repeat(n)

	# Poll the threaded load. Advance the progress bar to whatever the
	# loader reports (0..1), and when the load completes AND we've held
	# for the minimum time, swap to StartScreen.
	if not _load_started or _switched:
		return
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(START_SCENE_PATH, progress)
	var pct: float = 0.0
	if progress.size() > 0:
		pct = float(progress[0])
	if _progress_rect != null and _progress_bg != null:
		_progress_rect.size.x = _progress_bg.size.x * clamp(pct, 0.05, 1.0)

	# Also wait for the publisher splash to finish (or be skipped).
	if status == ResourceLoader.THREAD_LOAD_LOADED and _time >= MIN_HOLD_SECONDS and _splash_done:
		var packed: PackedScene = ResourceLoader.load_threaded_get(START_SCENE_PATH) as PackedScene
		if packed != null:
			_switched = true
			get_tree().change_scene_to_packed(packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		# Fall back to the path-based loader so the player still gets to
		# the menu even if the threaded request hit a snag.
		_switched = true
		get_tree().change_scene_to_file(START_SCENE_PATH)
