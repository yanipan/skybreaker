extends Node
## CO-OP ROOM SERVER (docs/MULTIPLAYER_PLAN.md). One headless Godot process =
## one room. Runs the real EnemySpawner and world objects; phones see puppets.
##   godot --headless --path . res://scenes/net/ServerWorld.tscn -- --port=24620 --sector=1 --players=2 --seed=123
## Owns: spawns, enemy fire, enemy HP (from phone hit reports), kills and who
## scored them, pickups (first claim wins), sector flow, game over.

const FIELD := Vector2i(816, 1800)   ## Fixed play field (phones: same x, may show less height)
const SNAP_EVERY: float = 0.05       ## 20 Hz snapshots
const CLEAR_PAUSE: float = 3.0       ## Seconds between sectors
const READY_TIMEOUT: float = 15.0    ## Longest wait for a phone to load the next sector
const SHOP_RESUME_SECS: float = 3.4  ## The phones' GET READY 3-2-1 (3.2 s) plus a breath

var port: int = Net.DEFAULT_PORT
var start_sector: int = 1
var expected: int = 2
var run_seed: int = 0
var max_sectors: int = GameState.MAX_LEVEL   ## Test hook: stop after N sectors
var duration_mul: float = 1.0                ## Test hook: shorter sectors
## Seconds the slower player gets once the other has left the shop (0 = no
## limit: friends). Matched games set it (plan: 30).
var shop_timer: float = 0.0
## Room lifetime before the run starts (the lobby service starts one process
## per room): give up when nobody is connected for EMPTY_SECS, or when the
## room has not filled within lobby_timeout (a friend code lives 10 minutes).
var room_code: String = ""
var lobby_timeout: float = 600.0
const EMPTY_SECS: float = 45.0
## AI partners (--bots=N): pilots that live in this process and take a seat
## once the first human has joined. peer id -> AiPilot.
var bot_count: int = 0
var bots: Dictionary = {}
const BOT_PEER: int = 900
## A phone whose link died keeps its seat this long (--reconnect_secs).
var reconnect_secs: float = 60.0
const PENDING_SECS: float = 6.0     ## A new connection must say who it is within this
var _pending: Dictionary = {}       ## connection id -> seconds waiting for its JOIN (no seat yet)
var _lobby_age: float = 0.0
var _empty_for: float = 0.0
var _go_sent: bool = false

var world: Node2D
var spawner: EnemySpawner = null
var ships: Dictionary = {}        ## peer -> Area2D stand-in (group "player")
var seats: Dictionary = {}        ## peer -> {seat, name, alive, out}
var entities: Dictionary = {}     ## net id -> Node
var _next_id: int = 1
var _snap_t: float = 0.0
var _clear_t: float = -1.0
var _started: bool = false
var _over: bool = false
var _sectors_done: int = 0
var _clock: float = 0.0
var _ready_wait: float = 0.0
var _last_shot_t: float = -1.0   ## Server clock of the newest enemy shot (diagnostics)
# Shared shop: the world is frozen from DOCK until everyone has left.
var _shop_open: bool = false
var _shop_base = null
var _shop_ready: Dictionary = {}     ## peer -> bool
var _shop_deadline: float = -1.0
var _shop_resume_t: float = -1.0
## Stats for tests / logs
var stats := {"spawns": 0, "shots": 0, "kills": 0, "grants": 0, "hits": 0, "sectors": 0, "shops": 0, "resumes": 0, "downs": 0, "revives": 0}


