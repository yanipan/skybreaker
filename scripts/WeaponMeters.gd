extends Node2D
class_name WeaponMeters
## Left-edge HUD widget — three vertical power meters, one per weapon type.
## Polls the active player each frame and shows:
##   * a colored weapon icon at the top of each meter
##   * a vertical fill bar (current level / max_power_level)
##   * a level number underneath
##   * a brighter frame around whichever meter is the currently-equipped weapon
##
## The data lives on Player.gd (`weapon_levels` dict + `weapon_type` int +
## `max_power_level`). This widget is purely a view — it draws what it sees
## and never mutates state.

# Mirrors Player.WeaponType — kept locally so we don't drag a Player.gd
# preload through the HUD. Order MUST match Player.WeaponType.
const PHASER: int = 0
const BEAM: int = 1
const MISSILE: int = 2

# Layout — anchored to the left screen edge, below the money/lives HUD.
const ORIGIN_X: float = 14.0
const ORIGIN_Y: float = 220.0
const METER_WIDTH: float = 22.0
const METER_HEIGHT: float = 130.0
const METER_GAP: float = 12.0
const ICON_HEIGHT: float = 22.0     ## space reserved above each fill for the icon
const LABEL_HEIGHT: float = 14.0    ## space reserved below each fill for the level number

# Per-weapon palette — bullet bar fills with the weapon's identity color so
# the player learns "cyan = phaser, magenta = beam, orange = missile" at a
# glance, matching the pickup colors in Pickup.gd.
const PHASER_COLOR: Color = Color(0.30, 0.90, 1.00)
const BEAM_COLOR: Color = Color(1.00, 0.35, 0.85)
const MISSILE_COLOR: Color = Color(1.00, 0.55, 0.15)

var _player: Node = null
var _font: Font = null


func _ready() -> void:
	z_index = 100  ## Above gameplay, beneath modal popups
	# Use whatever font the project default theme provides — falls back to
	# Godot's built-in if Fonts autoload isn't loaded yet (e.g. during early
	# scene startup before autoload bootstrap on a fresh project).
	if Engine.has_singleton("Fonts"):
		_font = Engine.get_singleton("Fonts").BODY
	set_process(true)


func _process(_delta: float) -> void:
	# Resolve the player lazily — Main spawns it during _ready, but we may
	# be added before that finishes.
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")
	queue_redraw()


func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not "weapon_levels" in _player:
		return
	var levels: Dictionary = _player.weapon_levels
	var current_weapon: int = int(_player.weapon_type) if "weapon_type" in _player else 0
	var max_level: int = int(_player.max_power_level) if "max_power_level" in _player else 20

	_draw_meter(0, PHASER, levels.get(PHASER, 1), max_level, current_weapon == PHASER, PHASER_COLOR)
	_draw_meter(1, BEAM, levels.get(BEAM, 1), max_level, current_weapon == BEAM, BEAM_COLOR)
	_draw_meter(2, MISSILE, levels.get(MISSILE, 1), max_level, current_weapon == MISSILE, MISSILE_COLOR)


