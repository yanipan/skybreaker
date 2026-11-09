extends RefCounted
class_name HitCheck
## Safety net for hits (6/11 device report: after a pause, shots passed through
## enemies and the ship while the physics watchdog still saw its probes).
## Every frame, bullets also test a plain rectangle overlap against their
## targets. If a bullet sits on a target for STUCK_FRAMES frames and the
## physics engine still has not reported the hit, the hit is applied here and
## counted (GameState.hit_fallbacks -> play stats), so the game stays fair
## whatever the engine does and we learn how often it happens.

## The engine reports a hit one physics tick after the overlap starts, so a
## shot counts as missed after 2 physics ticks or 50 ms on the target,
## whichever comes first (the time limit covers a slowed-down physics loop).
const STUCK_TICKS: int = 2
const STUCK_MS: int = 50

static var _enemy_cache: Array = []
static var _cache_frame: int = -1


static func half_extents(n: Node) -> Vector2:
	if "boss_size" in n:
		return Vector2(n.boss_size * 0.425, n.boss_size * 0.375)
	if "enemy_size" in n:
		return Vector2.ONE * (n.enemy_size * 0.5)
	if "ship_size" in n:
		return Vector2.ONE * (n.ship_size * 0.5)
	return Vector2(20, 20)


static func overlap(a_pos: Vector2, a_half: Vector2, b: Node2D) -> bool:
	var bh: Vector2 = half_extents(b)
	var d: Vector2 = (a_pos - b.global_position).abs()
	return d.x <= a_half.x + bh.x and d.y <= a_half.y + bh.y


static func _enemies(tree: SceneTree) -> Array:
	var f: int = Engine.get_process_frames()
	if f != _cache_frame:
		_cache_frame = f
		_enemy_cache = tree.get_nodes_in_group(&"enemies")
	return _enemy_cache


## First live enemy overlapping a player shot, or null.
static func enemy_at(shot: Node2D, half: Vector2) -> Node2D:
	for e in _enemies(shot.get_tree()):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if "cloaked" in e and e.cloaked:
			continue   # phased SHADE: nothing lands, not even the safety net
		if overlap(shot.global_position, half, e):
			return e
	return null


## Call every frame with whether the shot overlaps its target. `state` is the
## shot's own [start_tick, start_ms] (empty = not overlapping). True = apply now.
static func stuck(overlapping: bool, state: Array) -> bool:
	if not overlapping:
		state.clear()
		return false
	if state.is_empty():
		state.append(Engine.get_physics_frames())
		state.append(Time.get_ticks_msec())
		return false
	return Engine.get_physics_frames() - int(state[0]) >= STUCK_TICKS or Time.get_ticks_msec() - int(state[1]) >= STUCK_MS


static func note_fallback(who: String = "") -> void:
	if OS.is_debug_build():
		print("HitCheck fallback: ", who, " frame ", Engine.get_process_frames(), " phys ", Engine.get_physics_frames())
	GameState.hit_fallbacks += 1
