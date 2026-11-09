extends Control
class_name MobileFireWheel
## One round fire control split into three coloured wedges (9/11 playtest):
## PHASER on top, BEAM toward the middle of the screen, MISSILE curling back
## toward the screen corner. The thumb never has to find a button: touch
## anywhere on the wheel to fire that wedge's weapon, slide to another wedge
## to switch on the spot. The torpedo is NOT a wedge: it is limited ammo and a
## one-shot tap, so it keeps its own button in the corner pocket beside the
## wheel (a firing thumb can still curl onto it, see MobileControls).
## MobileControls owns the touches and the player calls; this node only knows
## geometry and how to draw itself.
##
## Slots: 0 phaser, 1 beam, 2 missile = Player.WeaponType.

const SLOTS: int = 3
const COLORS: Array = [
	Color(0.45, 0.90, 1.00),   # phaser  — cyan
	Color(0.55, 1.00, 0.50),   # beam    — green
	Color(1.00, 0.82, 0.35),   # missile — gold
]
const TORPEDO_COLOR: Color = Color(1.00, 0.42, 0.36)   ## the separate button uses this
const LETTERS: Array = ["P", "B", "M"]
## Inner hub as a fraction of the radius. A touch inside it keeps the wedge
## the finger came from, so crossing the middle never flickers.
const HUB_FRAC: float = 0.24
## A finger must travel this far past a wedge border before the wedge changes.
const HYSTERESIS_DEG: float = 10.0
## Touches count this far outside the drawn rim.
const HIT_SLACK: float = 1.25   # a thumb landing a little past the rim still counts
const HALF_WEDGE_DEG: float = 60.0

var radius: float = 140.0
## true = the wheel sits in the bottom-RIGHT corner (beam then points left).
var right_side: bool = false

var _weapon: int = 0            ## ship's current weapon (0..2)
var _held_slot: int = -1        ## wedge under a finger right now, -1 = none
var _levels: Array = [1, 1, 1]
var _time: float = 0.0
var _flash: Array = [0.0, 0.0, 0.0]   ## per-wedge press flash, decays


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= radius * HIT_SLACK


## Unit direction of each wedge's centre line, in screen space (y down):
## phaser straight up, beam inward and slightly down, missile outward and
## down (toward the screen corner, where the thumb curls).
static func slot_dir(slot: int, right: bool) -> Vector2:
	var inward: float = -1.0 if right else 1.0
	match slot:
		0: return Vector2.UP
		1: return Vector2(inward * cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
		_: return Vector2(-inward * cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))


## Wedge under `offset` (finger position minus wheel centre). `current` is the
## wedge that finger is already on (-1 = fresh touch); it wins inside the hub
## and within the hysteresis band. Static so the layout is testable headless.
static func slot_at(offset: Vector2, wheel_radius: float, current: int, right: bool) -> int:
	if offset.length() < wheel_radius * HUB_FRAC and current >= 0:
		return current
	if offset.length() < 1.0:
		return current if current >= 0 else 0
	var dir: Vector2 = offset.normalized()
	if current >= 0:
		var keep: float = rad_to_deg(dir.angle_to(slot_dir(current, right)))
		if absf(keep) <= HALF_WEDGE_DEG + HYSTERESIS_DEG:
			return current
	var best: int = 0
	var best_dot: float = -2.0
	for s in SLOTS:
		var d: float = dir.dot(slot_dir(s, right))
		if d > best_dot:
			best_dot = d
			best = s
	return best


## Screen-space point in the middle of a wedge (where its label sits).
func slot_center(slot: int) -> Vector2:
	return position + size * 0.5 + slot_dir(slot, right_side) * radius * 0.62


## Pushed by MobileControls every frame; redraws only when something changed.
func set_state(weapon: int, levels: Array, held_slot: int) -> void:
	if weapon == _weapon and held_slot == _held_slot and levels == _levels:
		return
	_weapon = weapon
	_held_slot = held_slot
	_levels = levels.duplicate()
	queue_redraw()