func _draw_meter(slot: int, weapon: int, level: int, max_level: int, is_active: bool, color: Color) -> void:
	var x: float = ORIGIN_X
	var y: float = ORIGIN_Y + float(slot) * (METER_HEIGHT + ICON_HEIGHT + LABEL_HEIGHT + METER_GAP)

	# Active weapon gets a wider frame and a soft outer glow so it pops
	if is_active:
		var glow := Rect2(x - 4, y - 4, METER_WIDTH + 8, ICON_HEIGHT + METER_HEIGHT + LABEL_HEIGHT + 8)
		draw_rect(glow, Color(color.r, color.g, color.b, 0.18), true)
		draw_rect(glow, Color(color.r, color.g, color.b, 0.85), false, 2.0)

	# --- Icon panel (top) ---
	var icon_rect := Rect2(x, y, METER_WIDTH, ICON_HEIGHT)
	draw_rect(icon_rect, Color(0.05, 0.08, 0.14, 0.85), true)
	draw_rect(icon_rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
	_draw_weapon_glyph(weapon, icon_rect.get_center(), color)

	# --- Fill bar (middle) ---
	var bar_rect := Rect2(x, y + ICON_HEIGHT + 2.0, METER_WIDTH, METER_HEIGHT - 2.0)
	draw_rect(bar_rect, Color(0.04, 0.06, 0.10, 0.85), true)
	draw_rect(bar_rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)

	# Vertical fill — grows from the bottom up so leveling reads as "filling"
	var pct: float = clamp(float(level) / float(max_level), 0.0, 1.0)
	var fill_h: float = (bar_rect.size.y - 4.0) * pct
	var fill_rect := Rect2(
		bar_rect.position.x + 2.0,
		bar_rect.position.y + bar_rect.size.y - 2.0 - fill_h,
		bar_rect.size.x - 4.0,
		fill_h,
	)
	draw_rect(fill_rect, color, true)
	# Bright highlight stripe along the fill's top edge so the meter has bite
	if fill_h > 2.0:
		draw_rect(
			Rect2(fill_rect.position.x, fill_rect.position.y, fill_rect.size.x, 1.5),
			Color(1, 1, 1, 0.85),
			true,
		)

	# Tick marks every 5 levels — helps the player count without squinting
	for i in range(5, max_level, 5):
		var tick_y: float = bar_rect.position.y + bar_rect.size.y - 2.0 - (bar_rect.size.y - 4.0) * (float(i) / float(max_level))
		draw_line(
			Vector2(bar_rect.position.x + 1, tick_y),
			Vector2(bar_rect.position.x + bar_rect.size.x - 1, tick_y),
			Color(0, 0, 0, 0.55),
			1.0,
		)

	# --- Level number (bottom) ---
	if _font != null:
		var label: String = str(level)
		var fs: int = 14
		var label_w: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var label_pos := Vector2(
			x + (METER_WIDTH - label_w) * 0.5,
			y + ICON_HEIGHT + METER_HEIGHT + LABEL_HEIGHT - 1.0,
		)
		draw_string(_font, label_pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		draw_string(_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


## Tiny stylized glyph that hints at each weapon's silhouette inside the
## icon box. Mirrors the convention used by Player._draw_weapon_indicator
## (which has been removed from the player's _draw, but the visual language
## carries over).
func _draw_weapon_glyph(weapon: int, center: Vector2, color: Color) -> void:
	match weapon:
		PHASER:
			# Three short vertical bars — three-bullet phaser silhouette
			for i in 3:
				var px: float = center.x - 4.0 + float(i) * 4.0
				draw_rect(Rect2(px - 0.9, center.y - 6, 1.8, 12), color, true)
		BEAM:
			# Solid vertical column with halo + arrow tip
			draw_rect(Rect2(center.x - 2.5, center.y - 8, 5, 16), Color(color.r, color.g, color.b, 0.35), true)
			draw_rect(Rect2(center.x - 1.0, center.y - 8, 2.0, 16), color, true)
			var arrow := PackedVector2Array([
				Vector2(center.x - 3, center.y - 6),
				Vector2(center.x + 3, center.y - 6),
				Vector2(center.x, center.y - 9),
			])
			draw_colored_polygon(arrow, color)
		MISSILE:
			# Capsule with nose cone + stubby fins
			draw_rect(Rect2(center.x - 2, center.y - 5, 4, 10), Color(0.85, 0.85, 0.90), true)
			var nose := PackedVector2Array([
				Vector2(center.x - 2, center.y - 5),
				Vector2(center.x + 2, center.y - 5),
				Vector2(center.x, center.y - 8),
			])
			draw_colored_polygon(nose, color)
			draw_rect(Rect2(center.x - 4, center.y + 3, 2, 3), Color(0.55, 0.55, 0.62), true)
			draw_rect(Rect2(center.x + 2, center.y + 3, 2, 3), Color(0.55, 0.55, 0.62), true)
