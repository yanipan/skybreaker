extends Node2D
class_name StartScreen
## Pre-game start menu — first scene the player sees on launch.
##
## Three options:
##   NEW GAME — fully resets GameState and switches to the gameplay scene.
##   CONTINUE — resumes an in-progress run if one exists.
##   EXIT     — quits the application.
##
## Layout is fully proportional to the actual viewport size returned by
## get_viewport_rect() so the menu fits portrait phones, tablet aspect, and
## the desktop window the editor opens at — the project uses
## stretch_mode="canvas_items" so this can be any size at runtime.

const StarfieldScript := preload("res://scripts/Starfield.gd")
const MAIN_SCENE_PATH: String = "res://scenes/main/Main.tscn"
## Preloaded so the new-game / continue transition swaps in instantly. With
## a runtime change_scene_to_file() call, Godot does the disk load + parse on
## the main thread AFTER freeing StartScreen, leaving the screen blank (grey
## clear color) for several seconds while Main.tscn instantiates. Preloading
## moves all of that cost to script-compile time so the transition is snappy.
const MAIN_SCENE: PackedScene = preload("res://scenes/main/Main.tscn")
# Loaded at runtime so a freshly added image (whose .import sidecar Godot
# may not have generated yet) doesn't crash the parser.
const HERO_PATH: String = "res://assets/sprites/ui/mainmenuphotoskybreaker.png"

# Game palette — same hues used by HUD, bullets and pickups so the menu
# reads as part of the same world.
const COL_CYAN := Color(0.55, 0.95, 1.0)
const COL_GREEN := Color(0.55, 1.0, 0.65)
const COL_RED := Color(1.0, 0.55, 0.55)
const COL_GOLD := Color(1.0, 0.85, 0.40)
const COL_PANEL_BG := Color(0.04, 0.06, 0.12, 0.78)

var _viewport_size: Vector2
var _starfield: Node2D
var _continue_btn: Button
var _hero_sprite: Sprite2D
var _hero_base_pos: Vector2
var _time: float = 0.0
## CanvasLayer that holds the menu chrome (panel, hero, buttons, footer).
## Stored as a member so the start-game handlers can animate the whole layer
## off-screen before switching scenes.
var _menu_layer: CanvasLayer
## True after the player has clicked NEW GAME / CONTINUE — blocks further
## input so the player can't double-trigger the transition.
var _transitioning: bool = false


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	# Make sure the tree isn't still paused from a prior session
	get_tree().paused = false
	_spawn_starfield()
	_build_ui()
	set_process(true)


# --- Drifting starfield ---

func _spawn_starfield() -> void:
	_starfield = StarfieldScript.new()
	_starfield.level = 1
	if "warp_factor" in _starfield:
		_starfield.warp_factor = 0.0
	add_child(_starfield)


func _process(delta: float) -> void:
	_time += delta
	if _hero_sprite != null:
		# Gentle float + very subtle breathing-scale so the hero feels alive.
		var bob: float = sin(_time * 1.4) * 6.0
		_hero_sprite.position = _hero_base_pos + Vector2(0, bob)
		var base_scale: float = _hero_sprite.get_meta("base_scale", 1.0)
		var breathe: float = 1.0 + sin(_time * 1.1) * 0.012
		_hero_sprite.scale = Vector2(base_scale * breathe, base_scale * breathe)


