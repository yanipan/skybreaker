extends Area2D
class_name RevivePod
## CO-OP rescue pod (docs/MULTIPLAYER_PLAN.md). A ship that loses its last
## life leaves one where it fell. The room server owns it (it hovers into the
## middle band of the field and stays there); phones show a puppet. When THIS
## phone's ship touches a pod that belongs to the OTHER player it asks the
## server to claim it; the server answers everyone with REVIVE.

const RADIUS := 46.0
const HOVER_SPEED := 40.0
const BAND_TOP := 0.35
const BAND_BOTTOM := 0.60
const CLAIM_CD := 1.0

var for_peer: int = 0          ## The downed player's peer id
var pilot_name: String = ""
var net_id: int = 0
var net_puppet: bool = false
var claimed: bool = false
var claims_sent: int = 0       ## How many claims this phone sent (tests)

var _viewport_size: Vector2
var _t: float = 0.0
var _claim_cd: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	add_to_group(&"revive_pods")
	z_index = 5
	area_entered.connect(_on_area_entered)
	var l := Label.new()
	l.name = "NameLabel"
	l.text = "RESCUE" if pilot_name.is_empty() else "RESCUE " + pilot_name
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(260.0, 24.0)
	l.position = Vector2(-130.0, -RADIUS - 30.0)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_claim_cd = maxf(0.0, _claim_cd - delta)
	if not net_puppet:
		# Server: drift into the band where a ship can reach it, and stay.
		var want_y: float = clampf(position.y, _viewport_size.y * BAND_TOP, _viewport_size.y * BAND_BOTTOM)
		var want_x: float = clampf(position.x, RADIUS + 10.0, _viewport_size.x - RADIUS - 10.0)
		position.y = move_toward(position.y, want_y, HOVER_SPEED * delta)
		position.x = move_toward(position.x, want_x, HOVER_SPEED * delta)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS * (1.0 + 0.08 * sin(_t * 4.0)), Color(0.4, 1.0, 0.6, 0.25))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(0.5, 1.0, 0.7), 4.0, true)
	var h: float = RADIUS * 0.45
	draw_line(Vector2(-h, 0.0), Vector2(h, 0.0), Color.WHITE, 6.0, true)
	draw_line(Vector2(0.0, -h), Vector2(0.0, h), Color.WHITE, 6.0, true)


## This phone's ship flew into the pod: ask the server (it decides).
func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group(&"player"):
		return
	if claimed or net_id <= 0 or not Net.is_client():
		return
	if for_peer == Net.my_peer:
		return   # nobody rescues themselves
	if _claim_cd > 0.0:
		return
	_claim_cd = CLAIM_CD
	claims_sent += 1
	Net.send(0, [Net.M.CLAIM, net_id])