## A wedge was just pressed or slid onto: short bright flash.
func flash(slot: int) -> void:
	if slot >= 0 and slot < SLOTS:
		_flash[slot] = 1.0
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var animating: bool = _held_slot >= 0
	for i in SLOTS:
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta * 4.0)
			animating = true
	if animating:
		queue_redraw()


func _sector(center: Vector2, r_in: float, r_out: float, mid: float, half: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps: int = 22
	for i in steps + 1:
		var a: float = mid - half + 2.0 * half * float(i) / float(steps)
		pts.append(center + Vector2(cos(a), sin(a)) * r_out)
	for i in steps + 1:
		var a2: float = mid + half - 2.0 * half * float(i) / float(steps)
		pts.append(center + Vector2(cos(a2), sin(a2)) * r_in)
	draw_colored_polygon(pts, color)


func _text(font: Font, at: Vector2, text: String, px: int, color: Color) -> void:
	var w: float = radius
	var pos := Vector2(at.x - w * 0.5, at.y + px * 0.36)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, px, maxi(3, px / 6), Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, px, color)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r_in: float = radius * HUB_FRAC
	var gap: float = deg_to_rad(2.0)
	var half: float = deg_to_rad(HALF_WEDGE_DEG) - gap
	var font: Font = Fonts.HEADLINE
	var pulse: float = 0.5 + 0.5 * sin(_time * 9.0)
	# Backing disc so the wheel reads on any background.
	draw_circle(c, radius + 7.0, Color(0.0, 0.02, 0.05, 0.42))
	for s in SLOTS:
		var col: Color = COLORS[s]
		var mid: float = slot_dir(s, right_side).angle()
		var held: bool = s == _held_slot
		var selected: bool = s == _weapon
		var fl: float = _flash[s]
		var fill: float = 0.20
		if selected:
			fill = 0.40
		if held:
			fill = 0.72 + 0.10 * pulse
		fill = minf(1.0, fill + fl * 0.35)
		var r_out: float = radius + (7.0 if held else 0.0) + fl * 5.0
		if held or fl > 0.0:
			# soft outer glow behind the pressed wedge
			_sector(c, radius * 0.9, r_out + 12.0, mid, half, Color(col.r, col.g, col.b, 0.16 + 0.10 * pulse))
		_sector(c, r_in + 3.0, r_out, mid, half, Color(col.r, col.g, col.b, fill))
		# glassy inner band + bright rim
		_sector(c, r_in + 3.0, r_in + 3.0 + (r_out - r_in) * 0.34, mid, half, Color(1, 1, 1, 0.05 + 0.05 * fill))
		draw_arc(c, r_out, mid - half, mid + half, 26,
				Color(col.r, col.g, col.b, 0.95 if (held or selected) else 0.50), 4.0 if (held or selected) else 2.0, true)
		# label: weapon letter with its level underneath
		var at: Vector2 = c + slot_dir(s, right_side) * radius * 0.62
		var txt_col: Color = Color(1, 1, 1, 1.0) if (held or selected) else Color(col.r, col.g, col.b, 0.95)
		var big: int = int(radius * 0.30)
		var small: int = int(radius * 0.14)
		_text(font, at + Vector2(0, -small * 0.5), LETTERS[s], big, txt_col)
		_text(font, at + Vector2(0, big * 0.60), "L%d" % int(_levels[s]), small, Color(1, 1, 1, 0.9))
	# Hub: dark core, ring in the active weapon's colour, hot dot while firing.
	var wc: Color = COLORS[clampi(_weapon, 0, 2)]
	draw_circle(c, r_in, Color(0.02, 0.05, 0.09, 0.92))
	draw_arc(c, r_in, 0.0, TAU, 28, Color(wc.r, wc.g, wc.b, 0.9), 3.0, true)
	var firing: bool = _held_slot >= 0
	draw_circle(c, r_in * (0.42 + (0.14 * pulse if firing else 0.0)), Color(wc.r, wc.g, wc.b, 0.95 if firing else 0.55))
	draw_circle(c, r_in * 0.18, Color(1, 1, 1, 0.9 if firing else 0.5))