func _ready() -> void:
	_parse_args()
	get_window().content_scale_size = FIELD
	get_window().size = FIELD
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	world.child_entered_tree.connect(_on_child)
	Net.peer_joined.connect(_on_join)
	Net.peer_left.connect(_on_left)
	Net.message.connect(_on_msg)
	var err: int = Net.start_server(port, expected + 2)   # spare slots: a reconnect can arrive before the dead link is noticed
	print("ServerWorld: listening on ", port, " err=", err, " expecting ", expected, " seed=", run_seed)
	if err != OK:
		get_tree().quit(2)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"port": port = int(kv[1])
			"sector": start_sector = int(kv[1])
			"players": expected = int(kv[1])
			"seed": run_seed = int(kv[1])
			"sectors": max_sectors = int(kv[1])
			"duration_mul": duration_mul = float(kv[1])
			"shop_timer": shop_timer = float(kv[1])
			"room": room_code = kv[1]
			"lobby_timeout": lobby_timeout = float(kv[1])
			"reconnect_secs": reconnect_secs = float(kv[1])
			"bots": bot_count = int(kv[1])
			"lag": Net.fake_lag_ms = int(kv[1])
			"loss": Net.fake_loss = float(kv[1])
	if run_seed == 0:
		run_seed = randi_range(1, 2147483646)


# --- Peers ---

func _on_join(peer: int) -> void:
	if _started or seats.size() >= expected:
		# The run is on (only a reconnect can take a seat) or the room is full:
		# no seat until its JOIN says who it is.
		_pending[peer] = 0.0
		return
	# Lowest free seat (someone may have left the waiting room).
	var taken: Array = []
	for q in seats:
		taken.append(int(seats[q]["seat"]))
	var seat: int = 0
	while seat in taken:
		seat += 1
	# out = gone for good (left, disconnected); down = no lives left, can be
	# rescued through its pod and returns anyway at the next sector.
	seats[peer] = {"seat": seat, "name": "", "alive": true, "out": false, "down": false, "away": false, "away_t": 0.0,
			"token": randi_range(1, 2147483646)}
	var s := Area2D.new()
	s.name = "Ship%d" % peer
	s.monitoring = false
	s.monitorable = false
	s.position = Vector2(FIELD.x * (0.35 + 0.3 * seat), FIELD.y * 0.8)
	s.add_to_group(&"player")
	s.set_meta("peer", peer)
	add_child(s)   # NOT under world: never replicated
	ships[peer] = s
	Net.send(peer, [Net.M.HELLO, Net.PROTO, peer, seat, start_sector, seats[peer]["token"]])
	print("ServerWorld: peer ", peer, " joined as seat ", seat)


## An AI partner takes the next free seat (called when the first human joins).
func _add_bot() -> void:
	var peer: int = BOT_PEER + bots.size()
	var taken: Array = []
	for q in seats:
		taken.append(int(seats[q]["seat"]))
	var seat: int = 0
	while seat in taken:
		seat += 1
	var ai := AiPilot.new()
	ai.name = "Ai%d" % peer
	add_child(ai)
	ai.setup(self, peer, run_seed + peer)
	seats[peer] = {"seat": seat, "name": ai.pilot_name, "alive": true, "out": false, "down": false, "away": false, "away_t": 0.0,
			"token": 0, "ai": true, "joined": true, "ready": true}
	var s := Area2D.new()
	s.name = "Ship%d" % peer
	s.monitoring = false
	s.monitorable = false
	s.position = Vector2(FIELD.x * (0.35 + 0.3 * seat), FIELD.y * 0.64)
	s.add_to_group(&"player")
	s.set_meta("peer", peer)
	add_child(s)
	ships[peer] = s
	ai.pos = s.position
	bots[peer] = ai
	print("ServerWorld: AI partner ", ai.pilot_name, " took seat ", seat, " (", "labelled" if ai.labelled else "disguised", ")")


## What kind of partner this room has, for the phone's telemetry only:
## 0 = human, 1 = labelled AI, 2 = disguised AI.
func partner_kind() -> int:
	for p in bots:
		return 1 if bots[p].labelled else 2
	return 0


## Money is shared: whoever grabs a money pickup, every other pilot gets the
## same amount (each pilot pays for their own upgrades, and with one wallet's
## worth of drops between two ships both would fall behind the sector).
func share_money(p: Pickup, from_peer: int) -> void:
	if p.type != Pickup.Type.MONEY or int(p.money_value) <= 0:
		return
	Net.broadcast([Net.M.SHARE, int(p.money_value), from_peer], true, from_peer)
	for b in bots:
		if b != from_peer:
			bots[b].money += int(p.money_value)


