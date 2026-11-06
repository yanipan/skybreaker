extends Node
## Seeded wave randomness (1.0.1 challenges). EnemySpawner draws every wave
## decision (timing, sizes, types, positions, asteroids, bonus drops) from
## this generator, reseeded at the start of each sector from the run seed,
## so two players with the same run seed meet the same waves no matter how
## they play. Combat noise (enemy fire jitter, drops, effects) stays on the
## global RNG.

var _rng := RandomNumberGenerator.new()


static func sector_seed(run_seed: int, sector: int) -> int:
	return hash(str(run_seed) + ":" + str(sector)) & 0x7fffffff


func seed_sector(run_seed: int, sector: int) -> void:
	if run_seed <= 0:
		_rng.randomize()
	else:
		_rng.seed = sector_seed(run_seed, sector)


func randf() -> float:
	return _rng.randf()


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func randi() -> int:
	return int(_rng.randi() & 0x7fffffff)


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)
