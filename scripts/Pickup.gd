extends Area2D
class_name Pickup
## Drop from destroyed enemies. Falls slowly, picked up on player overlap.
## Visuals are fully procedural — each type has a glowing capsule with an
## animated halo, a rotating accent ring, an icon, and shimmer highlights.

## NOTE: POWER (legacy generic) is kept for save compatibility and the boss
## drop fallback, but normal enemy/asteroid drops now roll one of the three
## per-weapon variants below. Each variant levels its matching weapon slot
## independently — the player picks which one matters by switching weapons.
enum Type {
	HEALTH_SMALL,
	HEALTH_MEDIUM,
	HEALTH_FULL,
	POWER,
	TORPEDO,
	MONEY,
	WEAPON_CHANGE,
	LIFE,
	SIDEKICK,
	POWER_PHASER,
	POWER_BEAM,
	POWER_MISSILE,
}

@export var type: Type = Type.HEALTH_SMALL
@export var fall_speed: float = 140.0
@export var pickup_size: float = 32.0
## Range at which the pickup starts drifting toward the player. Inside this
## radius, attraction strength scales up sharply so close pickups snap in.
@export var magnet_radius: float = 180.0
@export var magnet_strength: float = 900.0
var money_value: int = 0  ## Set by Enemy when type == MONEY

var _viewport_size: Vector2
var _time: float = 0.0
# Cached visual properties for the current type — set in _ready
var _radius: float = 18.0
var _color: Color = Color.WHITE
var _accent: Color = Color.WHITE


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	add_to_group(&"pickups")
	_resolve_visuals()
	_build_collision()
	queue_redraw()


## Pick the per-type visual settings once so _draw can stay tight.
func _resolve_visuals() -> void:
	match type:
		Type.HEALTH_SMALL:
			_radius = 16.0
			_color = Color(0.30, 0.95, 0.45)
			_accent = Color(0.70, 1.0, 0.85)
		Type.HEALTH_MEDIUM:
			_radius = 19.0
			_color = Color(0.30, 1.0, 0.45)
			_accent = Color(0.80, 1.0, 0.90)
		Type.HEALTH_FULL:
			_radius = 23.0
			_color = Color(0.50, 1.0, 0.65)
			_accent = Color(0.90, 1.0, 0.95)
		Type.POWER:
			_radius = 19.0
			_color = Color(1.0, 0.85, 0.20)
			_accent = Color(1.0, 1.0, 0.75)
		Type.POWER_PHASER:
			# Cyan/teal — matches the phaser bullet tier color family
			_radius = 19.0
			_color = Color(0.30, 0.90, 1.0)
			_accent = Color(0.80, 0.98, 1.0)
		Type.POWER_BEAM:
			# Magenta/pink — visually distinct from phaser cyan and missile orange
			_radius = 19.0
			_color = Color(1.0, 0.35, 0.85)
			_accent = Color(1.0, 0.85, 0.98)
		Type.POWER_MISSILE:
			# Orange/red — matches the missile flame palette
			_radius = 19.0
			_color = Color(1.0, 0.55, 0.15)
			_accent = Color(1.0, 0.90, 0.65)
		Type.TORPEDO:
			_radius = 19.0
			_color = Color(1.0, 0.50, 0.10)
			_accent = Color(1.0, 0.85, 0.50)
		Type.MONEY:
			# Larger coins for bigger payouts so the player can spot a Tank drop at a glance
			if money_value >= 50:
				_radius = 17.0
			elif money_value >= 15:
				_radius = 14.0
			else:
				_radius = 11.0
			_color = Color(1.0, 0.85, 0.10)
			_accent = Color(1.0, 0.95, 0.55)
		Type.WEAPON_CHANGE:
			_radius = 22.0
			_color = Color(0.55, 0.85, 1.0)
			_accent = Color(0.95, 0.98, 1.0)
		Type.LIFE:
			# Big rare bonus — pink heart orb. Bigger and more saturated than the
			# health pickups so it reads as exceptional at a glance.
			_radius = 26.0
			_color = Color(1.0, 0.30, 0.55)
			_accent = Color(1.0, 0.85, 0.90)
		Type.SIDEKICK:
			# Rare bonus — teal/cyan companion orb. Same scale as LIFE so the
			# player notices it as an exceptional drop.
			_radius = 26.0
			_color = Color(0.30, 0.95, 0.85)
			_accent = Color(0.85, 1.0, 0.95)


func _draw() -> void:
	# Coins get a special draw — circular metal disc with shine
	if type == Type.MONEY:
		_draw_coin()
		return
	_draw_orb()
	_draw_icon()


