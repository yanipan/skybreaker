extends Node
class_name NetClient
## CO-OP phone side (docs/MULTIPLAYER_PLAN.md). Turns server messages into
## local objects inside `world`:
## - enemies / rocks / megas = PUPPETS (no AI, server positions, hits go to the
##   server through Net.report_hit, death on KILL)
## - enemy shots and beams = real local EnemyBullet / EnemyBeam, launched with
##   the server's state and flown here, so this phone decides if they hit ITS ship
## - pickups fall locally; touching one claims it, the server grants it once
## Puppets are drawn INTERP seconds behind the server clock, interpolated
## between snapshots; shots wait for that same clock so they leave the muzzle
## the player sees.

signal sector_started(level: int)
signal sector_cleared(level: int)
signal game_over(won: bool)
signal partner_state(peer: int, state: Dictionary)
signal alert(text: String)
signal welcomed(peer: int, seat: int)
signal shop_opened(base_id: int, docker: int)
signal shop_state(peer: int, ready: bool)
signal shop_bought(peer: int, item: String)
signal shop_timer(seconds: float)
signal shop_closed
signal revived(peer: int, by: int)

const INTERP: float = 0.10
const SHIP_EVERY: float = 1.0 / 30.0

## Where puppets/shots go: the current Main (or a test world). The session
## object outlives Main (it is reloaded at every sector change and respawn),
## so a new Main calls attach(self). While no world is attached, world
## messages are dropped (attach asks the server for a SYNC: one SPAWN per
## living object) and flow messages are kept and replayed after the attach.
var world: Node
var player_name: String = "Pilot"
var start_sector: int = 1       ## From HELLO
var _flow_queue: Array = []     ## SECTOR / SECTOR_CLEAR / GAME_OVER / ALERT seen while detached
const FLOW_KINDS: Array = [Net.M.SECTOR, Net.M.SECTOR_CLEAR, Net.M.GAME_OVER, Net.M.ALERT,
		Net.M.SHOP_OPEN, Net.M.SHOP_STATE, Net.M.SHOP_TIMER, Net.M.SHOP_CLOSE, Net.M.REVIVE]
const WORLD_KINDS: Array = [Net.M.SPAWN, Net.M.SNAP, Net.M.SHOT, Net.M.BEAM, Net.M.KILL, Net.M.DESPAWN, Net.M.GRANT]
## Callable returning this phone's ship state Dictionary {p, a, w, l, f, ...};
## defaults to reading the node in group "player".
var ship_state: Callable

var puppets: Dictionary = {}    ## id -> Node2D
var pickups: Dictionary = {}    ## id -> Pickup
var _buf: Dictionary = {}       ## id -> Array of [server_t, Vector2]
var _offset: float = -INF       ## server clock - local clock (best estimate)
var _shots: Array = []          ## pending [server_t, params]
var _ship_t: float = 0.0
var stats := {"spawns": 0, "shots": 0, "kills": 0, "my_kills": 0, "grants": 0, "my_grants": 0, "snaps": 0}


func _ready() -> void:
	Net.message.connect(_on_msg)
	Net.connected.connect(func() -> void: Net.send(0, [Net.M.JOIN, Net.PROTO, player_name]))
	if Net.server_connected:
		Net.send(0, [Net.M.JOIN, Net.PROTO, player_name])


## A freshly loaded Main (or a test world) becomes the place puppets live.
## Everything from the previous scene died with it, so the tables are reset,
## the server is asked to resend what is alive, and it is told this phone is
## ready for `level`.
func attach(w: Node, level: int) -> void:
	world = w
	puppets.clear()
	pickups.clear()
	_buf.clear()
	_shots.clear()
	w.tree_exiting.connect(_detach.bind(w), CONNECT_ONE_SHOT)
	Net.send(0, [Net.M.SYNC])
	Net.send(0, [Net.M.READY, level])
	if not _flow_queue.is_empty():
		var q: Array = _flow_queue
		_flow_queue = []
		for m in q:
			_on_msg.call_deferred(0, m)


func _detach(w: Node) -> void:
	if world == w:
		world = null