## Ships flying right now (not down, not gone): sets the co-op HP scaling
## for whatever spawns next.
func _count_flying() -> void:
	var n: int = 0
	for p in seats:
		if not seats[p]["out"] and not seats[p]["down"] and not seats[p]["away"]:
			n += 1
	GameState.coop_players = maxi(1, n)


func humans_shop_ready() -> bool:
	for p in _shop_ready:
		if not bots.has(p) and not _shop_ready[p]:
			return false
	return true


func bot_shop_ready(peer: int) -> void:
	if _shop_open and _shop_ready.has(peer):
		_shop_ready[peer] = true
		Net.broadcast([Net.M.SHOP_STATE, peer, true])
		_check_shop_done()


func _on_left(peer: int, deliberate: bool = false) -> void:
	if _pending.erase(peer) or not seats.has(peer):
		return
	if ships.has(peer):
		ships[peer].remove_from_group(&"player")
	seats[peer]["alive"] = false
	# The shop never waits for a phone that is not there.
	_shop_ready.erase(peer)
	if _started and not _over and not deliberate and not seats[peer]["out"] and reconnect_secs > 0.0:
		# The link died (tunnel, app in the background): keep the seat, the
		# run goes on, the phone may come back (_resume) within reconnect_secs.
		seats[peer]["away"] = true
		seats[peer]["away_t"] = 0.0
		Net.broadcast([Net.M.LINK, peer, 0])
		print("ServerWorld: peer ", peer, " lost its link, seat kept for ", reconnect_secs, " s")
		_check_shop_done()
		return
	print("ServerWorld: peer ", peer, " left")
	seats[peer]["out"] = true
	seats[peer]["away"] = false
	if _started and not _over:
		Net.broadcast([Net.M.LINK, peer, 2])
	_check_shop_done()
	_check_over()
	if not _started:
		# Still in the waiting room: the seat is simply free again.
		seats.erase(peer)
		if ships.has(peer):
			ships[peer].queue_free()
			ships.erase(peer)
		_go_sent = false
		_send_lobby()


## A phone is back on a new connection, already rebound to its old id: tell
## it where the room is now and resend the world.
func _resume(peer: int) -> void:
	var s: Dictionary = seats[peer]
	s["away"] = false
	s["away_t"] = 0.0
	stats.resumes += 1
	Net.send(peer, [Net.M.HELLO, Net.PROTO, peer, int(s["seat"]), start_sector, s["token"]])
	Net.send(peer, [Net.M.RESUME, GameState.current_level, _clear_t >= 0.0, _shop_open, bool(s["down"])])
	_send_sync(peer)
	if _shop_open and _shop_base != null and is_instance_valid(_shop_base):
		_shop_ready[peer] = false
		Net.send(peer, [Net.M.SHOP_OPEN, int(_shop_base.get_meta("nid")), 0])
		Net.broadcast([Net.M.SHOP_STATE, peer, false], true, peer)
	Net.broadcast([Net.M.LINK, peer, 1], true, peer)
	print("ServerWorld: peer ", peer, " resumed its seat")


## Reconnect windows and connections that never said who they are.
func _tick_links(delta: float) -> void:
	for c in _pending.keys():
		_pending[c] = float(_pending[c]) + delta
		if float(_pending[c]) >= PENDING_SECS:
			_pending.erase(c)
			Net.kick(c)
	if not _started or _over:
		return
	for p in seats:
		if seats[p]["away"]:
			seats[p]["away_t"] = float(seats[p]["away_t"]) + delta
			if float(seats[p]["away_t"]) >= reconnect_secs:
				seats[p]["away"] = false
				seats[p]["out"] = true
				Net.broadcast([Net.M.LINK, p, 2])
				print("ServerWorld: peer ", p, " did not come back, gone for good")
				_check_over()
				if _over:
					return