# --- Generic glowing orb (shared by health/power/torpedo/weapon-change) ---

func _draw_orb() -> void:
	var pulse: float = 0.92 + 0.08 * sin(_time * 4.0)
	var r: float = _radius * pulse

	# Outer atmospheric halo (very soft)
	draw_circle(Vector2.ZERO, r * 2.4, Color(_color.r, _color.g, _color.b, 0.10))
	draw_circle(Vector2.ZERO, r * 1.8, Color(_color.r, _color.g, _color.b, 0.20))

	# Mid body — translucent fill
	draw_circle(Vector2.ZERO, r * 1.3, Color(_color.r, _color.g, _color.b, 0.45))
	# Solid core
	draw_circle(Vector2.ZERO, r, _color)
	# Inner brighter ring at the center for depth
	draw_circle(Vector2.ZERO, r * 0.7, Color(_color.r * 1.2, _color.g * 1.2, _color.b * 1.2, 0.85))

	# Specular highlight — top-left, sells the spherical 3D feel
	draw_circle(Vector2(-r * 0.35, -r * 0.40), r * 0.20, Color(1, 1, 1, 0.75))
	draw_circle(Vector2(-r * 0.35, -r * 0.40), r * 0.10, Color(1, 1, 1, 0.95))

	# Rotating accent ring — orbits the orb so the eye is drawn to it
	var spin: float = _time * 3.5
	var ring_r: float = r * 1.55
	draw_arc(Vector2.ZERO, ring_r, spin, spin + PI * 0.45, 18, _accent, 2.5, true)
	draw_arc(Vector2.ZERO, ring_r, spin + PI, spin + PI * 1.45, 18, _accent, 2.5, true)
	# Small orbital sparks at the ends of the arcs
	for ang in [spin, spin + PI * 0.45, spin + PI, spin + PI * 1.45]:
		var p := Vector2(cos(ang), sin(ang)) * ring_r
		draw_circle(p, 2.2, Color(1, 1, 1, 0.95))

	# HEALTH_FULL gets an extra outer ring + shimmering second halo
	if type == Type.HEALTH_FULL:
		draw_arc(Vector2.ZERO, r * 2.0, 0, TAU, 48, Color(0.70, 1.0, 0.80, 0.55), 2.0, true)
	# WEAPON_CHANGE gets a fast counter-rotating second ring so it reads as "different"
	if type == Type.WEAPON_CHANGE:
		var spin2: float = -_time * 5.5
		draw_arc(Vector2.ZERO, r * 1.85, spin2, spin2 + PI * 0.6, 22, Color(1, 1, 1, 0.7), 2.0, true)
		draw_arc(Vector2.ZERO, r * 1.85, spin2 + PI, spin2 + PI * 1.6, 22, Color(1, 1, 1, 0.7), 2.0, true)


# --- Per-type icon overlay ---

func _draw_icon() -> void:
	match type:
		Type.HEALTH_SMALL, Type.HEALTH_MEDIUM, Type.HEALTH_FULL:
			_draw_cross_icon()
		Type.POWER:
			_draw_bolt_icon()
		Type.POWER_PHASER:
			# Bolt + small "P" pip so the player learns "blue bolt = phaser"
			_draw_bolt_icon()
		Type.POWER_BEAM:
			# Bolt only — the magenta color does the type-signaling
			_draw_bolt_icon()
		Type.POWER_MISSILE:
			# Bolt only — orange color signals missile family
			_draw_bolt_icon()
		Type.TORPEDO:
			_draw_torpedo_icon()
		Type.WEAPON_CHANGE:
			_draw_weapon_change_icon()
		Type.LIFE:
			_draw_heart_icon()
		Type.SIDEKICK:
			_draw_sidekick_icon()


func _draw_cross_icon() -> void:
	var arm: float = _radius * 0.65
	var thick: float = _radius * 0.28
	# White cross with a subtle drop shadow
	draw_rect(Rect2(-thick * 0.5 + 1, -arm + 1, thick, arm * 2), Color(0, 0, 0, 0.45), true)
	draw_rect(Rect2(-arm + 1, -thick * 0.5 + 1, arm * 2, thick), Color(0, 0, 0, 0.45), true)
	draw_rect(Rect2(-thick * 0.5, -arm, thick, arm * 2), Color.WHITE, true)
	draw_rect(Rect2(-arm, -thick * 0.5, arm * 2, thick), Color.WHITE, true)


