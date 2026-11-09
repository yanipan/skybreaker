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


## Battery pass 9/11: every player shot asks this every frame. The enemy list
## is flattened ONCE per frame into parallel arrays (node, centre, half
## extents, cloaked), so the per-shot loop is plain float compares instead of
## three property probes and two engine calls per enemy.
static var _c_nodes: Array = []
static var _c_x: PackedFloat32Array = []
static var _c_y: PackedFloat32Array = []
static var _c_hx: PackedFloat32Array = []
static var _c_hy: PackedFloat32Array = []
static var _player_cache: Node2D = null
static var _player_frame: int = -1
static var _player_half: Vector2 = Vector2(20, 20)


static func _refresh(tree: SceneTree) -> void:
	var f: int = Engine.get_process_frames()
	if f == _cache_frame:
		return
	_cache_frame = f
	_enemy_cache = tree.get_nodes_in_group(&"enemies")
	_c_nodes.clear()
	_c_x.clear(); _c_y.clear(); _c_hx.clear(); _c_hy.clear()
	for e in _enemy_cache:
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if "cloaked" in e and e.cloaked:
			continue   # phased SHADE: nothing lands, not even the safety net
		var h: Vector2 = half_extents(e)
		var p: Vector2 = e.global_position
		_c_nodes.append(e)
		_c_x.append(p.x); _c_y.append(p.y); _c_hx.append(h.x); _c_hy.append(h.y)


static func _enemies(tree: SceneTree) -> Array:
	_refresh(tree)
	return _enemy_cache


## First live enemy overlapping a player shot, or null.
static func enemy_at(shot: Node2D, half: Vector2) -> Node2D:
	_refresh(shot.get_tree())
	var p: Vector2 = shot.global_position
	for i in _c_nodes.size():
		if absf(p.x - _c_x[i]) <= half.x + _c_hx[i] and absf(p.y - _c_y[i]) <= half.y + _c_hy[i]:
			var e: Node2D = _c_nodes[i]
			# The cache is one frame old at most: the enemy may have died or
			# cloaked since it was built.
			if is_instance_valid(e) and not e.is_queued_for_deletion() and not ("cloaked" in e and e.cloaked):
				return e
	return null


## The ship, looked up once per frame for every enemy shot's safety net.
static func player(tree: SceneTree) -> Node2D:
	var f: int = Engine.get_process_frames()
	if f != _player_frame or not is_instance_valid(_player_cache):
		_player_frame = f
		_player_cache = tree.get_first_node_in_group(&"player") as Node2D
		if _player_cache != null:
			_player_half = half_extents(_player_cache)
	return _player_cache


## True when a shot of half-size `r` at `pos` overlaps the ship found by
## player() this frame (same rectangle test as overlap(), without re-probing
## the ship's size for every shot).
static func on_player(pos: Vector2, r: float) -> bool:
	if _player_cache == null:
		return false
	var d: Vector2 = pos - _player_cache.global_position
	return absf(d.x) <= r + _player_half.x and absf(d.y) <= r + _player_half.y


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
