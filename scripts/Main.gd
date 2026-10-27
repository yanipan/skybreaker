extends Node2D
## Root scene of the game. For now, spawns a background, title, and player.

const PlayerScript := preload("res://scripts/Player.gd")
const EnemySpawnerScript := preload("res://scripts/EnemySpawner.gd")
const StarfieldScript := preload("res://scripts/Starfield.gd")


## Score awarded per second the player stays alive
const SURVIVAL_SCORE_PER_SECOND: int = 1

var _viewport_size: Vector2
var _money_label: Label
var _score_label: Label
var _high_score_label: Label
var _lives_label: Label
var _survival_accumulator: float = 0.0

# --- Death sequence ---
# Triggered by EventBus.player_died. Slow-mo + dwell + dramatic label, then
# either reload the same stage (lives left) or full reset (game over).
var _death_active: bool = false
var _death_time_left: float = 0.0
const DEATH_DURATION: float = 2.4
var _death_label: Label = null
var _death_subtitle: Label = null
## True when the current death used the last life. The run wipe + save happen
## immediately in _on_player_died; _finish_death_sequence is visual only.
var _game_over: bool = false

# --- Pause overlay ---
# Toggled with P. Pauses the tree and shows Resume / Main Menu / Quit.
var _pause_layer: CanvasLayer = null

# --- Level state ---
var _starfield: Node2D
var _spawner: EnemySpawner
var _level_data: Dictionary = {}
var _level_banner: Label
var _banner_time_left: float = 0.0
var _level_transitioning: bool = false
# Warp transition — when a level completes we ramp the starfield's warp_factor
# from 0 → 1 and fly the player off the top of the screen for ~1.6s before
# reloading the scene. Way cooler than just snapping to the new sector.
var _warp_total: float = 1.6
var _warp_time_left: float = 0.0
var _warp_active: bool = false
var _warp_label: Label = null
# Full-screen black curtain that fades up at the tail of the warp and fades
# back down at the head of the entry sequence. Its whole job is to HIDE the
# scene reload hitch — `get_tree().reload_current_scene()` causes a short
# freeze while every node gets freed and re-instantiated, and players were
# seeing that freeze as a visible stutter mid-transition. With the curtain
# fully opaque around the reload, the freeze happens off-camera.
var _warp_curtain: ColorRect = null

# Entry sequence — after a warp completes the next scene plays an "arrive
# from below" cinematic: ship slides up from off-screen while warp streaks
# linger for a beat, then settle into normal scrolling.
var _entry_total: float = 1.4
var _entry_time_left: float = 0.0
var _entry_active: bool = false
var _entry_player_target_y: float = 0.0
var _entry_player_start_y: float = 0.0

# Cutscene overlay — true while the story cutscene is on screen between
# sectors. Blocks pause, blocks level-complete re-checks, and freezes
# the spawner (via get_tree().paused from inside Cutscene). The cutscene
# emits `finished` when dismissed and Main either starts the warp
# transition (mid-game triggers) or bounces to StartScreen (ending).
var _cutscene_active: bool = false

# --- Screen shake ---
var _camera: Camera2D
var _shake_intensity: float = 0.0
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0


func _ready() -> void:
	print("=== Skybreaker booting ===")
	_viewport_size = get_viewport_rect().size
	print("Viewport size = ", _viewport_size)

	GameState.reset_mission_stats()
	_level_data = Levels.get_level(GameState.current_level)
	# Snapshot carry_sidekick BEFORE spawning the player — Player._ready calls
	# GameState.clear_carry(), which would otherwise wipe the flag before we
	# get a chance to act on it.
	var should_restore_sidekick: bool = GameState.carry_sidekick
	_spawn_starfield()
	# Parallax layer (planets, nebulae, wreckage) draws AFTER the starfield so
	# it sits in front of the opaque starfield backdrop rect. Visually this
	# reads correctly: distant stars first, then large celestial bodies in
	# front of them, then gameplay on top.
	_spawn_parallax_bg()
	_spawn_camera()
	_spawn_title()
	_spawn_hud()
	_spawn_weapon_meters()
	_spawn_player()
	_spawn_enemy_spawner()
	_spawn_level_banner()
	_spawn_mobile_controls()
	# If we just warped here from the previous sector, kick off the entry
	# cinematic — the player arrives from below the screen and the warp
	# streaks linger for a moment before settling into normal scrolling.
	if GameState.pending_warp_entry:
		GameState.pending_warp_entry = false
		_begin_entry_sequence()
	# Re-spawn the sidekick if one was alive at the end of the previous sector.
	if should_restore_sidekick:
		GameState.carry_sidekick = false
		var player := get_tree().get_first_node_in_group(&"player")
		if player != null and player.has_method("_grant_sidekick"):
			player._grant_sidekick()

	# Intro cutscene — plays once on first-ever entry to sector 1, then
	# `intro_seen` is persisted so a returning player skips it. Deferred one
	# frame so every _ready finishes before the cutscene pauses the tree.
	if GameState.current_level == 1 and not GameState.intro_seen and not GameState.pending_warp_entry:
		call_deferred("_begin_cutscene", CutsceneData.INTRO_KEY, false)

	queue_redraw()

	# Keep the HUD in sync with GameState as money/score change
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.screen_shake_requested.connect(_on_screen_shake_requested)
	EventBus.player_died.connect(_on_player_died)
	_refresh_hud()

	print("=== Boot complete ===")