func _draw_bolt_icon() -> void:
	# Lightning bolt zigzag
	var s: float = _radius * 0.85
	var pts := PackedVector2Array([
		Vector2(-s * 0.25, -s),
		Vector2(s * 0.45, -s * 0.10),
		Vector2(s * 0.05, -s * 0.10),
		Vector2(s * 0.40, s),
		Vector2(-s * 0.40, s * 0.15),
		Vector2(-s * 0.05, s * 0.15),
	])
	# Drop shadow
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(1.5, 1.5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	draw_colored_polygon(pts, Color.WHITE)


func _draw_torpedo_icon() -> void:
	var w: float = _radius * 0.45
	var h: float = _radius * 1.10
	# Body
	draw_rect(Rect2(-w * 0.5, -h * 0.4, w, h), Color.WHITE, true)
	# Nose triangle
	var nose := PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.4),
		Vector2(w * 0.5, -h * 0.4),
		Vector2(0, -h * 0.75),
	])
	draw_colored_polygon(nose, Color.WHITE)
	# Fins
	draw_rect(Rect2(-w * 0.9, h * 0.45, w * 0.4, h * 0.30), Color.WHITE, true)
	draw_rect(Rect2(w * 0.5, h * 0.45, w * 0.4, h * 0.30), Color.WHITE, true)


func _draw_heart_icon() -> void:
	# Plump white heart shape, drawn as two top circles + a bottom triangle.
	var s: float = _radius * 0.55
	# Drop shadow first
	draw_circle(Vector2(-s * 0.50 + 1, -s * 0.18 + 1), s * 0.55, Color(0, 0, 0, 0.45))
	draw_circle(Vector2(s * 0.50 + 1, -s * 0.18 + 1), s * 0.55, Color(0, 0, 0, 0.45))
	var shadow_tri := PackedVector2Array([
		Vector2(-s * 1.05 + 1, -s * 0.10 + 1),
		Vector2(s * 1.05 + 1, -s * 0.10 + 1),
		Vector2(0 + 1, s * 1.05 + 1),
	])
	draw_colored_polygon(shadow_tri, Color(0, 0, 0, 0.45))
	# Heart body
	draw_circle(Vector2(-s * 0.50, -s * 0.18), s * 0.55, Color.WHITE)
	draw_circle(Vector2(s * 0.50, -s * 0.18), s * 0.55, Color.WHITE)
	var tri := PackedVector2Array([
		Vector2(-s * 1.05, -s * 0.10),
		Vector2(s * 1.05, -s * 0.10),
		Vector2(0, s * 1.05),
	])
	draw_colored_polygon(tri, Color.WHITE)


func _draw_sidekick_icon() -> void:
	# Two small ship triangles side-by-side — a "wingmate" silhouette.
	var s: float = _radius * 0.55
	var offsets := [Vector2(-s * 0.55, 0), Vector2(s * 0.55, 0)]
	for o in offsets:
		var tri := PackedVector2Array([
			o + Vector2(0, -s * 0.7),
			o + Vector2(-s * 0.45, s * 0.45),
			o + Vector2(s * 0.45, s * 0.45),
		])
		var shadow := PackedVector2Array()
		for p in tri:
			shadow.append(p + Vector2(1, 1))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
		draw_colored_polygon(tri, Color.WHITE)


func _draw_weapon_change_icon() -> void:
	# Three pips arranged as a triangle — represents three weapon types
	var d: float = _radius * 0.50
	var dot_r: float = _radius * 0.16
	for p in [Vector2(0, -d), Vector2(-d * 0.85, d * 0.5), Vector2(d * 0.85, d * 0.5)]:
		draw_circle(p + Vector2(1, 1), dot_r, Color(0, 0, 0, 0.5))
		draw_circle(p, dot_r, Color.WHITE)
	# Connecting arrows hint at cycling
	for ang_offset in [-PI / 6, PI - PI / 6, PI + PI / 2]:
		var c: Vector2 = Vector2.ZERO
		# Just an inner orbiting arc to suggest "cycle"
	draw_arc(Vector2.ZERO, _radius * 0.42, 0, TAU, 18, Color(1, 1, 1, 0.75), 1.5, true)


# --- Coin draw (kept from previous version, polished slightly) ---

