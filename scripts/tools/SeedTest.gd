extends Node
## Headless: same run seed -> identical spawn log for a sector, even when the
## rest of the game burns global randomness differently; other seed -> differs.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _spawn_log(run_seed: int, sector: int, noise: int) -> Array:
	GameState.current_level = sector
	GameRng.seed_sector(run_seed, sector)
	var arena := Node2D.new()
	add_child(arena)
	var sp: Node = load("res://scripts/EnemySpawner.gd").new()
	arena.add_child(sp)
	var log: Array = []
	var seen := {}
	for f in 60 * 40:   # 40 s of game time at 60 fps
		for i in noise:
			randf()     # combat randomness elsewhere in the game
		sp._process(1.0 / 60.0)
		for c in arena.get_children():
			if c == sp or seen.has(c):
				continue
			seen[c] = true
			var kind: String = str(c.get("type")) if "type" in c else c.get_class()
			log.append("%d:%s:%d" % [f, kind, int(c.position.x)])
	arena.queue_free()
	return log

func _ready() -> void:
	var a: Array = _spawn_log(12345, 3, 0)
	var b: Array = _spawn_log(12345, 3, 7)
	var c: Array = _spawn_log(99999, 3, 0)
	print("spawns: a=%d b=%d c=%d" % [a.size(), b.size(), c.size()])
	_check(a.size() > 5, "spawner produced waves in 40 s (%d)" % a.size())
	_check(a == b, "same seed, different combat randomness -> identical waves")
	_check(a != c, "different seed -> different waves")
	var s1: Array = _spawn_log(12345, 4, 0)
	_check(s1 != a, "each sector has its own wave pattern")
	_check(GameRng.sector_seed(12345, 3) == GameRng.sector_seed(12345, 3), "sector seed is stable")
	print("SEED TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
