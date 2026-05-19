extends Node2D
class_name Beam
## Continuous energy beam fired by the player. While active, sweeps straight
## upward from the ship's nose, finds the topmost enemy in the column, and
## applies damage-over-time. Drains charge faster than phasers in exchange.
##
## Visuals are fully procedural — animated layered laser with a wide outer
## halo, mid-glow, hot inner core, scrolling energy bands, and an impact burst
## at the contact point.

@export var beam_color: Color = Color(0.55, 0.95, 1.0)
@export var dps: float = 22.0           ## Damage per second to the topmost target
@export var damage_tick: float = 0.10   ## Apply damage in chunks every N seconds (~10/sec)
@export var beam_width: float = 6.0     ## Visual core width
@export var hit_tolerance: float = 28.0 ## Half-width of the CORE column (full damage)
## Half-width of the outer HALO column. Anything sitting in the halo but
## outside the core takes 50% damage — matches the visual glow that the
## player sees, so the wide aura isn't purely cosmetic.
@export var halo_damage_factor: float = 0.35  ## Was 0.25 — small bump back, beam was the weakest weapon

var active: bool = false  ## Player toggles this each frame
var _viewport_size: Vector2
var _time: float = 0.0
var _damage_accum: float = 0.0
var _halo_damage_accum: float = 0.0
var _impact_pos: Vector2 = Vector2.ZERO
var _impact_active: bool = false


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	z_index = 5
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if not active:
		queue_redraw()
		return
	# --- Find topmost enemy in our CORE vertical column ---
	var origin: Vector2 = global_position + Vector2(0, -38)  # nose of ship
	var hit_y: float = -200.0  # default: beam shoots off the top of the screen
	var hit_target: Node = null
	# Halo column extends past the core, matching the visual outer glow
	# (~beam_width * 2.25 half-width). Cap at a reasonable minimum so even
	# a thin level-1 beam still rewards the player for grazing shots.
	var halo_tolerance: float = max(hit_tolerance * 1.6, beam_width * 2.25)
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		# Only consider enemies within our column and above the ship
		if abs(e.global_position.x - origin.x) > hit_tolerance:
			continue
		if e.global_position.y > origin.y:
			continue
		# Pick the LOWEST one (closest to player) — core beam stops on first target
		if hit_target == null or e.global_position.y > hit_y:
			hit_target = e
			hit_y = e.global_position.y
	# --- Vaporize enemy bullets sitting in our column. Burn band tightened
	# again — was halo_tolerance * 2.08 (already a 20% cut), now 1.5 with a
	# tighter min. Combined with the 30% pop chance below and the boss-fire
	# immunity, the beam no longer doubles as a defensive shield.
	var burn_tolerance: float = max(halo_tolerance * 1.5, 56.0)
	var bullets := get_tree().get_nodes_in_group(&"enemy_bullets")
	for b in bullets:
		if not is_instance_valid(b):
			continue
		if abs(b.global_position.x - origin.x) > burn_tolerance:
			continue
		if b.global_position.y > origin.y:
			continue
		# Only burn bullets between the player and the current impact point
		# so a beam blocked early on a tank still lets bullets above pass.
		if hit_target != null and b.global_position.y < hit_y:
			continue
		# Boss bullets are immune — the player has to dodge boss patterns
		# the hard way, beam or no beam.
		if "from_boss" in b and b.from_boss:
			continue
		# Roll dropped from 50% to 30% — most bullets now leak through the
		# beam. Combined with the narrower burn band, beam-only kids will
		# actually take hits.
		if randf() < 0.42:
			b.queue_free()
	# --- Apply core damage to the topmost core target in tick chunks ---
	if hit_target != null:
		_damage_accum += dps * delta
		if _damage_accum >= dps * damage_tick:
			var dmg: int = max(1, int(round(_damage_accum)))
			if hit_target.has_method("take_damage"):
				hit_target.take_damage(dmg)
			_damage_accum = 0.0
		_impact_pos = Vector2(0.0, hit_y - origin.y)
		_impact_active = true
	else:
		_impact_pos = Vector2(0.0, -origin.y - 200.0)
		_impact_active = false
	# --- HALO damage: every enemy that sits inside the wider aura (but outside
	# the core column) takes a fraction of the core dps. Applied to ALL halo
	# enemies simultaneously since the aura is wide and visually splashes them.
	# Capped to enemies between the player and the core impact point so a
	# blocked beam doesn't reach things above the blocker.
	_halo_damage_accum += dps * halo_damage_factor * delta
	if _halo_damage_accum >= dps * halo_damage_factor * damage_tick:
		var halo_dmg: int = max(1, int(round(_halo_damage_accum)))
		for e2 in enemies:
			if not is_instance_valid(e2) or e2 == hit_target:
				continue
			var dx: float = abs(e2.global_position.x - origin.x)
			if dx <= hit_tolerance or dx > halo_tolerance:
				continue   # in core column (handled above) or outside halo
			if e2.global_position.y > origin.y:
				continue   # below the ship
			if hit_target != null and e2.global_position.y < hit_y:
				continue   # above the blocker
			if e2.has_method("take_damage"):
				e2.take_damage(halo_dmg)
		_halo_damage_accum = 0.0
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	# Draw in local space — Beam is a child of Player so origin is the ship.
	# Beam extends from a point 38px above the ship up to the impact y.
	var start := Vector2(0, -38)
	var end := _impact_pos

	# --- Layered beam: wide halo → mid glow → core → inner white-hot ---
	# Outer halo
	_draw_thick_line(start, end, beam_width * 4.5, Color(beam_color.r, beam_color.g, beam_color.b, 0.18))
	# Mid glow
	_draw_thick_line(start, end, beam_width * 2.5, Color(beam_color.r, beam_color.g, beam_color.b, 0.45))
	# Core body
	_draw_thick_line(start, end, beam_width, beam_color)
	# White-hot inner line
	_draw_thick_line(start, end, beam_width * 0.45, Color(1, 1, 1, 0.95))

	# --- Scrolling energy bands along the length for "alive" feel ---
	var beam_len: float = (end - start).length()
	var band_count: int = int(beam_len / 28.0)
	var scroll: float = fmod(_time * 220.0, 28.0)
	for i in band_count:
		var y: float = start.y - (float(i) * 28.0 + scroll)
		if y < end.y:
			break
		# Brighter pulse-pip across the beam
		draw_circle(Vector2(0, y), beam_width * 0.85, Color(1, 1, 1, 0.65))

	# --- Muzzle flash at the start ---
	var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
	draw_circle(start, beam_width * 2.4 * flicker, Color(beam_color.r, beam_color.g, beam_color.b, 0.55))
	draw_circle(start, beam_width * 1.4 * flicker, Color(1, 1, 1, 0.85))
	draw_circle(start, beam_width * 0.7 * flicker, Color(1, 1, 1, 1))

	# --- Impact burst at the target ---
	if _impact_active:
		var burst_r: float = (8.0 + 4.0 * sin(_time * 40.0))
		draw_circle(end, burst_r * 2.0, Color(beam_color.r, beam_color.g, beam_color.b, 0.40))
		draw_circle(end, burst_r * 1.3, Color(beam_color.r, beam_color.g, beam_color.b, 0.70))
		draw_circle(end, burst_r * 0.8, Color(1, 1, 1, 0.95))
		# Radial sparks at the impact
		for i in 6:
			var ang: float = (TAU / 6.0) * float(i) + _time * 8.0
			var p: Vector2 = end + Vector2(cos(ang), sin(ang)) * burst_r * 1.6
			draw_line(end, p, Color(1, 1, 1, 0.65), 1.5)


## Helper — draws a vertical (or near-vertical) thick "line" as a rectangle
## stretched between start and end. Beams are always vertical so this is fine.
func _draw_thick_line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	# Both points have x=0 in local space, so we can just draw a rect.
	var top_y: float = min(a.y, b.y)
	var bot_y: float = max(a.y, b.y)
	draw_rect(Rect2(-width * 0.5, top_y, width, bot_y - top_y), color, true)