func _now() -> float:
	return Time.get_ticks_usec() / 1e6


## Server clock time we are drawing right now.
func render_time() -> float:
	return _now() + _offset - INTERP


func _on_msg(_peer: int, msg: Array) -> void:
	var kind: int = int(msg[0])
	if world == null or not is_instance_valid(world):
		if kind in FLOW_KINDS:
			_flow_queue.append(msg)
			return
		if kind in WORLD_KINDS:
			return
	match kind:
		Net.M.HELLO:
			Net.my_peer = int(msg[2])
			Net.seat = int(msg[3])
			start_sector = int(msg[4]) if msg.size() > 4 else 1
			welcomed.emit(Net.my_peer, Net.seat)
		Net.M.SECTOR:
			_clear()
			GameState.current_level = int(msg[1])
			sector_started.emit(int(msg[1]))
		Net.M.SECTOR_CLEAR:
			sector_cleared.emit(int(msg[1]))
		Net.M.GAME_OVER:
			game_over.emit(bool(msg[1]))
		Net.M.SPAWN:
			_spawn(int(msg[1]), str(msg[2]), msg[3])
		Net.M.SNAP:
			_snap(float(msg[1]), msg[2], msg[3], msg[4], msg[5] if msg.size() > 5 else PackedByteArray())
		Net.M.SHOT:
			var sp: Dictionary = msg[1]
			_shots.append([float(sp.get("t", 0.0)), sp])
		Net.M.BEAM:
			_beam(int(msg[1]), msg[2])
		Net.M.KILL:
			_kill(int(msg[1]), int(msg[2]))
		Net.M.DESPAWN:
			_despawn(int(msg[1]))
		Net.M.GRANT:
			_grant(int(msg[1]), int(msg[2]))
		Net.M.PARTNER:
			partner_state.emit(int(msg[1]), msg[2])
		Net.M.ALERT:
			alert.emit(str(msg[1]))
		Net.M.SHOP_OPEN:
			shop_opened.emit(int(msg[1]), int(msg[2]))
		Net.M.SHOP_STATE:
			shop_state.emit(int(msg[1]), bool(msg[2]))
		Net.M.SHOP_BOUGHT:
			shop_bought.emit(int(msg[1]), str(msg[2]))
		Net.M.SHOP_TIMER:
			shop_timer.emit(float(msg[1]))
		Net.M.SHOP_CLOSE:
			reset_clock()
			shop_closed.emit()
		Net.M.REVIVE:
			revived.emit(int(msg[1]), int(msg[2]))


## The server clock stood still (shop) while this phone's clock did not: drop
## the clock estimate and the snapshot history, or puppets and held shots
## would be drawn far ahead of the server. The next snapshot starts afresh.
func reset_clock() -> void:
	_offset = -INF
	for id in _buf:
		_buf[id] = []


func _clear() -> void:
	for n in puppets.values():
		if is_instance_valid(n):
			n.queue_free()
	for n in pickups.values():
		if is_instance_valid(n):
			n.queue_free()
	puppets.clear()
	pickups.clear()
	_buf.clear()
	_shots.clear()