func _unhandled_input(event: InputEvent) -> void:
	# Toggle pause overlay with P or Esc. Doesn't fire while dying, warping,
	# entering, or during a story cutscene so the player can't pause out
	# of a dramatic transition.
	if _death_active or _warp_active or _entry_active or _cutscene_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
			_toggle_pause()


func _process(delta: float) -> void:
	# Survival score — one point per second of staying alive
	_survival_accumulator += delta
	if _survival_accumulator >= 1.0:
		var ticks: int = int(_survival_accumulator)
		_survival_accumulator -= ticks
		GameState.add_score(ticks * SURVIVAL_SCORE_PER_SECOND)
	_update_shake(delta)
	_update_level_banner(delta)
	_update_warp(delta)
	_update_entry(delta)
	_update_death(delta)
	_check_level_complete()


func _draw() -> void:
	# Solid backdrop in case starfield isn't ready yet — Starfield draws over this.
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.03, 0.03, 0.08), true)


## Far-distance parallax layer (planets, debris). Must be spawned BEFORE the
## starfield so it naturally ends up behind it in the tree; the node also
## sets z_index = -10 as a belt-and-braces against z-order bugs.
## Three vertical weapon power meters anchored to the left edge of the screen.
## Driven by the new per-weapon level system in Player.gd. Spawned BEFORE the
## player so the widget exists by the time the player polls.
func _spawn_weapon_meters() -> void:
	var script: GDScript = load("res://scripts/WeaponMeters.gd") as GDScript
	if script == null:
		print("WeaponMeters script missing — skipping")
		return
	var meters: Node2D = script.new() as Node2D
	if meters == null:
		return
	add_child(meters)


func _spawn_parallax_bg() -> void:
	var script: GDScript = load("res://scripts/ParallaxBg.gd") as GDScript
	if script == null:
		return
	var bg: Node2D = script.new() as Node2D
	if bg == null:
		return
	add_child(bg)


func _spawn_starfield() -> void:
	_starfield = StarfieldScript.new()
	# Starfield picks its own per-act palette from the level number.
	# We additionally apply the per-level theme_color tint on top so neighbors
	# in the same act still read distinctly.
	_starfield.level = GameState.current_level
	var tint: Color = _level_data.get("theme_color", Color(1, 1, 1))
	_starfield.modulate = tint
	add_child(_starfield)


func _spawn_camera() -> void:
	# Camera2D is the cleanest way to do screen shake — we just nudge its offset.
	# It's centered on the viewport and stays put unless shake is active.
	_camera = Camera2D.new()
	_camera.position = _viewport_size * 0.5
	_camera.make_current()
	add_child(_camera)


func _on_screen_shake_requested(intensity: float, duration: float) -> void:
	# Take the strongest pending shake — additive feels jittery, max feels punchy.
	if intensity > _shake_intensity or _shake_time_left <= 0.0:
		_shake_intensity = intensity
		_shake_time_left = duration
		_shake_duration = duration


func _update_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_time_left > 0.0:
		_shake_time_left = max(0.0, _shake_time_left - delta)
		# Decay intensity smoothly toward zero so the shake settles
		var k: float = _shake_time_left / _shake_duration if _shake_duration > 0.0 else 0.0
		var amp: float = _shake_intensity * k
		var ox: float = randf_range(-amp, amp)
		var oy: float = randf_range(-amp, amp)
		_camera.offset = Vector2(ox, oy)
	else:
		_camera.offset = Vector2.ZERO


