extends RefCounted
class_name Targeting
## Which ship an enemy aims at. Single-player has one ship, so this returns
## the same node get_first_node_in_group(&"player") did. In co-op the room
## server holds one stand-in per phone in group "player", and every enemy,
## boss and homing shot picks the NEAREST one.
## The group is read once per frame and shared by every caller: enemies ask
## every frame.

static var _ships: Array = []
static var _frame: int = -1


static func ships(tree: SceneTree) -> Array:
	var f: int = Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_ships = tree.get_nodes_in_group(&"player") if tree != null else []
	return _ships


## Drop the per-frame cache (tests add and remove ships inside one frame).
static func invalidate() -> void:
	_frame = -1
	_ships = []


## Nearest live ship to `from`, or null when there is none.
static func nearest_ship(tree: SceneTree, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for s in ships(tree):
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var d: float = (s as Node2D).global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = s
	return best
