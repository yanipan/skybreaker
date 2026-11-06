extends Node
## Headless: every shield level blocks one more hit. Each hit spends one
## full pip; the hull is only hit once the pips are gone; a partly
## recharged pip does not block.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _hit(p: Node) -> void:
	p._i_frame_timer = 0.0
	p._take_damage(1)

func _ready() -> void:
	var p: Node = load("res://scripts/Player.gd").new()
	p.position = Vector2(400, 1000)
	add_child(p)
	await get_tree().process_frame
	for lvl in [1, 3, 5]:
		p.max_shield = lvl
		p.shield = float(lvl)
		p.hp = p.max_hp
		var hp0: int = p.hp
		for i in lvl:
			_hit(p)
		_check(p.hp == hp0, "level %d shield blocks %d hits" % [lvl, lvl])
		_hit(p)
		_check(p.hp < hp0, "level %d: hit %d reaches the hull" % [lvl, lvl + 1])
	p.max_shield = 3
	p.shield = 0.6
	p.hp = p.max_hp
	_hit(p)
	_check(p.hp < p.max_hp, "a partly recharged pip does not block")
	print("ShieldPipTest done, fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
