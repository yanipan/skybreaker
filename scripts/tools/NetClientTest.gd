extends Node
## Headless, no network: feeds NetClient the server's messages directly.
## Covers the race that froze a bot on 11/11: an object frees itself locally
## and the server's DESPAWN / KILL / GRANT / SNAP for it arrives afterwards.
## Run: godot --headless --path . res://scenes/tools/NetClientTest.tscn
## (the runner must also see no "SCRIPT ERROR" in the output)

var _fails: int = 0
var _passes: int = 0

func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("PASS  ", what)
	else:
		_fails += 1
		print("FAIL  ", what)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.current_level = 13
	Net.mode = Net.Mode.CLIENT
	Net.my_peer = 1
	var world := Node2D.new()
	add_child(world)
	var nc := NetClient.new()
	nc.world = world
	nc.ship_state = func() -> Dictionary: return {}
	add_child(nc)
	nc.set_process(false)

	var M := Net.M
	nc._on_msg(0, [M.SPAWN, 1, "enemy", {"p": Vector2(100, 100), "t": Enemy.Type.TANK, "s": 120.0, "h": 1}])
	nc._on_msg(0, [M.SPAWN, 2, "rock", {"p": Vector2(300, 100), "z": Asteroid.Size.MEDIUM, "sh": false, "d": Vector2(0, 100)}])
	nc._on_msg(0, [M.SPAWN, 3, "pickup", {"p": Vector2(500, 100), "t": Pickup.Type.MONEY, "m": 10}])
	nc._on_msg(0, [M.SPAWN, 4, "mega", {"p": Vector2(400, 300), "d": Vector2(0, 46), "hp": 500}])
	_check(nc.puppets.size() == 3 and nc.pickups.size() == 1, "spawns build 3 puppets + 1 pickup")
	var enemy = nc.puppets[1]
	var rock = nc.puppets[2]
	_check(enemy.net_puppet and enemy.enemy_size == 120.0, "enemy puppet uses the server's size roll")
	_check(rock.net_puppet and nc.puppets[4] is MegaAsteroid, "rock and mega are puppets")

	# Puppets never move or free themselves
	rock.position = Vector2(300, 99999)
	rock._process(0.1)
	_check(is_instance_valid(rock) and not rock.is_queued_for_deletion(), "an off-screen puppet rock waits for the server")
	_check(rock.position.y == 99999.0, "puppet rock is not moved by its own drift")
	var ey: float = enemy.position.y
	enemy._process(0.1)
	_check(enemy.position.y == ey, "puppet enemy does not move itself")
	var bullets_before: int = 0
	for c in world.get_children():
		if c is EnemyBullet: bullets_before += 1
	enemy._fire_timer = 0.0
	enemy._process(0.5)
	var bullets_after: int = 0
	for c in world.get_children():
		if c is EnemyBullet: bullets_after += 1
	_check(bullets_after == bullets_before, "puppet enemy fires nothing on its own")

	# Hits are reported, not applied
	var hp0: int = enemy.hp
	enemy.take_damage(7)
	enemy.take_damage(5)
	_check(enemy.hp == hp0 and int(Net._hits.get(1, 0)) == 12, "hits on a puppet are batched for the server (12), hp untouched")

	# Snapshots -> interpolation
	var t0: float = 100.0
	nc._on_msg(0, [M.SNAP, t0, PackedInt32Array([1, 2, 4]), PackedFloat32Array([100, 100, 300, 100, 400, 300]), PackedByteArray([0, 0, 0]), PackedByteArray([255, 255, 128])])
	nc._on_msg(0, [M.SNAP, t0 + 0.05, PackedInt32Array([1, 2, 4]), PackedFloat32Array([100, 110, 300, 105, 400, 302]), PackedByteArray([0, 0, 0]), PackedByteArray([128, 255, 128])])
	_check(absf(float(enemy.hp) - float(enemy.max_hp) * 0.5) <= 1.0, "puppet hp follows the server (half)")
	var mega = nc.puppets[4]
	_check(absf(float(mega.hp) - float(mega.max_hp) * 0.5) <= 2.0, "mega hp bar follows the server")
	nc._offset = (t0 + 0.05) - nc._now() + NetClient.INTERP - 0.025   # draw halfway between the two snaps
	nc._process(0.016)
	_check(absf(enemy.position.y - 105.0) < 1.5, "puppet drawn between snapshots (y=%.1f)" % enemy.position.y)

	# THE RACE: the object is gone locally, then the server talks about it
	rock.free()
	_check(not nc.puppets.has(2) and not nc._buf.has(2), "a puppet that left the scene is forgotten at once")
	nc._on_msg(0, [M.SNAP, t0 + 0.10, PackedInt32Array([1, 2, 4]), PackedFloat32Array([100, 120, 300, 110, 400, 304]), PackedByteArray([0, 0, 0]), PackedByteArray([128, 255, 128])])
	nc._on_msg(0, [M.DESPAWN, 2])
	nc._on_msg(0, [M.KILL, 2, 1, 50])
	var pk = nc.pickups[3]
	pk.free()
	_check(not nc.pickups.has(3), "a pickup that fell off the screen is forgotten at once")
	nc._on_msg(0, [M.GRANT, 3, 1])
	nc._on_msg(0, [M.DESPAWN, 3])
	# Stale entry injected by hand (belt and braces): the loop must skip it and go on
	var ghost := Node2D.new()
	nc.puppets[99] = ghost
	nc._buf[99] = [[t0, Vector2.ZERO]]
	ghost.free()
	nc._offset = (t0 + 0.10) - nc._now() + NetClient.INTERP
	nc._process(0.016)
	_check(not nc.puppets.has(99), "a stale reference is dropped by the update loop")
	_check(absf(enemy.position.y - 120.0) < 1.5, "the update loop still runs after all that (enemy y=%.1f)" % enemy.position.y)

	# Shots wait for the render clock, then fly locally
	var shot := {"p": Vector2(100, 160), "d": Vector2.DOWN, "v": 400.0, "dm": 5, "st": EnemyBullet.Style.DART, "r": 7.0, "c": Color(1, 0.5, 0.2), "t": t0 + 0.30}
	nc._on_msg(0, [M.SHOT, shot])
	nc._process(0.016)
	var flown: int = 0
	for c in world.get_children():
		if c is EnemyBullet: flown += 1
	_check(flown == bullets_after, "a shot from the server's future is held back")
	nc._offset = (t0 + 0.31) - nc._now() + NetClient.INTERP
	nc._process(0.016)
	var shot_node: EnemyBullet = null
	for c in world.get_children():
		if c is EnemyBullet: shot_node = c
	_check(shot_node != null and absf(shot_node.speed - 400.0) < 0.5 and shot_node.damage == 5, "then launched with the server's speed and damage")

	# Kills: score only for the phone that made the kill
	var score0: int = GameState.run_score
	nc._on_msg(0, [M.SPAWN, 5, "enemy", {"p": Vector2(200, 200), "t": Enemy.Type.GRUNT, "s": 60.0, "h": 1}])
	nc._on_msg(0, [M.SPAWN, 6, "enemy", {"p": Vector2(250, 200), "t": Enemy.Type.GRUNT, "s": 60.0, "h": 1}])
	nc._on_msg(0, [M.KILL, 5, 2, 30])
	_check(GameState.run_score == score0, "partner's kill: no score for me")
	nc._on_msg(0, [M.KILL, 6, 1, 30])
	_check(GameState.run_score > score0, "my kill: score added")
	_check(not nc.puppets.has(5) and not nc.puppets.has(6), "killed puppets are gone from the table")

	# Sector change wipes everything
	nc._on_msg(0, [M.SECTOR, 14, 77])
	await get_tree().process_frame
	await get_tree().process_frame
	_check(nc.puppets.is_empty() and nc.pickups.is_empty() and GameState.current_level == 14, "new sector clears the old world")

	Net.mode = Net.Mode.OFF
	print("NetClientTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
