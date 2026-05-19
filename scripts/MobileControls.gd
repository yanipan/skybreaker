extends CanvasLayer
class_name MobileControls
## On-screen touch controls overlay for mobile builds.
##
## Skybreaker's core movement is already touch-driven (drag anywhere on the
## screen to fly the ship — see Player._unhandled_input), but mobile players
## have no way to fire torpedoes or switch weapons because those are bound
## to right-click and middle-click on desktop. This overlay adds:
##
##   * BIG TORPEDO BUTTON in the bottom-right safe area — large circular
##     hitbox so it's hittable with the right thumb without looking. Glows
##     when a torpedo is ready, dims + shows a cooldown ring when empty,
##     and shows the live ammo count in the center.
##   * BIG WEAPON-SWITCH BUTTON in the bottom-left safe area — same size,
##     cycles PHASER → BEAM → MISSILE → PHASER. Center shows the active
##     weapon's letter (P / B / M) so the player always knows what they're
##     about to shoot.
##   * ANIMATED FINGER RING that follows the player's drag position. Gives
##     real visual confirmation that the touch is registering — a major
##     QoL win on phones where the ship offsets above the finger and
##     players otherwise can't tell if their touch was missed.
##
## Design rules:
##   * The two buttons are real Control nodes with mouse_filter = STOP, so
##     taps inside them are CONSUMED before reaching Player._unhandled_input.
##     This means tapping the torpedo button never accidentally yanks the
##     ship to the bottom-right corner — exactly what you want.
##   * The finger ring listens via _input (NOT _unhandled_input) so it sees
##     touches even when other nodes will consume them, but it never calls
##     accept_event() so the player still gets the same events.
##   * Safe area: on iOS / Android we pull DisplayServer.screen_get_usable_rect
##     so the buttons sit above the home indicator and avoid the notch.
##   * Visibility: auto-shows on real mobile builds (OS.has_feature("mobile"))
##     and can be force-shown in the editor via the `force_visible` export
##     for desktop testing without flashing the whole codebase.

## Force the overlay visible even on desktop. Flip this in the inspector or
## via code while testing in the editor — production mobile builds get the
## overlay automatically via OS.has_feature("mobile").
@export var force_visible: bool = false

## Diameter of the action buttons in pixels at the design viewport size.
## Scaled by viewport width at runtime so the buttons feel the same size
## on a 5" phone and a 6.7" phone.
const BUTTON_BASE_SIZE: float = 170.0

## Distance from the safe-area corner to the center of each button.
const BUTTON_INSET: float = 110.0

## How quickly the finger ring fades after the player lifts off.
const RING_FADE_TIME: float = 0.35

## Palette — matches the rest of the HUD so the overlay reads as part of
## the same visual system.
const COL_CYAN := Color(0.55, 0.95, 1.00)
const COL_GOLD := Color(1.00, 0.85, 0.40)
const COL_RED := Color(1.00, 0.45, 0.45)
const COL_PANEL := Color(0.04, 0.08, 0.14, 0.55)
const COL_BORDER_DIM := Color(0.55, 0.95, 1.00, 0.45)

var _viewport_size: Vector2
var _player: Node = null
var _torpedo_btn: Control
var _weapon_btn: Control
var _pause_btn: Control
var _torpedo_label: Label
var _weapon_label: Label
var _torpedo_count_label: Label
var _finger_ring: Node2D
var _ring_pos: Vector2 = Vector2.ZERO
var _ring_alpha: float = 0.0
var _ring_pulse: float = 0.0
var _time: float = 0.0
## Re-resolved every frame from the player so the ammo readout / weapon
## icon stay in sync with shop purchases and pickups.
var _last_torpedo_count: int = -1
var _last_weapon_type: int = -1
## True while at least one player torpedo is in flight — flips the
## torpedo button into DETONATE mode (different label, red glow, faster
## pulse) so the player knows the next tap will manually burst it.
var _last_in_flight: bool = false


func _ready() -> void:
	# Always sit on top of the gameplay HUD. Layer 50 is well above the
	# default HUD layers (typically 1-10) but below pause menu overlays.
	layer = 50
	# Don't pause when the game does — buttons should still respond to a
	# tap that closes the pause menu, etc. Pause menu can hide the layer
	# explicitly when it doesn't want input.
	process_mode = Node.PROCESS_MODE_ALWAYS

	visible = force_visible or OS.has_feature("mobile")
	if not visible:
		return

	_viewport_size = get_viewport().get_visible_rect().size
	_resolve_player()
	_build_finger_ring()
	_build_torpedo_button()
	_build_weapon_button()
	_build_pause_button()
	set_process(true)