func _spawn_title() -> void:
	# In-game HUD title — uses the gamelogo art instead of plain text so the
	# top-of-screen branding matches the start menu. Centered horizontally
	# and scaled to a comfortable banner height.
	# load() instead of preload() so the script doesn't fail to parse on the
	# very first run after the PNG is added (Godot's importer hasn't yet
	# generated the .import sidecar at parse time).
	var logo_raw: Texture2D = load("res://assets/sprites/ui/gamelogo.png") as Texture2D
	if logo_raw == null:
		print("Title logo missing — skipping title spawn")
		return
	# Strip the white background out of the logo so the HUD shows just the
	# letterforms over the starfield. Same chroma-key trick used on BOSS2.
	var logo: Texture2D = _strip_white_bg(logo_raw)
	if logo == null:
		logo = logo_raw
	var sprite := Sprite2D.new()
	sprite.texture = logo
	sprite.centered = true
	# Banner anchored to the LEFT side of the HUD — sits above the FUNDS/lives
	# column instead of dead-center, so it stops competing with the score
	# block on the right and reads as a proper top-left brand.
	var target_h: float = 120.0
	var src: Vector2 = logo.get_size()
	if src.y > 0:
		var s: float = target_h / src.y
		# Cap so the logo never reaches the score column on the right.
		var max_w: float = _viewport_size.x * 0.55
		if src.x * s > max_w:
			s = max_w / src.x
		sprite.scale = Vector2(s, s)
	# Centered sprite — place its center a bit in from the left edge so the
	# left side of the artwork lines up roughly with the FUNDS label.
	var logo_w: float = src.x * sprite.scale.x
	sprite.position = Vector2(20.0 + logo_w * 0.5, 70)
	add_child(sprite)
	print("Title spawned (logo)")


# Chroma-key strip: removes near-white pixels by sampling the four corners,
# averaging them as a key color, and erasing every pixel within tolerance.
# Returns null on failure so the caller can fall back to the raw texture.
func _strip_white_bg(tex: Texture2D) -> ImageTexture:
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return null
	var c00: Color = img.get_pixel(0, 0)
	var c10: Color = img.get_pixel(w - 1, 0)
	var c01: Color = img.get_pixel(0, h - 1)
	var c11: Color = img.get_pixel(w - 1, h - 1)
	var key := Color(
		(c00.r + c10.r + c01.r + c11.r) * 0.25,
		(c00.g + c10.g + c01.g + c11.g) * 0.25,
		(c00.b + c10.b + c01.b + c11.b) * 0.25,
		1.0
	)
	var tol: float = 0.20
	for y in h:
		for x in w:
			var p: Color = img.get_pixel(x, y)
			var dr: float = p.r - key.r
			var dg: float = p.g - key.g
			var db: float = p.b - key.b
			if dr * dr + dg * dg + db * db < tol:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _spawn_hud() -> void:
	# Money — left column, tucked BELOW the logo banner (logo center y=70,
	# height ~120, so its bottom edge sits near y=130).
	_money_label = Label.new()
	_money_label.position = Vector2(30, 140)
	_money_label.add_theme_font_override("font", Fonts.HEADLINE)
	_money_label.add_theme_font_size_override("font_size", 28)
	_money_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	add_child(_money_label)

	# Score — top-right. Width pinned to the right edge with a bit of padding
	# so the label can grow with longer numbers without running off-screen.
	var score_w: float = 260.0
	var score_x: float = _viewport_size.x - score_w - 16.0
	_score_label = Label.new()
	_score_label.position = Vector2(score_x, 60)
	_score_label.size = Vector2(score_w, 40)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_override("font", Fonts.HEADLINE)
	_score_label.add_theme_font_size_override("font_size", 28)
	_score_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_score_label)

	# High score — under score, dimmer/smaller
	_high_score_label = Label.new()
	_high_score_label.position = Vector2(score_x, 96)
	_high_score_label.size = Vector2(score_w, 28)
	_high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_high_score_label.add_theme_font_override("font", Fonts.SUBHEAD)
	_high_score_label.add_theme_font_size_override("font_size", 20)
	_high_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	add_child(_high_score_label)

	# Lives — under money on the left, hearts read instantly across the HUD
	_lives_label = Label.new()
	_lives_label.position = Vector2(30, 178)
	_lives_label.size = Vector2(290, 32)
	_lives_label.add_theme_font_size_override("font_size", 26)
	_lives_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	add_child(_lives_label)


func _refresh_hud() -> void:
	if _money_label != null:
		_money_label.text = "$%d" % GameState.money
	if _score_label != null:
		_score_label.text = "SCORE %d" % GameState.mission_score
	if _high_score_label != null:
		# Show the higher of saved best vs the current run, so a new record
		# updates live as the player passes their previous best.
		var best: int = max(GameState.high_score, GameState.mission_score)
		_high_score_label.text = "BEST %d" % best
	if _lives_label != null:
		# One heart glyph per remaining life — caps at MAX_LIVES.
		var hearts := ""
		var shown_lives: int = 0 if _game_over else GameState.lives
		for i in clamp(shown_lives, 0, GameState.MAX_LIVES):
			hearts += "♥ "
		_lives_label.text = hearts.strip_edges()


