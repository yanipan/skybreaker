extends Node
## Co-op transport (docs/MULTIPLAYER_PLAN.md). Raw ENet over UDP: the server
## (headless ServerWorld) has a public address, phones connect to it, no NAT
## traversal. Messages are Arrays: [kind:int, ...fields], var_to_bytes encoded.
## Channel 0 reliable+ordered (spawns, shots, kills, flow, hits, claims),
## channel 1 unreliable (snapshots, ship states).
##
## Nothing here knows about the game: ServerWorld and NetClient read
## `message` and call send()/broadcast().

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected
signal disconnected
signal message(peer_id: int, msg: Array)   ## peer_id = 0 on the client side

enum Mode { OFF, SERVER, CLIENT }
const PROTO: int = 2
const DEFAULT_PORT: int = 24620
const CH_RELIABLE: int = 0
const CH_FAST: int = 1

## Message kinds. Server -> phone
enum M {
	HELLO,        ## [HELLO, proto, your_peer_id, seat, start_sector]
	SPAWN,        ## [SPAWN, id, kind, params:Dictionary]
	SNAP,         ## [SNAP, server_time, ids:PackedInt32Array, xy:PackedFloat32Array, flags:PackedByteArray (1 = cloaked), hp:PackedByteArray (0-255 of max)]
	SHOT,         ## [SHOT, params:Dictionary]  enemy bullet launch state
	BEAM,         ## [BEAM, emitter_id, params:Dictionary]
	KILL,         ## [KILL, id, killer_peer, reward]
	DESPAWN,      ## [DESPAWN, id]
	SECTOR,       ## [SECTOR, level, seed]
	SECTOR_CLEAR, ## [SECTOR_CLEAR, level]
	GRANT,        ## [GRANT, pickup_id, peer]
	PARTNER,      ## [PARTNER, peer, state:Dictionary]
	ALERT,        ## [ALERT, text]
	GAME_OVER,    ## [GAME_OVER, won]
	SHOP_OPEN,    ## [SHOP_OPEN, starbase_id, docker_peer]  world frozen, both phones shop
	SHOP_STATE,   ## [SHOP_STATE, peer, ready]
	SHOP_BOUGHT,  ## [SHOP_BOUGHT, peer, item]
	SHOP_TIMER,   ## [SHOP_TIMER, seconds]  the slower player is on the clock
	SHOP_CLOSE,   ## [SHOP_CLOSE]  everyone ready: GET READY countdown, then the world runs
	# Phone -> server
	JOIN = 50,    ## [JOIN, proto, name]
	SHIP,         ## [SHIP, state:Dictionary]  pos, alive, weapon, power, firing
	HITS,         ## [HITS, Dictionary id -> damage]
	CLAIM,        ## [CLAIM, pickup_id]
	DOWN,         ## [DOWN]  lost its last life
	READY,        ## [READY, level]  this phone has the sector scene loaded
	SYNC,         ## [SYNC]  resend a SPAWN for everything alive (scene reload, reconnect)
	DOCK,         ## [DOCK, starbase_id]  this ship touched the starbase
	SHOP_READY,   ## [SHOP_READY, bool]  left the shop / went back in
	SHOP_BUY,     ## [SHOP_BUY, item]  shown to the partner
}

var mode: Mode = Mode.OFF
var my_peer: int = 0          ## Client: id the server gave us
var seat: int = 0             ## Client: 0 or 1
## Client: true between ENet connect and disconnect.
var server_connected: bool = false
## Client: the co-op session object. It is a child of this autoload so it
## survives the scene reload at every sector change and every respawn; the
## current Main attaches itself as its world (NetClient.attach).
var client: Node = null


## Phone: start a co-op session against a room server.
func start_coop(address: String, port: int = DEFAULT_PORT, player_name: String = "Pilot") -> int:
	leave_coop(false)
	SaveSystem.begin_coop_hold()
	var c: Node = load("res://scripts/net/NetClient.gd").new()
	c.name = "Client"
	c.player_name = player_name
	add_child(c)
	client = c
	var err: int = connect_to(address, port)
	if err != OK:
		leave_coop(false)
	return err


## Phone: end the co-op session and put the solo run, money and lives back
## exactly as they were when it started (SaveSystem co-op hold).
func leave_coop(_restore_solo: bool = true) -> void:
	stop()
	if client != null and is_instance_valid(client):
		client.queue_free()
	client = null
	SaveSystem.end_coop_hold()

## Test hooks: simulated one-way latency (ms) and loss (0-1) on everything
## this process SENDS. Both ends set it -> RTT = 2x.
var fake_lag_ms: int = 0
var fake_loss: float = 0.0

## Traffic counters (bytes sent / received since start).
var bytes_out: int = 0
var bytes_in: int = 0

