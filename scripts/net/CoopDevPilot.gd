extends Node
## DEV helper for CoopDev: optional autopilot (steer under the nearest enemy,
## hold fire) and periodic screenshots. Lives under the root so it survives
## Main's scene reloads.

var pilot: String = "Pilot"
var autopilot: bool = false
var shot_every: float = 0.0
## --die_at=T: T seconds after the first ship appears, this pilot loses its
## last life on purpose (to show DOWN, the rescue pod and the revive).
var die_at: float = -1.0
var drop_at: float = -1.0
var drop_secs: float = 0.5
var _dropped: bool = false
var no_rescue: bool = false
## --perf: sample the script time per frame (Performance.TIME_PROCESS) while a
## ship is flying and print PERF lines (avg / p95 / worst, frames per second).
var perf: bool = false
var _perf_ms: PackedFloat32Array = PackedFloat32Array()
var _perf_t: float = 0.0
var _perf_frames: int = 0
var _perf_puppets: int = 0
var _perf_shots: int = 0
var _flown: float = 0.0
var _died: bool = false
var _shot_t: float = 0.0
var _shot_n: int = 0
var _t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Autopilot in the shared shop. Seat 0 leaves after 3 s, goes BACK TO SHOP
## 2 s later, and leaves for good 2 s after that; seat 1 shops for 9 s. So one
## run shows: both shopping, one waiting, the change of mind, both ready.
var _shop_t: float = 0.0
var _shop_step: int = 0

func _drive_shop(delta: float) -> void:
	var main: Node = get_tree().current_scene
	var cs = main.get_node_or_null("CoopShop") if main != null else null
	if cs == null or not cs.open:
		_shop_t = 0.0
		_shop_step = 0
		return
	_shop_t += delta
	var shop = cs._shop
	if Net.seat == 0:
		if _shop_step == 0 and _shop_t > 3.0 and shop != null and is_instance_valid(shop):
			_shop_step = 1
			shop._on_leave()
		elif _shop_step == 1 and _shop_t > 5.0:
			_shop_step = 2
			cs._back_to_shop()
		elif _shop_step == 2 and _shop_t > 7.0 and shop != null and is_instance_valid(shop):
			_shop_step = 3
			shop._on_leave()
	else:
		if _shop_step == 0 and _shop_t > 2.0 and shop != null and is_instance_valid(shop):
			_shop_step = 1
			shop._on_buy(&"repair")   # shows up on the partner's strip (if affordable)
		elif _shop_step == 1 and _shop_t > 9.0 and shop != null and is_instance_valid(shop):
			_shop_step = 2
			shop._on_leave()


## PERF: real time between frames while a ship is flying (hitches show up as
## long frames), plus Godot's own process-time monitor, which is the WORST
## process step of the last second (so its median is "a typical bad frame").
## The first PERF_GRACE seconds after a scene (re)load are left out.
const PERF_GRACE: float = 3.0
var god: bool = false            ## --god: the ship cannot be hit (keeps the sample going)
var _perf_last_usec: int = 0
var _perf_ship_id: int = 0
var _perf_ship_age: float = 0.0
var _perf_mon: PackedFloat32Array = PackedFloat32Array()