func _on_msg(peer: int, msg: Array) -> void:
	if _pending.has(peer):
		if int(msg[0]) != Net.M.JOIN:
			return
		var old: int = int(msg[3]) if msg.size() > 4 else 0
		if int(msg[1]) == Net.PROTO and _started and not _over and seats.has(old) and not seats[old]["out"] \
				and int(msg[4]) == int(seats[old]["token"]):
			_pending.erase(peer)
			Net.rebind(peer, old)
			_resume(old)
		else:
			print("ServerWorld: connection ", peer, " refused (no seat for it)")
			Net.send(peer, [Net.M.REFUSED, "version" if int(msg[1]) != Net.PROTO else "gone"])
			Net.kick(peer)
		return
	if not seats.has(peer):
		return
	match int(msg[0]):
		Net.M.JOIN:
			if int(msg[1]) != Net.PROTO:
				print("ServerWorld: peer ", peer, " wrong protocol ", msg[1])
				Net.send(peer, [Net.M.REFUSED, "version"])
				Net.kick(peer)
				return
			seats[peer]["name"] = str(msg[2]).substr(0, 24) if msg.size() > 2 else ""
			seats[peer]["joined"] = true
			while bots.size() < bot_count and seats.size() < expected:
				_add_bot()
			_send_lobby()
			if not _started and not _go_sent and _joined() >= expected:
				_go_sent = true
				Net.broadcast([Net.M.GO, start_sector, run_seed, partner_kind()])
				print("ServerWorld: room full, GO")
		Net.M.READY:
			# The phone has the sector scene up. The first sector starts when
			# every expected seat is ready; later sectors in _process.
			if seats.has(peer):
				seats[peer]["ready"] = true
			if not _started and _joined() >= expected and _all_ready():
				_started = true
				_begin_sector(start_sector)
		Net.M.SYNC:
			_send_sync(peer)
		Net.M.SHIP:
			var st: Dictionary = msg[1]
			var ship: Area2D = ships.get(peer)
			if ship != null:
				ship.position = st.get("p", ship.position)
				var alive: bool = bool(st.get("a", true))
				if alive != ship.is_in_group(&"player"):
					if alive: ship.add_to_group(&"player")
					else: ship.remove_from_group(&"player")
				seats[peer]["alive"] = alive
			if st.has("sc"):
				seats[peer]["score"] = maxi(0, int(st["sc"]))   # for the end-of-run screen
			Net.broadcast([Net.M.PARTNER, peer, st], false, peer)
		Net.M.HITS:
			var d: Dictionary = msg[1]
			for id in d:
				var n = entities.get(int(id))
				if n != null and is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_method("take_damage"):
					n.set_meta("last_hitter", peer)
					# A hit on a part can be what kills the boss: credit it there too.
					if "boss" in n and n.boss != null and is_instance_valid(n.boss):
						n.boss.set_meta("last_hitter", peer)
					n.take_damage(int(d[id]))
					stats.hits += 1
		Net.M.CLAIM:
			var pid: int = int(msg[1])
			var p = entities.get(pid)
			if p != null and is_instance_valid(p) and p is RevivePod:
				_claim_pod(p, peer)
			elif p != null and is_instance_valid(p) and p is Pickup and not p.has_meta("granted"):
				p.set_meta("granted", peer)
				Net.broadcast([Net.M.GRANT, pid, peer])
				stats.grants += 1
				share_money(p, peer)
				p.queue_free()
		Net.M.DOWN:
			_go_down(peer, msg[1] if msg.size() > 1 and msg[1] is Vector2 else Vector2(FIELD.x * 0.5, FIELD.y * 0.5))
		Net.M.DOCK:
			_dock(peer, int(msg[1]))
		Net.M.SHOP_READY:
			if _shop_open and _shop_ready.has(peer):
				var rdy: bool = bool(msg[1])
				_shop_ready[peer] = rdy
				Net.broadcast([Net.M.SHOP_STATE, peer, rdy])
				if rdy and shop_timer > 0.0 and _shop_deadline < 0.0:
					_shop_deadline = shop_timer
					Net.broadcast([Net.M.SHOP_TIMER, shop_timer])
				_check_shop_done()
		Net.M.SHOP_BUY:
			if _shop_open:
				Net.broadcast([Net.M.SHOP_BOUGHT, peer, str(msg[1])], true, peer)


