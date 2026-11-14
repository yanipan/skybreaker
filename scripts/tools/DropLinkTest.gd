extends Node
## Regression for the iPhone build 27 crash: SIGSEGV in ENetConnection::service
## after NetClient's resume-from-background called Net.drop_link(). Godot's
## service() frees an inactive peer's list node and then reads it, so a peer cut
## with peer_disconnect_now() must never stay in a live host. Real sockets on
## localhost. The Mac allocator rarely trips the freed read, so the host check
## below is what fails on the old code.
## Mutation proof: put `_host.destroy()` / `_host = null` in drop_link back out.

var fails: int = 0
var passes: int = 0
var _srv: ENetConnection


func _ok(c: bool, what: String) -> void:
	if c:
		passes += 1
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


func _pump(frames: int, until: Callable = Callable()) -> void:
	for i in frames:
		if _srv != null:
			for k in 20:
				var ev: Array = _srv.service(0)
				if ev[0] == ENetConnection.EVENT_NONE:
					break
		await get_tree().process_frame
		if until.is_valid() and until.call():
			return


func _ready() -> void:
	var port: int = 47000 + randi() % 2000
	_srv = ENetConnection.new()
	_ok(_srv.create_host_bound("127.0.0.1", port, 4, 2) == OK, "test server listening")
	var lost: Array = [0]
	Net.disconnected.connect(func() -> void: lost[0] += 1)

	_ok(Net.connect_to("127.0.0.1", port) == OK, "client host created")
	await _pump(300, func() -> bool: return Net.server_connected)
	_ok(Net.server_connected, "client connected")

	Net.drop_link()   # what NetClient does on resume after >= 3 s in the background
	_ok(lost[0] == 1, "drop_link emits disconnected once")
	_ok(not Net.server_connected, "link marked down")
	# The real guard: no live host may keep a peer cut with _now (Godot
	# enet_connection.cpp service(): erase(E) then E->next() = use after free;
	# the Mac allocator rarely trips it, the iPhone did).
	_ok(Net._host == null, "drop_link destroyed the host (no cut peer left in a live list)")
	await _pump(60)   # the old code crashed inside Net._process -> service() here
	_ok(true, "60 frames after drop_link without a crash")

	_ok(Net.connect_to("127.0.0.1", port) == OK, "reconnect builds a fresh host")
	await _pump(300, func() -> bool: return Net.server_connected)
	_ok(Net.server_connected, "reconnected")

	# Twice more, back to back, like a phone flicking between apps
	for r in 2:
		Net.drop_link()
		await _pump(10)
		Net.connect_to("127.0.0.1", port)
		await _pump(300, func() -> bool: return Net.server_connected)
	_ok(Net.server_connected and lost[0] == 3, "repeated drop + reconnect ok")

	Net.stop()
	await _pump(5)
	_srv.destroy()
	_srv = null
	print("DropLinkTest: ", passes, " passed, ", fails, " failed")
	get_tree().quit(1 if fails > 0 else 0)
