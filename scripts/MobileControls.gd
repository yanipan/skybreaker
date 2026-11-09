extends CanvasLayer
class_name MobileControls
## On-screen touch controls overlay for mobile builds.
##
## Skybreaker's core movement is already touch-driven (drag anywhere on the
## screen to fly the ship — see Player._unhandled_input). Desktop binds fire
## to left-click and torpedoes to right-click; this overlay adds the mobile
## equivalents:
##
##   * (6/11) The FIRE button + double-tap switch is replaced by ONE BUTTON
##     PER WEAPON (P / B / M) plus the torpedo, all clustered in one bottom
##     corner (GameState.controls_side, set on the Settings page). Pressing
##     a weapon button selects it and fires (HOLD) or pauses fire (AUTO).
##     Buttons are ~30% smaller than before. Notes below predate this.
##   * BIG TORPEDO BUTTON in the bottom-right safe area — large circular
##     hitbox so it's hittable with the right thumb without looking. Glows
##     when a torpedo is ready, dims + shows a cooldown ring when empty,
##     and shows the live ammo count in the center.
##   * BIG FIRE BUTTON in the bottom-left safe area — 1.2× the action-button
##     size, kept fully on-screen in the safe area. Label reads "FIRE"
##     (or "STOP" in AUTO fire_mode) with the active weapon letter
##     (P / B / M) underneath, coloured to the current weapon. HOLD mode
##     fires while held; AUTO mode pauses fire while held. Double-tap
##     anywhere else (consumed button taps never reach the player) cycles
##     PHASER → BEAM → MISSILE. Release is delivered even if the finger
##     slides off the control.
##   * ANIMATED FINGER RING that follows the player's drag position. Gives
##     real visual confirmation that the touch is registering — a major
##     QoL win on phones where the ship offsets above the finger and
##     players otherwise can't tell if their touch was missed.
##
## Design rules:
##   * The two buttons are real Control nodes with mouse_filter = STOP, so
##     taps inside them are CONSUMED before reaching Player._unhandled_input.
##     This means tapping the fire/torpedo button never accidentally yanks
##     the ship to that corner — exactly what you want.
##   * The finger ring listens via _input (NOT _unhandled_input) so it sees
##     touches even when other nodes will consume them, but it never calls
##     accept_event() so the player still gets the same events.
##   * Safe area: on iOS / Android we pull DisplayServer.get_display_safe_area
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
const BUTTON_BASE_SIZE: float = 118.0

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
var _weapon_btns: Array = []        ## Index = Player.WeaponType
var _weapon_lvl_labels: Array = []
var _weapon_held: Dictionary = {}
var _joystick: Control = null
var _pause_btn: Control
var _torpedo_label: Label
var _torpedo_count_label: Label
var _finger_ring: Node2D
var _ring_pos: Vector2 = Vector2.ZERO
var _ring_alpha: float = 0.0
var _ring_index: int = -1   ## Finger the ring follows (the first one down); a second finger never moves it
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
	_build_weapon_buttons()
	# 9/11: the three round weapon buttons are replaced by ONE fire wheel.
	# They stay in the tree, hidden, because the per-frame readout code still
	# writes to their labels; weapon touches and drawing go through the
	# wheel. The torpedo keeps its own visible button.
	for wb in _weapon_btns:
		wb.visible = false
	_build_button_pad()
	if GameState.joystick_enabled:
		_build_joystick()
	_build_pause_button()
	EventBus.cutscene_started.connect(_on_cutscene_started)
	EventBus.cutscene_finished.connect(_on_cutscene_finished)
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
	# A finger that started on the fire wheel stays the wheel's until it
	# lifts, wherever it goes: keep switching wedges past the rim and never
	# miss its release.
	if _pad != null and is_instance_valid(_pad):
		if event is InputEventScreenDrag and _pad_touch.has(event.index):
			_pad_drag(event.index, event.position - _pad.position)
		elif event is InputEventScreenTouch and not event.pressed and _pad_touch.has(event.index):
			_pad_release(event.index)
	if event is InputEventScreenTouch:
		if event.pressed:
			if _ring_index != -1 and event.index != _ring_index:
				return
			if _over_controls(event.position):
				return
			_ring_index = event.index
			_ring_pos = event.position
			_ring_alpha = 1.0
		elif event.index == _ring_index:
			_ring_index = -1
			# Don't snap to 0 — let _process fade it out smoothly.
			_ring_alpha = max(_ring_alpha, 0.6)
	elif event is InputEventScreenDrag:
		if event.index != _ring_index:
			return
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