## Tell everyone in the waiting room who is here.
func _send_lobby() -> void:
	if _started:
		return
	var players: Array = []
	for p in seats:
		if seats[p].get("joined", false):
			players.append([p, int(seats[p]["seat"]), str(seats[p]["name"])])
	Net.broadcast([Net.M.LOBBY, players, expected])
	print("ServerWorld: lobby ", players.size(), "/", expected)


## Every seat still in the run has its scene loaded.
func _all_ready() -> bool:
	for p in seats:
		if not seats[p]["out"] and not seats[p]["away"] and not seats[p].has("ai") and not seats[p].get("ready", false):
			return false   # a phone that lost its link holds nobody up; it catches up when it is back
	return true


## One SPAWN per living object, to one phone (it reloaded its scene for a
## respawn or a new sector, or it reconnected), plus the sector it is in.
func _send_sync(peer: int) -> void:
	if not _started or _clear_t >= 0.0:
		return   # between sectors: the old world is about to be wiped, send nothing
	for id in entities.keys():
		var n = entities[id]
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n.is_node_ready() and not (n is BossPart):
			_send_spawn(n, peer)   # parts travel inside their boss's SPAWN


func _joined() -> int:
	var n: int = 0
	for p in seats:
		if seats[p].get("joined", false):
			n += 1
	return n


# --- Down and rescue ---

## A ship lost its last life. It is DOWN, not out: a rescue pod appears where
## it fell, the partner can fly through it, and the ship returns anyway at
## the next sector. Everyone down (or gone) at the same time = run over.
func _go_down(peer: int, at: Vector2) -> void:
	if not seats.has(peer) or seats[peer]["down"] or seats[peer]["out"] or not _started or _over:
		return
	seats[peer]["down"] = true
	seats[peer]["alive"] = false
	if ships.has(peer):
		ships[peer].remove_from_group(&"player")
	stats.downs += 1
	print("ServerWorld: peer ", peer, " is down")
	if _all_down():
		_game_over(false)
		return
	var pod := RevivePod.new()
	pod.for_peer = peer
	pod.pilot_name = str(seats[peer]["name"])
	pod.position = Vector2(clampf(at.x, 60.0, FIELD.x - 60.0), clampf(at.y, 100.0, FIELD.y - 100.0))
	world.add_child(pod)


func _claim_pod(pod: RevivePod, by: int) -> void:
	var who: int = pod.for_peer
	if pod.claimed or by == who or not seats.has(by) or seats[by]["down"] or seats[by]["out"]:
		return
	if not seats.has(who) or not seats[who]["down"]:
		return
	pod.claimed = true
	seats[who]["down"] = false
	stats.revives += 1
	Net.broadcast([Net.M.REVIVE, who, by])
	print("ServerWorld: peer ", who, " rescued by peer ", by)
	pod.queue_free()


func _all_down() -> bool:
	if not bots.is_empty():
		# An AI partner never carries a run on its own: no human left = over.
		var human_in: bool = false
		for p in seats:
			if not seats[p].has("ai") and not seats[p]["out"]:
				human_in = true
		if not human_in:
			return true
	for p in seats:
		if not seats[p]["out"] and not seats[p]["down"]:
			return false
	return true


# --- Shared shop ---

## A ship touched the starbase: freeze the world and open the shop for
## everyone still in the run. One visit per station.
func _dock(peer: int, base_id: int) -> void:
	if _shop_open or _shop_resume_t >= 0.0 or _clear_t >= 0.0 or not _started or _over:
		return
	var sb = entities.get(base_id)
	if sb == null or not is_instance_valid(sb) or not (sb is Starbase) or sb._used:
		return
	sb._used = true
	sb._shop_open = true
	_shop_base = sb
	_shop_open = true
	_shop_deadline = -1.0
	_shop_ready = {}
	for p in seats:
		if not seats[p]["out"]:
			_shop_ready[p] = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	stats.shops += 1
	Net.broadcast([Net.M.SHOP_OPEN, base_id, peer])
	for b in bots:
		bots[b].shop_opened()
	print("ServerWorld: shop open (docked by peer ", peer, "), world frozen")