var _host: ENetConnection = null
var _server_peer: ENetPacketPeer = null          ## client side
var _peers: Dictionary = {}                      ## server side: id -> ENetPacketPeer
var _ids: Dictionary = {}                        ## server side: ENetPacketPeer -> id
var _next_id: int = 1
var _delayed: Array = []                         ## [due_ms, peer, channel, bytes, flags]
## Client: damage this phone's shots did to server entities, sent 20x/s.
var _hits: Dictionary = {}
var _hits_t: float = 0.0
const HITS_EVERY: float = 0.05


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func start_server(port: int = DEFAULT_PORT, max_peers: int = 2) -> int:
	stop()
	_host = ENetConnection.new()
	var err: int = _host.create_host_bound("*", port, max_peers, 2)
	if err != OK:
		_host = null
		return err
	mode = Mode.SERVER
	return OK


func connect_to(address: String, port: int = DEFAULT_PORT) -> int:
	stop()
	_host = ENetConnection.new()
	var err: int = _host.create_host(1, 2)
	if err != OK:
		_host = null
		return err
	_server_peer = _host.connect_to_host(address, port, 2)
	if _server_peer == null:
		_host = null
		return ERR_CANT_CONNECT
	mode = Mode.CLIENT
	return OK


func stop() -> void:
	if _host != null:
		for p in _peers.values():
			p.peer_disconnect_now()
		if _server_peer != null:
			_server_peer.peer_disconnect_now()
		_host.flush()
		_host.destroy()
	_host = null
	_server_peer = null
	_peers.clear()
	_ids.clear()
	_delayed.clear()
	_hits = {}
	mode = Mode.OFF
	my_peer = 0
	server_connected = false


func peers() -> Array:
	return _peers.keys()


## Server: one peer. Client: peer_id ignored (always the server).
func send(peer_id: int, msg: Array, reliable: bool = true) -> void:
	var p: ENetPacketPeer = _server_peer if mode == Mode.CLIENT else _peers.get(peer_id)
	if p == null:
		return
	_send_raw(p, msg, reliable)


func broadcast(msg: Array, reliable: bool = true, except_peer: int = 0) -> void:
	if mode != Mode.SERVER:
		return
	var bytes: PackedByteArray = var_to_bytes(msg)
	for id in _peers:
		if id != except_peer:
			_queue(_peers[id], bytes, reliable)


func _send_raw(p: ENetPacketPeer, msg: Array, reliable: bool) -> void:
	_queue(p, var_to_bytes(msg), reliable)


func _queue(p: ENetPacketPeer, bytes: PackedByteArray, reliable: bool) -> void:
	var ch: int = CH_RELIABLE if reliable else CH_FAST
	var flags: int = ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED
	if not reliable and fake_loss > 0.0 and randf() < fake_loss:
		return
	bytes_out += bytes.size()
	if fake_lag_ms > 0:
		_delayed.append([Time.get_ticks_msec() + fake_lag_ms, p, ch, bytes, flags])
	else:
		p.send(ch, bytes, flags)


## Client: a puppet (server-owned enemy / rock) was hit by our shots.
func report_hit(net_id: int, amount: int) -> void:
	if mode != Mode.CLIENT or net_id <= 0 or amount <= 0:
		return
	_hits[net_id] = int(_hits.get(net_id, 0)) + amount


func _process(delta: float) -> void:
	if _host == null:
		return
	if mode == Mode.CLIENT and not _hits.is_empty():
		_hits_t += delta
		if _hits_t >= HITS_EVERY:
			_hits_t = 0.0
			send(0, [M.HITS, _hits])
			_hits = {}
	if not _delayed.is_empty():
		var now: int = Time.get_ticks_msec()
		while not _delayed.is_empty() and int(_delayed[0][0]) <= now:
			var d: Array = _delayed.pop_front()
			var dp: ENetPacketPeer = d[1]
			if is_instance_valid(dp) and dp.get_state() == ENetPacketPeer.STATE_CONNECTED:
				dp.send(d[2], d[3], d[4])
	# Drain everything that arrived this frame
	for i in 200:
		var ev: Array = _host.service(0)
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE:
			break
		if t == ENetConnection.EVENT_ERROR:
			push_warning("Net: ENet error")
			break
		var peer: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				if mode == Mode.SERVER:
					var id: int = _next_id
					_next_id += 1
					_peers[id] = peer
					_ids[peer] = id
					peer.set_timeout(0, 10000, 20000)   # 20 s before a silent phone counts as gone
					peer_joined.emit(id)
				else:
					server_connected = true
					connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				if mode == Mode.SERVER:
					var gone: int = int(_ids.get(peer, 0))
					_ids.erase(peer)
					_peers.erase(gone)
					if gone != 0:
						peer_left.emit(gone)
				else:
					_server_peer = null
					server_connected = false
					disconnected.emit()
			ENetConnection.EVENT_RECEIVE:
				var pkt: PackedByteArray = peer.get_packet()
				bytes_in += pkt.size()
				var v: Variant = bytes_to_var(pkt)   # never objects: bytes_to_var refuses them
				if v is Array and not (v as Array).is_empty():
					var from: int = int(_ids.get(peer, 0)) if mode == Mode.SERVER else 0
					message.emit(from, v)
	_host.flush()