# --- Foreground UI ---
#
# Built once. Everything is sized as a fraction of the actual viewport so
# nothing falls off the bottom on shorter windows. The hero photo is added
# to the same CanvasLayer (after the panel background, before the buttons)
# so it draws on TOP of the dark slab — fixing the "image behind overlay"
# bug from the Sprite2D-in-world version.
func _build_ui() -> void:
	var vw: float = _viewport_size.x
	var vh: float = _viewport_size.y

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_menu_layer = layer

	# --- Panel ---  near-fullscreen with small margins, so we always have
	# room for title + hero + 3 buttons + footer regardless of aspect.
	var panel_w: float = vw * 0.92
	var panel_h: float = vh * 0.94
	var panel_x: float = (vw - panel_w) * 0.5
	var panel_y: float = (vh - panel_h) * 0.5
	var panel := Panel.new()
	panel.position = Vector2(panel_x, panel_y)
	panel.size = Vector2(panel_w, panel_h)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	_add_corner_accents(layer, panel.position, panel.size, COL_CYAN)

	# --- Vertical layout (no title text — it's baked into the hero art) ---
	# Hero band:   top 0.03 .. 0.60   (photo + tagline + divider)
	# Button band: 0.60 .. 0.96       (3 buttons + spacing)
	# Footer band: 0.96 .. 1.00       (high score)
	var hero_top: float = panel_y + panel_h * 0.03
	var hero_bottom: float = panel_y + panel_h * 0.58
	_spawn_hero_in_layer(layer, panel_x, panel_w, hero_top, hero_bottom - hero_top)

	# Tagline sits just under the hero art
	var subtitle_font: int = int(clamp(panel_h * 0.026, 14, 28))
	var subtitle := Label.new()
	subtitle.text = "20 SECTORS  ·  ONE SHIP  ·  BREAK THE SKY"
	subtitle.add_theme_font_override("font", Fonts.SUBHEAD)
	subtitle.add_theme_font_size_override("font_size", subtitle_font)
	subtitle.add_theme_color_override("font_color", COL_GOLD)
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 4)
	subtitle.size = Vector2(panel_w, subtitle_font + 8)
	subtitle.position = Vector2(panel_x, hero_bottom + 2)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(subtitle)

	# Neon divider under the tagline — flanked by two tiny diamond accents
	# for a proper arcade-cabinet feel.
	var div_y: float = hero_bottom + subtitle_font + 14
	var div_w: float = panel_w * 0.68
	var div_x: float = panel_x + (panel_w - div_w) * 0.5
	var divider := ColorRect.new()
	divider.color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.75)
	divider.size = Vector2(div_w, 2)
	divider.position = Vector2(div_x, div_y)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(divider)
	for dx in [-6.0, div_w - 2.0]:
		var diamond := ColorRect.new()
		diamond.color = COL_CYAN
		diamond.size = Vector2(8, 8)
		diamond.position = Vector2(div_x + dx, div_y - 3)
		diamond.rotation = PI * 0.25
		diamond.pivot_offset = Vector2(4, 4)
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(diamond)

	# --- Button column ---
	var btn_h: float = clamp(panel_h * 0.075, 56, 92)
	var gap: float = clamp(panel_h * 0.018, 10, 22)
	var btn_w: float = panel_w * 0.84
	var col_x: float = panel_x + (panel_w - btn_w) * 0.5
	# Anchor the button column to the bottom of the panel (above the footer
	# band) so all three buttons are guaranteed visible.
	var footer_h: float = panel_h * 0.06
	var col_y: float = panel_y + panel_h - footer_h - (btn_h * 3 + gap * 2) - 10
	var btn_font: int = int(clamp(btn_h * 0.42, 22, 36))

	var new_btn := _make_button("NEW GAME", btn_w, btn_h, COL_GREEN, btn_font)
	new_btn.position = Vector2(col_x, col_y)
	new_btn.pressed.connect(_on_new_game)
	layer.add_child(new_btn)

	_continue_btn = _make_button("CONTINUE", btn_w, btn_h, COL_CYAN, btn_font)
	_continue_btn.position = Vector2(col_x, col_y + (btn_h + gap) * 1)
	_continue_btn.pressed.connect(_on_continue)
	_continue_btn.disabled = not GameState.has_active_run
	if _continue_btn.disabled:
		_continue_btn.modulate = Color(0.55, 0.55, 0.65, 0.6)
	layer.add_child(_continue_btn)

	var exit_btn := _make_button("EXIT", btn_w, btn_h, COL_RED, btn_font)
	exit_btn.position = Vector2(col_x, col_y + (btn_h + gap) * 2)
	exit_btn.pressed.connect(_on_exit)
	layer.add_child(exit_btn)

	# Footer high score
	if GameState.high_score > 0:
		var hs := Label.new()
		hs.text = "★ BEST RUN  %d ★" % GameState.high_score
		var hs_font: int = int(clamp(footer_h * 0.55, 14, 24))
		hs.add_theme_font_override("font", Fonts.HEADLINE)
		hs.add_theme_font_size_override("font_size", hs_font)
		hs.add_theme_color_override("font_color", COL_GOLD)
		hs.add_theme_color_override("font_outline_color", Color.BLACK)
		hs.add_theme_constant_override("outline_size", 3)
		hs.size = Vector2(panel_w, footer_h)
		hs.position = Vector2(panel_x, panel_y + panel_h - footer_h - 4)
		hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(hs)