# --- Player resolution ---

## The player gets spawned by Main on the same frame as us, so it may not
## exist on the very first _ready. We retry through _process until found.
func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group(&"player")


# --- Finger ring ---
#
# Custom Node2D with a _draw() override. We listen to InputEventScreenTouch
# / InputEventScreenDrag from _input (the highest-priority hook) so we get
# the touch position before anything else, but we never consume the event.

func _build_finger_ring() -> void:
	_finger_ring = Node2D.new()
	_finger_ring.z_index = 100
	add_child(_finger_ring)
	# Draw is wired to a sibling so the parent CanvasLayer doesn't need a
	# _draw of its own (CanvasLayer isn't a CanvasItem).
	_finger_ring.set_script(preload("res://scripts/MobileControlsRing.gd"))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_ring_pos = event.position
			_ring_alpha = 1.0
		else:
			# Don't snap to 0 — let _process fade it out smoothly.
			_ring_alpha = max(_ring_alpha, 0.6)
	elif event is InputEventScreenDrag:
		_ring_pos = event.position
		_ring_alpha = 1.0
	# Desktop testing: mirror with mouse so force_visible mode is usable
	# in the editor without a touchscreen.
	elif force_visible and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_ring_pos = event.position
		_ring_alpha = 1.0
	elif force_visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_ring_pos = event.position
			_ring_alpha = 1.0
		else:
			_ring_alpha = max(_ring_alpha, 0.6)


# --- Torpedo button (bottom-right) ---

func _build_torpedo_button() -> void:
	var safe := _safe_area()
	var size: float = _button_size()
	var center := Vector2(
		safe.position.x + safe.size.x - BUTTON_INSET,
		safe.position.y + safe.size.y - BUTTON_INSET
	)
	_torpedo_btn = _make_circle_button(center, size, &"TORPEDO")
	_torpedo_btn.gui_input.connect(_on_torpedo_input)
	add_child(_torpedo_btn)

	# Center label — large "T" icon
	_torpedo_label = Label.new()
	_torpedo_label.text = "TORP"
	_torpedo_label.add_theme_font_size_override("font_size", int(size * 0.20))
	_torpedo_label.add_theme_color_override("font_color", COL_GOLD)
	_torpedo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_torpedo_label.add_theme_constant_override("outline_size", 4)
	_torpedo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_torpedo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_torpedo_label.size = Vector2(size, size * 0.45)
	_torpedo_label.position = Vector2(0, size * 0.18)
	_torpedo_btn.add_child(_torpedo_label)

	# Ammo count label below the icon
	_torpedo_count_label = Label.new()
	_torpedo_count_label.text = "x0"
	_torpedo_count_label.add_theme_font_size_override("font_size", int(size * 0.32))
	_torpedo_count_label.add_theme_color_override("font_color", Color.WHITE)
	_torpedo_count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_torpedo_count_label.add_theme_constant_override("outline_size", 5)
	_torpedo_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_torpedo_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_torpedo_count_label.size = Vector2(size, size * 0.45)
	_torpedo_count_label.position = Vector2(0, size * 0.42)
	_torpedo_btn.add_child(_torpedo_count_label)


func _on_torpedo_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_fire_torpedo()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_fire_torpedo()
		get_viewport().set_input_as_handled()


func _fire_torpedo() -> void:
	_resolve_player()
	if _player == null or not _player.has_method("_try_fire_torpedo"):
		return
	_player._try_fire_torpedo()
	_pop(_torpedo_btn)
	# Torpedo is a heavy action — medium haptic so the player feels the
	# commitment. AudioManager.haptic_medium is a no-op on desktop.
	if Engine.has_singleton("AudioManager") or get_node_or_null("/root/AudioManager") != null:
		var am: Node = get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("haptic_medium"):
			am.haptic_medium()


# --- Weapon switch button (bottom-left) ---

func _build_weapon_button() -> void:
	var safe := _safe_area()
	var size: float = _button_size()
	var center := Vector2(
		safe.position.x + BUTTON_INSET,
		safe.position.y + safe.size.y - BUTTON_INSET
	)
	_weapon_btn = _make_circle_button(center, size, &"WEAPON")
	_weapon_btn.gui_input.connect(_on_weapon_input)
	add_child(_weapon_btn)

	_weapon_label = Label.new()
	_weapon_label.text = "P"
	_weapon_label.add_theme_font_size_override("font_size", int(size * 0.55))
	_weapon_label.add_theme_color_override("font_color", COL_CYAN)
	_weapon_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_weapon_label.add_theme_constant_override("outline_size", 5)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_weapon_label.size = Vector2(size, size)
	_weapon_label.position = Vector2(0, 0)
	_weapon_btn.add_child(_weapon_label)


