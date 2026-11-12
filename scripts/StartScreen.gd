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
var _side_btn: Button
var _settings_layer: CanvasLayer
var _stats_btn: Button
var _joy_btn: Button
var _online_ui: CanvasLayer
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
var _coop_ui: Node = null


## DEV (debug builds, desktop): drive the co-op lobby from the command line.
##   -- --lobby=http://127.0.0.1:24600 --name=ACE --coop_auto=menu|friend|join|quick [--pid=<uuid>] [--autopilot] [--coopshots=2]
## (never use --shots / --beats: those belong to scripts/tools/ShotDirector.gd)
func _coop_dev_args() -> void:
	if not OS.is_debug_build():
		return
	var auto: String = ""
	var pilot_wanted: bool = false
	var pilot_args := {"autopilot": false, "shot_every": 0.0, "name": "Pilot"}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		match kv[0]:
			"lobby":
				if kv.size() > 1: LobbyApi.url_override = a.trim_prefix("--lobby=")
			"name":
				if kv.size() > 1:
					CoopSession.name_override = kv[1]
					pilot_args["name"] = kv[1]
			"coop_auto":
				if kv.size() > 1: auto = kv[1]
			"pid":
				if kv.size() > 1: LobbyApi.player_id_override = kv[1]
			"scan":   # offer the QR scanner on desktop too (it is phones-only otherwise)
				load("res://scripts/net/CoopLobbyUI.gd").scan_on_desktop = true
			"autopilot":
				pilot_args["autopilot"] = true
				pilot_wanted = true
			"coopshots":
				if kv.size() > 1:
					pilot_args["shot_every"] = float(kv[1])
					pilot_wanted = true
	if pilot_wanted and get_tree().root.get_node_or_null("CoopDevPilot") == null:
		var h: Node = load("res://scripts/net/CoopDevPilot.gd").new()
		h.name = "CoopDevPilot"
		h.pilot = str(pilot_args["name"])
		h.autopilot = bool(pilot_args["autopilot"])
		h.shot_every = float(pilot_args["shot_every"])
		get_tree().root.add_child.call_deferred(h)
	if auto != "" and not _coop_dev_done:
		_coop_dev_done = true
		_coop_ui.dev_auto.call_deferred(auto)

static var _coop_dev_done: bool = false


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	# Make sure the tree isn't still paused from a prior session
	get_tree().paused = false
	# Backstop: a death cinematic interrupted by a scene change must never
	# leave the menu (or the next run) in slow motion.
	Engine.time_scale = 1.0
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
	# Count comes from the game, so the menu can never disagree with the campaign again.
	subtitle.text = "%d SECTORS  ·  ONE SHIP  ·  BREAK THE SKY" % GameState.MAX_LEVEL
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
	# Fourth, slimmer row under EXIT: the touch fire-mode toggle.
	var opt_h: float = btn_h * 0.68
	var col_y: float = panel_y + panel_h - footer_h - (btn_h * 3 + gap * 3 + opt_h) - 10
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

	# Third row: EXIT alone, or CO-OP + EXIT where a co-op lobby exists.
	var exit_w: float = btn_w
	var exit_x: float = col_x
	if LobbyApi.available():
		# Where the app cannot close itself (iOS) there is no EXIT: CO-OP takes the row.
		var coop_w: float = (btn_w - gap) * 0.62 if GameState.app_can_quit else btn_w
		exit_w = btn_w - gap - coop_w
		exit_x = col_x + coop_w + gap
		var coop_btn := _make_button("CO-OP", coop_w, btn_h, Color(0.80, 0.62, 1.00), btn_font)
		coop_btn.name = "CoopButton"
		coop_btn.position = Vector2(col_x, col_y + (btn_h + gap) * 2)
		coop_btn.pressed.connect(func() -> void:
			if not _transitioning:
				_coop_ui.open_menu())
		layer.add_child(coop_btn)
	if GameState.app_can_quit:
		var exit_btn := _make_button("EXIT", exit_w, btn_h, COL_RED, btn_font)
		exit_btn.name = "ExitButton"
		exit_btn.position = Vector2(exit_x, col_y + (btn_h + gap) * 2)
		exit_btn.pressed.connect(_on_exit)
		layer.add_child(exit_btn)

	var opt_font: int = int(clamp(opt_h * 0.40, 16, 26))
	var half_w: float = (btn_w - gap) * 0.5
	var lb_btn := _make_button("LEADERBOARD", half_w, opt_h, COL_GOLD, opt_font)
	lb_btn.position = Vector2(col_x, col_y + (btn_h + gap) * 3)
	lb_btn.pressed.connect(func() -> void:
		if not _transitioning:
			_online_ui.open_leaderboard())
	layer.add_child(lb_btn)
	var settings_btn := _make_button("SETTINGS", half_w, opt_h, COL_GOLD, opt_font)
	settings_btn.position = Vector2(col_x + half_w + gap, col_y + (btn_h + gap) * 3)
	settings_btn.pressed.connect(_open_settings)
	layer.add_child(settings_btn)
	_online_ui = preload("res://scripts/OnlineUI.gd").new()
	_online_ui.host = self
	add_child(_online_ui)
	_coop_ui = preload("res://scripts/net/CoopLobbyUI.gd").new()
	_coop_ui.host = self
	add_child(_coop_ui)
	_coop_dev_args()
	if not GameState.last_run.is_empty():
		_online_ui.call_deferred("open_last_run")
	elif Online.should_ask_name():
		# First launch (9/11): ask the pilot's name once. LATER keeps the
		# server's Pilot-#### name; the prompt stays reachable from the
		# leaderboard screen.
		_online_ui.call_deferred("open_name_prompt", Callable(), true)

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
	GameState.begin_run(randi_range(1, 2147483646))
	# Registers the run for the leaderboard in the background (gets a token);
	# play never waits for it. Offline = the run is simply not ranked.
	Online.start_run()
	_prepare_new_run()