## Everyone still in the run has left the shop: tell the phones to count
## down, and let the world run again when their countdown ends.
func _check_shop_done() -> void:
	if not _shop_open:
		return
	for p in _shop_ready:
		if not _shop_ready[p]:
			return
	_shop_open = false
	_shop_deadline = -1.0
	_shop_resume_t = SHOP_RESUME_SECS
	Net.broadcast([Net.M.SHOP_CLOSE])
	print("ServerWorld: shop closed, resuming in ", SHOP_RESUME_SECS, " s")


func _process_shop(delta: float) -> void:
	if _shop_open:
		for b in bots:
			bots[b].shop_tick(delta)
			if not _shop_open:
				break
	if _shop_open and _shop_deadline >= 0.0:
		_shop_deadline -= delta
		if _shop_deadline <= 0.0:
			for p in _shop_ready:
				_shop_ready[p] = true   # time is up for the slower player
			_check_shop_done()
	if _shop_resume_t >= 0.0:
		_shop_resume_t -= delta
		if _shop_resume_t < 0.0:
			world.process_mode = Node.PROCESS_MODE_INHERIT
			if _shop_base != null and is_instance_valid(_shop_base):
				_shop_base._on_shop_closed()   # farewell, then it frees itself -> DESPAWN
			_shop_base = null
			print("ServerWorld: world running again")


# --- Sectors ---

func _begin_sector(level: int) -> void:
	_clear_world()
	_count_flying()
	GameState.current_level = level
	GameRng.seed_sector(run_seed, level)
	spawner = EnemySpawner.new()
	spawner.name = "Spawner"
	world.add_child(spawner)
	_clock = 0.0
	Net.broadcast([Net.M.SECTOR, level, run_seed])
	print("ServerWorld: sector ", level, " start")


func _clear_world() -> void:
	for id in entities.keys():
		var n = entities[id]
		if is_instance_valid(n):
			n.set_meta("silent", true)
	for c in world.get_children():
		c.queue_free()
	entities.clear()
	spawner = null


func _process(delta: float) -> void:
	if not _over:
		_tick_links(delta)
	if not _started and not _over:
		# Waiting room: do not live for ever.
		_lobby_age += delta
		_empty_for = 0.0 if not Net.peers().is_empty() else _empty_for + delta
		if _empty_for >= EMPTY_SECS or _lobby_age >= lobby_timeout:
			print("ServerWorld: room closed before the run (empty ", snappedf(_empty_for, 1.0), " s, age ", snappedf(_lobby_age, 1.0), " s)")
			_over = true
			Net.stop()
			get_tree().quit(0)
		return
	if not _started or _over:
		return
	if _shop_open or _shop_resume_t >= 0.0:
		_process_shop(delta)
		return   # frozen: no clock, no sector timer, no snapshots
	_clock += delta
	_count_flying()
	for b in bots:
		bots[b].tick(delta)
		if _over:
			return
	if spawner != null and is_instance_valid(spawner):
		var dur: float = spawner.get_level_duration() * duration_mul
		# Same rule as Main._check_level_complete: every boss dead, then the
		# timer; the finale ends the moment its last boss dies.
		var finale_kill: bool = spawner.ends_on_boss() and spawner.bosses_spawned() > 0
		if spawner.boss_sequence_done() and (finale_kill or spawner.get_mission_time() >= dur) and _clear_t < 0.0:
			_clear_t = CLEAR_PAUSE
			stats.sectors += 1
			_sectors_done += 1
			for p in seats:
				seats[p]["ready"] = false   # each phone reloads its scene for the next sector
			_ready_wait = 0.0
			Net.broadcast([Net.M.SECTOR_CLEAR, GameState.current_level])
			print("ServerWorld: sector ", GameState.current_level, " clear")
	if _clear_t >= 0.0:
		_clear_t -= delta
		if _clear_t < 0.0:
			if GameState.current_level >= GameState.MAX_LEVEL or _sectors_done >= max_sectors:
				_game_over(GameState.current_level >= GameState.MAX_LEVEL)
				return
			# Next sector once every phone still in the run has loaded it, or
			# after READY_TIMEOUT (a slow or silent phone does not hold the room).
			_ready_wait += delta
			if not _all_ready() and _ready_wait < READY_TIMEOUT:
				_clear_t = 0.0
				return
			_revive_all()
			_begin_sector(GameState.current_level + 1)
	_snap_t += delta
	if _snap_t >= SNAP_EVERY:
		_snap_t = fmod(_snap_t, SNAP_EVERY)   # keep the remainder: a true 20 Hz, not every 4th frame
		_send_snapshot()