func _on_weapon_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_cycle_weapon()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cycle_weapon()
		get_viewport().set_input_as_handled()


func _cycle_weapon() -> void:
	_resolve_player()
	if _player == null or not _player.has_method("cycle_weapon"):
		return
	_player.cycle_weapon()
	_pop(_weapon_btn)
	# Light tap for weapon switch — it's a quick QoL toggle, not a
	# committed action like firing a torpedo.
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("haptic_light"):
		am.haptic_light()


# --- Pause button (top-right safe corner) ---
#
# Mobile has no Esc key and no way to reach the existing keyboard-triggered
# pause toggle in Main.gd. Small top-right button that emits the same
# ui_cancel action the keyboard binding already uses, so Main's _input
# handler picks it up and opens the pause overlay without any cross-wiring.

func _build_pause_button() -> void:
	var safe := _safe_area()
	var size: float = _button_size() * 0.55  # Smaller than the action buttons
	var center := Vector2(
		safe.position.x + safe.size.x - BUTTON_INSET * 0.55,
		safe.position.y + BUTTON_INSET * 0.55
	)
	_pause_btn = _make_circle_button(center, size, &"PAUSE")
	_pause_btn.gui_input.connect(_on_pause_input)
	add_child(_pause_btn)

	# Two vertical bars inside the button = universally-recognized pause icon
	var bars := Control.new()
	bars.size = Vector2(size, size)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_btn.add_child(bars)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = COL_CYAN
		bar.size = Vector2(size * 0.12, size * 0.38)
		bar.position = Vector2(size * 0.38 + i * size * 0.18, size * 0.31)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(bar)


func _on_pause_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_pause()
		get_viewport().set_input_as_handled()


## Routes to Main._toggle_pause directly so we reuse the existing pause
## overlay instead of duplicating it. Main is the root of the current scene
## when MobileControls is active (we're spawned as a Main child), so
## get_tree().current_scene returns the Main node.
func _toggle_pause() -> void:
	_pop(_pause_btn)
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("haptic_light"):
		am.haptic_light()
	var main: Node = get_tree().current_scene
	if main != null and main.has_method("_toggle_pause"):
		main._toggle_pause()


# --- Shared button construction ---
#
# A "circle button" is actually a square Control whose draw() lays down a
# circular panel + border. We use a Control so gui_input fires only inside
# the visible button — the outer corners of the bounding square pass touch
# through to the player's movement handler, which is what we want for
# corner-aligned buttons.

func _make_circle_button(center: Vector2, size: float, name: StringName) -> Control:
	var c := Control.new()
	c.name = String(name)
	c.size = Vector2(size, size)
	c.position = center - Vector2(size, size) * 0.5
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_script(preload("res://scripts/MobileControlsButton.gd"))
	# Pass colors via metadata so the button script doesn't need to know
	# about MobileControls.
	c.set_meta("col_panel", COL_PANEL)
	c.set_meta("col_border", COL_BORDER_DIM)
	c.set_meta("col_glow", COL_CYAN)
	return c


