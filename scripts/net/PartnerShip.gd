extends Node2D
class_name PartnerShip
## Cosmetic replica of the other co-op player's ship. No collision, no groups,
## shots never damage — the partner's own phone reports the real hits.

const SHIP_SIZE := 74.0
const SMOOTH := 18.0
const BANK_SPEED := 60.0
const TINT := Color(0.72, 0.90, 1.0)
const MAX_VISUAL_RATE := 10.0
## States arrive ~30 times a second. If they stop (the partner lost its
## connection or left), the ship must not sit there firing for ever: after
## STALE_HOLD_FIRE seconds it stops firing, after STALE_HIDE it is hidden.
## The next state brings it straight back.
const STALE_HOLD_FIRE := 1.0
const STALE_HIDE := 5.0
## Shots released in one frame after a long frame (hitch): never a clump.
const MAX_SHOTS_PER_FRAME := 2

const SHIP_TEX_NEUTRAL: Texture2D = preload("res://assets/sprites/playership.png")
const SHIP_TEX_BANK_LEFT: Texture2D = preload("res://assets/sprites/playerbankingleft.png")
const SHIP_TEX_BANK_RIGHT: Texture2D = preload("res://assets/sprites/playerbankingright.png")

const PHASER_COLOR := Color(0.55, 0.95, 1.0)
const MISSILE_COLOR := Color(1.0, 0.6, 0.25)
const BEAM_COLOR := Color(0.5, 0.9, 1.0, 0.45)
const PHASER_SPEED := 1200.0
const MISSILE_SPEED := 700.0
const MISSILE_INTERVAL := 0.33
const SHOT_OFFSET := Vector2(0, -38)
const BEAM_FROM := Vector2(0, -38)
const BEAM_TO := Vector2(0, -2000)
const NAME_LABEL_Y := -SHIP_SIZE * 0.5 - 34.0

var peer: int = 0
var pilot_name: String = ""
var alive: bool = true
var weapon: int = 0
var power: int = 1
var firing: bool = false
var target_pos: Vector2 = Vector2.ZERO

var _sprite: Sprite2D
var _name_label: Label
var _got_pos: bool = false
var _prev_x: float = 0.0
var _fire_timer: float = 0.0
var _beam_showing: bool = false
var _since_state: float = 0.0


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = SHIP_TEX_NEUTRAL
	var tex_w: float = float(_sprite.texture.get_width())
	var s: float = SHIP_SIZE / tex_w * 1.6
	_sprite.scale = Vector2(s, s)
	_sprite.modulate = TINT
	add_child(_sprite)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.position = Vector2(-120.0, NAME_LABEL_Y)
	_name_label.size = Vector2(240.0, 22.0)
	_name_label.visible = false
	add_child(_name_label)


func apply_state(st: Dictionary) -> void:
	_since_state = 0.0
	visible = alive
	if st.has("p"):
		var p: Vector2 = st["p"]
		if not _got_pos:
			position = p
			target_pos = p
			_prev_x = p.x
			_got_pos = true
		else:
			target_pos = p
	if st.has("a"):
		alive = bool(st["a"])
		visible = alive
	if st.has("w"):
		weapon = int(st["w"])
	if st.has("l"):
		power = int(st["l"])
	if st.has("f"):
		firing = bool(st["f"])
	if st.has("n"):
		pilot_name = str(st["n"])
		_name_label.text = pilot_name
		_name_label.visible = not pilot_name.is_empty()
	_sync_beam_draw()


func _process(delta: float) -> void:
	if _got_pos:
		position = position.lerp(target_pos, 1.0 - exp(-SMOOTH * delta))
	var h_vel := 0.0
	if delta > 0.0:
		h_vel = (position.x - _prev_x) / delta
	_prev_x = position.x
	_update_banking(h_vel)

	_since_state += delta
	if _since_state >= STALE_HIDE:
		visible = false
	if _active_fire():
		if weapon == 0 or weapon == 2:
			_fire_timer -= delta
			var made: int = 0
			while _fire_timer <= 0.0:
				if made < MAX_SHOTS_PER_FRAME:
					_spawn_shot()
					made += 1
				var interval := _fire_interval()
				if interval <= 0.0:
					break
				_fire_timer += interval
	else:
		_fire_timer = 0.0
	_sync_beam_draw()


## Firing for real: alive, the partner says so, and the news is fresh.
func _active_fire() -> bool:
	return alive and firing and _since_state < STALE_HOLD_FIRE


func _draw() -> void:
	if _active_fire() and weapon == 1:
		draw_line(BEAM_FROM, BEAM_TO, BEAM_COLOR, 6.0)


func _update_banking(h_velocity: float) -> void:
	if _sprite == null:
		return
	if h_velocity > BANK_SPEED:
		_sprite.texture = SHIP_TEX_BANK_RIGHT
	elif h_velocity < -BANK_SPEED:
		_sprite.texture = SHIP_TEX_BANK_LEFT
	else:
		_sprite.texture = SHIP_TEX_NEUTRAL


func _fire_interval() -> float:
	if weapon == 2:
		return MISSILE_INTERVAL
	var rate := minf(MAX_VISUAL_RATE, 6.9 + 0.49 * float(power - 1))
	return 1.0 / maxf(rate, 0.001)


func _spawn_shot() -> void:
	var host := get_parent()
	if host == null:
		return
	var shot := PartnerShot.new()
	if weapon == 2:
		shot.speed = MISSILE_SPEED
		shot.color = MISSILE_COLOR
	else:
		shot.speed = PHASER_SPEED
		shot.color = PHASER_COLOR
	shot.position = position + SHOT_OFFSET
	host.add_child(shot)


func _sync_beam_draw() -> void:
	var showing := _active_fire() and weapon == 1
	if showing != _beam_showing:
		_beam_showing = showing
		queue_redraw()


class PartnerShot extends Node2D:
	var speed: float = 0.0
	var color: Color = Color.WHITE

	func _ready() -> void:
		queue_redraw()

	func _process(delta: float) -> void:
		position.y -= speed * delta
		if position.y < -60.0:
			queue_free()

	func _draw() -> void:
		draw_line(Vector2(0, 0), Vector2(0, -18), color, 3.0)