func _revive_all() -> void:
	# Own lives: a downed (not out) ship comes back at the next sector. Phones
	# track their own lives; the server only needs to know who is still in.
	for p in seats:
		if not seats[p]["out"]:
			seats[p]["alive"] = true
			seats[p]["down"] = false   # a downed ship flies again in the new sector


func _check_over() -> void:
	if not _started or _over:
		return
	if _all_down():
		_game_over(false)


func _game_over(won: bool) -> void:
	_over = true
	var players: Array = []
	for p in seats:
		if seats[p].get("joined", false):
			players.append([p, str(seats[p]["name"]), int(seats[p].get("score", 0))])
	Net.broadcast([Net.M.GAME_OVER, won, GameState.current_level, players])
	for b in bots:
		print("ServerWorld: AI ", bots[b].pilot_name, " score ", bots[b].score, " level ", bots[b].level, " money ", bots[b].money, " lives ", bots[b].lives, " ", bots[b].stats)
	print("ServerWorld: game over won=", won, " stats=", stats, " out=", Net.bytes_out, " in=", Net.bytes_in, " clock=", snappedf(_clock, 0.01), " last_shot=", snappedf(_last_shot_t, 0.01))
	await get_tree().create_timer(1.0).timeout
	Net.stop()
	get_tree().quit(0)


# --- Replication ---

func _on_child(n: Node) -> void:
	if n is Enemy or n is Asteroid or n is Pickup or n is Boss or n is Starbase or n is RevivePod:
		var id: int = _next_id
		_next_id += 1
		n.set_meta("nid", id)
		entities[id] = n
		n.ready.connect(_send_spawn.bind(n), CONNECT_ONE_SHOT)
		n.tree_exiting.connect(_on_gone.bind(n), CONNECT_ONE_SHOT)
	elif n is EnemyBullet:
		if not n.has_meta("net_local"):
			n.ready.connect(_send_shot.bind(n), CONNECT_ONE_SHOT)
	elif n is EnemyBeam:
		n.ready.connect(_send_beam.bind(n), CONNECT_ONE_SHOT)


func _send_spawn(n: Node, only_peer: int = 0) -> void:
	var id: int = int(n.get_meta("nid"))
	var kind: String = ""
	var p: Dictionary = {"p": n.position}
	if n is Enemy:
		kind = "enemy"
		p["t"] = n.type
		p["s"] = n.enemy_size
		p["h"] = n.h_dir
		if n.alt_pattern != &"":
			p["alt"] = n.alt_pattern
			p["ae"] = n.alt_every
	elif n is Boss:
		kind = "boss"
		p["t"] = n.type
		p["mi"] = n.mini
		p["hs"] = n.hp_scale
		p["nm"] = n.name_override
		p["mh"] = n.max_hp
		p["parts"] = _register_parts(n)
	elif n is MegaAsteroid:
		kind = "mega"
		p["d"] = n.drift
		p["hp"] = n.max_hp
	elif n is Asteroid:
		kind = "rock"
		p["z"] = n.size
		p["sh"] = n.shower
		p["d"] = n.drift
	elif n is Pickup:
		kind = "pickup"
		p["t"] = n.type
		p["m"] = n.money_value
	elif n is Starbase:
		kind = "starbase"
	elif n is RevivePod:
		kind = "pod"
		p["for"] = n.for_peer
		p["nm"] = n.pilot_name
	if only_peer != 0:
		Net.send(only_peer, [Net.M.SPAWN, id, kind, p])
		return
	stats.spawns += 1
	Net.broadcast([Net.M.SPAWN, id, kind, p])