func _spawn(id: int, kind: String, p: Dictionary) -> void:
	if puppets.has(id) or pickups.has(id):
		return   # a SYNC answer and the normal SPAWN can both carry the same object
	stats.spawns += 1
	var n: Node2D = null
	match kind:
		"enemy":
			var e: Enemy = Enemy.new()
			e.type = int(p["t"])
			e.net_size = float(p["s"])
			e.h_dir = int(p.get("h", 1))
			if p.has("alt"):
				e.alt_pattern = p["alt"]
				e.alt_every = int(p.get("ae", 3))
			e.net_puppet = true
			e.net_id = id
			n = e
		"boss":
			var boss := Boss.new()
			boss.type = int(p["t"])
			boss.mini = bool(p.get("mi", false))
			boss.hp_scale = float(p.get("hs", 1.0))
			boss.name_override = str(p.get("nm", ""))
			boss.net_max_hp = int(p.get("mh", 0))
			boss.net_puppet = true
			boss.net_id = id
			boss.position = p["p"]
			world.add_child(boss)
			puppets[id] = boss
			_buf[id] = []
			boss.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)
			# Its parts are built from the type on both ends; give each the
			# server's id. Parts ride on the boss, so they get no position buffer.
			var part_ids: Dictionary = p.get("parts", {})
			for part in boss._parts:
				var pid: int = int(part_ids.get(String(part.part_id), 0))
				if pid > 0:
					part.net_id = pid
					puppets[pid] = part
					part.tree_exiting.connect(_forget.bind(pid), CONNECT_ONE_SHOT)
			return
		"pod":
			var pod := RevivePod.new()
			pod.for_peer = int(p.get("for", 0))
			pod.pilot_name = str(p.get("nm", ""))
			pod.net_puppet = true
			pod.net_id = id
			n = pod
		"starbase":
			var sb := Starbase.new()
			sb.net_puppet = true
			sb.net_id = id
			n = sb
		"mega":
			var m := MegaAsteroid.new()
			m.drift = p.get("d", Vector2.ZERO)
			m.net_puppet = true
			m.net_id = id
			n = m
		"rock":
			var r := Asteroid.new()
			r.size = int(p["z"])
			r.shower = bool(p.get("sh", false))
			r.drift = p.get("d", Vector2.ZERO)
			r.net_puppet = true
			r.net_id = id
			n = r
		"pickup":
			var k := Pickup.new()
			k.type = int(p["t"])
			k.money_value = int(p.get("m", 0))
			k.net_id = id
			k.position = p["p"]
			world.add_child(k)
			pickups[id] = k
			# A pickup that falls off the screen frees itself: forget it then,
			# so a late DESPAWN / GRANT never touches a freed object.
			k.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)
			return
	if n == null:
		return
	n.position = p["p"]
	world.add_child(n)
	puppets[id] = n
	_buf[id] = []
	n.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)


## An object left the scene (killed, despawned, or freed itself): drop every
## reference to it. References in these dictionaries are never typed when
## read back, because assigning a freed object to a typed variable is itself
## an error that would abort the caller.
func _forget(id: int) -> void:
	puppets.erase(id)
	pickups.erase(id)
	_buf.erase(id)


func _snap(t: float, ids: PackedInt32Array, xy: PackedFloat32Array, fl: PackedByteArray, hpb: PackedByteArray) -> void:
	stats.snaps += 1
	var sample: float = t - _now()
	# Fastest packet = least delay; let the estimate creep down slowly so a
	# clock that drifts is followed.
	_offset = sample if _offset == -INF else maxf(sample, _offset - 0.002)
	for i in ids.size():
		var id: int = ids[i]
		if _buf.has(id):
			var b: Array = _buf[id]
			b.append([t, Vector2(xy[i * 2], xy[i * 2 + 1])])
			if b.size() > 8:
				b.pop_front()
		var n = puppets.get(id)
		if n == null:
			continue
		# A boss part the server has broken becomes a wreck here too.
		if is_instance_valid(n) and "alive" in n and n.alive and (fl[i] & 2) == 2 and n.has_method("destroy"):
			n.destroy(true)
			continue
		if n != null and is_instance_valid(n) and i < hpb.size() and "max_hp" in n:
			var nhp: int = maxi(1, int(round(float(hpb[i]) / 255.0 * float(n.max_hp))))
			if nhp != n.hp:
				n.hp = nhp
				n.queue_redraw()
		if n != null and is_instance_valid(n) and "cloaked" in n:
			var c: bool = fl[i] & 1 == 1
			if n.cloaked != c:
				n.cloaked = c
				n.set_deferred("monitorable", not c)


func _process(delta: float) -> void:
	if not Net.is_client() or _offset == -INF:
		return
	var rt: float = render_time()
	for id in puppets.keys():
		var n = puppets[id]
		if not is_instance_valid(n):
			_forget(id)
			continue
		var b: Array = _buf.get(id, [])
		if b.is_empty():
			continue
		n.position = _sample(b, rt)
	while not _shots.is_empty() and float(_shots[0][0]) <= rt:
		_fire(_shots.pop_front()[1])
	_ship_t += delta
	if _ship_t >= SHIP_EVERY:
		_ship_t = 0.0
		var st: Dictionary = ship_state.call() if ship_state.is_valid() else _default_ship_state()
		if not st.is_empty():
			Net.send(0, [Net.M.SHIP, st], false)