func _on_money_changed(_value: int) -> void:
	_refresh_hud()


func _on_score_changed(_value: int) -> void:
	_refresh_hud()


func _spawn_player() -> void:
	var player: Area2D = PlayerScript.new()
	# Lower portion of screen — classic shmup player position
	player.position = Vector2(_viewport_size.x * 0.5, _viewport_size.y * 0.78)
	add_child(player)
	print("Player spawned at ", player.position)


func _spawn_enemy_spawner() -> void:
	_spawner = EnemySpawnerScript.new()
	add_child(_spawner)
	print("EnemySpawner active")


## Touch overlay for mobile builds — torpedo + weapon-switch buttons and a
## finger ring at the touch position. Auto-hides on desktop unless the
## script's force_visible export is flipped for editor testing.
func _spawn_mobile_controls() -> void:
	var mc := preload("res://scripts/MobileControls.gd").new()
	add_child(mc)


func _spawn_level_banner() -> void:
	# Big centered "Sector N: Name" title that fades out after a couple seconds.
	_level_banner = Label.new()
	_level_banner.text = String(_level_data.get("name", "Sector"))
	_level_banner.add_theme_font_override("font", Fonts.HEADLINE)
	_level_banner.add_theme_font_size_override("font_size", 56)
	_level_banner.add_theme_color_override("font_color", Color(1, 1, 1))
	_level_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_level_banner.add_theme_constant_override("outline_size", 6)
	_level_banner.size = Vector2(_viewport_size.x, 80)
	_level_banner.position = Vector2(0, _viewport_size.y * 0.35)
	_level_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_level_banner)
	_banner_time_left = 3.0


func _update_level_banner(delta: float) -> void:
	if _level_banner == null or _banner_time_left <= 0.0:
		return
	_banner_time_left = max(0.0, _banner_time_left - delta)
	# Fade out over the last second
	var a: float = clamp(_banner_time_left, 0.0, 1.0)
	_level_banner.modulate = Color(1, 1, 1, a if _banner_time_left < 1.0 else 1.0)
	if _banner_time_left <= 0.0:
		_level_banner.queue_free()
		_level_banner = null


func _check_level_complete() -> void:
	if _level_transitioning or _entry_active or _spawner == null or _cutscene_active or _death_active:
		return
	if _spawner.get_mission_time() < _spawner.get_level_duration():
		return
	# If this is a boss stage, the boss must die before the level can advance
	# (otherwise the timer would end the fight prematurely).
	var bosses := get_tree().get_nodes_in_group(&"bosses")
	if not bosses.is_empty():
		return
	# Story intercept — if this sector completion triggers a cutscene, play
	# it before the warp. Cutscene's `finished` signal resumes the original
	# warp transition, so the player sees: beats → fade to black → warp
	# cinematic → scene reload.
	var trigger_key: StringName = CutsceneData.TRIGGERS.get(GameState.current_level, &"")
	if trigger_key != &"":
		_begin_cutscene(trigger_key, true)
		return
	_begin_warp_transition()


## Spawn the cutscene overlay, play the beat list for `key`, and hook the
## `finished` signal to whatever should happen next.
##
## `then_warp` controls post-dismissal routing:
##   * true  — mid-game trigger (sectors 5/10/15/19): continue with warp
##             transition to the next sector.
##   * false — intro trigger OR ending trigger: no warp follows. For
##             ending, we additionally bounce back to StartScreen and
##             wipe the run so the player lands on the menu.
func _begin_cutscene(key: StringName, then_warp: bool) -> void:
	if _cutscene_active:
		return
	var beats: Array = CutsceneData.beats_for(key)
	if beats.is_empty():
		# No beats defined — fall through to whatever would have happened.
		if then_warp:
			_begin_warp_transition()
		return
	_cutscene_active = true
	# Freeze the spawner so nothing keeps ticking behind the overlay. The
	# cutscene also pauses the whole tree via get_tree().paused, but the
	# explicit spawner freeze is defense-in-depth.
	if _spawner != null:
		_spawner.set_process(false)

	var cs: Cutscene = preload("res://scripts/Cutscene.gd").new()
	add_child(cs)
	var is_ending: bool = key == CutsceneData.ENDING_KEY
	cs.finished.connect(func() -> void:
		_cutscene_active = false
		# Mark intro as seen regardless of whether player tapped skip —
		# once they've been shown it, we don't subject them to it again.
		if key == CutsceneData.INTRO_KEY and not GameState.intro_seen:
			GameState.intro_seen = true
			_snapshot_and_save()
		if is_ending:
			# Ending: wipe the run and bounce to StartScreen. No warp.
			GameState.has_active_run = false
			GameState.current_level = 1
			GameState.lives = GameState.STARTING_LIVES
			GameState.clear_carry()
			GameState.clear_respawn()
			GameState.save_run_state()
			get_tree().change_scene_to_file("res://scenes/main/StartScreen.tscn")
		elif then_warp:
			_begin_warp_transition()
		else:
			# Intro: resume gameplay. Spawner already frozen — unfreeze.
			if _spawner != null:
				_spawner.set_process(true)
	)
	cs.play(beats)