## A boss's breakable parts get ids of their own, so a phone can report hits
## on a plate or a turret and see its HP and its wreck. Both ends build the
## same parts from the boss type, matched by part_id. Returns {part_id: id}.
func _register_parts(boss: Boss) -> Dictionary:
	var out: Dictionary = {}
	for part in boss._parts:
		if not is_instance_valid(part):
			continue
		if not part.has_meta("nid"):
			part.set_meta("nid", _next_id)
			entities[_next_id] = part
			_next_id += 1
		out[String(part.part_id)] = int(part.get_meta("nid"))
	return out


func _send_shot(b: EnemyBullet) -> void:
	stats.shots += 1
	_last_shot_t = _clock
	var p := {"p": b.global_position, "d": b.direction, "v": b.speed, "dm": b.damage, "st": b.style,
			"r": b.bullet_radius, "c": b.bullet_color, "t": _clock}
	if b.from_boss: p["fb"] = true
	if b.burst_after > 0.0:
		p["ba"] = b.burst_after; p["bc"] = b.burst_count; p["bd"] = b.burst_damage; p["bs"] = b.burst_speed
	if b.homing_turn_rate > 0.0:
		p["ht"] = b.homing_turn_rate; p["hs"] = b.homing_secs
	Net.broadcast([Net.M.SHOT, p])


func _send_beam(beam: EnemyBeam) -> void:
	var em: Node = beam.emitter
	if em == null or not em.has_meta("nid"):
		return
	Net.broadcast([Net.M.BEAM, int(em.get_meta("nid")), {"o": beam.offset, "dm": beam.damage,
			"cs": beam.charge_secs, "fs": beam.fire_secs, "w": beam.width, "c": beam.beam_color}])


func _on_gone(n: Node) -> void:
	var id: int = int(n.get_meta("nid", 0))
	entities.erase(id)
	if n is Boss:
		for part in n._parts:
			if is_instance_valid(part) and part.has_meta("nid"):
				entities.erase(int(part.get_meta("nid")))
	if n.has_meta("silent") or n.has_meta("granted"):
		return
	var dead: bool = ("hp" in n) and int(n.hp) <= 0
	if dead:
		stats.kills += 1
		var killer: int = int(n.get_meta("last_hitter", 0))
		var reward: int = int(n.reward) if "reward" in n else 0
		if bots.has(killer):
			bots[killer].on_kill(reward)
		Net.broadcast([Net.M.KILL, id, killer, reward])
	else:
		Net.broadcast([Net.M.DESPAWN, id])


func _send_snapshot() -> void:
	var ids := PackedInt32Array()
	var xy := PackedFloat32Array()
	var fl := PackedByteArray()
	var hpb := PackedByteArray()
	for id in entities:
		var n = entities[id]
		if not is_instance_valid(n) or n is Pickup:
			continue   # pickups fly locally on each phone
		ids.append(id)
		xy.append(n.position.x)
		xy.append(n.position.y)
		# bit 0 = cloaked (SHADE), bit 1 = broken (a boss part that is now a wreck)
		fl.append((1 if ("cloaked" in n and n.cloaked) else 0) | (2 if ("alive" in n and not n.alive) else 0))
		var frac: float = clampf(float(n.hp) / float(maxi(1, n.max_hp)), 0.0, 1.0) if ("hp" in n and "max_hp" in n) else 1.0
		hpb.append(int(round(frac * 255.0)))
	Net.broadcast([Net.M.SNAP, _clock, ids, xy, fl, hpb], false)