## From the challenge-code screen: needs the server for the challenger's seed.
func start_challenge(code: String, target: int, who: String, msg: Label) -> void:
	if _transitioning:
		return
	_transitioning = true
	GameState.begin_run(0, code, target, who)
	var r: Dictionary = await Online.start_run(code)
	if not r.get("success", false) or GameState.run_seed <= 0:
		_transitioning = false
		if is_instance_valid(msg):
			msg.text = "Could not start the challenge. Check your connection."
		return
	_online_ui.close()
	_prepare_new_run()


func _prepare_new_run() -> void:
	GameState.lives = GameState.STARTING_LIVES
	GameState.current_level = 1
	GameState.clear_carry()
	Telemetry.start_run("new")
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
	GameState.resume_pending = true
	Telemetry.start_run("continue")
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


# --- Settings page ---
# Full-screen overlay above the menu: weapon-button side + fire mode.

func _open_settings() -> void:
	if _transitioning or _settings_layer != null:
		return
	var vw: float = _viewport_size.x
	var vh: float = _viewport_size.y
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 20
	add_child(_settings_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.96)
	dim.size = Vector2(vw, vh)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(dim)
	var pw: float = vw * 0.86
	var bh: float = clamp(vh * 0.07, 54, 86)
	var gap: float = clamp(vh * 0.02, 12, 24)
	var font: int = int(clamp(bh * 0.36, 18, 30))
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_override("font", Fonts.HEADLINE)
	title.add_theme_font_size_override("font_size", int(font * 1.6))
	title.add_theme_color_override("font_color", COL_CYAN)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vw, font * 2.2)
	var top: float = vh * 0.5 - (bh * 4 + gap * 3) * 0.5
	title.position = Vector2(0, top - font * 3.0)
	_settings_layer.add_child(title)
	var x: float = (vw - pw) * 0.5
	_side_btn = _make_button(_side_text(), pw, bh, COL_GOLD, font)
	_side_btn.position = Vector2(x, top)
	_side_btn.pressed.connect(_on_side)
	_settings_layer.add_child(_side_btn)
	_joy_btn = _make_button(_joy_text(), pw, bh, COL_GOLD, font)
	_joy_btn.position = Vector2(x, top + bh + gap)
	_joy_btn.pressed.connect(_on_joy)
	_settings_layer.add_child(_joy_btn)
	_stats_btn = _make_button(_stats_text(), pw, bh, COL_GOLD, font)
	_stats_btn.position = Vector2(x, top + (bh + gap) * 2)
	_stats_btn.pressed.connect(_on_stats)
	_settings_layer.add_child(_stats_btn)
	var note := Label.new()
	note.text = "Anonymous play stats help balance the game.\nNo name, no account, no ads.  ID %s" % Telemetry.player_id.substr(0, 8)
	note.add_theme_font_size_override("font_size", int(font * 0.7))
	note.add_theme_color_override("font_color", Color(0.78, 0.80, 0.92, 0.85))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(vw, font * 2.4)
	note.position = Vector2(0, top + (bh + gap) * 3 - gap * 0.5)
	_settings_layer.add_child(note)
	var back := _make_button("BACK", pw, bh, COL_CYAN, font)
	back.position = Vector2(x, top + (bh + gap) * 3 + font * 2.4)
	back.pressed.connect(_close_settings)
	_settings_layer.add_child(back)


func _joy_text() -> String:
	return "JOYSTICK: ON" if GameState.joystick_enabled else "JOYSTICK: OFF  (DRAG ONLY)"


func _on_joy() -> void:
	GameState.set_joystick_enabled(not GameState.joystick_enabled)
	if _joy_btn != null:
		_joy_btn.text = _joy_text()


func _stats_text() -> String:
	return "PLAY STATS: ON" if Telemetry.enabled else "PLAY STATS: OFF"


func _on_stats() -> void:
	if Telemetry.enabled:
		Telemetry.track("settings_changed", {"stats": false})
		Telemetry.flush()
	Telemetry.set_enabled(not Telemetry.enabled)
	if _stats_btn != null:
		_stats_btn.text = _stats_text()


func _close_settings() -> void:
	if _settings_layer != null:
		Telemetry.track("settings_changed", {
			"side": "right" if GameState.controls_side == GameState.ControlsSide.RIGHT else "left",
			"joystick": GameState.joystick_enabled,
		})
		_stats_btn = null
		_joy_btn = null
		_settings_layer.queue_free()
		_settings_layer = null
		_side_btn = null


func _side_text() -> String:
	if GameState.controls_side == GameState.ControlsSide.LEFT:
		return "WEAPONS LEFT  ·  STICK RIGHT"
	return "WEAPONS RIGHT  ·  STICK LEFT"


func _on_side() -> void:
	var next: int = GameState.ControlsSide.RIGHT if GameState.controls_side == GameState.ControlsSide.LEFT else GameState.ControlsSide.LEFT
	GameState.set_controls_side(next)
	if _side_btn != null:
		_side_btn.text = _side_text()


func _on_exit() -> void:
	get_tree().quit()