# --- Per-frame update ---

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_resolve_player()

	# Fade the finger ring out when the player isn't touching
	if not _is_any_touch_down():
		_ring_alpha = max(0.0, _ring_alpha - delta / RING_FADE_TIME)
	_ring_pulse = (sin(_time * 4.0) * 0.5 + 0.5)

	if _finger_ring != null and _finger_ring.has_method("update_ring"):
		_finger_ring.update_ring(_ring_pos, _ring_alpha, _ring_pulse)

	# Sync button readouts to player state
	if _player != null and is_instance_valid(_player):
		var tc: int = int(_player.get("torpedo_count")) if "torpedo_count" in _player else 0
		var wt: int = int(_player.get("weapon_type")) if "weapon_type" in _player else 0
		var in_flight: bool = _has_torpedo_in_flight()

		# Detonate mode flips precedence — once a torpedo is in flight the
		# button reads DETONATE regardless of remaining ammo, because the
		# next tap will burst the live torpedo, not consume an ammo charge.
		if in_flight != _last_in_flight or tc != _last_torpedo_count:
			_last_in_flight = in_flight
			_last_torpedo_count = tc
			if _torpedo_label != null:
				if in_flight:
					_torpedo_label.text = "BOOM"
					_torpedo_label.add_theme_color_override("font_color", COL_RED)
				else:
					_torpedo_label.text = "TORP"
					_torpedo_label.add_theme_color_override("font_color", COL_GOLD)
			if _torpedo_count_label != null:
				if in_flight:
					_torpedo_count_label.text = "TAP!"
					_torpedo_count_label.add_theme_color_override("font_color", COL_RED)
				else:
					_torpedo_count_label.text = "x%d" % tc
					_torpedo_count_label.add_theme_color_override(
						"font_color",
						Color.WHITE if tc > 0 else COL_RED
					)
		if wt != _last_weapon_type:
			_last_weapon_type = wt
			if _weapon_label != null:
				_weapon_label.text = ["P", "B", "M"][clamp(wt, 0, 2)]
				_weapon_label.add_theme_color_override("font_color", _color_for_weapon(wt))

		# Pulse + glow color depends on mode:
		#  * DETONATE — fast red pulse, always "ready"
		#  * READY    — gentle cyan pulse, ready
		#  * EMPTY    — dim, slow pulse, not ready
		if _torpedo_btn != null:
			var ready: bool = in_flight or tc > 0
			_torpedo_btn.set_meta("ready", ready)
			if in_flight:
				# Detonate mode — angry red glow + double-speed pulse
				var fast_pulse: float = sin(_time * 9.0) * 0.5 + 0.5
				_torpedo_btn.set_meta("pulse", fast_pulse)
				_torpedo_btn.set_meta("col_glow", COL_RED)
				_torpedo_btn.set_meta("col_border", Color(1.0, 0.5, 0.5, 0.85))
			else:
				_torpedo_btn.set_meta("pulse", _ring_pulse)
				_torpedo_btn.set_meta("col_glow", COL_CYAN)
				_torpedo_btn.set_meta("col_border", COL_BORDER_DIM)
			_torpedo_btn.queue_redraw()
		if _weapon_btn != null:
			_weapon_btn.set_meta("ready", true)
			_weapon_btn.set_meta("pulse", _ring_pulse * 0.5)
			_weapon_btn.queue_redraw()


## True if any player torpedo is currently airborne. Drives the torpedo
## button's DETONATE mode — Player._try_fire_torpedo already routes a
## second tap to detonate_now() on the in-flight torpedo, so we just need
## to surface that state to the player visually.
func _has_torpedo_in_flight() -> bool:
	var torps := get_tree().get_nodes_in_group(&"player_torpedoes")
	for t in torps:
		if is_instance_valid(t):
			return true
	return false


func _is_any_touch_down() -> bool:
	# We don't track touch state explicitly — Input has a pressed-mouse
	# fallback that covers desktop testing, and on mobile the ring just
	# fades after the last drag event, which feels right.
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _color_for_weapon(wt: int) -> Color:
	match wt:
		0: return COL_CYAN              # Phaser
		1: return Color(0.6, 1.0, 0.5)  # Beam
		2: return COL_GOLD              # Missile
		_: return Color.WHITE


# --- Tap feedback ---
# Tween a brief scale pop on the button when pressed for tactile feedback.

func _pop(node: Control) -> void:
	if node == null:
		return
	var t: Tween = create_tween()
	node.pivot_offset = node.size * 0.5
	t.tween_property(node, "scale", Vector2(1.18, 1.18), 0.07)
	t.tween_property(node, "scale", Vector2(1.0, 1.0), 0.12)


# --- Layout helpers ---

## Compute the safe drawable rect, respecting iOS notch / Android home bar.
## On desktop or platforms without a usable rect we just return the full
## viewport.
func _safe_area() -> Rect2:
	if OS.has_feature("mobile"):
		var sr: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var win_size := DisplayServer.window_get_size()
		# Convert from screen pixels to viewport coordinates by ratio.
		var vp := get_viewport().get_visible_rect().size
		var sx: float = vp.x / max(1.0, float(win_size.x))
		var sy: float = vp.y / max(1.0, float(win_size.y))
		return Rect2(
			Vector2(sr.position.x * sx, sr.position.y * sy),
			Vector2(sr.size.x * sx, sr.size.y * sy)
		)
	return get_viewport().get_visible_rect()


## Button size scales gently with viewport width so the controls feel the
## same physical size on different phone aspect ratios.
func _button_size() -> float:
	var vp := get_viewport().get_visible_rect().size
	var scale: float = clamp(vp.x / 816.0, 0.85, 1.4)
	return BUTTON_BASE_SIZE * scale