## Kicks off the warp animation. Locks transition state, stops new spawns,
## clears the active enemies/bullets so the warp screen reads as clean space,
## and starts the warp_factor ramp on the starfield.
func _begin_warp_transition() -> void:
	_level_transitioning = true
	_warp_active = true
	_warp_time_left = _warp_total
	# Stop further spawns and pickup drops mid-warp
	if _spawner != null:
		_spawner.set_process(false)
	# Clear current enemies + bullets so the warp jump looks like deep space.
	# Pickups are intentionally NOT cleared here — _update_warp magnetises them
	# to the player during the ramp so the player scoops up anything still on
	# the field as a reward for clearing the sector.
	for grp in [&"enemies", &"enemy_bullets", &"player_bullets", &"bosses", &"starbases"]:
		for n in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n):
				n.queue_free()
	# Big "WARP" headline label
	_warp_label = Label.new()
	_warp_label.text = "WARPING TO SECTOR %d" % min(GameState.current_level + 1, GameState.MAX_LEVEL)
	_warp_label.add_theme_font_override("font", Fonts.HEADLINE)
	_warp_label.add_theme_font_size_override("font_size", 60)
	_warp_label.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
	_warp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_warp_label.add_theme_constant_override("outline_size", 6)
	_warp_label.size = Vector2(_viewport_size.x, 80)
	_warp_label.position = Vector2(0, _viewport_size.y * 0.40)
	_warp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_warp_label)
	# Black fade curtain — alpha starts at 0 and ramps to 1 during the last
	# stretch of the warp so the reload_current_scene() hitch happens under
	# a solid black screen instead of a visibly frozen starfield.
	_warp_curtain = ColorRect.new()
	_warp_curtain.color = Color(0, 0, 0, 0)
	_warp_curtain.size = _viewport_size
	_warp_curtain.position = Vector2.ZERO
	_warp_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_curtain.z_index = 4096
	add_child(_warp_curtain)


## Drives the warp ramp each frame. Eases warp_factor 0 → 1, flies the player
## up off the screen, then commits the carry slots and reloads the scene.
func _update_warp(delta: float) -> void:
	if not _warp_active:
		return
	_warp_time_left = max(0.0, _warp_time_left - delta)
	var t: float = 1.0 - (_warp_time_left / _warp_total)   # 0..1 progress
	# Smoothstep for an easy-out feel
	var eased: float = t * t * (3.0 - 2.0 * t)
	if _starfield != null:
		_starfield.warp_factor = eased
	# Camera shake from the engines straining
	_shake_intensity = max(_shake_intensity, 3.0 + 6.0 * eased)
	_shake_time_left = 0.15
	_shake_duration = 0.15
	# Fly the player upward off the top of the screen
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and is_instance_valid(player):
		var fly_speed: float = 200.0 + 1100.0 * eased
		player.position.y -= fly_speed * delta
		# Override the drag target so the player doesn't snap back down
		if "_target_position" in player:
			player._target_position = player.position
		# Magnet sweep: any pickups still floating on the field accelerate
		# toward the player so the warp jump scoops them all up. Speed ramps
		# with the warp progress so leftover drops streak in like tracer
		# rounds right before the cut.
		var magnet_speed: float = 700.0 + 2400.0 * eased
		for p in get_tree().get_nodes_in_group(&"pickups"):
			if not is_instance_valid(p):
				continue
			var to_player: Vector2 = player.position - p.position
			var dist: float = to_player.length()
			if dist < 4.0:
				# Close enough — let the normal Area2D collision trigger the
				# pickup effect rather than teleporting it.
				continue
			var step: float = magnet_speed * delta
			if step >= dist:
				p.position = player.position
			else:
				p.position += to_player / dist * step
	# Pulse the warp label
	if _warp_label != null:
		var k: float = 0.7 + 0.3 * sin(_warp_time_left * 14.0)
		_warp_label.modulate = Color(1, 1, 1, k)
	# Curtain fade-in during the last 55% of warp. By t=1.0 the screen is
	# fully black so the scene reload freeze is invisible.
	if _warp_curtain != null:
		var curtain_a: float = clamp((t - 0.45) / 0.55, 0.0, 1.0)
		_warp_curtain.color = Color(0, 0, 0, curtain_a)
	if _warp_time_left <= 0.0:
		_finish_warp_transition()


