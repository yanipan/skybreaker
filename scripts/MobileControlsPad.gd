extends Control
## Invisible touch pad over the whole weapon corner (6/11). Each touch goes to
## the NEAREST button center (P / B / M / torpedo), so the corner is split into
## four wedges and the thumb lands on the right one without aiming. The round
## buttons stay as visuals only; MobileControls routes the touches.

var radius: float = 200.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= radius


## Index of the nearest center to `pos` (both in the same space).
static func nearest_slot(pos: Vector2, centers: Array) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in centers.size():
		var d: float = pos.distance_squared_to(centers[i])
		if d < best_d:
			best_d = d
			best = i
	return best