func _draw_coin() -> void:
	# Coin spin — animate the horizontal scale so it reads as a flipping disc.
	# Squish factor goes 1.0 → 0.15 → 1.0 over the spin cycle.
	var spin_phase: float = fmod(_time * 2.4, TAU)
	var squish: float = abs(cos(spin_phase))
	squish = max(0.18, squish)  # never fully edge-on, keeps it readable
	var r: float = _radius
	var rx: float = r * squish        # horizontal radius
	var ry: float = r                  # vertical radius
	# Tilt the face brightness based on spin so the lit side reads
	var face_lit: float = 0.55 + 0.45 * cos(spin_phase)

	# --- Outer glow halo (always round) ---
	draw_circle(Vector2.ZERO, r * 1.9, Color(1.0, 0.80, 0.10, 0.15))
	draw_circle(Vector2.ZERO, r * 1.45, Color(1.0, 0.85, 0.15, 0.30))

	# --- Coin face: build an oval as a fan polygon ---
	var oval := PackedVector2Array()
	var seg: int = 28
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		oval.append(Vector2(cos(a) * rx, sin(a) * ry))
	# Outer rim ring (darker gold)
	draw_colored_polygon(oval, Color(0.85, 0.55, 0.05))
	# Inner face
	var inner := PackedVector2Array()
	for i in seg:
		var a2: float = TAU * float(i) / float(seg)
		inner.append(Vector2(cos(a2) * rx * 0.86, sin(a2) * ry * 0.86))
	var face_color := Color(_color.r * face_lit + 0.25, _color.g * face_lit + 0.20, _color.b * face_lit * 0.5)
	face_color = face_color.clamp()
	draw_colored_polygon(inner, face_color)
	# Brighter inner ring (sells the coined edge)
	var inner2 := PackedVector2Array()
	for i in seg:
		var a3: float = TAU * float(i) / float(seg)
		inner2.append(Vector2(cos(a3) * rx * 0.70, sin(a3) * ry * 0.70))
	draw_colored_polygon(inner2, _accent)

	# --- "$" stamp on the face — squished with the spin so it spins WITH the coin ---
	# Skip drawing the stamp when the coin is near-edge-on (illegible anyway)
	if squish > 0.30:
		var mark_color := Color(0.45, 0.22, 0.02)
		# Vertical bar
		draw_rect(Rect2(-rx * 0.07, -ry * 0.50, rx * 0.14, ry * 1.00), mark_color, true)
		# S-curve made from two arcs (stretched horizontally with the squish)
		var top_pts := PackedVector2Array()
		var bot_pts := PackedVector2Array()
		var arc_seg: int = 12
		for i in arc_seg + 1:
			var t1: float = float(i) / float(arc_seg)
			var ang_t: float = lerp(PI * 0.20, PI * 1.20, t1)
			top_pts.append(Vector2(cos(ang_t) * rx * 0.32, -ry * 0.20 + sin(ang_t) * ry * 0.30))
		for i in arc_seg + 1:
			var t2: float = float(i) / float(arc_seg)
			var ang_b: float = lerp(PI * 1.20, PI * 2.20, t2)
			bot_pts.append(Vector2(cos(ang_b) * rx * 0.32, ry * 0.20 + sin(ang_b) * ry * 0.30))
		for i in top_pts.size() - 1:
			draw_line(top_pts[i], top_pts[i + 1], mark_color, max(1.5, rx * 0.10))
		for i in bot_pts.size() - 1:
			draw_line(bot_pts[i], bot_pts[i + 1], mark_color, max(1.5, rx * 0.10))

	# --- Specular highlight on the lit side ---
	if squish > 0.25:
		# Highlight slides across the face as the coin spins
		var hx: float = sin(spin_phase) * rx * 0.45
		draw_circle(Vector2(hx - rx * 0.20, -ry * 0.45), max(rx, ry) * 0.18, Color(1, 1, 1, 0.70))
		draw_circle(Vector2(hx - rx * 0.20, -ry * 0.45), max(rx, ry) * 0.09, Color(1, 1, 1, 0.95))

	# --- Edge highlight — thin bright arc on the leading edge of the spin ---
	var edge_x: float = sign(sin(spin_phase)) * rx
	if abs(sin(spin_phase)) > 0.25:
		draw_line(Vector2(edge_x, -ry * 0.85), Vector2(edge_x, ry * 0.85), Color(1, 1, 0.85, 0.85), 2.0)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = max(_radius, 14.0)
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	position.y += fall_speed * delta

	# Magnetism — within magnet_radius the pickup accelerates toward the player.
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		var to_player: Vector2 = player.global_position - global_position
		var dist: float = to_player.length()
		if dist > 0.0 and dist < magnet_radius:
			var k: float = 1.0 - (dist / magnet_radius)
			var pull: float = magnet_strength * (k * k)
			position += to_player.normalized() * pull * delta

	# Gentle bob (vertical) plus wobble (rotation) — reads as "alive"
	rotation = sin(_time * 4.0) * 0.10
	queue_redraw()
	if position.y > _viewport_size.y + 50:
		queue_free()