func _spawn_hero_in_layer(layer: CanvasLayer, region_x: float, region_w: float, region_y: float, region_h: float) -> void:
	if region_h <= 20.0:
		return
	var hero_tex: Texture2D = load(HERO_PATH) as Texture2D
	if hero_tex == null:
		return
	_hero_sprite = Sprite2D.new()
	_hero_sprite.texture = hero_tex
	_hero_sprite.centered = true
	var tex_size: Vector2 = hero_tex.get_size()
	var sx: float = (region_w * 0.86) / tex_size.x
	var sy: float = (region_h * 0.95) / tex_size.y
	# Hero gets a bit more room now that there's no redundant title text.
	var s: float = min(sx, sy) * 1.05
	_hero_sprite.scale = Vector2(s, s)
	_hero_sprite.set_meta("base_scale", s)
	_hero_base_pos = Vector2(region_x + region_w * 0.5, region_y + region_h * 0.5)
	_hero_sprite.position = _hero_base_pos
	_hero_sprite.modulate = Color(0.98, 1.0, 1.05)
	layer.add_child(_hero_sprite)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL_BG
	s.border_color = COL_CYAN
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 18
	s.corner_radius_top_right = 18
	s.corner_radius_bottom_left = 18
	s.corner_radius_bottom_right = 18
	s.shadow_color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.35)
	s.shadow_size = 12
	return s


# Tiny neon "L" brackets at each corner of the panel — pure ColorRects.
func _add_corner_accents(parent: CanvasLayer, pos: Vector2, size: Vector2, col: Color) -> void:
	var arm: float = 28.0
	var thick: float = 4.0
	var c := Color(col.r, col.g, col.b, 0.95)
	var corners: Array = [
		Vector2(pos.x, pos.y),
		Vector2(pos.x + size.x, pos.y),
		Vector2(pos.x, pos.y + size.y),
		Vector2(pos.x + size.x, pos.y + size.y),
	]
	var dirs: Array = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for i in corners.size():
		var p: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		var h := ColorRect.new()
		h.color = c
		h.size = Vector2(arm, thick)
		h.position = Vector2(p.x if d.x > 0 else p.x - arm, p.y if d.y > 0 else p.y - thick)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(h)
		var v := ColorRect.new()
		v.color = c
		v.size = Vector2(thick, arm)
		v.position = Vector2(p.x if d.x > 0 else p.x - thick, p.y if d.y > 0 else p.y - arm)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(v)


func _make_button(text: String, w: float, h: float, color: Color, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Fonts.HEADLINE)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 5)
	b.size = Vector2(w, h)
	var normal := _btn_style(color, 0.18)
	var hover := _btn_style(color, 0.32)
	var pressed := _btn_style(color, 0.46)
	var disabled := _btn_style(Color(0.5, 0.5, 0.55), 0.10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
	return b


func _btn_style(color: Color, fill_alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, fill_alpha + 0.35)
	s.border_color = color
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	s.shadow_color = Color(color.r, color.g, color.b, 0.45)
	s.shadow_size = 8
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _on_new_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	GameState.lives = GameState.STARTING_LIVES
	GameState.current_level = 1
	GameState.clear_carry()
	GameState.clear_respawn()
	GameState.reset_mission_stats()
	# New Game means "new story from the beginning" — replay the intro
	# cutscene for returning players too. Anyone bored of it can tap SKIP.
	# Without this reset, a player who already watched the intro once would
	# never see it again even after starting a fresh run.
	GameState.intro_seen = false
	GameState.has_active_run = true
	# Persist the fresh-run state immediately so a crash-to-home-screen
	# right after New Game still lets Continue resume at sector 1.
	GameState.save_run_state()
	_animate_menu_out()


func _on_continue() -> void:
	if _transitioning:
		return
	if not GameState.has_active_run:
		return
	_transitioning = true
	_animate_menu_out()


## Slide the entire menu CanvasLayer up off the screen (TRANS_BACK overshoot
## gives it a snappy "whoosh" feel) while fading it out, then switch to the
## gameplay scene. The starfield underneath stays visible during the slide so
## the transition reads as "the menu peels away to reveal the cockpit."
func _animate_menu_out() -> void:
	if _menu_layer == null or not is_instance_valid(_menu_layer):
		get_tree().change_scene_to_packed(MAIN_SCENE)
		return
	# Block button clicks during the animation so the user can't re-trigger
	for child in _menu_layer.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slide_dur: float = 0.55
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	# Slide the whole canvas layer upward off the top edge
	tween.tween_property(_menu_layer, "offset:y", -_viewport_size.y, slide_dur)
	# Tiny rotation tilt for a bit of "ripped away" character
	tween.tween_property(_menu_layer, "rotation", -0.06, slide_dur)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_packed(MAIN_SCENE)
	)


func _on_exit() -> void:
	get_tree().quit()
