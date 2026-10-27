extends Area2D
class_name Enemy
## Generic enemy. Type-driven configuration. Self-builds visual + collision.
## Sector 1 only — three placeholder archetypes (Grunt, Dodger, Tank).

enum Type { GRUNT, DODGER, TANK, STRAFER, BOMBER, SWARMER, LANCER, BROODER, REAPER }

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

@export var type: Type = Type.GRUNT

# Filled in by _configure() based on type
var max_hp: int
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
	var t: float = float(lvl - 1) / float(GameState.MAX_LEVEL - 1)  # 0..1
	# Late-game tuning: fewer enemies per wave (Levels.gd) but each one is now
	# ~2.9x HP at Sector 20 (was 2.2x). Result: same time-on-screen pressure
	# with much lower spawn count, which is far easier on phone GPU/physics.
	var hp_mul: float = lerp(0.70, 2.90, t)
	var speed_mul: float = lerp(0.80, 1.30, t)
	var fire_t: float = t * t * (3.0 - 2.0 * t)  # smoothstep
	var fire_mul: float = lerp(1.70, 0.45, fire_t)
	max_hp = max(1, int(round(float(max_hp) * hp_mul)))
	speed *= speed_mul
	if fire_interval > 0.0:
		fire_interval *= fire_mul
	# Late-game enemies hit harder on contact too — by Sector 20 a graze costs
	# nearly twice as much HP as it does in Sector 1.
	contact_damage = max(1, int(round(float(contact_damage) * lerp(0.85, 1.80, t))))
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
		_:
			tex = null
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
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
	if _hit_flash > 0.0:
		_hit_flash = max(0.0, _hit_flash - delta * 8.0)
		queue_redraw()
		if _sprite != null:
			# Brighten the sprite toward white during the flash
			var k: float = 1.0 + _hit_flash * 2.5
			_sprite.modulate = Color(k, k, k, 1.0)
	elif _sprite != null and _sprite.modulate != Color(1, 1, 1, 1):
		_sprite.modulate = Color(1, 1, 1, 1)
	if movement == &"horizontal":
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

	# Firing — only once on screen
	var on_screen: bool = position.y > 0.0 and position.y < _viewport_size.y
	if fire_pattern != &"none" and on_screen:
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
			_spawn_enemy_bullet(Vector2.DOWN.rotated(-0.35), 6)
			_spawn_enemy_bullet(Vector2.DOWN, 6)
			_spawn_enemy_bullet(Vector2.DOWN.rotated(0.35), 6)
		&"fan":
			# Bomber lobs a wide downward fan of 5 shots
			_spawn_enemy_bullet(Vector2.DOWN.rotated(-0.45), 4)
			_spawn_enemy_bullet(Vector2.DOWN.rotated(-0.22), 4)
			_spawn_enemy_bullet(Vector2.DOWN, 4)
			_spawn_enemy_bullet(Vector2.DOWN.rotated(0.22), 4)
			_spawn_enemy_bullet(Vector2.DOWN.rotated(0.45), 4)
		&"drone_burst":
			# Swarmer releases a tight cluster of 4 cyan drones in a downward
			# spread. Drones are slower than normal bullets so they linger and
			# create a real area-denial effect.
			for off in [-0.25, -0.08, 0.08, 0.25]:
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
	var lvl: int = clamp(GameState.current_level, 1, GameState.MAX_LEVEL)
	var t: float = float(lvl - 1) / float(GameState.MAX_LEVEL - 1)
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
		get_parent().add_child(bullet)


func _spawn_enemy_bullet(dir: Vector2, dmg: int) -> void:
	var bullet: EnemyBullet = EnemyBulletScript.new()
	bullet.position = global_position + Vector2(0, enemy_size * 0.5)
	bullet.direction = dir
	bullet.damage = dmg
	bullet.style = bullet_style
	get_parent().add_child(bullet)


func take_damage(amount: int) -> void:
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
	if roll < health_drop_chance + power_drop_chance:
		# Roll one of the three weapon-specific power variants. Each is
		# equally likely so all three slots level over time regardless of
		# which weapon the player is currently wielding.
		_drop_pickup(_random_power_variant())
		return
	if roll < health_drop_chance + power_drop_chance + torpedo_drop_chance:
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


## Equal-weight pick across the three per-weapon power variants. Used by
## every enemy drop site so the slots level over time even if the player
## sticks to one weapon.
func _random_power_variant() -> int:
	var roll: int = randi() % 3
	match roll:
		0: return Pickup.Type.POWER_PHASER
		1: return Pickup.Type.POWER_BEAM
		_: return Pickup.Type.POWER_MISSILE


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
