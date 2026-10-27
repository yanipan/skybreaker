extends Node
class_name EnemySpawner
## Spawns waves of enemies based on the current level's data from Levels.gd.
## Each wave is built procedurally: pick a random size, then sample enemies
## from the level's enemy pool and spread them across the formation.

const EnemyScript := preload("res://scripts/Enemy.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const BossScript := preload("res://scripts/Boss.gd")
const StarbaseScript := preload("res://scripts/Starbase.gd")
const AsteroidScript := preload("res://scripts/Asteroid.gd")

@export var first_spawn_delay: float = 3.0   ## Pre-roll between waves at level start
@export var x_jitter_range: float = 0.12     ## Random horizontal shift applied to whole formations
## Average seconds between asteroid spawns. Each asteroid is rolled
## independently of waves so the rocks add ambient pressure.
@export var asteroid_interval_min: float = 4.5
@export var asteroid_interval_max: float = 9.0

var _viewport_size: Vector2
var _timer: float = 0.0
var _mission_time: float = 0.0
var _level_data: Dictionary = {}
## Mutable copy of the level's spawn_interval — Levels.get_level may return
## a read-only dictionary, so we can't write back into _level_data.
var _spawn_interval: float = 3.0

# Guarantees at least one POWER pickup per stage. Picks a random moment in
# the middle 60% of the level and force-drops one from the top of the screen
# if it hasn't fired yet.
var _guaranteed_power_time: float = -1.0
var _guaranteed_power_dropped: bool = false
var _guaranteed_power_enabled: bool = false
# Weapon-change drop — appears every 3 levels at a random moment, so the player
# routinely sees their other weapon options without being overwhelmed.
var _weapon_change_time: float = -1.0
var _weapon_change_dropped: bool = false
var _weapon_change_enabled: bool = false

# LIFE pickup — very rare. Each stage rolls once; on success it drops at a
# random time in the middle 60% of the level. Skipped on stages 1-2 so the
# first encounter feels exceptional, and never on a boss stage (already busy).
var _life_time: float = -1.0
var _life_dropped: bool = false
var _life_enabled: bool = false

# SIDEKICK pickup — even rarer than LIFE. Same per-stage roll pattern.
var _sidekick_time: float = -1.0
var _sidekick_dropped: bool = false
var _sidekick_enabled: bool = false

# Boss — spawned partway into a level if Levels.gd marks it as has_boss.
# Regular enemies keep spawning before, during, and after — the player still
# needs steady fodder for pickups while fighting the boss.
var _boss_spawn_time: float = -1.0
var _boss_spawned: bool = false
var _boss_enabled: bool = false
var _boss_type_idx: int = 0

# Asteroid drift — independent timer. Rocks start showing up at sector 2 so
# the very first stage stays a clean introduction. Cadence tightens slightly
# in late sectors via the timer roll below.
var _asteroid_timer: float = 0.0
var _asteroids_enabled: bool = false

# Starbase — friendly shop. Random chance every level to roll one in mid-stage,
# but never on a boss stage (the player is busy enough). Skipping early levels
# so the first encounter is exciting rather than guaranteed.
var _starbase_time: float = -1.0
var _starbase_spawned: bool = false
var _starbase_enabled: bool = false


func _ready() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	_timer = first_spawn_delay
	_level_data = Levels.get_level(GameState.current_level)
	_spawn_interval = float(_level_data.get("spawn_interval", 3.0))
	# Guaranteed power-up drop only every other stage now (was every stage —
	# combined with enemy drops + shop it was overwhelming the upgrade pacing).
	var dur: float = float(_level_data.get("duration", 60.0))
	_guaranteed_power_enabled = (GameState.current_level % 2 == 0)
	if _guaranteed_power_enabled:
		_guaranteed_power_time = randf_range(dur * 0.20, dur * 0.80)
	# Weapon-change drop every 3rd stage so the player still sees their other
	# weapon options without flooding the field with goodies.
	_weapon_change_enabled = (GameState.current_level % 3 == 1)
	if _weapon_change_enabled:
		_weapon_change_time = randf_range(dur * 0.30, dur * 0.70)
	# Rare LIFE drop — ~12% chance per stage from level 3 onward, never on a
	# boss stage. Tied to a single random moment in the middle of the stage.
	var has_boss_now: bool = bool(_level_data.get("has_boss", false))
	if not has_boss_now and GameState.current_level >= 3 and randf() < 0.12:
		_life_enabled = true
		_life_time = randf_range(dur * 0.30, dur * 0.70)
	# SIDEKICK drop — was ~8% from level 4 onward, bumped to ~22% from level 3
	# onward. Sidekick is the more interesting friendly buff so we want the
	# player to actually see it land in most runs (not once a session).
	if not has_boss_now and GameState.current_level >= 3 and randf() < 0.22:
		_sidekick_enabled = true
		_sidekick_time = randf_range(dur * 0.30, dur * 0.70)
	# Boss setup — appears about 35% of the way in so the player has time to warm
	# up and the regular spawn cadence is established before the encounter.
	_boss_enabled = bool(_level_data.get("has_boss", false))
	if _boss_enabled:
		_boss_type_idx = int(_level_data.get("boss_type", 0))
		_boss_spawn_time = dur * 0.35
	# Starbase — normally never on boss stages, ~45% chance otherwise from
	# level 2 onward. BUT we always guarantee a shop on the stage immediately
	# preceding a boss so the player can stock up. This guarantee even
	# overrides the "no shop on boss stages" rule for back-to-back boss
	# stages (sectors 18→19, 19→20) — otherwise the player would face two
	# bosses in a row with zero re-stock.
	var next_is_boss: bool = bool(Levels.get_level(GameState.current_level + 1).get("has_boss", false))
	if next_is_boss:
		_starbase_enabled = true
		_starbase_time = randf_range(dur * 0.30, dur * 0.65)
	elif not _boss_enabled and GameState.current_level >= 2:
		if randf() < 0.45:
			_starbase_enabled = true
			_starbase_time = randf_range(dur * 0.30, dur * 0.65)
	# Asteroids — enabled from sector 2 onward, never on boss stages (the
	# screen is busy enough). First rock takes a beat to show up.
	_asteroids_enabled = (GameState.current_level >= 2 and not _boss_enabled)
	if _asteroids_enabled:
		_asteroid_timer = randf_range(6.0, 12.0)
	print("EnemySpawner _ready: level=", GameState.current_level,
			" name=", _level_data.get("name", "?"),
			" pool=", _level_data.get("enemy_pool", []))


func _process(delta: float) -> void:
	_mission_time += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = _spawn_interval
		_spawn_wave()
	if _guaranteed_power_enabled and not _guaranteed_power_dropped and _mission_time >= _guaranteed_power_time:
		_drop_guaranteed_power()
	if _weapon_change_enabled and not _weapon_change_dropped and _mission_time >= _weapon_change_time:
		_drop_weapon_change()
	if _life_enabled and not _life_dropped and _mission_time >= _life_time:
		_drop_life()
	if _sidekick_enabled and not _sidekick_dropped and _mission_time >= _sidekick_time:
		_drop_sidekick()
	if _boss_enabled and not _boss_spawned and _mission_time >= _boss_spawn_time:
		_spawn_boss()
	if _starbase_enabled and not _starbase_spawned and _mission_time >= _starbase_time:
		_spawn_starbase()
	if _asteroids_enabled:
		_asteroid_timer -= delta
		if _asteroid_timer <= 0.0:
			_spawn_asteroid()
			# Late sectors roll a tighter cadence so the rocks become a real threat.
			var lvl_t: float = clamp(float(GameState.current_level - 1) / 19.0, 0.0, 1.0)
			var lo: float = lerp(asteroid_interval_min, asteroid_interval_min * 0.55, lvl_t)
			var hi: float = lerp(asteroid_interval_max, asteroid_interval_max * 0.55, lvl_t)
			_asteroid_timer = randf_range(lo, hi)


## Force-drops a POWER pickup from the top of the screen so every level
## delivers at least one weapon upgrade chance even if RNG is unkind. Picks
## a random weapon-specific variant so the slots level over time even on a
## starvation-RNG run.
func _drop_guaranteed_power() -> void:
	_guaranteed_power_dropped = true
	var pickup: Pickup = PickupScript.new()
	var v: int = randi() % 3
	var pwr: int = Pickup.Type.POWER_PHASER
	if v == 1:
		pwr = Pickup.Type.POWER_BEAM
	elif v == 2:
		pwr = Pickup.Type.POWER_MISSILE
	pickup.type = pwr
	var x: float = randf_range(_viewport_size.x * 0.20, _viewport_size.x * 0.80)
	pickup.position = Vector2(x, -40.0)
	get_parent().add_child(pickup)
	if OS.is_debug_build():
		print("Guaranteed POWER drop (variant ", pwr, ") at x=", x)


## WEAPON_CHANGE pickup is gone — the player switches weapons manually with
## the middle mouse button now. This stub stays so the timer hook in
## _process can still call it without crashing; it just no-ops.
func _drop_weapon_change() -> void:
	_weapon_change_dropped = true


## Force-drops a rare LIFE pickup. Doesn't always trigger — gated by per-stage
## chance in _ready, so the player encounters one only every several stages.	
func _drop_life() -> void:
	_life_dropped = true
	var pickup: Pickup = PickupScript.new()
	pickup.type = Pickup.Type.LIFE
	var x: float = randf_range(_viewport_size.x * 0.25, _viewport_size.x * 0.75)
	pickup.position = Vector2(x, -40.0)
	get_parent().add_child(pickup)
	if OS.is_debug_build():
		print("Rare LIFE drop at x=", x)


## Force-drops a rare SIDEKICK pickup from the top of the screen.
func _drop_sidekick() -> void:
	_sidekick_dropped = true
	var pickup: Pickup = PickupScript.new()
	pickup.type = Pickup.Type.SIDEKICK
	var x: float = randf_range(_viewport_size.x * 0.25, _viewport_size.x * 0.75)
	pickup.position = Vector2(x, -40.0)
	get_parent().add_child(pickup)
	if OS.is_debug_build():
		print("Rare SIDEKICK drop at x=", x)


## Spawns a friendly starbase that drifts down from above.
func _spawn_starbase() -> void:
	_starbase_spawned = true
	var sb: Starbase = StarbaseScript.new()
	sb.position = Vector2(randf_range(_viewport_size.x * 0.30, _viewport_size.x * 0.70), -160.0)
	get_parent().add_child(sb)
	print("STARBASE spawned at x=", sb.position.x)


## Spawns the level's boss centered above the playfield. Regular waves continue
## firing in the background — the boss is layered on top, not a replacement —
## but their cadence is throttled by 25% so the player isn't getting buried by
## fodder while trying to focus on the boss pattern.
func _spawn_boss() -> void:
	_boss_spawned = true
	var boss: Boss = BossScript.new()
	boss.type = clamp(_boss_type_idx, 0, 5)
	boss.position = Vector2(_viewport_size.x * 0.5, -120.0)
	get_parent().add_child(boss)
	# 25% slower wave cadence for the rest of the stage. We stretch the
	# baseline interval AND the currently-running countdown so the slowdown
	# is felt immediately, not only after the next spawn.
	_spawn_interval = _spawn_interval * 1.3333
	_timer = _timer * 1.3333
	print("BOSS spawned: type=", _boss_type_idx, " — wave cadence x1.33")


## Spawns a single drifting asteroid. Size weights shift toward bigger rocks
## in late sectors so the player isn't just shrugging off small chunks at L20.
func _spawn_asteroid() -> void:
	var roll: float = randf()
	var size_pick: int = AsteroidScript.Size.SMALL
	var lvl_t: float = clamp(float(GameState.current_level - 1) / 19.0, 0.0, 1.0)
	# Small/medium/large weights drift from 60/30/10 → 25/45/30 across the run.
	var p_small: float = lerp(0.60, 0.25, lvl_t)
	var p_med: float = lerp(0.90, 0.70, lvl_t)
	if roll < p_small:
		size_pick = AsteroidScript.Size.SMALL
	elif roll < p_med:
		size_pick = AsteroidScript.Size.MEDIUM
	else:
		size_pick = AsteroidScript.Size.LARGE
	var rock: Node = AsteroidScript.new()
	rock.size = size_pick
	# Spawn somewhere along the top edge with a touch of horizontal slack.
	var x: float = randf_range(-40.0, _viewport_size.x + 40.0)
	rock.position = Vector2(x, -120.0)
	# Drift mostly down, occasionally angled across the screen.
	var vy: float = randf_range(110.0, 200.0)
	var vx: float = randf_range(-60.0, 60.0)
	# If spawned off-edge, push it inward so it actually crosses the playfield
	if x < 0:
		vx = abs(vx) + 40.0
	elif x > _viewport_size.x:
		vx = -abs(vx) - 40.0
	rock.drift = Vector2(vx, vy)
	get_parent().add_child(rock)


## Builds a procedural wave from the current level's enemy pool.
## Wave size scales with the level; types are sampled randomly from the pool.
func _spawn_wave() -> void:
	var pool: Array = _level_data.get("enemy_pool", [Enemy.Type.GRUNT])
	if pool.is_empty():
		return
	var size_min: int = int(_level_data.get("wave_size_min", 1))
	var size_max: int = int(_level_data.get("wave_size_max", 3))
	var wave_size: int = randi_range(size_min, size_max)
	var x_jitter: float = randf_range(-x_jitter_range, x_jitter_range)

	for i in wave_size:
		var t: int = pool[randi() % pool.size()]
		# Evenly distribute across the screen, then jitter the whole formation
		var x_pct: float = float(i + 1) / float(wave_size + 1)
		var y_offset: float = randf_range(-60.0, 60.0)

		var enemy: Enemy = EnemyScript.new()
		enemy.type = t

		if t == Enemy.Type.STRAFER:
			# Strafers spawn at a screen edge and fly across.
			if randf() < 0.5:
				enemy.position = Vector2(-60.0, y_offset + 200.0)
				enemy.h_dir = 1
			else:
				enemy.position = Vector2(_viewport_size.x + 60.0, y_offset + 200.0)
				enemy.h_dir = -1
		else:
			var jx: float = clamp(x_pct + x_jitter, 0.08, 0.92)
			enemy.position = Vector2(jx * _viewport_size.x, -80.0 + y_offset)

		get_parent().add_child(enemy)


func get_level_duration() -> float:
	return float(_level_data.get("duration", 60.0))


func get_mission_time() -> float:
	return _mission_time
