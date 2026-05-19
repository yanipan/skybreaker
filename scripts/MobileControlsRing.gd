extends Node2D
## Animated finger ring drawn at the player's current touch position.
##
## Lives as a child of MobileControls. The parent calls update_ring() each
## frame with the current position, alpha, and pulse phase. We just store
## those and queue_redraw — all the actual rendering happens in _draw().
##
## Visual: a soft cyan double-ring (outer pulses, inner stays steady) with
## a faint cross hairline so the player can clearly see where their finger
## is registering. Designed to be unmistakable but never visually noisy
## enough to obscure the gameplay underneath.

const COL_CYAN := Color(0.55, 0.95, 1.00)

var _ring_pos: Vector2 = Vector2.ZERO
var _ring_alpha: float = 0.0
var _ring_pulse: float = 0.0


func update_ring(pos: Vector2, alpha: float, pulse: float) -> void:
	_ring_pos = pos
	_ring_alpha = alpha
	_ring_pulse = pulse
	queue_redraw()


func _draw() -> void:
	if _ring_alpha <= 0.01:
		return
	# Outer pulsing ring — radius breathes between 38 and 54 px
	var outer_r: float = lerp(38.0, 54.0, _ring_pulse)
	var outer_col := Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, _ring_alpha * 0.55)
	draw_arc(_ring_pos, outer_r, 0.0, TAU, 48, outer_col, 3.0, true)

	# Inner steady ring
	var inner_col := Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, _ring_alpha * 0.85)
	draw_arc(_ring_pos, 28.0, 0.0, TAU, 40, inner_col, 2.5, true)

	# Soft fill dot in the center for clarity
	var dot_col := Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, _ring_alpha * 0.20)
	draw_circle(_ring_pos, 22.0, dot_col)

	# Crosshair hairlines — small "+" at the touch point
	var line_col := Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, _ring_alpha * 0.65)
	draw_line(_ring_pos + Vector2(-10, 0), _ring_pos + Vector2(10, 0), line_col, 1.5, true)
	draw_line(_ring_pos + Vector2(0, -10), _ring_pos + Vector2(0, 10), line_col, 1.5, true)
