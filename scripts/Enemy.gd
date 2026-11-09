extends Area2D
class_name Enemy
## Generic enemy. Type-driven configuration. Self-builds visual + collision.
## Sector 1 only — three placeholder archetypes (Grunt, Dodger, Tank).

## SHARD is never in a level pool: it only comes out of a dying SPLITTER.
enum Type { GRUNT, DODGER, TANK, STRAFER, BOMBER, SWARMER, LANCER, BROODER, REAPER, SHADE, ARTILLERY, MINELAYER, SPLITTER, PULSAR, SHARD, HUNTER, BEAMER }

const EnemyBulletScript := preload("res://scripts/EnemyBullet.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const EnemyExplosionScript := preload("res://scripts/EnemyExplosion.gd")
const ScorePopupScript := preload("res://scripts/ScorePopup.gd")

const SFX_FIRE_STRAFER: AudioStream = preload("res://assets/audio/sfx/fire1.mp3")
const SFX_FIRE_DODGER: AudioStream = preload("res://assets/audio/sfx/fire2.mp3")
const SFX_FIRE_BOMBER: AudioStream = preload("res://assets/audio/sfx/fire3.mp3")
const SFX_FIRE_TANK: AudioStream = preload("res://assets/audio/sfx/fire4.mp3")

## Per-type sprite textures. Null = no sprite yet, fall back to procedural _draw.
const TEX_GRUNT: Texture2D = preload("res://assets/sprites/enemy_grunt.png")
const TEX_DODGER: Texture2D = preload("res://assets/sprites/enemy_dodger.png")
const TEX_BOMBER: Texture2D = preload("res://assets/sprites/enemy_bomber.png")
const TEX_STRAFER: Texture2D = preload("res://assets/sprites/enemy_strafer.png")
const TEX_TANK: Texture2D = preload("res://assets/sprites/enemy_tank.png")
# These four shipped with solid black backgrounds; the background is baked
# out to alpha offline (scripts/tools/strip_backgrounds.gd) and their
# .import files generate mipmaps, matching the old runtime ImageTexture.
const TEX_SWARMER: Texture2D = preload("res://assets/sprites/enemy_swarmer.png")
const TEX_LANCER: Texture2D = preload("res://assets/sprites/enemy_lancer.png")
const TEX_BROODER: Texture2D = preload("res://assets/sprites/enemy_brooder.png")
const TEX_REAPER: Texture2D = preload("res://assets/sprites/enemy_reaper.png")
## 9/11 expansion types. Until their own art lands (see docs/ART_PROMPTS_24.md)
## they borrow an existing hull and a tint; drop the PNG in and the tint goes.
const PATH_SHADE: String = "res://assets/sprites/enemy_shade.png"
const PATH_ARTILLERY: String = "res://assets/sprites/enemy_artillery.png"
const PATH_MINELAYER: String = "res://assets/sprites/enemy_minelayer.png"
const PATH_SPLITTER: String = "res://assets/sprites/enemy_splitter.png"
const PATH_PULSAR: String = "res://assets/sprites/enemy_pulsar.png"
const PATH_HUNTER: String = "res://assets/sprites/enemy_hunter.png"
const PATH_BEAMER: String = "res://assets/sprites/enemy_beamer.png"
const EnemyBeamScript := preload("res://scripts/EnemyBeam.gd")
## BEAMER: hold line, hold time, and the slowest it may ever cycle its beam
## (the sector fire-rate ladder must not turn it into a permanent wall).
const BEAMER_HOLD_Y: float = 0.15
const BEAMER_HOLD_SECS: float = 9.0
const BEAMER_MIN_INTERVAL: float = 3.0
const BEAMER_TRACK_SPEED: float = 70.0

## SHADE phase cycle: visible (fires) then cloaked (untouchable, no contact).
const SHADE_VISIBLE_SECS: float = 1.7
const SHADE_CLOAKED_SECS: float = 1.2
const SHADE_CLOAK_ALPHA: float = 0.22
## ARTILLERY holds at this fraction of the screen height, for this long.
const ARTILLERY_HOLD_Y: float = 0.22
const ARTILLERY_HOLD_SECS: float = 7.5

@export var type: Type = Type.GRUNT

# Filled in by _configure() based on type
var max_hp: int
## SHADE: true while phased out (untouchable). Read by HitCheck.
var cloaked: bool = false
var _phase_timer: float = 0.0
## ARTILLERY: seconds spent on the hold line (0 = still descending).
var _hold_elapsed: float = 0.0
## Stand-in hull tint for types without their own art yet (WHITE = none).
var _sprite_tint: Color = Color.WHITE
## SHARD: sideways speed it was flung with (px/s, decays).
var _kick_x: float = 0.0
## PULSAR: running rotation of its ring volleys.
var _ring_turn: float = 0.0
## BEAMER: the beam it currently has out (null / freed = none).
var _beam: EnemyBeam = null
var hp: int
var speed: float
var enemy_size: float
var enemy_color: Color
var movement: StringName
var reward: int  ## Score awarded for the kill, scales with strength
var contact_damage: int = 1

# Firing
var fire_pattern: StringName = &"none"  ## "none", "aimed", "spread", "straight", "fan"
var fire_interval: float = 0.0
## Sector 1 fire interval multiplier (Sector 20 is 0.45). Was 1.70: early
## sectors felt like bullet hell (playtest 6/11).
const EARLY_FIRE_MUL: float = 2.4
const FIRST_SHOT_MIN: float = 0.9
## Up to this sector, multi-shot volleys are thinned (fan 5 -> 3, drones 4 -> 2,
## tank spread 3 -> 2). Was 4; the pirate sectors (6-7) were a wall of bomber
## fans (playtest 7/11), so full volleys now start at the Act 2 boss stage.
const LIGHT_VOLLEY_UNTIL: int = 7
## Extra hull / ram damage for enemies in the last two sectors.
const LATE_SECTOR_MUL: float = 1.08
## Sector at which the original difficulty ladder reached its top (t = 1.0).
const LADDER_TOP: int = 20
var _fire_timer: float = 0.0
var fire_sfx: AudioStream = null
var bullet_style: int = 0   ## EnemyBullet.Style — set per type so each enemy has distinct shots

# Horizontal-only movement (Strafer): -1 left, +1 right
var h_dir: int = 1

# Drop chances on death (0..1)
var health_drop_chance: float = 0.0
var power_drop_chance: float = 0.0
var torpedo_drop_chance: float = 0.0
var money_drop_chance: float = 0.0
var money_value: int = 0  ## Coins inside a money pickup from this enemy

var _viewport_size: Vector2
var _spawn_x: float
var _time: float = 0.0
var _hit_flash: float = 0.0   ## Flashes the sprite white briefly after a hit
var _sprite: Sprite2D = null  ## Set when this enemy type has art; null = procedural _draw

# Damage smoke — replaces the HP bar. Each puff: {pos, age, life, radius, drift}
var _smoke: Array = []
var _smoke_emit_timer: float = 0.0


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_spawn_x = position.x
	_configure()
	_build_collision()
	_build_sprite()
	add_to_group(&"enemies")
	area_entered.connect(_on_area_entered)
	queue_redraw()


func _configure() -> void:
	match type:
		Type.GRUNT:
			max_hp = 3          ## Bumped: was popping before the player could react to groups
			speed = 180.0       ## Slow enough that the player has time to shoot or dodge
			# Grunts vary a bit in size — 48..68 — so a wave reads as a mixed
			# squadron instead of identical clones.
			enemy_size = randf_range(55.0, 78.0)  # +15% over 48-68
			enemy_color = Color(1.0, 0.35, 0.30)
			movement = &"straight"
			reward = 10
			fire_pattern = &"straight"
			fire_interval = 2.8   ## Slow — fodder, but enough to keep the player honest
			_fire_timer = randf_range(1.0, 2.4)
			fire_sfx = SFX_FIRE_STRAFER
			bullet_style = EnemyBullet.Style.PELLET
			contact_damage = 3   ## Light contact
			health_drop_chance = 0.005   ## Halved — health was too common
			power_drop_chance = 0.00328  ## +15% from 0.00285 — three slots need feeding now
			torpedo_drop_chance = 0.006
			money_drop_chance = 0.35
			money_value = 5
		Type.DODGER:
			max_hp = 6          ## Bumped from 4 — sniper was still dying to a single volley at mid-power
			speed = 320.0
			enemy_size = randf_range(53.0, 71.0)  # +15% over 46-62
			enemy_color = Color(1.0, 0.45, 1.0)
			movement = &"sine"
			reward = 25
			fire_pattern = &"aimed"
			fire_interval = 1.6
			_fire_timer = randf_range(0.4, 1.2)
			bullet_style = EnemyBullet.Style.DART
			contact_damage = 5   ## Medium contact (it's fast and hits hard)
			health_drop_chance = 0.010   ## Halved
			power_drop_chance = 0.00874  ## +15% from 0.0076 — three slots need feeding now
			torpedo_drop_chance = 0.012
			money_drop_chance = 0.55
			money_value = 15
			fire_sfx = SFX_FIRE_DODGER
		Type.TANK:
			max_hp = 16         ## Real wall — harder now that missile spam can melt 12
			speed = 95.0
			# Tanks get the biggest variance — some are "mini tanks", some are
			# intimidating hulks you really need missiles for.
			enemy_size = randf_range(110.0, 154.0)  # +15% over 96-134
			enemy_color = Color(0.65, 0.15, 0.15)
			movement = &"straight"
			reward = 60
			fire_pattern = &"spread"
			fire_interval = 1.4
			_fire_timer = randf_range(0.6, 1.4)
			bullet_style = EnemyBullet.Style.SHELL
			contact_damage = 9   ## Heavy contact — almost half life
			health_drop_chance = 0.045   ## Halved
			power_drop_chance = 0.03824  ## +15% from 0.03325 — three slots need feeding now
			torpedo_drop_chance = 0.05
			money_drop_chance = 0.95
			money_value = 60
			fire_sfx = SFX_FIRE_TANK
		Type.STRAFER:
			# Fast horizontal flyer that crosses the screen edge-to-edge.
			# Light HP, sniping shots — pressures the player to move sideways.
			max_hp = 4          ## Bumped from 3
			speed = 360.0
			enemy_size = randf_range(51.0, 67.0)  # +15% over 44-58
			enemy_color = Color(0.3, 0.95, 0.95)
			movement = &"horizontal"
			reward = 35
			fire_pattern = &"aimed"
			fire_interval = 1.1
			_fire_timer = randf_range(0.3, 0.9)
			bullet_style = EnemyBullet.Style.SPARK
			contact_damage = 4
			health_drop_chance = 0.008   ## Halved
			power_drop_chance = 0.00656  ## +15% from 0.0057 — three slots need feeding now
			torpedo_drop_chance = 0.012
			money_drop_chance = 0.50
			money_value = 12
			fire_sfx = SFX_FIRE_STRAFER
		Type.BOMBER:
			# Slow, bulky, lobs a wide downward fan — area denial.
			max_hp = 11         ## Chunky but not Tank-tier (was 8)
			speed = 75.0
			enemy_size = randf_range(94.0, 124.0)  # +15% over 82-108
			enemy_color = Color(0.6, 0.35, 0.95)
			movement = &"straight"
			reward = 50
			fire_pattern = &"fan"
			fire_interval = 2.0
			_fire_timer = randf_range(0.7, 1.5)
			bullet_style = EnemyBullet.Style.PLASMA
			contact_damage = 7
			health_drop_chance = 0.032   ## Halved
			power_drop_chance = 0.02404  ## +15% from 0.0209 — three slots need feeding now
			torpedo_drop_chance = 0.035
			money_drop_chance = 0.85
			money_value = 35
			fire_sfx = SFX_FIRE_BOMBER
		Type.SWARMER:
			# Mid-tank carrier that periodically vomits a cluster of mini drones
			# downward. Doesn't fire bullets — its threat is the drone trail it
			# leaves behind. Must be killed promptly or the screen fills up.
			max_hp = 9
			speed = 110.0
			enemy_size = randf_range(98.0, 130.0)
			enemy_color = Color(0.95, 0.55, 0.20)
			movement = &"straight"
			reward = 55
			fire_pattern = &"drone_burst"
			fire_interval = 2.6
			_fire_timer = randf_range(0.8, 1.6)
			bullet_style = EnemyBullet.Style.SPARK   # Cyan drone swarm
			contact_damage = 6
			health_drop_chance = 0.030
			power_drop_chance = 0.025
			torpedo_drop_chance = 0.020
			money_drop_chance = 0.80
			money_value = 30
			fire_sfx = SFX_FIRE_BOMBER
		Type.LANCER:
			# Slow glass-cannon that locks on, telegraphs a thick red line, then
			# fires a single high-damage tracer down it. Punishes camping.
			# Squishy — drops in 2-3 phaser hits — but every shot HURTS.
			max_hp = 5
			speed = 130.0
			enemy_size = randf_range(70.0, 92.0)
			enemy_color = Color(0.95, 0.20, 0.25)
			movement = &"straight"
			reward = 40
			fire_pattern = &"lance"
			fire_interval = 3.4   # Long because there's a 0.9s telegraph baked in
			_fire_timer = randf_range(0.6, 1.4)
			bullet_style = EnemyBullet.Style.DART
			contact_damage = 5
			health_drop_chance = 0.018
			power_drop_chance = 0.012
			torpedo_drop_chance = 0.014
			money_drop_chance = 0.65
			money_value = 22
			fire_sfx = SFX_FIRE_DODGER
		Type.BROODER:
			# Slow biological heavy. Spits slow lumpy acid blobs (low HP cost
			# per hit but they LINGER — area denial with how slow they move),
			# AND on death erupts a wide downward fan of mini drone embryos.
			# Best killed from afar: get close and you'll eat both the spit
			# AND the death swarm.
			max_hp = 18
			speed = 70.0
			enemy_size = randf_range(118.0, 158.0)
			enemy_color = Color(0.55, 1.0, 0.45)   # Bioluminescent green
			movement = &"straight"
			reward = 75
			fire_pattern = &"acid_spit"
			fire_interval = 2.4
			_fire_timer = randf_range(0.8, 1.6)
			bullet_style = EnemyBullet.Style.ACID
			contact_damage = 8
			health_drop_chance = 0.060
			power_drop_chance = 0.040
			torpedo_drop_chance = 0.040
			money_drop_chance = 0.95
			money_value = 50
			fire_sfx = SFX_FIRE_BOMBER
		Type.SHADE:
			# Phase-shifter from the Skybreaker's own body. Cycles between a
			# visible window (fires a twin aimed dart) and a cloak in which it
			# cannot be hit or touched. Teaches the player to hold fire and
			# punish the window.
			max_hp = 7
			speed = 150.0
			enemy_size = randf_range(60.0, 80.0)
			enemy_color = Color(0.65, 0.40, 1.0)
			movement = &"sine"
			reward = 55
			fire_pattern = &"shade_pair"
			fire_interval = SHADE_VISIBLE_SECS + SHADE_CLOAKED_SECS
			_fire_timer = 0.6
			bullet_style = EnemyBullet.Style.DART
			contact_damage = 6
			health_drop_chance = 0.020
			power_drop_chance = 0.016
			torpedo_drop_chance = 0.018
			money_drop_chance = 0.75
			money_value = 30
			fire_sfx = SFX_FIRE_DODGER
			_phase_timer = SHADE_VISIBLE_SECS
		Type.ARTILLERY:
			# Siege hull. Descends to the top of the screen, holds there and
			# lobs slow mortar shells at the player's position that burst
			# into a ring of pellets. Leaves after its hold time so it can't
			# camp forever.
			max_hp = 22
			speed = 60.0
			enemy_size = randf_range(110.0, 140.0)
			enemy_color = Color(1.0, 0.75, 0.35)
			movement = &"hold"
			reward = 90
			fire_pattern = &"mortar"
			fire_interval = 2.6
			_fire_timer = 1.2
			bullet_style = EnemyBullet.Style.SHELL
			contact_damage = 9
			health_drop_chance = 0.060
			power_drop_chance = 0.045
			torpedo_drop_chance = 0.045
			money_drop_chance = 0.95
			money_value = 60
			fire_sfx = SFX_FIRE_BOMBER
		Type.MINELAYER:
			# Crosses the screen sideways like a Strafer and seeds slow mines
			# behind it. Each mine drifts down and bursts into a small ring
			# after its fuse, so the lane it crossed stays dangerous.
			max_hp = 9
			speed = 210.0
			enemy_size = randf_range(80.0, 100.0)
			enemy_color = Color(0.75, 1.0, 0.35)
			movement = &"horizontal"
			reward = 60
			fire_pattern = &"mine"
			fire_interval = 2.2
			_fire_timer = randf_range(0.4, 0.9)
			bullet_style = EnemyBullet.Style.ORB
			contact_damage = 6
			health_drop_chance = 0.025
			power_drop_chance = 0.018
			torpedo_drop_chance = 0.020
			money_drop_chance = 0.80
			money_value = 35
			fire_sfx = SFX_FIRE_BOMBER
		Type.SPLITTER:
			# Crystal hull that cracks into two fast SHARDs when it dies. Kill
			# it high on the screen or the shards are on top of you.
			max_hp = 14
			speed = 110.0
			enemy_size = randf_range(95.0, 120.0)
			enemy_color = Color(0.60, 0.90, 1.0)
			movement = &"straight"
			reward = 70
			fire_pattern = &"aimed"
			fire_interval = 2.4
			_fire_timer = randf_range(0.8, 1.6)
			bullet_style = EnemyBullet.Style.DART
			contact_damage = 7
			health_drop_chance = 0.030
			power_drop_chance = 0.024
			torpedo_drop_chance = 0.024
			money_drop_chance = 0.85
			money_value = 40
			fire_sfx = SFX_FIRE_DODGER
		Type.SHARD:
			# Half of a dead SPLITTER: small, fast, no guns, flung sideways.
			max_hp = 3
			speed = 300.0
			enemy_size = randf_range(46.0, 56.0)
			enemy_color = Color(0.60, 0.90, 1.0)
			movement = &"shard"
			reward = 15
			fire_pattern = &"none"
			contact_damage = 4
			health_drop_chance = 0.0
			power_drop_chance = 0.0
			torpedo_drop_chance = 0.0
			money_drop_chance = 0.30
			money_value = 10
		Type.PULSAR:
			# Slow drifting emitter. Every few seconds it fires a full ring
			# of pellets; the ring turns a little each time so the gaps move.
			max_hp = 12
			speed = 75.0
			enemy_size = randf_range(85.0, 105.0)
			enemy_color = Color(1.0, 0.50, 0.90)
			movement = &"straight"
			reward = 80
			fire_pattern = &"ring"
			fire_interval = 4.4
			_fire_timer = randf_range(1.0, 2.0)
			bullet_style = EnemyBullet.Style.PELLET
			contact_damage = 7
			health_drop_chance = 0.040
			power_drop_chance = 0.030
			torpedo_drop_chance = 0.030
			money_drop_chance = 0.90
			money_value = 45
			fire_sfx = SFX_FIRE_TANK
		Type.HUNTER:
			# Missile boat. Lobs slow homing missiles that curve after the
			# ship for a couple of seconds, then fly straight. Sidestep late,
			# or burn them with the beam.
			max_hp = 10
			speed = 120.0
			enemy_size = randf_range(85.0, 105.0)
			enemy_color = Color(1.0, 0.60, 0.30)
			movement = &"sine"
			reward = 65
			fire_pattern = &"homing"
			fire_interval = 3.6
			_fire_timer = randf_range(0.8, 1.6)
			bullet_style = EnemyBullet.Style.DART
			contact_damage = 6
			health_drop_chance = 0.030
			power_drop_chance = 0.022
			torpedo_drop_chance = 0.026
			money_drop_chance = 0.85
			money_value = 40
			fire_sfx = SFX_FIRE_BOMBER
		Type.BEAMER:
			# Beam frigate. Parks at the top, lines itself up over the ship
			# and fires a telegraphed beam straight down. Kill it during the
			# wind-up and the beam never comes.
			max_hp = 13
			speed = 90.0
			enemy_size = randf_range(95.0, 115.0)
			enemy_color = Color(0.55, 0.85, 1.0)
			movement = &"hold"
			reward = 85
			fire_pattern = &"beam"
			fire_interval = 5.0
			_fire_timer = 1.4
			contact_damage = 8
			health_drop_chance = 0.045
			power_drop_chance = 0.034
			torpedo_drop_chance = 0.034
			money_drop_chance = 0.90
			money_value = 50
		Type.REAPER:
			# Kamikaze ramship. No projectiles — its threat IS the ram. Locks
			# onto the player's X each frame and accelerates downward to ram.
			# Squishy enough that focused fire kills it before impact, but if
			# you're not paying attention it'll cleave your hull in half.
			max_hp = 6
			speed = 360.0      # Starts fast and only gets faster (chase)
			enemy_size = randf_range(78.0, 102.0)
			enemy_color = Color(1.0, 0.30, 0.20)
			movement = &"chase"
			reward = 45
			fire_pattern = &"none"
			contact_damage = 14   # Massive — half the player's health on a hit
			health_drop_chance = 0.020
			power_drop_chance = 0.014
			torpedo_drop_chance = 0.020
			money_drop_chance = 0.70
			money_value = 25
	# --- Level-based difficulty scaling ---
	# Early sectors are noticeably easier than the static type stats — slower,
	# fewer hits to kill, slower fire — and ramp up to ~1.4x HP / 1.18x speed
	# by Sector 20. The fire interval shrinks by ~25% over the same range.
	var lvl: int = clamp(GameState.current_level, 1, GameState.MAX_LEVEL)
	# The ladder was tuned on 20 sectors; t = 1.0 at sector 20 and keeps
	# climbing linearly to ~1.21 at sector 24 (9/11 expansion), so sectors
	# 1-20 play exactly as before and 21-24 are harder than anything was.
	var t: float = float(lvl - 1) / float(LADDER_TOP - 1)
	# Late-game tuning: fewer enemies per wave (Levels.gd) but each one is now
	# ~2.9x HP at Sector 20 (was 2.2x). Result: same time-on-screen pressure
	# with much lower spawn count, which is far easier on phone GPU/physics.
	var hp_mul: float = lerp(0.70, 2.90, t)
	var speed_mul: float = lerp(0.80, 1.30, t)
	# Playtest 9/11: the last two sectors should bite harder. Hull and ram
	# damage get LATE_SECTOR_MUL on top of the ladder; fire rate is unchanged.
	var late_mul: float = LATE_SECTOR_MUL if lvl >= GameState.MAX_LEVEL - 1 else 1.0
	hp_mul *= late_mul
	var fire_t: float = clampf(t, 0.0, 1.0)
	fire_t = fire_t * fire_t * (3.0 - 2.0 * fire_t)  # smoothstep, 1.0 from sector 20 on
	var fire_mul: float = lerp(EARLY_FIRE_MUL, 0.45, fire_t)
	if lvl > LADDER_TOP:
		# Past the old ceiling the fire rate tightens another 12% by sector 24.
		fire_mul *= lerp(1.0, 0.88, float(lvl - LADDER_TOP) / float(GameState.MAX_LEVEL - LADDER_TOP))
	max_hp = max(1, int(round(float(max_hp) * hp_mul)))
	speed *= speed_mul
	if fire_interval > 0.0:
		fire_interval *= fire_mul
		if fire_pattern == &"beam":
			fire_interval = maxf(fire_interval, BEAMER_MIN_INTERVAL)
		# First shot waits too, and never comes the instant a ship enters.
		_fire_timer = max(_fire_timer * fire_mul, FIRST_SHOT_MIN)
	# Late-game enemies hit harder on contact too — by Sector 20 a graze costs
	# nearly twice as much HP as it does in Sector 1.
	contact_damage = max(1, int(round(float(contact_damage) * lerp(0.85, 1.80, t) * late_mul)))
	hp = max_hp


func _draw() -> void:
	var half: float = enemy_size * 0.5
	# Procedural body — only drawn when this type has no sprite yet
	if _sprite == null:
		var rect := Rect2(-half, -half, enemy_size, enemy_size)
		var body_color: Color = enemy_color.lerp(Color(1, 1, 1), _hit_flash)
		draw_rect(rect, body_color, true)
		draw_rect(rect, Color(0, 0, 0, 0.6), false, 2.0)
	# Damage smoke — heavier as HP drops. Drawn in local space.
	# Light grey on the outside (reads against dark space) with a hot ember core
	# so it's clearly visible against the busy starfield.
	for puff in _smoke:
		var k: float = 1.0 - (puff.age / puff.life)
		if k <= 0.0:
			continue
		var r: float = puff.radius * (0.7 + 1.1 * (1.0 - k))
		var a: float = clamp(k, 0.0, 1.0)
		# Outer billow — light grey, soft edge
		draw_circle(puff.pos, r * 1.7, Color(0.78, 0.78, 0.82, a * 0.55))
		# Mid body — denser grey
		draw_circle(puff.pos, r, Color(0.92, 0.90, 0.90, a * 0.85))
		# Hot core fades with age — fresh puffs glow orange
		var ember: float = clamp(k * 1.4 - 0.2, 0.0, 1.0)
		if ember > 0.0:
			draw_circle(puff.pos, r * 0.5, Color(1.0, 0.55, 0.20, ember * 0.9))
			draw_circle(puff.pos, r * 0.25, Color(1.0, 0.95, 0.55, ember))


## Emit and age damage smoke. Emission rate scales with how hurt the enemy is —
## a barely-scratched tank trickles, a near-dead one belches.
func _update_smoke(delta: float) -> void:
	# Tick existing puffs
	if not _smoke.is_empty():
		var alive: Array = []
		for puff in _smoke:
			puff.age += delta
			if puff.age < puff.life:
				puff.pos += puff.drift * delta
				alive.append(puff)
		_smoke = alive
		queue_redraw()

	# Only damaged enemies smoke. Skip 1-HP fodder — they pop too fast to matter.
	if max_hp <= 1 or hp >= max_hp or hp <= 0:
		return
	var damage_pct: float = 1.0 - (float(hp) / float(max_hp))
	# Emission interval: 0.35s when lightly hurt → ~0.08s when nearly dead
	var interval: float = lerp(0.35, 0.08, damage_pct)
	_smoke_emit_timer -= delta
	if _smoke_emit_timer > 0.0:
		return
	_smoke_emit_timer = interval
	var half: float = enemy_size * 0.5
	var puff := {
		"pos": Vector2(randf_range(-half * 0.6, half * 0.6), randf_range(-half * 0.5, half * 0.3)),
		"age": 0.0,
		"life": randf_range(0.6, 1.1),
		"radius": randf_range(enemy_size * 0.10, enemy_size * 0.18) * (0.7 + damage_pct * 0.6),
		"drift": Vector2(randf_range(-12.0, 12.0), randf_range(-40.0, -18.0)),
	}
	_smoke.append(puff)
	queue_redraw()


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(enemy_size, enemy_size)
	shape.shape = rect
	add_child(shape)


## Pick a texture for this type, if one exists. Otherwise leave _sprite null
## and the procedural _draw fallback will run.
## Own art when the file exists, otherwise the stand-in hull (tinted).
static func _optional_tex(path: String, fallback: Texture2D) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			return t
	return fallback


func _build_sprite() -> void:
	var tex: Texture2D = null
	match type:
		Type.GRUNT:
			tex = TEX_GRUNT
		Type.DODGER:
			tex = TEX_DODGER
		Type.BOMBER:
			tex = TEX_BOMBER
		Type.STRAFER:
			tex = TEX_STRAFER
		Type.TANK:
			tex = TEX_TANK
		Type.SWARMER:
			tex = TEX_SWARMER
		Type.LANCER:
			tex = TEX_LANCER
		Type.BROODER:
			tex = TEX_BROODER
		Type.REAPER:
			tex = TEX_REAPER
		Type.SHADE:
			tex = _optional_tex(PATH_SHADE, TEX_DODGER)
			if tex == TEX_DODGER:
				_sprite_tint = Color(0.55, 0.35, 0.95)
		Type.ARTILLERY:
			tex = _optional_tex(PATH_ARTILLERY, TEX_TANK)
			if tex == TEX_TANK:
				_sprite_tint = Color(1.0, 0.72, 0.38)
		Type.MINELAYER:
			tex = _optional_tex(PATH_MINELAYER, TEX_STRAFER)
			if tex == TEX_STRAFER:
				_sprite_tint = Color(0.75, 1.0, 0.35)
		Type.SPLITTER, Type.SHARD:
			tex = _optional_tex(PATH_SPLITTER, TEX_LANCER)
			if tex == TEX_LANCER:
				_sprite_tint = Color(0.55, 0.90, 1.0)
		Type.PULSAR:
			tex = _optional_tex(PATH_PULSAR, TEX_SWARMER)
			if tex == TEX_SWARMER:
				_sprite_tint = Color(1.0, 0.55, 0.90)
		Type.HUNTER:
			tex = _optional_tex(PATH_HUNTER, TEX_BOMBER)
			if tex == TEX_BOMBER:
				_sprite_tint = Color(1.0, 0.62, 0.32)
		Type.BEAMER:
			tex = _optional_tex(PATH_BEAMER, TEX_TANK)
			if tex == TEX_TANK:
				_sprite_tint = Color(0.50, 0.82, 1.0)
		_:
			tex = null
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.modulate = _sprite_tint
	# Sprites are authored at 1024x1024 — scale to roughly enemy_size, slightly bigger
	# so the readable silhouette matches the collision footprint.
	var s: float = (enemy_size / float(tex.get_width())) * 1.6
	_sprite.scale = Vector2(s, s)
	# Source art is drawn pointing up (like the player ship). Rotate per movement:
	# - downward movers face down (PI)
	# - horizontal movers (Strafer) face along their travel direction
	if movement == &"horizontal":
		_sprite.rotation = -PI * 0.5 if h_dir > 0 else PI * 0.5
	else:
		_sprite.rotation = PI
	add_child(_sprite)


func _process(delta: float) -> void:
	_time += delta
	_update_smoke(delta)
	if type == Type.SHADE:
		_update_phase(delta)
	var alpha: float = SHADE_CLOAK_ALPHA if cloaked else 1.0
	if _hit_flash > 0.0:
		_hit_flash = max(0.0, _hit_flash - delta * 8.0)
		queue_redraw()
		if _sprite != null:
			# Brighten the sprite toward white during the flash
			var k: float = 1.0 + _hit_flash * 2.5
			_sprite.modulate = Color(_sprite_tint.r * k, _sprite_tint.g * k, _sprite_tint.b * k, alpha)
	elif _sprite != null:
		var rest := Color(_sprite_tint.r, _sprite_tint.g, _sprite_tint.b, alpha)
		if _sprite.modulate != rest:
			_sprite.modulate = rest
	if movement == &"hold":
		# Artillery: descend to the hold line, hover there for a while, then
		# carry on down and leave.
		var is_beamer: bool = type == Type.BEAMER
		var hold_y: float = _viewport_size.y * (BEAMER_HOLD_Y if is_beamer else ARTILLERY_HOLD_Y)
		var hold_secs: float = BEAMER_HOLD_SECS if is_beamer else ARTILLERY_HOLD_SECS
		if position.y < hold_y and _hold_elapsed <= 0.0:
			position.y = minf(hold_y, position.y + speed * delta)
			if position.y >= hold_y:
				_hold_elapsed = 0.001
		elif _hold_elapsed < hold_secs or _beam_live():
			_hold_elapsed += delta
			if is_beamer:
				# Line up over the ship, but stand still while a beam is out
				# so the warning line means what it shows.
				if not _beam_live():
					var ship := get_tree().get_first_node_in_group(&"player") as Node2D
					if ship != null:
						position.x = move_toward(position.x, ship.global_position.x, BEAMER_TRACK_SPEED * delta)
			else:
				position.x = clampf(_spawn_x + sin(_time * 0.7) * 70.0, enemy_size * 0.5, _viewport_size.x - enemy_size * 0.5)
		else:
			position.y += speed * 1.6 * delta
	elif movement == &"shard":
		# Flung sideways out of the dead SPLITTER, the kick bleeds off fast.
		position.y += speed * delta
		position.x = clampf(position.x + _kick_x * delta, 20.0, _viewport_size.x - 20.0)
		_kick_x = move_toward(_kick_x, 0.0, 520.0 * delta)
	elif movement == &"horizontal":
		position.x += speed * delta * h_dir
	elif movement == &"chase":
		# Reaper-style ram: accelerates down + drifts horizontally toward the
		# player's current X. Can't reverse, only steer. Speed ramps up to
		# 1.5x its base over 2 seconds so the kill window is the first second.
		position.y += speed * delta * (1.0 + min(_time * 0.25, 0.5))
		var p := get_tree().get_first_node_in_group(&"player")
		if p != null:
			var dx: float = p.global_position.x - position.x
			# Strafe rate scales with vertical speed for a believable arc
			var strafe: float = clamp(dx, -speed * 0.7 * delta, speed * 0.7 * delta)
			position.x += strafe
	else:
		position.y += speed * delta
		if movement == &"sine":
			position.x = _spawn_x + sin(_time * 4.0) * 120.0

	# Firing — only once on screen (and never while cloaked)
	var on_screen: bool = position.y > 0.0 and position.y < _viewport_size.y
	if fire_pattern == &"beam" and (_hold_elapsed <= 0.0 or _hold_elapsed >= BEAMER_HOLD_SECS or _beam_live()):
		pass   # beams only from the hold line, one at a time
	elif fire_pattern != &"none" and on_screen and not cloaked:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = fire_interval
			_fire()

	# Despawn off the screen — bottom for downward movers, sides for horizontal
	if movement == &"horizontal":
		if position.x < -100.0 or position.x > _viewport_size.x + 100.0:
			queue_free()
	elif position.y > _viewport_size.y + 100.0:
		queue_free()


func _light_volley() -> bool:
	return GameState.current_level <= LIGHT_VOLLEY_UNTIL


func _beam_live() -> bool:
	return _beam != null and is_instance_valid(_beam) and not _beam.is_queued_for_deletion()


## SHADE phase cycle. Cloaked = not monitorable (bullets and the ship pass
## through) and take_damage is ignored; HitCheck skips cloaked enemies too.
func _update_phase(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	if cloaked:
		cloaked = false
		monitorable = true
		_phase_timer = SHADE_VISIBLE_SECS
		# Fire shortly after reappearing: the window is the whole point.
		_fire_timer = minf(_fire_timer, 0.25)
	else:
		cloaked = true
		monitorable = false
		_phase_timer = SHADE_CLOAKED_SECS


func _fire() -> void:
	match fire_pattern:
		&"straight":
			_spawn_enemy_bullet(Vector2.DOWN, 3)
		&"aimed":
			# Fast, precise — Dodger/Strafer snipes
			var dir := Vector2.DOWN
			var player := get_tree().get_first_node_in_group(&"player")
			if player != null:
				dir = (player.global_position - global_position).normalized()
			_spawn_enemy_bullet(dir, 4)
		&"spread":
			# Heavier rounds from a Tank
			if _light_volley():
				_spawn_enemy_bullet(Vector2.DOWN.rotated(-0.18), 6)
				_spawn_enemy_bullet(Vector2.DOWN.rotated(0.18), 6)
			else:
				_spawn_enemy_bullet(Vector2.DOWN.rotated(-0.35), 6)
				_spawn_enemy_bullet(Vector2.DOWN, 6)
				_spawn_enemy_bullet(Vector2.DOWN.rotated(0.35), 6)
		&"fan":
			# Bomber lobs a wide downward fan of 5 shots (3 in early sectors)
			var fan_offs: Array = [-0.30, 0.0, 0.30] if _light_volley() else [-0.45, -0.22, 0.0, 0.22, 0.45]
			for fo in fan_offs:
				_spawn_enemy_bullet(Vector2.DOWN.rotated(fo), 4)
		&"drone_burst":
			# Swarmer releases a tight cluster of 4 cyan drones in a downward
			# spread. Drones are slower than normal bullets so they linger and
			# create a real area-denial effect.
			var drone_offs: Array = [-0.15, 0.15] if _light_volley() else [-0.25, -0.08, 0.08, 0.25]
			for off in drone_offs:
				var d := Vector2.DOWN.rotated(off)
				var bullet: EnemyBullet = EnemyBulletScript.new()
				bullet.position = global_position + Vector2(0, enemy_size * 0.4)
				bullet.direction = d
				bullet.damage = 4
				bullet.style = EnemyBullet.Style.SPARK
				bullet.speed = 280.0   # Slower than the 550 default — drones loiter
				get_parent().add_child(bullet)
		&"acid_spit":
			# Brooder vomits 3 slow acid blobs in a tight downward spread.
			# Slow and heavy — they eat space in front of the player and
			# punish standing still under the brooder.
			for off in [-0.18, 0.0, 0.18]:
				var d := Vector2.DOWN.rotated(off)
				var bullet: EnemyBullet = EnemyBulletScript.new()
				bullet.position = global_position + Vector2(0, enemy_size * 0.4)
				bullet.direction = d
				bullet.damage = 5
				bullet.style = EnemyBullet.Style.ACID
				get_parent().add_child(bullet)
		&"homing":
			# One homing missile (two from sector 20 on), launched to the side
			# so its curve is readable.
			var count: int = 2 if GameState.current_level >= LADDER_TOP else 1
			for hi in count:
				var side: float = (-1.0 if hi == 0 else 1.0) * (1.0 if count > 1 else (1.0 if randf() < 0.5 else -1.0))
				var hm: EnemyBullet = EnemyBulletScript.new()
				hm.position = global_position + Vector2(side * enemy_size * 0.3, enemy_size * 0.3)
				hm.direction = Vector2.DOWN.rotated(-side * 0.6)
				hm.damage = 6
				hm.style = EnemyBullet.Style.DART
				hm.speed_override = 250.0
				hm.radius_override = 7.0
				hm.color_override = Color(1.0, 0.55, 0.20)
				hm.homing_turn_rate = 1.6
				hm.homing_secs = 2.6
				get_parent().add_child(hm)
		&"beam":
			# Telegraphed beam straight down from the hull (EnemyBeam.gd).
			var beam: EnemyBeam = EnemyBeamScript.new()
			beam.emitter = self
			beam.offset = Vector2(0.0, enemy_size * 0.35)
			beam.damage = 8
			beam.beam_color = Color(0.45, 0.85, 1.0)
			get_parent().add_child(beam)
			_beam = beam
		&"mine":
			# One slow mine dropped straight down; it bursts on a fuse.
			var mine: EnemyBullet = EnemyBulletScript.new()
			mine.position = global_position + Vector2(0, enemy_size * 0.3)
			mine.direction = Vector2.DOWN
			mine.damage = 6
			mine.style = EnemyBullet.Style.ORB
			mine.speed = 85.0
			mine.burst_after = 3.2
			mine.burst_count = 5
			mine.burst_damage = 3
			get_parent().add_child(mine)
		&"ring":
			# Full ring of pellets, rotated a little every volley.
			var ring_n: int = 6 if _light_volley() else 8
			_ring_turn += 0.26
			for ri in ring_n:
				var rb: EnemyBullet = EnemyBulletScript.new()
				rb.position = global_position
				rb.direction = Vector2.DOWN.rotated(TAU * float(ri) / float(ring_n) + _ring_turn)
				rb.damage = 3
				rb.style = EnemyBullet.Style.PELLET
				rb.speed_override = 300.0
				get_parent().add_child(rb)
		&"shade_pair":
			# Two aimed darts a hair apart, fired once per visible window.
			var sdir := Vector2.DOWN
			var sp := get_tree().get_first_node_in_group(&"player")
			if sp != null:
				sdir = (sp.global_position - global_position).normalized()
			for so in [-0.07, 0.07]:
				var sb: EnemyBullet = EnemyBulletScript.new()
				sb.position = global_position + Vector2(0, enemy_size * 0.4)
				sb.direction = sdir.rotated(so)
				sb.damage = 5
				sb.style = EnemyBullet.Style.DART
				sb.speed_override = 620.0
				get_parent().add_child(sb)
		&"mortar":
			# One slow shell lobbed at the player's current position; after
			# its fuse it bursts into a ring of pellets (EnemyBullet.burst_*).
			var mdir := Vector2.DOWN
			var mp := get_tree().get_first_node_in_group(&"player")
			if mp != null:
				mdir = (mp.global_position - global_position).normalized()
			var shell: EnemyBullet = EnemyBulletScript.new()
			shell.position = global_position + Vector2(0, enemy_size * 0.45)
			shell.direction = mdir
			shell.damage = 6
			shell.style = EnemyBullet.Style.SHELL
			shell.speed_override = 240.0
			shell.burst_after = 1.0
			shell.burst_count = 6
			shell.burst_damage = 3
			get_parent().add_child(shell)
		&"lance":
			# Lancer fires one fast aimed dart down the player's bearing. The
			# 3.4s fire_interval already bakes in a long wind-up so this reads
			# as a "telegraphed snipe" — the player should learn to strafe
			# whenever a Lancer comes on screen.
			var ldir := Vector2.DOWN
			var lp := get_tree().get_first_node_in_group(&"player")
			if lp != null:
				ldir = (lp.global_position - global_position).normalized()
			var lbullet: EnemyBullet = EnemyBulletScript.new()
			lbullet.position = global_position + Vector2(0, enemy_size * 0.4)
			lbullet.direction = ldir
			lbullet.damage = 9        # HIGH single-shot damage to justify rarity
			lbullet.style = EnemyBullet.Style.DART
			lbullet.speed = 780.0     # Faster than normal — sniper round
			get_parent().add_child(lbullet)
	if fire_sfx != null:
		AudioManager.play_sfx(fire_sfx, -8.0)


## Death-spawn for BROODER: erupt a wide downward fan of mini drones. Called
## from take_damage() right before queue_free(). The number of drones scales
## with level so late-game brooders are scarier than early-game ones.
func _brooder_death_spawn() -> void:
	var lvl: int = clamp(GameState.current_level, 1, LADDER_TOP)
	var t: float = float(lvl - 1) / float(LADDER_TOP - 1)
	var drone_count: int = int(round(lerp(6.0, 12.0, t)))
	for i in drone_count:
		var ang_t: float = float(i) / float(drone_count - 1)   # 0..1
		var off: float = lerp(-0.55, 0.55, ang_t)
		var d := Vector2.DOWN.rotated(off)
		var bullet: EnemyBullet = EnemyBulletScript.new()
		bullet.position = global_position
		bullet.direction = d
		bullet.damage = 4
		bullet.style = EnemyBullet.Style.SPARK
		bullet.speed = 320.0
		# take_damage() runs inside a physics callback; adding an Area2D to
		# the tree there trips "Can't change this state while flushing
		# queries", so the add is deferred to the end of the frame.
		get_parent().add_child.call_deferred(bullet)


## Death-spawn for SPLITTER: two SHARDs, one flung each way. Deferred for the
## same reason as the brooder swarm (take_damage runs in a physics callback).
func _splitter_death_spawn() -> void:
	for side in [-1.0, 1.0]:
		var shard: Enemy = get_script().new()
		shard.type = Type.SHARD
		shard.position = global_position + Vector2(side * enemy_size * 0.3, 0.0)
		shard._kick_x = side * 340.0
		get_parent().add_child.call_deferred(shard)


func _spawn_enemy_bullet(dir: Vector2, dmg: int) -> void:
	var bullet: EnemyBullet = EnemyBulletScript.new()
	bullet.position = global_position + Vector2(0, enemy_size * 0.5)
	bullet.direction = dir
	bullet.damage = dmg
	bullet.style = bullet_style
	get_parent().add_child(bullet)


func take_damage(amount: int) -> void:
	if cloaked:
		return   # a phased SHADE cannot be hurt
	hp -= amount
	_hit_flash = 1.0
	queue_redraw()
	if hp <= 0:
		# Score only — money is earned via coin pickups, not directly from kills
		GameState.add_score(reward)
		GameState.mission_kills += 1
		# BROODER ruptures into a fan of mini drones on death — its whole
		# threat is the post-mortem swarm. Other types just explode.
		if type == Type.BROODER:
			_brooder_death_spawn()
		elif type == Type.SPLITTER:
			_splitter_death_spawn()
		_spawn_death_burst()
		_spawn_score_popup()
		_maybe_drop_pickup()
		# Bigger enemies kick the camera harder when they pop
		var shake: float = clamp(enemy_size / 18.0, 2.0, 8.0)
		EventBus.screen_shake_requested.emit(shake, 0.18)
		queue_free()


func _spawn_score_popup() -> void:
	var popup: ScorePopup = ScorePopupScript.new()
	popup.amount = reward
	# Spawn slightly above the kill so it doesn't fight the explosion for attention
	popup.position = global_position + Vector2(randf_range(-8, 8), -enemy_size * 0.4)
	get_parent().add_child(popup)


func _spawn_death_burst() -> void:
	var burst: EnemyExplosion = EnemyExplosionScript.new()
	burst.position = global_position
	# Burst scales with enemy size; tank gets a bigger pop than a grunt
	burst.burst_radius = enemy_size * 0.65
	# Bigger enemies throw more particles
	burst.spark_count = 10 + int(enemy_size / 12.0)
	burst.debris_count = 4 + int(enemy_size / 18.0)
	burst.smoke_count = 4 + int(enemy_size / 24.0)
	burst.base_color = enemy_color
	get_parent().add_child(burst)


func _maybe_drop_pickup() -> void:
	# Money is rolled independently — coins are the common drop, bonuses are rare
	if randf() < money_drop_chance:
		_drop_money()

	var roll: float = randf()
	if roll < health_drop_chance:
		# Weighted health tier: 70% small, 25% medium, 5% full
		var tier_roll: float = randf()
		if tier_roll < 0.70:
			_drop_pickup(Pickup.Type.HEALTH_SMALL)
		elif tier_roll < 0.95:
			_drop_pickup(Pickup.Type.HEALTH_MEDIUM)
		else:
			_drop_pickup(Pickup.Type.HEALTH_FULL)
		return
	var pwr_chance: float = power_drop_chance * Pickup.ENEMY_POWER_DROP_SCALE
	if roll < health_drop_chance + pwr_chance:
		# Equal-weight weapon roll; a weapon already at the sector soft cap
		# pays out money instead (see Pickup.roll_power_drop).
		var pt: int = Pickup.roll_power_drop(get_tree())
		if pt < 0:
			_drop_money()
		else:
			_drop_pickup(pt)
		return
	if roll < health_drop_chance + pwr_chance + torpedo_drop_chance:
		_drop_pickup(Pickup.Type.TORPEDO)


func _drop_pickup(t: int) -> void:
	var pickup: Pickup = PickupScript.new()
	pickup.type = t
	# Slight horizontal scatter so multi-drops don't perfectly overlap
	pickup.position = global_position + Vector2(randf_range(-12, 12), 0)
	# Deferred: drops usually spawn from inside an area_entered callback
	# (bullet / ram kill), where adding an Area2D trips "Can't change this
	# state while flushing queries".
	get_parent().add_child.call_deferred(pickup)


func _drop_money() -> void:
	var pickup: Pickup = PickupScript.new()
	pickup.type = Pickup.Type.MONEY
	pickup.money_value = money_value
	pickup.position = global_position + Vector2(randf_range(-12, 12), 0)
	# Deferred: drops usually spawn from inside an area_entered callback
	# (bullet / ram kill), where adding an Area2D trips "Can't change this
	# state while flushing queries".
	get_parent().add_child.call_deferred(pickup)


func _on_area_entered(_area: Area2D) -> void:
	# Bullets handle damage from their side; this is here so future
	# enemy-vs-player or enemy-vs-bomb logic has a hook.
	pass