## Stashes carry state and reloads the scene to the next sector.
func _finish_warp_transition() -> void:
	_warp_active = false
	# Backstop: never carry slow-mo into the next sector.
	Engine.time_scale = 1.0
	GameState.commit_high_score()
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		GameState.snapshot_player(player)
	# Sidekick survives the jump if one is currently in the field.
	GameState.carry_sidekick = get_tree().get_first_node_in_group(&"sidekick") != null
	if GameState.current_level < GameState.MAX_LEVEL:
		GameState.current_level += 1
	GameState.pending_warp_entry = true
	# commit_high_score earlier in this function already fired a save, but
	# it ran BEFORE the carry_* and current_level updates above. Save again
	# now so the on-disk state matches what we're about to reload into.
	GameState.save_run_state()
	print("Level complete — advancing to ", GameState.current_level)
	get_tree().reload_current_scene()


# --- Entry sequence (warp arrival) ---

## Plays the "drop in from below" cinematic at the start of a sector that
## was reached via warp. Pushes the player off the bottom of the screen,
## holds the starfield in warp streak mode, and slides everything into
## place over _entry_total seconds. Spawns are frozen until it finishes.
func _begin_entry_sequence() -> void:
	_entry_active = true
	_entry_time_left = _entry_total
	# Start the new scene under a full-black curtain and fade it out during
	# the first stretch of the entry — matches the fade-in at the end of the
	# previous sector's warp so the transition reads as one continuous fade
	# through black instead of a freeze-jump.
	_warp_curtain = ColorRect.new()
	_warp_curtain.color = Color(0, 0, 0, 1)
	_warp_curtain.size = _viewport_size
	_warp_curtain.position = Vector2.ZERO
	_warp_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_curtain.z_index = 4096
	add_child(_warp_curtain)
	# Hold spawns until the cinematic ends so the player isn't shot at
	# while their ship is still flying onto the field.
	if _spawner != null:
		_spawner.set_process(false)
	# Starfield begins streaking, settles to normal as the entry plays out.
	if _starfield != null:
		_starfield.warp_factor = 0.85
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and is_instance_valid(player):
		_entry_player_target_y = player.position.y
		_entry_player_start_y = _viewport_size.y + 120.0
		player.position.y = _entry_player_start_y
		# Make the player drag target follow so they don't snap back.
		if "_target_position" in player:
			player._target_position = player.position
		# Disable collision while flying in so they can't be hit before they're "real".
		player.set_deferred("monitoring", false)
		player.set_deferred("monitorable", false)


func _update_entry(delta: float) -> void:
	if not _entry_active:
		return
	_entry_time_left = max(0.0, _entry_time_left - delta)
	var t: float = 1.0 - (_entry_time_left / _entry_total)   # 0..1 progress
	# Ease-out for the slide so the ship arrives gently into place.
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	# Warp streaks fade out: hold high early, drop fast at the end.
	if _starfield != null:
		_starfield.warp_factor = (1.0 - eased) * 0.85
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and is_instance_valid(player):
		player.position.y = lerp(_entry_player_start_y, _entry_player_target_y, eased)
		if "_target_position" in player:
			player._target_position = player.position
	# Fade the black curtain out during the first 55% of the entry so the
	# new sector reveals smoothly under the incoming ship.
	if _warp_curtain != null:
		var curtain_a: float = clamp(1.0 - t / 0.55, 0.0, 1.0)
		_warp_curtain.color = Color(0, 0, 0, curtain_a)
	if _entry_time_left <= 0.0:
		_finish_entry_sequence()


func _finish_entry_sequence() -> void:
	_entry_active = false
	if _starfield != null:
		_starfield.warp_factor = 0.0
	if _warp_curtain != null and is_instance_valid(_warp_curtain):
		_warp_curtain.queue_free()
	_warp_curtain = null
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and is_instance_valid(player):
		player.position.y = _entry_player_target_y
		if "_target_position" in player:
			player._target_position = player.position
		player.set_deferred("monitoring", true)
		player.set_deferred("monitorable", true)
	if _spawner != null:
		_spawner.set_process(true)


# --- Death sequence ---

