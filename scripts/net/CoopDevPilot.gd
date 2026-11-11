extends Node
## DEV helper for CoopDev: optional autopilot (steer under the nearest enemy,
## hold fire) and periodic screenshots. Lives under the root so it survives
## Main's scene reloads.

var pilot: String = "Pilot"
var autopilot: bool = false
var shot_every: float = 0.0
var _shot_t: float = 0.0
var _shot_n: int = 0
var _t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
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
			me.set_stick_target(Vector2(want_x / size.x, 0.80), true)
			me._fire_button_held = true
			me._is_firing = true
	if shot_every > 0.0 and DisplayServer.get_name() != "headless":
		_shot_t += delta
		if _shot_t >= shot_every:
			_shot_t = 0.0
			_shot_n += 1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://coop_%s_%02d.png" % [pilot, _shot_n])
