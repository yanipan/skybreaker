extends Node
## Headless: the co-op rescue pod (scripts/net/RevivePod.gd).
## Run: godot --headless --path . res://scenes/tools/RevivePodTest.tscn

const DT: float = 0.016
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


func _pod(host: Node, at: Vector2, puppet: bool = false, pilot: String = "") -> RevivePod:
	var p := RevivePod.new()
	p.position = at
	p.net_puppet = puppet
	p.pilot_name = pilot
	host.add_child(p)
	p.set_process(false)
	return p


func _steps(p: RevivePod, n: int) -> void:
	for i in n:
		p._process(DT)


func _ship(host: Node, in_group: bool = true) -> Area2D:
	var s := Area2D.new()
	s.monitoring = false
	s.monitorable = false
	if in_group:
		s.add_to_group(&"player")
	host.add_child(s)
	return s


func _run() -> void:
	var host := Node2D.new()
	add_child(host)

	# 1. What it is
	var p1: Node = _pod(host, Vector2(400, 700))
	var circle_ok: bool = false
	for c in p1.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D and is_equal_approx(c.shape.radius, 46.0):
			circle_ok = true
	_check(p1 is Area2D and p1.is_in_group(&"revive_pods") and not p1.is_in_group(&"player") and not p1.is_in_group(&"enemies") and circle_ok,
			"1. an Area2D in group revive_pods only, circle shape radius 46")

	# 2. Label
	var named := _pod(host, Vector2(400, 700), false, "VIPER")
	var anon := _pod(host, Vector2(400, 700))
	_check((named.get_node("NameLabel") as Label).text == "RESCUE VIPER" and (anon.get_node("NameLabel") as Label).text == "RESCUE",
			"2. label reads RESCUE <name>, or RESCUE without a name")

	var vh: float = named._viewport_size.y
	var vw: float = named._viewport_size.x
	# 3-5. Server hover into the reachable band
	var top := _pod(host, Vector2(400, 50))
	_steps(top, 1200)
	_check(top.position.y >= vh * 0.35 - 1.0, "3. from the top it sinks into the band (y=%.0f, band from %.0f)" % [top.position.y, vh * 0.35])
	var low := _pod(host, Vector2(400, vh + 200.0))
	_steps(low, 2500)
	_check(low.position.y <= vh * 0.60 + 1.0, "4. from below it rises into the band (y=%.0f, band to %.0f)" % [low.position.y, vh * 0.60])
	var side := _pod(host, Vector2(-200, vh * 0.5))
	_steps(side, 800)
	_check(side.position.x >= 46.0 + 10.0 - 1.0 and side.position.x <= vw, "5. from off the left edge it comes on screen (x=%.0f)" % side.position.x)
	var mid := _pod(host, Vector2(400, vh * 0.5))
	_steps(mid, 300)
	_check(mid.position == Vector2(400, vh * 0.5), "5b. a pod already in the band stays put")

	# 6. Puppet never moves itself
	var pup := _pod(host, Vector2(400, 50), true)
	_steps(pup, 600)
	_check(pup.position == Vector2(400, 50), "6. a puppet pod does not move itself")

	# 7-13. Claiming
	Net.mode = Net.Mode.CLIENT
	Net.my_peer = 1
	var ship := _ship(host)
	var theirs := _pod(host, Vector2(400, 700), true)
	theirs.net_id = 7
	theirs.for_peer = 2
	theirs._on_area_entered(ship)
	_check(theirs.claims_sent == 1, "7. touching the partner's pod sends one claim")
	theirs._on_area_entered(ship)
	var after_second: int = theirs.claims_sent
	_steps(theirs, 70)
	theirs._on_area_entered(ship)
	_check(after_second == 1 and theirs.claims_sent == 2, "8. cooldown: no second claim at once, one more after 1.1 s (%d, %d)" % [after_second, theirs.claims_sent])
	var mine := _pod(host, Vector2(400, 700), true)
	mine.net_id = 8
	mine.for_peer = 1
	mine._on_area_entered(ship)
	_check(mine.claims_sent == 0, "9. nobody rescues themselves")
	var rock := _ship(host, false)
	var p10 := _pod(host, Vector2(400, 700), true)
	p10.net_id = 9
	p10.for_peer = 2
	p10._on_area_entered(rock)
	_check(p10.claims_sent == 0, "10. something that is not a ship does not claim")
	var local := _pod(host, Vector2(400, 700), true)
	local.for_peer = 2
	local._on_area_entered(ship)
	_check(local.claims_sent == 0, "11. a pod without a server id is never claimed")
	var done := _pod(host, Vector2(400, 700), true)
	done.net_id = 10
	done.for_peer = 2
	done.claimed = true
	done._on_area_entered(ship)
	_check(done.claims_sent == 0, "12. an already claimed pod is left alone")
	Net.mode = Net.Mode.OFF
	var off := _pod(host, Vector2(400, 700), true)
	off.net_id = 11
	off.for_peer = 2
	off._on_area_entered(ship)
	_check(off.claims_sent == 0, "13. outside co-op nothing is sent")

	Net.mode = Net.Mode.OFF
	Net.my_peer = 0
	print("RevivePodTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