## Triggered by EventBus.player_died from Player._die(). Stashes a respawn
## snapshot, decrements lives, then plays a slow-motion explosion dwell. After
## DEATH_DURATION seconds we either reload the same stage (lives > 0) or
## perform the full game-over reset to Sector 1.
func _on_player_died() -> void:
	if _death_active:
		return
	# Sector already cleared and warping out — the warp wins, ignore the death
	# so we never stash respawn/carry from a dead player one sector ahead.
	if _warp_active or _level_transitioning:
		return
	_death_active = true
	_death_time_left = DEATH_DURATION
	# Any mid-level carry snapshot (pause / shop / focus-out) is superseded
	# by the respawn slot — drop it so its sidekick flag etc. can't leak
	# into the respawned stage.
	GameState.clear_carry()
	# Stash respawn snapshot BEFORE decrementing — this captures their gear
	# at the moment of death (50% rounded up).
	var player := get_tree().get_first_node_in_group(&"player")
	var lives_after: int = GameState.lives - 1
	if player != null and lives_after > 0:
		GameState.stash_respawn(player)
	GameState.lives = max(0, lives_after)
	_game_over = lives_after <= 0
	if _game_over:
		# Full game over — wipe the run and persist it NOW. If the OS kills
		# the app during the death cinematic, relaunch must not offer
		# Continue into a 0-life run with un-halved money.
		# Cash penalty: losing the run burns 50% of the player's funds so the
		# stakes don't feel weightless. Rounded down, floored at 0.
		var lost: int = GameState.money / 2
		GameState.money = max(0, GameState.money - lost)
		print("GAME OVER — lost $%d (50%%)" % lost)
		GameState.has_active_run = false
		GameState.current_level = 1
		GameState.lives = GameState.STARTING_LIVES
		GameState.clear_carry()
		GameState.clear_respawn()
		# Saves unconditionally (mission_score still intact for the record).
		GameState.commit_high_score()
		EventBus.money_changed.emit(GameState.money)
	else:
		# Persist death + respawn slot immediately. If the OS kills the app
		# during the death cinematic, the player's respawn gear is still there.
		GameState.save_run_state()
	_refresh_hud()
	# Freeze new spawns and clear the field so the dramatic moment reads clean.
	if _spawner != null:
		_spawner.set_process(false)
	# Heavy time-extended shake — wobbles for the whole sequence
	_shake_intensity = 18.0
	_shake_time_left = DEATH_DURATION
	_shake_duration = DEATH_DURATION
	# Big centered SHIP DESTROYED label
	_death_label = Label.new()
	_death_label.text = "SHIP DESTROYED"
	_death_label.add_theme_font_override("font", Fonts.HEADLINE)
	_death_label.add_theme_font_size_override("font_size", 72)
	_death_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.25))
	_death_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_death_label.add_theme_constant_override("outline_size", 8)
	_death_label.size = Vector2(_viewport_size.x, 90)
	_death_label.position = Vector2(0, _viewport_size.y * 0.38)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.modulate = Color(1, 1, 1, 0)
	add_child(_death_label)
	# Subtitle — either lives remaining or GAME OVER
	_death_subtitle = Label.new()
	if not _game_over:
		_death_subtitle.text = "%d LIVES REMAINING" % GameState.lives
		_death_subtitle.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	else:
		_death_subtitle.text = "GAME OVER"
		_death_subtitle.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_death_subtitle.add_theme_font_size_override("font_size", 38)
	_death_subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	_death_subtitle.add_theme_constant_override("outline_size", 5)
	_death_subtitle.size = Vector2(_viewport_size.x, 50)
	_death_subtitle.position = Vector2(0, _viewport_size.y * 0.50)
	_death_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_subtitle.modulate = Color(1, 1, 1, 0)
	add_child(_death_subtitle)


## Drives the death dwell. Engine.time_scale ramps to slow-mo and the labels
## fade in. When the timer expires we reload the scene with the appropriate
## GameState — same level for a respawn, level 1 for a game over.
func _update_death(delta: float) -> void:
	if not _death_active:
		return
	_death_time_left = max(0.0, _death_time_left - delta)
	var t: float = 1.0 - (_death_time_left / DEATH_DURATION)
	# Slow-mo ramps in over the first 0.4s, then back to normal at the end
	var slow: float = 1.0 - 0.65 * clamp(t * 2.5, 0.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, t))
	Engine.time_scale = clamp(slow, 0.25, 1.0)
	if _death_label != null:
		_death_label.modulate = Color(1, 1, 1, clamp(t * 2.0, 0.0, 1.0))
	if _death_subtitle != null:
		_death_subtitle.modulate = Color(1, 1, 1, clamp((t - 0.2) * 2.5, 0.0, 1.0))
	if _death_time_left <= 0.0:
		_finish_death_sequence()


