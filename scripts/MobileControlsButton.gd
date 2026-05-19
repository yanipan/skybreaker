extends Control
## Round action button used by MobileControls (torpedo + weapon switch).
##
## Renders a circular panel with a glowing border. The parent
## (MobileControls) sets metadata on us each frame:
##   * "ready" (bool)  — true = bright glow, false = dim red border
##   * "pulse" (float) — 0..1 phase used for the breathing glow
##   * "col_panel" / "col_border" / "col_glow" — palette colors
##
## We deliberately don't use a Button + StyleBox because the rounded
## radius + animated border glow is much cleaner with a custom _draw().

const COL_RED_DIM := Color(1.0, 0.45, 0.45, 0.85)


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	# Parent calls queue_redraw via metadata changes; nothing to do here.
	pass


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.5

	var panel_col: Color = get_meta("col_panel", Color(0, 0, 0, 0.55))
	var border_col: Color = get_meta("col_border", Color(1, 1, 1, 0.5))
	var glow_col: Color = get_meta("col_glow", Color(0.55, 0.95, 1.0))
	var ready: bool = get_meta("ready", true)
	var pulse: float = get_meta("pulse", 0.0)

	# --- Soft outer halo ---
	# A few concentric translucent circles fake a glow without needing a
	# shader. Brighter when the button is ready, dimmer otherwise.
	var halo_strength: float = (0.55 if ready else 0.18) + pulse * 0.20
	for i in 5:
		var t: float = float(i) / 4.0
		var r: float = radius * (1.04 + t * 0.18)
		var a: float = halo_strength * (1.0 - t) * 0.18
		draw_circle(center, r, Color(glow_col.r, glow_col.g, glow_col.b, a))

	# --- Filled panel background ---
	draw_circle(center, radius, panel_col)

	# --- Border ring ---
	# Two strokes for a "thick + soft" look. Color shifts to red-dim when
	# the button is unavailable (e.g. torpedo with zero ammo).
	var ring_outer_col: Color = border_col if ready else COL_RED_DIM
	if ready:
		ring_outer_col.a = clamp(0.55 + pulse * 0.40, 0.0, 1.0)
	draw_arc(center, radius - 2.0, 0.0, TAU, 64, ring_outer_col, 4.0, true)
	draw_arc(center, radius - 8.0, 0.0, TAU, 64, Color(ring_outer_col.r, ring_outer_col.g, ring_outer_col.b, ring_outer_col.a * 0.45), 2.0, true)

	# --- Inner shine arc ---
	# A short bright arc near the top edge sells the "polished glass" look.
	if ready:
		var shine_col := Color(1, 1, 1, 0.18 + pulse * 0.10)
		draw_arc(center, radius - 4.0, -PI * 0.85, -PI * 0.35, 24, shine_col, 3.0, true)