# --- Corner pad (6/11) ---
# Players fire without looking at the corner, and the round buttons were small
# targets. One invisible pad covers the whole cluster plus a margin; every
# touch on it picks the nearest button. The buttons become visuals only.

var _pad: Control = null            ## the MobileFireWheel (one wheel, four wedges, 9/11)
var _pad_centers: Array = []         ## wedge label centres [P, B, M, torpedo] in screen space
## touch index (or -100 for the mouse) -> {"slot": wedge under it, "weapon": weapon it holds or -1}
var _pad_touch: Dictionary = {}

## Wheel radius and torpedo button radius as multiples of the button size.
## Static for tests.
const WHEEL_SIZE_MUL: float = 1.0    # 1.16 -> 1.0 (9/11 playtest: "a bit smaller"), radius = one button size
const TORPEDO_SIZE_MUL: float = 0.42
const WHEEL_TORPEDO_GAP: float = 12.0
const TORPEDO_HIT_MUL: float = 1.45
var _torpedo_hit: Control = null

## How far a touch counts from the WHEEL centre.
static func pad_reach(size: float) -> float:
	return size * WHEEL_SIZE_MUL * MobileFireWheel.HIT_SLACK


## [wheel centre, wheel radius, torpedo centre, torpedo radius]. The torpedo
## keeps the corner pocket it always had; the wheel sits diagonally up and
## inward from it with a small gap, whole circle on screen. Static so the
## layout can be checked headless.
static func wheel_layout(safe: Rect2, size: float, side: int) -> Array:
	var r: float = size * WHEEL_SIZE_MUL
	var tr: float = size * TORPEDO_SIZE_MUL
	var right: bool = side == 1
	var inward: float = -1.0 if right else 1.0
	var tmargin: float = tr + 16.0
	var tc := Vector2(
		safe.position.x + safe.size.x - tmargin if right else safe.position.x + tmargin,
		safe.position.y + safe.size.y - tmargin
	)
	var d: float = (r + tr + WHEEL_TORPEDO_GAP) / sqrt(2.0)
	var c := tc + Vector2(inward * d, -d)
	return [c, r, tc, tr]


func _build_button_pad() -> void:
	var size: float = _button_size()
	var lay: Array = wheel_layout(_safe_area(), size, GameState.controls_side)
	var center: Vector2 = lay[0]
	var r: float = lay[1]
	var box: float = r * MobileFireWheel.HIT_SLACK
	var wheel: MobileFireWheel = MobileFireWheel.new()
	wheel.name = "FIRE_WHEEL"
	wheel.radius = r
	wheel.right_side = GameState.controls_side == 1
	wheel.size = Vector2(box, box) * 2.0
	wheel.position = center - Vector2(box, box)
	wheel.gui_input.connect(_on_pad_input)
	add_child(wheel)
	_pad = wheel
	_pad_centers = [wheel.slot_center(0), wheel.slot_center(1), wheel.slot_center(2), lay[2]]
	_torpedo_center = lay[2]
	_torpedo_radius = lay[3]


func _wheel_slot(local_pos: Vector2, current: int) -> int:
	var wheel: MobileFireWheel = _pad as MobileFireWheel
	return MobileFireWheel.slot_at(local_pos - wheel.size * 0.5, wheel.radius, current, wheel.right_side)


func _pad_press(key: int, local_pos: Vector2) -> void:
	var slot: int = _wheel_slot(local_pos, -1)
	_pad_touch[key] = {"slot": slot, "weapon": -1}
	_pad_enter(key, slot)


var _torpedo_center: Vector2 = Vector2.ZERO
var _torpedo_radius: float = 50.0

## The finger moved: switch as soon as it is on another wedge. A firing thumb
## that curls onto the torpedo button fires ONE torpedo per visit and keeps
## its gun going, so the flick never drops the main weapon.
func _pad_drag(key: int, local_pos: Vector2) -> void:
	if not _pad_touch.has(key):
		return
	var st: Dictionary = _pad_touch[key]
	var screen_pos: Vector2 = _pad.position + local_pos
	var d_torp: float = screen_pos.distance_to(_torpedo_center)
	if bool(st.get("on_torpedo", false)):
		if d_torp > _torpedo_radius * 1.25:
			st["on_torpedo"] = false
		return   # while on the torpedo button the wedge does not change
	if d_torp <= _torpedo_radius * 0.9:
		st["on_torpedo"] = true
		_fire_torpedo()
		return
	var slot: int = _wheel_slot(local_pos, int(st["slot"]))
	if slot == int(st["slot"]):
		return
	st["slot"] = slot
	_pad_enter(key, slot)


