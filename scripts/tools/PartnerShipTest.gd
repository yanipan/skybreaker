extends Node
## Headless: PartnerShip is cosmetic — no collision, no groups, interpolated
## pose, capped visual fire, banking sprites, name label.
## Run: godot --headless --path . res://scenes/tools/PartnerShipTest.tscn

const TEX_NEUTRAL: Texture2D = preload("res://assets/sprites/playership.png")
const TEX_BANK_RIGHT: Texture2D = preload("res://assets/sprites/playerbankingright.png")
const DT := 0.016

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


func _count_shots(host: Node) -> int:
	var n: int = 0
	for c in host.get_children():
		if c is PartnerShip.PartnerShot:
			n += 1
	return n


func _free_shots(host: Node) -> void:
	for c in host.get_children():
		if c is PartnerShip.PartnerShot:
			c.free()


func _first_shot(host: Node) -> PartnerShip.PartnerShot:
	for c in host.get_children():
		if c is PartnerShip.PartnerShot:
			return c
	return null


func _step(ship: PartnerShip, n: int) -> void:
	for i in n:
		ship._process(DT)


func _silence_shots(host: Node) -> void:
	for c in host.get_children():
		if c is PartnerShip.PartnerShot:
			c.set_process(false)


func _run() -> void:
	var host := Node2D.new()
	add_child(host)
	var ship_node: Node = PartnerShip.new()
	host.add_child(ship_node)
	ship_node.set_process(false)

	# 1. Fresh PartnerShip is a Node2D, not an Area2D, in none of the combat groups
	# Typed as Node so `is Area2D` is a runtime check (GDScript rejects it on PartnerShip).
	_check(ship_node is Node2D, "fresh PartnerShip is a Node2D")
	_check(not (ship_node is Area2D), "fresh PartnerShip is not an Area2D")
	_check(
		not ship_node.is_in_group("player")
		and not ship_node.is_in_group("enemies")
		and not ship_node.is_in_group("player_bullets"),
		"fresh PartnerShip is in none of player/enemies/player_bullets"
	)
	var ship: PartnerShip = ship_node

	# 2. First apply_state with "p" snaps position
	ship.apply_state({"p": Vector2(300, 900)})
	_check(ship.position == Vector2(300, 900), "first p snaps position to (300, 900)")

	# 3. Later p only sets target; lerp moves toward it
	ship.apply_state({"p": Vector2(400, 900)})
	_check(is_equal_approx(ship.position.x, 300.0), "later p leaves position.x at 300 right after")
	ship._process(DT)
	_check(ship.position.x > 300.0 and ship.position.x < 400.0, "after one step x is between 300 and 400 (x=%.2f)" % ship.position.x)
	_step(ship, 60)
	_check(absf(ship.position.x - 400.0) < 1.0, "after 60 more steps x is within 1 of 400 (x=%.2f)" % ship.position.x)

	# 4. Partial state keeps previous weapon/power/firing
	ship.apply_state({"w": 2, "l": 7, "f": true})
	ship.apply_state({"p": Vector2(410, 900)})
	_check(
		ship.weapon == 2 and ship.power == 7 and ship.firing == true,
		"partial p keeps weapon=2 power=7 firing=true"
	)

	# 5. Phaser, power 1, firing, alive: 62 steps -> 6..8 shots
	ship.apply_state({"w": 0, "l": 1, "f": true, "a": true})
	_free_shots(host)
	_step(ship, 62)
	_silence_shots(host)
	var n5: int = _count_shots(host)
	_check(n5 >= 6 and n5 <= 8, "phaser power 1: 62 steps create 6-8 shots (%d)" % n5)

	# 6. Phaser, power 20: 62 steps -> 9..11 shots (MAX_VISUAL_RATE cap)
	ship.apply_state({"w": 0, "l": 20, "f": true, "a": true})
	_free_shots(host)
	_step(ship, 62)
	_silence_shots(host)
	var n6: int = _count_shots(host)
	_check(n6 >= 9 and n6 <= 11, "phaser power 20: 62 steps create 9-11 shots, the cap (%d)" % n6)

	# 7. A shot is a Node2D, not Area2D, in no combat group, parented to host, moves up
	var shot_node: Node = _first_shot(host)
	_check(shot_node != null, "a shot exists to inspect")
	if shot_node != null:
		shot_node.set_process(false)
		_check(shot_node is Node2D, "shot is a Node2D")
		_check(not (shot_node is Area2D), "shot is not an Area2D")
		_check(
			not shot_node.is_in_group("player")
			and not shot_node.is_in_group("enemies")
			and not shot_node.is_in_group("player_bullets"),
			"shot is in none of player/enemies/player_bullets"
		)
		_check(shot_node.get_parent() == host, "shot parent is the host, not the ship")
		var shot_2d: Node2D = shot_node
		var y_before: float = shot_2d.position.y
		shot_2d._process(DT)
		_check(shot_2d.position.y < y_before, "after one step the shot's y is smaller than before")
	else:
		_check(false, "shot is a Node2D")
		_check(false, "shot is not an Area2D")
		_check(false, "shot is in none of player/enemies/player_bullets")
		_check(false, "shot parent is the host, not the ship")
		_check(false, "after one step the shot's y is smaller than before")

	# 8. A shot at y = -70 is queued for deletion after one _process
	var shot: PartnerShip.PartnerShot = shot_node as PartnerShip.PartnerShot
	if shot == null:
		shot = _first_shot(host)
	_check(shot != null, "a shot exists to delete")
	if shot != null:
		shot.set_process(false)
		shot.position.y = -70.0
		shot._process(DT)
		_check(shot.is_queued_for_deletion(), "shot at y=-70 is queued for deletion after one step")
	else:
		_check(false, "shot at y=-70 is queued for deletion after one step")

	# 9. Dead: invisible and no new shots even while firing; revived: visible
	ship.apply_state({"a": false})
	_check(ship.visible == false, "alive=false makes the ship invisible")
	var n9_before: int = _count_shots(host)
	_step(ship, 62)
	_silence_shots(host)
	var n9_after: int = _count_shots(host)
	_check(n9_after == n9_before, "dead ship creates 0 new shots even though firing is true (%d new)" % (n9_after - n9_before))
	ship.apply_state({"a": true})
	_check(ship.visible == true, "alive=true makes the ship visible again")

	# 10. Missile (weapon 2): 62 steps -> 2..4 shots
	ship.apply_state({"w": 2, "l": 1, "f": true, "a": true})
	_free_shots(host)
	_step(ship, 62)
	_silence_shots(host)
	var n10: int = _count_shots(host)
	_check(n10 >= 2 and n10 <= 4, "missile: 62 steps create 2-4 shots (%d)" % n10)

	# 11. Beam (weapon 1): 62 steps -> 0 shots
	ship.apply_state({"w": 1, "l": 1, "f": true, "a": true})
	_free_shots(host)
	_step(ship, 62)
	_silence_shots(host)
	var n11: int = _count_shots(host)
	_check(n11 == 0, "beam: 62 steps create 0 shots (%d)" % n11)

	# 12. Not firing for 200 steps, then firing: first step creates at most 1 shot
	ship.apply_state({"w": 0, "l": 1, "f": false, "a": true})
	_free_shots(host)
	_step(ship, 200)
	var n12_before: int = _count_shots(host)
	ship.apply_state({"f": true})
	ship._process(DT)
	_silence_shots(host)
	var n12_after: int = _count_shots(host)
	_check(n12_after - n12_before <= 1, "after 200 idle steps the first firing step creates at most 1 shot (%d)" % (n12_after - n12_before))

	# 13. Banking: far right target -> right-bank texture; parked 120 steps -> neutral
	var spr: Sprite2D = ship.get_node("Sprite")
	ship.apply_state({"p": Vector2(ship.position.x + 400.0, 900.0)})
	ship._process(DT)
	_check(spr.texture == TEX_BANK_RIGHT, "far right target: Sprite uses the right-bank texture")
	ship.apply_state({"p": ship.position})
	_step(ship, 120)
	_check(spr.texture == TEX_NEUTRAL, "target equal to position for 120 steps: Sprite uses the neutral texture")

	# 14. Name label follows "n" and hides when empty
	ship.apply_state({"n": "VIPER"})
	var nl: Label = ship.get_node("NameLabel")
	_check(nl.text == "VIPER" and nl.visible, "NameLabel.text is VIPER and visible")
	ship.apply_state({"n": ""})
	_check(not nl.visible, "empty name hides NameLabel")

	# 15. (added in review) States stop arriving: firing stops after STALE_HOLD_FIRE,
	# the ship is hidden after STALE_HIDE, and the next state brings it back.
	ship.apply_state({"w": 0, "l": 1, "f": true, "a": true, "p": ship.position})
	_free_shots(host)
	_step(ship, 62)        # ~1.0 s of silence: fired for at most the first second
	_silence_shots(host)
	var n15a: int = _count_shots(host)
	_check(n15a >= 5 and n15a <= 8, "silent partner fires during the first second only (%d)" % n15a)
	_free_shots(host)
	_step(ship, 125)       # 2 more seconds of silence
	_silence_shots(host)
	_check(_count_shots(host) == 0, "silent for more than 1 s: no more shots (%d)" % _count_shots(host))
	_check(ship.visible, "silent for 3 s: still shown")
	_step(ship, 190)       # past 5 s in total
	_check(not ship.visible, "silent for more than 5 s: hidden")
	ship.apply_state({"p": ship.position})
	_check(ship.visible, "the next state shows the ship again")
	ship._process(DT)
	_silence_shots(host)
	_check(_count_shots(host) == 1, "and it fires again at once (%d)" % _count_shots(host))
	# 16. (added in review) One very long frame never releases a clump of shots.
	ship.apply_state({"w": 0, "l": 20, "f": true, "a": true})
	_free_shots(host)
	ship._process(0.9)     # a 0.9 s hitch: without the cap this is 9 shots at one spot
	_silence_shots(host)
	_check(_count_shots(host) <= PartnerShip.MAX_SHOTS_PER_FRAME, "a 0.9 s hitch releases at most %d shots (%d)" % [PartnerShip.MAX_SHOTS_PER_FRAME, _count_shots(host)])
	print("PartnerShipTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
