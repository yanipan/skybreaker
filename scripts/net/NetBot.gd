extends Node
## Headless co-op bot: connects to a ServerWorld, flies a stand-in ship that
## chases the nearest target, "fires" by hitting the lowest puppet in its
## column (through the real puppet take_damage -> Net.report_hit path) and
## claims every pickup it sees. Prints one STATS line at game over.
##   godot --headless --path . res://scenes/net/NetBot.tscn -- --host=127.0.0.1 --port=24620 --name=botA [--lag=60] [--loss=0.02]

const FIELD := Vector2i(816, 1800)
var host: String = "127.0.0.1"
var port: int = Net.DEFAULT_PORT
var bot_name: String = "bot"
var dps_tick: float = 0.1
var dmg: int = 2

var world: Node2D
var nc: NetClient
var ship: Area2D
var _fire_t: float = 0.0
var _claim_age: Dictionary = {}
var _sectors: Array = []
var _cleared: Array = []
var _hits_sent: int = 0
var shop_secs: float = 1.5
var _in_shop: bool = false
var _shops: int = 0
var _dock_age: Dictionary = {}
var _hits_in_shop: int = 0
## Test hooks: --die_at=T makes the bot go DOWN T seconds into the first
## sector; --no_rescue stops it picking up the partner's pod.
var die_at: float = -1.0
var give_up_after: float = 600.0   ## --timeout=N seconds (a full 24-sector run needs more)
var no_rescue: bool = false
var no_pickups: bool = false
## --drop_at=T cuts the link T seconds into the run and stays away --drop_secs
## (then NetClient reconnects); --drop_in_shop cuts it when the shop opens;
## --give_up=N = how long the bot keeps trying.
var drop_at: float = -1.0
var drop_secs: float = 0.5
var drop_in_shop: bool = false
var give_up: float = 45.0
var _dropped: bool = false
var _links: Array = []      ## partner LINK states seen
var _link_failed: bool = false
var _down: bool = false
var _died: bool = false
var _mission_t: float = -1.0
var _revived: int = 0
var _rescues: int = 0
var _claim_cd: float = 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		if kv.size() == 1:
			if kv[0] == "no_rescue":   # flags have no value
				no_rescue = true
			if kv[0] == "drop_in_shop":
				drop_in_shop = true
			if kv[0] == "no_pickups":   # leave every pickup to the partner
				no_pickups = true
			continue
		if kv.size() != 2:
			continue
		match kv[0]:
			"host": host = kv[1]
			"port": port = int(kv[1])
			"name": bot_name = kv[1]
			"lag": Net.fake_lag_ms = int(kv[1])
			"loss": Net.fake_loss = float(kv[1])
			"dmg": dmg = int(kv[1])
			"shop_secs": shop_secs = float(kv[1])
			"die_at": die_at = float(kv[1])
			"timeout": give_up_after = float(kv[1])
			"drop_at": drop_at = float(kv[1])
			"drop_secs": drop_secs = float(kv[1])
			"give_up": give_up = float(kv[1])
	get_window().content_scale_size = FIELD
	get_window().size = FIELD
	world = Node2D.new()
	add_child(world)
	ship = Area2D.new()
	ship.monitoring = false
	ship.monitorable = false
	ship.position = Vector2(408, 1500)
	ship.add_to_group(&"player")
	add_child(ship)
	nc = NetClient.new()
	nc.world = world
	nc.player_name = bot_name
	nc.ship_state = func() -> Dictionary: return {"p": ship.position, "a": not _down, "w": 0, "l": 5, "f": not _down, "n": bot_name}
	nc.first_retry_after = drop_secs
	nc.give_up_after = give_up
	nc.partner_link.connect(func(_p: int, st: int) -> void: _links.append(st))
	nc.link_failed.connect(func() -> void:
		_link_failed = true
		_on_over(false))
	nc.revived.connect(func(peer: int, by: int) -> void:
		if peer == Net.my_peer:
			_down = false
			_revived += 1
		if by == Net.my_peer:
			_rescues += 1)
	add_child(nc)
	nc.sector_started.connect(func(l: int) -> void:
		_sectors.append(l)
		_down = false   # a downed ship returns in the new sector
		if _mission_t < 0.0:
			_mission_t = 0.0)
	nc.sector_cleared.connect(func(l: int) -> void:
		_cleared.append(l)
		Net.send(0, [Net.M.READY, l + 1]))   # a bot has nothing to load
	nc.welcomed.connect(func(_p: int, _s: int) -> void: Net.send(0, [Net.M.READY, nc.start_sector]))
	# Shop: a bot "shops" for shop_secs, then leaves. Its bullets and the
	# server's world are frozen meanwhile, so it also stops firing.
	nc.shop_opened.connect(func(_b: int, _d: int) -> void:
		_in_shop = true
		_shops += 1
		if drop_in_shop and not _dropped:
			_dropped = true
			Net.drop_link()
			return
		get_tree().create_timer(shop_secs).timeout.connect(func() -> void: Net.send(0, [Net.M.SHOP_READY, true])))
	nc.shop_closed.connect(func() -> void: _in_shop = false)
	nc.game_over.connect(_on_over)
	var err: int = Net.connect_to(host, port)
	print(bot_name, ": connecting ", host, ":", port, " err=", err)
	get_tree().create_timer(give_up_after).timeout.connect(func() -> void:
		print(bot_name, ": TIMEOUT")
		get_tree().quit(3))