## Finger `key` just landed on (or slid onto) wedge `slot`.
func _pad_enter(key: int, slot: int) -> void:
	var st: Dictionary = _pad_touch[key]
	(_pad as MobileFireWheel).flash(slot)
	var old: int = int(st["weapon"])
	if old == slot:
		return
	st["weapon"] = slot
	# Press the new weapon BEFORE letting go of the old one so the ship never
	# sees a frame with no weapon held.
	_set_weapon(slot, true)
	if old >= 0 and not _weapon_held_by_other(key, old):
		_set_weapon(old, false)


func _weapon_held_by_other(key: int, weapon: int) -> bool:
	for k in _pad_touch:
		if k != key and int(_pad_touch[k]["weapon"]) == weapon:
			return true
	return false


func _pad_release(key: int) -> void:
	if not _pad_touch.has(key):
		return
	var weapon: int = int(_pad_touch[key]["weapon"])
	_pad_touch.erase(key)
	if weapon >= 0 and not _weapon_held_by_other(key, weapon):
		_set_weapon(weapon, false)


func _on_pad_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# A press on an index we still hold means its release was lost
			# (pause menu): drop the stale hold first.
			_pad_release(event.index)
			_pad_press(event.index, event.position)
			_pad.accept_event()
		elif _pad_touch.has(event.index):
			_pad_release(event.index)
			_pad.accept_event()
	elif event is InputEventScreenDrag:
		# Our own finger sliding across the wheel switches wedges (also
		# tracked in _input, which keeps following it past the rim). A
		# steering finger passing through is not ours and goes to the ship.
		if _pad_touch.has(event.index):
			_pad_drag(event.index, event.position)
			_pad.accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_pad_press(-100, event.position)
		else:
			_pad_release(-100)
		_pad.accept_event()
	elif event is InputEventMouseMotion and _pad_touch.has(-100) and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pad_drag(-100, event.position)
		_pad.accept_event()


## Release everything the pad holds (pause / focus loss never delivers it).
func _pad_reset() -> void:
	for key in _pad_touch.keys():
		_pad_release(key)
	_pad_touch.clear()


# --- Torpedo button (bottom-right) ---

func _build_torpedo_button() -> void:
	# 9/11: its own round button in the corner pocket beside the fire wheel
	# (limited ammo and a one-shot tap: not something to slide onto by
	# accident). Sized from the wheel layout.
	var lay: Array = wheel_layout(_safe_area(), _button_size(), GameState.controls_side)
	var center: Vector2 = lay[2]
	var size: float = float(lay[3]) * 2.0
	_torpedo_btn = _make_circle_button(center, size, &"TORPEDO")
	# The drawn button is visual only. An invisible round pad around it takes
	# the taps, 45% bigger than the button, so a thumb that lands near the
	# corner still fires (the wheel is added later and wins where they meet).
	_torpedo_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit_r: float = float(lay[3]) * TORPEDO_HIT_MUL
	_torpedo_hit = Control.new()
	_torpedo_hit.name = "TORPEDO_HIT"
	_torpedo_hit.set_script(preload("res://scripts/MobileControlsPad.gd"))
	_torpedo_hit.radius = hit_r
	_torpedo_hit.size = Vector2(hit_r, hit_r) * 2.0
	_torpedo_hit.position = center - Vector2(hit_r, hit_r)
	_torpedo_hit.gui_input.connect(_on_torpedo_input)
	add_child(_torpedo_hit)
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		# (a touch also arrives as an emulated click: it must not fire twice)
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


# --- Weapon buttons (one per weapon, clustered with the torpedo) ---

const WEAPON_LETTERS: Array = ["P", "B", "M"]


## Button centers for the corner cluster: [phaser, beam, missile, torpedo].
## The torpedo sits in the corner; the three weapons fan around it on a
## quarter arc (straight up, diagonal, straight inward) so each is one
## thumb-roll from the corner. Mirrored for the right side. Static so the
## layout can be checked headless.
static func cluster_centers(safe: Rect2, size: float, side: int) -> Array:
	var margin: float = size * 0.5 + 18.0
	var right: bool = side == 1
	var corner := Vector2(
		safe.position.x + safe.size.x - margin if right else safe.position.x + margin,
		safe.position.y + safe.size.y - margin
	)
	var inward: float = -1.0 if right else 1.0
	# Radius chosen so neighbours 45 deg apart don't overlap (chord >= size*1.08).
	var r: float = size * 1.42
	var out: Array = []
	for ang in [90.0, 45.0, 0.0]:   # P up, B diagonal, M inward
		var a: float = deg_to_rad(ang)
		out.append(corner + Vector2(cos(a) * r * inward, -sin(a) * r))
	out.append(corner)
	return out