# --- Pause overlay ---

## Single entry point for keyboard AND the mobile pause button, so the state
## guard lives here. Closing is always allowed; opening is refused while
## dying, warping, entering, in a cutscene, or while something else (the
## starbase shop) already holds the tree paused.
func _toggle_pause() -> void:
	if _pause_layer != null:
		_close_pause()
	elif _can_open_pause():
		_open_pause()


func _can_open_pause() -> bool:
	if _death_active or _warp_active or _entry_active or _cutscene_active or _level_transitioning:
		return false
	if get_tree().paused:
		return false
	return true


## Snapshot the live player into the carry slot (no penalty) and save. Every
## mid-level save must go through here — Player._ready already consumed the
## carry/respawn slots, so a bare save would persist default gear.
func _snapshot_and_save() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		GameState.snapshot_player(player)
	GameState.save_run_state()


## App backgrounded (home swipe, call, notification shade): open the pause
## overlay, which snapshots + saves. Main only exists during gameplay, so this
## never runs on StartScreen.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if not is_inside_tree() or not GameState.has_active_run:
		return
	if _pause_layer != null:
		return
	if _death_active or _warp_active or _entry_active or _cutscene_active or _level_transitioning:
		return
	if get_tree().paused:
		# Shop holds the tree paused — don't stack the pause overlay on it,
		# just persist the current loadout.
		_snapshot_and_save()
		return
	_open_pause()


func _open_pause() -> void:
	# Pause is the most common quit precursor on mobile (player swipes home
	# or gets a call) — save the full run state before freezing so the app
	# can die mid-pause without losing anything.
	_snapshot_and_save()
	get_tree().paused = true
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 110
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.size = _viewport_size
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.add_child(dim)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.size = Vector2(_viewport_size.x, 90)
	title.position = Vector2(0, _viewport_size.y * 0.25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_layer.add_child(title)

	var btn_w: float = 460
	var btn_h: float = 92
	var col_x: float = (_viewport_size.x - btn_w) * 0.5
	var col_y: float = _viewport_size.y * 0.42
	var gap: float = 24

	var resume_btn := _make_pause_button("RESUME", btn_w, btn_h, Color(0.55, 1.0, 0.65))
	resume_btn.position = Vector2(col_x, col_y)
	resume_btn.pressed.connect(_close_pause)
	_pause_layer.add_child(resume_btn)

	var menu_btn := _make_pause_button("MAIN MENU", btn_w, btn_h, Color(0.65, 0.95, 1.0))
	menu_btn.position = Vector2(col_x, col_y + (btn_h + gap))
	menu_btn.pressed.connect(_on_main_menu)
	_pause_layer.add_child(menu_btn)

	var quit_btn := _make_pause_button("QUIT", btn_w, btn_h, Color(1.0, 0.55, 0.55))
	quit_btn.position = Vector2(col_x, col_y + (btn_h + gap) * 2)
	quit_btn.pressed.connect(_on_quit_app)
	_pause_layer.add_child(quit_btn)


func _make_pause_button(text: String, w: float, h: float, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.size = Vector2(w, h)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b


func _close_pause() -> void:
	if _pause_layer != null:
		_pause_layer.queue_free()
		_pause_layer = null
	get_tree().paused = false


func _on_main_menu() -> void:
	Engine.time_scale = 1.0
	# No-penalty carry snapshot so Continue from the start screen restores the
	# player's current loadout exactly. has_active_run stays true so Continue
	# is enabled. Never snapshot a finished (0-life) run.
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and GameState.lives > 0 and GameState.has_active_run:
		GameState.snapshot_player(player)
	GameState.commit_high_score()
	# commit_high_score already saves — but this is an explicit quit-ish
	# action, so the redundancy is cheap insurance against a store crash.
	GameState.save_run_state()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main/StartScreen.tscn")


func _on_quit_app() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit()


func _finish_death_sequence() -> void:
	_death_active = false
	Engine.time_scale = 1.0
	GameState.commit_high_score()
	if not _game_over:
		# Respawn slot already stashed in _on_player_died — just reload current stage.
		print("Respawning at sector ", GameState.current_level)
		get_tree().reload_current_scene()
	else:
		# Game over — the run wipe and 50% money penalty were already applied
		# and saved in _on_player_died. Visual only: bounce to the start screen.
		print("GAME OVER — returning to start screen")
		GameState.reset_mission_stats()
		get_tree().change_scene_to_file("res://scenes/main/StartScreen.tscn")
