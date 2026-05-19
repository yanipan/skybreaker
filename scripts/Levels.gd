extends Object
class_name Levels
## Static level data table — 20 levels of Skybreaker.
## Each level entry drives the spawner, the background, and the win condition.
##
## Fields per level:
##   name             Display title shown on the level banner
##   theme_color      Background tint (multiplied with the starfield)
##   bg_texture_path  Optional path to a background image; "" = pure starfield
##   enemy_pool       Array of Enemy.Type values that may spawn this level
##   wave_size_min    Lower bound for the random wave size
##   wave_size_max    Upper bound for the random wave size
##   spawn_interval   Seconds between waves (lower = harder)
##   duration         Seconds the level lasts before "level complete"
##   has_boss         Reserved — true once boss system exists
##
## Difficulty curve: enemy pool grows, wave sizes grow, spawn cadence tightens.
## Levels 1-4 introduce types one at a time. 5-8 mix 2-3 types. 9-12 mix 4.
## 13-16 mix all 5 + tighter cadence. 17-20 are the gauntlet runs.

const ENTRIES: Array = [
	# --- ACT 1: Earth Defense (Levels 1-5) ---
	{
		"name": "Sector 1: First Contact",
		"theme_color": Color(0.85, 0.90, 1.10),
		"bg_texture_path": "",
		"enemy_pool": [0],  # GRUNT
		"wave_size_min": 1, "wave_size_max": 3,
		"spawn_interval": 4.5, "duration": 60.0, "has_boss": false,
	},
	{
		"name": "Sector 2: Hornet's Nest",
		"theme_color": Color(1.10, 0.85, 1.00),
		"bg_texture_path": "",
		"enemy_pool": [0, 1],  # GRUNT + DODGER
		"wave_size_min": 2, "wave_size_max": 4,
		"spawn_interval": 4.0, "duration": 65.0, "has_boss": false,
	},
	{
		"name": "Sector 3: Crosswinds",
		"theme_color": Color(0.85, 1.10, 1.00),
		"bg_texture_path": "",
		"enemy_pool": [0, 3],  # GRUNT + STRAFER
		"wave_size_min": 2, "wave_size_max": 4,
		"spawn_interval": 3.8, "duration": 70.0, "has_boss": false,
	},
	{
		"name": "Sector 4: Carpet Run",
		"theme_color": Color(1.10, 1.00, 0.80),
		"bg_texture_path": "",
		"enemy_pool": [0, 4],  # GRUNT + BOMBER
		"wave_size_min": 3, "wave_size_max": 5,
		"spawn_interval": 3.6, "duration": 70.0, "has_boss": true, "boss_type": 0,
	},
	{
		"name": "Sector 5: The Gauntlet",
		"theme_color": Color(1.10, 0.85, 0.85),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 3, 4],
		"wave_size_min": 3, "wave_size_max": 5,
		"spawn_interval": 3.4, "duration": 75.0, "has_boss": false,
	},
	# --- ACT 2: Outer Colonies (Levels 6-10) ---
	{
		"name": "Sector 6: Pirate Skies",
		"theme_color": Color(1.05, 0.80, 0.95),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 4],
		"wave_size_min": 3, "wave_size_max": 6,
		"spawn_interval": 3.2, "duration": 80.0, "has_boss": false,
	},
	{
		"name": "Sector 7: Asteroid Drift",
		"theme_color": Color(0.95, 0.85, 0.70),
		"bg_texture_path": "",
		"enemy_pool": [0, 3, 4],
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 3.0, "duration": 80.0, "has_boss": false,
	},
	{
		"name": "Sector 8: Bulwark Patrol",
		"theme_color": Color(1.10, 0.70, 0.70),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2],  # first TANK
		"wave_size_min": 3, "wave_size_max": 5,
		"spawn_interval": 3.2, "duration": 85.0, "has_boss": true, "boss_type": 1,
	},
	{
		"name": "Sector 9: Ion Storm",
		"theme_color": Color(0.70, 0.85, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 6],   # First LANCER appearance — telegraphed sniper
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 2.9, "duration": 85.0, "has_boss": false,
	},
	{
		"name": "Sector 10: Colony Fall",
		"theme_color": Color(1.20, 0.80, 0.60),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 6],
		"wave_size_min": 4, "wave_size_max": 7,
		"spawn_interval": 2.8, "duration": 90.0, "has_boss": false,
	},
	# --- ACT 3: Insectoid Swarm (Levels 11-15) ---
	{
		"name": "Sector 11: First Swarm",
		"theme_color": Color(0.75, 1.20, 0.75),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 3, 5],   # First SWARMER appearance — drone carrier
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 2.9, "duration": 90.0, "has_boss": false,
	},
	{
		"name": "Sector 12: Hive Mind",
		"theme_color": Color(0.85, 1.10, 0.65),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 5, 6],
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 2.9, "duration": 95.0, "has_boss": true, "boss_type": 2,
	},
	{
		"name": "Sector 13: Spore Field",
		"theme_color": Color(0.95, 1.10, 0.70),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 4, 5],
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 2.8, "duration": 95.0, "has_boss": false,
	},
	{
		"name": "Sector 14: Brood Mother",
		"theme_color": Color(1.05, 0.95, 0.55),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 7],   # First BROODER — death-spawn swarm
		"wave_size_min": 4, "wave_size_max": 7,
		"spawn_interval": 2.8, "duration": 100.0, "has_boss": false,
	},
	{
		"name": "Sector 15: The Spire",
		"theme_color": Color(0.70, 1.30, 0.85),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7],
		"wave_size_min": 5, "wave_size_max": 7,
		"spawn_interval": 2.7, "duration": 100.0, "has_boss": false,
	},
	# --- ACT 4: Crystal Dominion (Levels 16-19) ---
	{
		"name": "Sector 16: Crystal Frontier",
		"theme_color": Color(0.75, 0.90, 1.30),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7],
		"wave_size_min": 5, "wave_size_max": 7,
		"spawn_interval": 2.6, "duration": 105.0, "has_boss": true, "boss_type": 3,
	},
	{
		"name": "Sector 17: Prism Storm",
		"theme_color": Color(0.85, 0.75, 1.30),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8],   # First REAPER — kamikaze rams
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.5, "duration": 105.0, "has_boss": false,
	},
	{
		"name": "Sector 18: Shardfall",
		"theme_color": Color(0.95, 0.70, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8],
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.4, "duration": 110.0, "has_boss": false,
	},
	{
		"name": "Sector 19: Heart of Glass",
		"theme_color": Color(1.20, 0.85, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8],
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.3, "duration": 110.0, "has_boss": true, "boss_type": 4,
	},
	# --- ACT 5: The Skybreaker (Level 20) ---
	{
		"name": "Sector 20: The Skybreaker",
		"theme_color": Color(1.30, 0.55, 0.55),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8],
		"wave_size_min": 6, "wave_size_max": 9,
		"spawn_interval": 2.2, "duration": 120.0, "has_boss": true, "boss_type": 5,
	},
]


static func get_level(n: int) -> Dictionary:
	var idx: int = clamp(n - 1, 0, ENTRIES.size() - 1)
	return ENTRIES[idx]


static func count() -> int:
	return ENTRIES.size()
