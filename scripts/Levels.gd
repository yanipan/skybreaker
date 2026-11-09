extends Object
class_name Levels
## Static level data table — 24 levels of Skybreaker.
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
##   has_boss         Boss stage: the boss spawns ~35% in; the stage cannot
##                    end while a boss lives
##   boss_type        Boss.Type index of the main boss
##   escort_boss      Optional {type, name, hp_scale}: a first boss that
##                    guards the stage; the main boss enters after it dies
##   ends_on_boss     true = the stage ends right after the last boss dies,
##                    whatever the timer says (used by the finale)
##
## Difficulty curve: enemy pool grows, wave sizes grow, spawn cadence tightens.
## Levels 1-4 introduce types one at a time. 5-8 mix 2-3 types. 9-12 mix 4.
## 13-16 mix all 5 + tighter cadence. 17-19 are the gauntlet runs. 20-24
## Enemy ids: 0 GRUNT 1 DODGER 2 TANK 3 STRAFER 4 BOMBER 5 SWARMER 6 LANCER
## 7 BROODER 8 REAPER 9 SHADE 10 ARTILLERY 11 MINELAYER 12 SPLITTER 13 PULSAR
## (14 SHARD is spawned by a dying SPLITTER, never pooled) 15 HUNTER 16 BEAMER.
## First seen: HUNTER 13, PULSAR 14, MINELAYER 17, BEAMER 18, SPLITTER 19,
## SHADE 20, ARTILLERY 21.
## (9/11 expansion) add SHADE and ARTILLERY and keep climbing past the old
## sector-20 ceiling (Enemy.gd extends the ladder, LATE_SECTOR_MUL at 23-24).

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
		"wave_size_min": 3, "wave_size_max": 4,
		"spawn_interval": 3.6, "duration": 75.0, "has_boss": false,
	},
	# --- ACT 2: Outer Colonies (Levels 6-10) ---
	{
		"name": "Sector 6: Pirate Skies",
		"theme_color": Color(1.05, 0.80, 0.95),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 4],
		# Playtest 7/11: 3-6 every 3.2 s with full bomber fans was a wall of
		# fire right after the Act 1 boss. Thinned, and volleys stay light
		# through Sector 7 (Enemy.LIGHT_VOLLEY_UNTIL).
		"wave_size_min": 3, "wave_size_max": 5,
		"spawn_interval": 3.6, "duration": 80.0, "has_boss": false,
	},
	{
		"name": "Sector 7: Asteroid Drift",
		"theme_color": Color(0.95, 0.85, 0.70),
		"bg_texture_path": "",
		"enemy_pool": [0, 3, 4],
		"wave_size_min": 3, "wave_size_max": 5,
		"spawn_interval": 3.4, "duration": 80.0, "has_boss": false,
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
		"enemy_pool": [0, 1, 4, 5, 15],
		"wave_size_min": 4, "wave_size_max": 6,
		"spawn_interval": 2.8, "duration": 95.0, "has_boss": false,
	},
	{
		"name": "Sector 14: Brood Mother",
		"theme_color": Color(1.05, 0.95, 0.55),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 7, 13, 15],   # First BROODER — death-spawn swarm; first PULSAR — ring volleys
		"wave_size_min": 4, "wave_size_max": 7,
		"spawn_interval": 2.8, "duration": 100.0, "has_boss": false,
	},
	{
		"name": "Sector 15: The Spire",
		"theme_color": Color(0.70, 1.30, 0.85),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 13, 15],
		"wave_size_min": 5, "wave_size_max": 7,
		"spawn_interval": 2.7, "duration": 100.0, "has_boss": false,
	},
	# --- ACT 4: Crystal Dominion (Levels 16-19) ---
	{
		"name": "Sector 16: Crystal Frontier",
		"theme_color": Color(0.75, 0.90, 1.30),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 13, 15],
		"wave_size_min": 5, "wave_size_max": 7,
		"spawn_interval": 2.6, "duration": 105.0, "has_boss": true, "boss_type": 3,
	},
	{
		"name": "Sector 17: Prism Storm",
		"theme_color": Color(0.85, 0.75, 1.30),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 15],   # First REAPER — kamikaze rams; first MINELAYER — fused mines
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.5, "duration": 105.0, "has_boss": false,
	},
	{
		"name": "Sector 18: Shardfall",
		"theme_color": Color(0.95, 0.70, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 15, 16],
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.4, "duration": 110.0, "has_boss": false,
	},
	{
		"name": "Sector 19: Heart of Glass",
		"theme_color": Color(1.20, 0.85, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 15, 16],   # First SPLITTER — cracks into two shards
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.3, "duration": 110.0, "has_boss": true, "boss_type": 4,
	},
	# --- ACT 5: The Heart (Levels 20-22) ---
	# 9/11 expansion: the Skybreaker's own body. SHADE (9) appears first, then
	# ARTILLERY (10). The Null Archon guards the way out at 22.
	{
		"name": "Sector 20: Heart Chamber",
		"theme_color": Color(0.70, 1.10, 1.20),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 5, 6, 9, 11, 13, 16],   # First SHADE — phases in and out
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.3, "duration": 110.0, "has_boss": false,
	},
	{
		"name": "Sector 21: Pulse Conduit",
		"theme_color": Color(0.75, 1.00, 1.25),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 3, 4, 5, 6, 8, 9, 10, 12, 13, 15],   # First ARTILLERY — mortar bursts
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.2, "duration": 115.0, "has_boss": false,
	},
	{
		"name": "Sector 22: The Null Gate",
		"theme_color": Color(0.60, 0.95, 1.30),
		"bg_texture_path": "",
		"enemy_pool": [1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 15, 16],
		"wave_size_min": 5, "wave_size_max": 8,
		"spawn_interval": 2.2, "duration": 115.0, "has_boss": true, "boss_type": 6,
	},
	# --- ACT 6: The Null Reach (Levels 23-24) ---
	{
		"name": "Sector 23: Null Reach",
		"theme_color": Color(1.25, 0.60, 0.65),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16],
		"wave_size_min": 6, "wave_size_max": 9,
		"spawn_interval": 2.1, "duration": 120.0, "has_boss": false,
	},
	{
		"name": "Sector 24: The Skybreaker",
		"theme_color": Color(1.30, 0.55, 0.55),
		"bg_texture_path": "",
		"enemy_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16],
		"wave_size_min": 6, "wave_size_max": 9,
		"spawn_interval": 2.1, "duration": 120.0, "has_boss": true, "boss_type": 5,
		# The finale is a boss PAIR: the Herald (a splinter of the Skybreaker
		# at 75% HP) comes first, THE SKYBREAKER itself enters a few seconds
		# after it falls, and the sector ends the moment the Skybreaker dies.
		"escort_boss": {"type": 7, "name": "", "hp_scale": 0.75},
		"ends_on_boss": true,
	},
]


static func get_level(n: int) -> Dictionary:
	var idx: int = clamp(n - 1, 0, ENTRIES.size() - 1)
	return ENTRIES[idx]


static func count() -> int:
	return ENTRIES.size()
