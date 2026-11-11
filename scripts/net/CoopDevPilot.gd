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
var no_rescue: bool = false
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