## Something a real shot could hit: not a wrecked boss part, not a cloaked ship.
static func _hittable(n) -> bool:
	if not is_instance_valid(n):
		return false
	if n is Starbase or n is RevivePod:
		return false
	if "alive" in n and not n.alive:
		return false
	if "cloaked" in n and n.cloaked:
		return false
	return true


func _process(delta: float) -> void:
	# Dock at any starbase that has been in view for 2 s
	for id in nc.puppets.keys():
		var sb = nc.puppets.get(id)
		if sb != null and is_instance_valid(sb) and sb is Starbase and not sb._used and sb.position.y > 100.0:
			_dock_age[id] = float(_dock_age.get(id, 0.0)) + delta
			if _dock_age[id] > 2.0:
				_dock_age[id] = -3.0
				Net.send(0, [Net.M.DOCK, id])
	if _in_shop:
		return
	if _mission_t >= 0.0:
		_mission_t += delta
	if drop_at >= 0.0 and not _dropped and _mission_t >= drop_at:
		_dropped = true
		print(bot_name, ": dropping the link")
		Net.drop_link()
	if die_at >= 0.0 and not _died and _mission_t >= die_at:
		_died = true
		_down = true
		Net.send(0, [Net.M.DOWN, ship.position])
	if _down:
		return   # no ship: nothing to fly, shoot or grab
	# Rescue: fly to the partner's pod and claim it on touch
	_claim_cd = maxf(0.0, _claim_cd - delta)
	if not no_rescue:
		for id in nc.puppets.keys():
			var pod = nc.puppets.get(id)
			if pod != null and is_instance_valid(pod) and pod is RevivePod and pod.for_peer != Net.my_peer:
				ship.position = ship.position.move_toward(pod.global_position, 600.0 * delta)
				if ship.position.distance_to(pod.global_position) < 50.0 and _claim_cd <= 0.0:
					_claim_cd = 1.0
					Net.send(0, [Net.M.CLAIM, id])
				return
	ship.position.y = move_toward(ship.position.y, 1500.0, 600.0 * delta)
	# Steer toward the nearest puppet's x
	var best: Node2D = null
	var bd: float = INF
	for n in nc.puppets.values():
		if _hittable(n) and n.global_position.y > 0.0 and n.global_position.y < ship.position.y:
			var d: float = absf(n.global_position.x - ship.position.x)
			if d < bd:
				bd = d
				best = n
	if best != null:
		ship.position.x = move_toward(ship.position.x, best.global_position.x, 500.0 * delta)
	_fire_t += delta
	if _fire_t >= dps_tick:
		_fire_t = 0.0
		var target: Node2D = null
		for n in nc.puppets.values():
			if _hittable(n) and absf(n.global_position.x - ship.position.x) < 60.0 and n.global_position.y > 0.0 and n.global_position.y < ship.position.y:
				if target == null or n.global_position.y > target.global_position.y:
					target = n
		if target != null and target.has_method("take_damage"):
			target.take_damage(dmg)
			_hits_sent += 1
	for id in nc.pickups.keys():
		var k = nc.pickups.get(id)
		if k == null or not is_instance_valid(k) or k.net_claimed or no_pickups:
			continue
		_claim_age[id] = float(_claim_age.get(id, 0.0)) + delta
		if _claim_age[id] > 0.4:
			k.net_claimed = true
			Net.send(0, [Net.M.CLAIM, id])


func _on_over(won: bool) -> void:
	var s: Dictionary = nc.stats.duplicate()
	s["won"] = won
	s["sectors"] = _sectors
	s["cleared"] = _cleared
	s["hits_sent"] = _hits_sent
	s["shops"] = _shops
	s["revived"] = _revived
	s["reconnects"] = nc.reconnects
	s["links"] = _links
	s["link_failed"] = _link_failed
	s["puppets"] = nc.puppets.size()
	s["rescues"] = _rescues
	s["pending_shots"] = nc._shots.size()
	s["pending_t"] = float(nc._shots[0][0]) if not nc._shots.is_empty() else -1.0
	s["render_t"] = snappedf(nc.render_time(), 0.01) if nc._offset != -INF else -1.0
	s["score"] = GameState.run_score
	s["bytes_in"] = Net.bytes_in
	s["bytes_out"] = Net.bytes_out
	s["peer"] = Net.my_peer
	s["shared_money"] = nc.shared_money
	print(bot_name, ": STATS ", JSON.stringify(s))
	await get_tree().create_timer(0.5).timeout
	Net.stop()
	get_tree().quit(0)