func _perf_sample(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var gap_ms: float = float(now - _perf_last_usec) / 1000.0
	_perf_last_usec = now
	var me = get_tree().get_first_node_in_group(&"player")
	if me == null or not is_instance_valid(me) or get_tree().paused:
		_perf_ship_id = 0
		return
	if god and me.monitoring:
		me.set_deferred("monitoring", false)
	if me.get_instance_id() != _perf_ship_id:
		_perf_ship_id = me.get_instance_id()
		_perf_ship_age = 0.0
	_perf_ship_age += delta
	if _perf_ship_age < PERF_GRACE:
		return
	_perf_ms.append(gap_ms)
	_perf_mon.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf_puppets += get_tree().get_nodes_in_group(&"enemies").size()
	_perf_shots += get_tree().get_nodes_in_group(&"enemy_bullets").size()
	_perf_t += gap_ms / 1000.0
	if _perf_t >= 20.0:
		_perf_report()


func _perf_report() -> void:
	if _perf_ms.is_empty():
		return
	var sorted: Array = Array(_perf_ms)
	sorted.sort()
	var mon: Array = Array(_perf_mon)
	mon.sort()
	var n: int = sorted.size()
	var sum: float = 0.0
	var over25: int = 0
	var over50: int = 0
	for v in sorted:
		sum += v
		if v > 25.0: over25 += 1
		if v > 50.0: over50 += 1
	print("PERF %s %s sector=%d frames=%d fps=%.1f  frame ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f worst=%.1f  long frames >25ms=%d >50ms=%d  | process-step monitor median=%.2f ms | avg enemies=%.1f enemy_shots=%.1f" % [
			"CO-OP" if Net.is_client() else "SOLO", pilot, GameState.current_level, n, float(n) / maxf(0.001, _perf_t), sum / n,
			sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], over25, over50, mon[mon.size() / 2],
			float(_perf_puppets) / n, float(_perf_shots) / n])
	_perf_ms = PackedFloat32Array()
	_perf_mon = PackedFloat32Array()
	_perf_t = 0.0
	_perf_puppets = 0
	_perf_shots = 0


func _process(delta: float) -> void:
	if perf:
		_perf_sample(delta)
	_t += delta
	if drop_at >= 0.0 and not _dropped and _t >= drop_at and Net.client != null:
		_dropped = true
		Net.client.first_retry_after = drop_secs
		print("CoopDev ", pilot, ": dropping the link for ", drop_secs, " s")
		Net.drop_link()
	if autopilot and not get_tree().paused:
		var me = get_tree().get_first_node_in_group(&"player")
		if me != null and is_instance_valid(me) and me.has_method("set_stick_target"):
			var size: Vector2 = me.get_viewport_rect().size
			var want_x: float = size.x * (0.5 + 0.3 * sin(_t * 0.7 + (0.0 if Net.seat == 0 else PI)))
			var best: float = INF
			for e in get_tree().get_nodes_in_group(&"enemies"):
				if not is_instance_valid(e):
					continue
				var p: Vector2 = (e as Node2D).global_position
				if p.y < 0.0 or p.y > me.global_position.y:
					continue
				var d: float = absf(p.x - me.global_position.x) + (me.global_position.y - p.y) * 0.3
				if d < best:
					best = d
					want_x = p.x + (-70.0 if Net.seat == 0 else 70.0)   # two ships, two lanes
			_flown += delta
			if die_at >= 0.0 and not _died and _flown >= die_at and me.visible and me.has_method("_die"):
				_died = true
				GameState.lives = 1
				me._die()
				return
			# A starbase in view: fly into it (docking opens the shared shop).
			var want_y: float = size.y * 0.80
			# The partner's rescue pod comes first.
			for pod in get_tree().get_nodes_in_group(&"revive_pods"):
				if not no_rescue and is_instance_valid(pod) and pod.for_peer != Net.my_peer and not pod.claimed:
					want_x = (pod as Node2D).global_position.x
					want_y = (pod as Node2D).global_position.y
					me.set_stick_target(Vector2(want_x / size.x, want_y / size.y), true)
					me._fire_button_held = true
					me._is_firing = true
					return
			for sb in get_tree().get_nodes_in_group(&"starbases"):
				if is_instance_valid(sb) and not sb._used and (sb as Node2D).global_position.y > 120.0:
					want_x = (sb as Node2D).global_position.x
					want_y = (sb as Node2D).global_position.y
			me.set_stick_target(Vector2(want_x / size.x, want_y / size.y), true)
			me._fire_button_held = true
			me._is_firing = true
	if autopilot:
		_drive_shop(delta)
	if shot_every > 0.0 and DisplayServer.get_name() != "headless":
		_shot_t += delta
		if _shot_t >= shot_every:
			_shot_t = 0.0
			_shot_n += 1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://coop_%s_%02d.png" % [pilot, _shot_n])
