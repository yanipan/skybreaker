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


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_build_ui()
	_spawn_stars()
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
	add_child(title)

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
	add_child(sub)

	# Progress bar — thin cyan strip under the title
	var bar_w: float = vw * 0.55
	var bar_h: float = max(4.0, vh * 0.006)
	var bar_x: float = (vw - bar_w) * 0.5
	var bar_y: float = vh * 0.66
	_progress_bg = ColorRect.new()
	_progress_bg.color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.18)
	_progress_bg.size = Vector2(bar_w, bar_h)
	_progress_bg.position = Vector2(bar_x, bar_y)
	add_child(_progress_bg)
	_progress_rect = ColorRect.new()
	_progress_rect.color = COL_CYAN
	_progress_rect.size = Vector2(0, bar_h)
	_progress_rect.position = Vector2(bar_x, bar_y)
	add_child(_progress_rect)

	# Animated "loading" label
	_dots_label = Label.new()
	_dots_label.text = "loading"
	_dots_label.add_theme_font_size_override("font_size", int(vw * 0.035))
	_dots_label.add_theme_color_override("font_color", Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.85))
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_label.size = Vector2(vw, vh * 0.05)
	_dots_label.position = Vector2(0, vh * 0.70)
	add_child(_dots_label)


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

	if status == ResourceLoader.THREAD_LOAD_LOADED and _time >= MIN_HOLD_SECONDS:
		var packed: PackedScene = ResourceLoader.load_threaded_get(START_SCENE_PATH) as PackedScene
		if packed != null:
			_switched = true
			get_tree().change_scene_to_packed(packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		# Fall back to the path-based loader so the player still gets to
		# the menu even if the threaded request hit a snag.
		_switched = true
		get_tree().change_scene_to_file(START_SCENE_PATH)