static func _sample(b: Array, rt: float) -> Vector2:
	if rt <= float(b[0][0]):
		return b[0][1]
	for i in range(b.size() - 1):
		var a: Array = b[i]
		var c: Array = b[i + 1]
		if rt <= float(c[0]):
			var k: float = (rt - float(a[0])) / maxf(0.0001, float(c[0]) - float(a[0]))
			return (a[1] as Vector2).lerp(c[1], k)
	# Past the newest snapshot: extrapolate up to 0.1 s on the last velocity
	var last: Array = b[b.size() - 1]
	if b.size() >= 2:
		var prev: Array = b[b.size() - 2]
		var dt: float = float(last[0]) - float(prev[0])
		if dt > 0.0:
			var v: Vector2 = ((last[1] as Vector2) - (prev[1] as Vector2)) / dt
			return (last[1] as Vector2) + v * minf(rt - float(last[0]), 0.1)
	return last[1]


func _fire(p: Dictionary) -> void:
	stats.shots += 1
	var b: EnemyBullet = EnemyBullet.new()
	b.position = p["p"]
	b.direction = p["d"]
	b.style = int(p["st"])
	b.speed_override = float(p["v"])
	b.radius_override = float(p["r"])
	b.color_override = p["c"]
	b.damage = int(p["dm"])
	b.damage_scaled = true
	b.from_boss = bool(p.get("fb", false))
	if p.has("ba"):
		b.burst_after = float(p["ba"]); b.burst_count = int(p["bc"]); b.burst_damage = int(p["bd"]); b.burst_speed = float(p["bs"])
	if p.has("ht"):
		b.homing_turn_rate = float(p["ht"]); b.homing_secs = float(p["hs"])
	world.add_child(b)


func _beam(emitter_id: int, p: Dictionary) -> void:
	var em = puppets.get(emitter_id)
	if em == null or not is_instance_valid(em):
		return
	var beam: EnemyBeam = EnemyBeam.new()
	beam.emitter = em
	beam.offset = p["o"]
	beam.damage = int(p["dm"])
	beam.charge_secs = float(p["cs"])
	beam.fire_secs = float(p["fs"])
	beam.width = float(p["w"])
	beam.beam_color = p["c"]
	world.add_child(beam)
	if "_beam" in em:
		em._beam = beam


func _kill(id: int, killer: int) -> void:
	stats.kills += 1
	var mine: bool = killer == Net.my_peer
	if mine:
		stats.my_kills += 1
	var n = puppets.get(id)
	_forget(id)
	if n != null and is_instance_valid(n) and n.has_method("net_kill"):
		n.net_kill(mine)


func _despawn(id: int) -> void:
	for d in [puppets, pickups]:
		var n = d.get(id)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_forget(id)


func _grant(id: int, peer: int) -> void:
	stats.grants += 1
	var k = pickups.get(id)
	_forget(id)
	if k == null or not is_instance_valid(k):
		return
	if peer == Net.my_peer:
		stats.my_grants += 1
		var me: Node = get_tree().get_first_node_in_group(&"player")
		if me != null and me.has_method("_consume_pickup"):
			me._consume_pickup(k)   # frees it
			return
	k.queue_free()


## This phone's ship as the server and the partner need it. No ship in the
## scene (dead, between scenes) = not alive.
func _default_ship_state() -> Dictionary:
	var me = get_tree().get_first_node_in_group(&"player")
	if me == null or not is_instance_valid(me) or not (me is Node2D):
		return {"a": false}
	var st: Dictionary = {"p": me.global_position, "a": me.visible, "n": player_name}
	if "weapon_type" in me:
		st["w"] = int(me.weapon_type)
		if "weapon_levels" in me:
			st["l"] = int(me.weapon_levels.get(me.weapon_type, 1))
	if "_is_firing" in me:
		st["f"] = bool(me._is_firing) and not bool(me.get("firing_locked"))
	return st