## Joystick in the bottom corner opposite the weapon cluster. Returns
## [center, base_radius, hit_radius]. Static so the layout can be tested.
static func joystick_layout(safe: Rect2, size: float, side: int) -> Array:
	var r: float = size * 0.95
	var hit: float = r * 1.45
	var margin: float = r + 26.0
	var on_right: bool = side == 0   # weapons LEFT -> stick RIGHT
	var c := Vector2(
		safe.position.x + safe.size.x - margin if on_right else safe.position.x + margin,
		safe.position.y + safe.size.y - margin
	)
	return [c, r, hit]


func _build_joystick() -> void:
	var lay: Array = joystick_layout(_safe_area(), _button_size(), GameState.controls_side)
	var hit: float = lay[2]
	_joystick = Control.new()
	_joystick.name = "JOYSTICK"
	_joystick.set_script(preload("res://scripts/MobileJoystick.gd"))
	_joystick.size = Vector2(hit, hit) * 2.0
	_joystick.position = lay[0] - Vector2(hit, hit)
	# Keep the whole mini-screen inside the safe area.
	var safe: Rect2 = _safe_area()
	_joystick.position = _joystick.position.clamp(safe.position, safe.end - _joystick.size)
	_joystick.base_radius = lay[1]
	_joystick.screen_aspect = _viewport_size.x / maxf(_viewport_size.y, 1.0)
	_joystick.aimed.connect(_on_joystick)
	add_child(_joystick)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _joystick != null and is_instance_valid(_joystick):
			_joystick.reset()
		_pad_reset()


func _on_joystick(u: Vector2, active: bool) -> void:
	_resolve_player()
	if _player != null and is_instance_valid(_player) and _player.has_method("set_stick_target"):
		_player.set_stick_target(u, active)


## Finger ring ignores touches that land on the joystick or a button.
func _over_controls(pos: Vector2) -> bool:
	var nodes: Array = _weapon_btns.duplicate()
	nodes.append(_torpedo_btn)
	nodes.append(_torpedo_hit)
	nodes.append(_pause_btn)
	nodes.append(_joystick)
	nodes.append(_pad)
	for n in nodes:
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		var local: Vector2 = pos - n.position
		# Round buttons have no _has_point override (calling it errored on
		# every touch and aborted this handler): test the circle here.
		if n.has_method("_has_point"):
			if n._has_point(local):
				return true
		elif local.distance_to(n.size * 0.5) <= minf(n.size.x, n.size.y) * 0.5:
			return true
	return false


func _build_weapon_buttons() -> void:
	var size: float = _button_size()
	var centers: Array = cluster_centers(_safe_area(), size, GameState.controls_side)
	for wt in 3:
		var b: Control = _make_circle_button(centers[wt], size, StringName("WEAPON_%d" % wt))
		b.gui_input.connect(_on_weapon_input.bind(wt))
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # corner pad routes touches
		add_child(b)
		var col: Color = _color_for_weapon(wt)
		b.set_meta("col_glow", col)
		var letter := Label.new()
		letter.text = WEAPON_LETTERS[wt]
		letter.add_theme_font_size_override("font_size", int(size * 0.40))
		letter.add_theme_color_override("font_color", col)
		letter.add_theme_color_override("font_outline_color", Color.BLACK)
		letter.add_theme_constant_override("outline_size", 5)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.size = Vector2(size, size * 0.55)
		letter.position = Vector2(0, size * 0.10)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(letter)
		var lvl := Label.new()
		lvl.text = "L1"
		lvl.add_theme_font_size_override("font_size", int(size * 0.20))
		lvl.add_theme_color_override("font_color", Color.WHITE)
		lvl.add_theme_color_override("font_outline_color", Color.BLACK)
		lvl.add_theme_constant_override("outline_size", 4)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lvl.size = Vector2(size, size * 0.30)
		lvl.position = Vector2(0, size * 0.60)
		lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lvl)
		_weapon_btns.append(b)
		_weapon_lvl_labels.append(lvl)


func _on_weapon_input(event: InputEvent, wt: int) -> void:
	if event is InputEventScreenTouch:
		_set_weapon(wt, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_set_weapon(wt, event.pressed)
		get_viewport().set_input_as_handled()


func _set_weapon(wt: int, held: bool) -> void:
	if held:
		_weapon_held[wt] = true
	else:
		_weapon_held.erase(wt)
	_resolve_player()
	if _player != null and is_instance_valid(_player) and _player.has_method("set_weapon_button"):
		_player.set_weapon_button(wt, held)
	if held:
		_pop(_weapon_btns[wt])
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
	var size: float = _button_size() * 0.80  # Same physical size as before the 6/11 shrink
	# Top edge 12 px below the notch / Dynamic Island inset.
	var center := Vector2(
		safe.position.x + safe.size.x - BUTTON_INSET * 0.55,
		safe.position.y + 12.0 + size * 0.5
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


## The cutscene SKIP button shares the top-right corner (iPad), so a second
## SKIP tap used to land on PAUSE once the cutscene freed itself. Hide the
## pause button for the cutscene plus a short grace window after it.
func _on_cutscene_started() -> void:
	if _pause_btn != null:
		_pause_btn.visible = false


func _on_cutscene_finished() -> void:
	if _pause_btn == null:
		return
	get_tree().create_timer(0.6, true).timeout.connect(func() -> void:
		if is_instance_valid(_pause_btn):
			_pause_btn.visible = true
	)


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
	# Round hit area so the corners of neighbouring buttons don't steal taps.
	c.set_meta("round_hit", true)
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

	# Ship dot on the mini-screen stick.
	if _joystick != null and is_instance_valid(_joystick) and _player != null and is_instance_valid(_player) and _player.has_method("stick_position"):
		_joystick.set_ship_u(_player.stick_position())
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
		var levels: Dictionary = _player.get("weapon_levels") if "weapon_levels" in _player else {}
		for i in _weapon_btns.size():
			var wb: Control = _weapon_btns[i]
			var active: bool = i == wt
			wb.set_meta("ready", true)
			wb.set_meta("col_border", Color(_color_for_weapon(i), 0.95) if active else COL_BORDER_DIM)
			wb.set_meta("pulse", 1.0 if _weapon_held.has(i) else (_ring_pulse if active else 0.0))
			wb.modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.62)
			wb.queue_redraw()
			_weapon_lvl_labels[i].text = "L%d" % int(levels.get(i, 1))

		# Pulse + glow color depends on mode:
		#  * DETONATE — fast red pulse, always "ready"
		#  * READY    — gentle cyan pulse, ready
		#  * EMPTY    — dim, slow pulse, not ready
		# Fire wheel readout: current weapon, levels, torpedo state and the
		# wedge a finger is on (the newest touch wins).
		if _pad != null and is_instance_valid(_pad) and _pad.has_method("set_state"):
			var held_slot: int = -1
			for k in _pad_touch:
				held_slot = int(_pad_touch[k]["slot"])
			_pad.set_state(wt, [int(levels.get(0, 1)), int(levels.get(1, 1)), int(levels.get(2, 1))], held_slot)

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
				_torpedo_btn.set_meta("col_glow", MobileFireWheel.TORPEDO_COLOR)
				_torpedo_btn.set_meta("col_border", Color(MobileFireWheel.TORPEDO_COLOR, 0.80 if tc > 0 else 0.30))
			_torpedo_btn.queue_redraw()


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
	return safe_rect_canvas(get_viewport())


## Safe area (notch, Dynamic Island, home indicator) in canvas coordinates.
## get_display_safe_area() is in physical window pixels; screen_get_usable_rect
## does NOT include the iOS island inset. Under stretch mode canvas_items +
## aspect expand the canvas is the window scaled uniformly from (0,0), so
## dividing by window_size / visible_rect.size maps pixels to canvas units.
## Shared with Main._hud_safe_rect so HUD text and buttons agree.
static func safe_rect_canvas(viewport: Viewport) -> Rect2:
	var vp_rect: Rect2 = viewport.get_visible_rect()
	if not OS.has_feature("mobile"):
		return vp_rect
	var sr: Rect2i = DisplayServer.get_display_safe_area()
	if sr.size.x <= 0 or sr.size.y <= 0:
		sr = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var win_size: Vector2i = DisplayServer.window_get_size()
	if sr.size.x <= 0 or sr.size.y <= 0 or win_size.x <= 0 or win_size.y <= 0:
		return vp_rect
	var sx: float = vp_rect.size.x / float(win_size.x)
	var sy: float = vp_rect.size.y / float(win_size.y)
	var safe := Rect2(
		Vector2(sr.position.x * sx, sr.position.y * sy),
		Vector2(sr.size.x * sx, sr.size.y * sy)
	)
	# Never extend past the canvas (safe area can be reported in screen space).
	return safe.intersection(vp_rect) if safe.intersects(vp_rect) else vp_rect


## Button size scales gently with viewport width so the controls feel the
## same physical size on different phone aspect ratios.
func _button_size() -> float:
	var vp := get_viewport().get_visible_rect().size
	var scale: float = clamp(vp.x / 816.0, 0.85, 1.4)
	return BUTTON_BASE_SIZE * scale
