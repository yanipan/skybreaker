extends Area2D
class_name Sidekick
## Companion ship — rare bonus drop. Follows the player at a side offset,
## fires its own weapon (a different type than the player's), and survives
## a few hits before exploding. Uses the same player ship sprites for now;
## we'll swap in dedicated art when it lands.
##
## Lifecycle:
##   - Spawned by Player when SIDEKICK pickup is consumed.
##   - Picks a weapon type different from the player's at spawn time.
##   - Inherits half the player's power_level (rounded up, min 1).
##   - On HP <= 0, explodes and frees itself.
##   - Only one sidekick exists at a time — Player checks before spawning.

const BulletScript := preload("res://scripts/Bullet.gd")
const MissileScript := preload("res://scripts/Missile.gd")
const BeamScript := preload("res://scripts/Beam.gd")
const SHIP_TEX_NEUTRAL: Texture2D = preload("res://assets/sprites/sidekickship.png")
const SHIP_TEX_BANK_LEFT: Texture2D = preload("res://assets/sprites/sidekickshipbankingleft.png")
const SHIP_TEX_BANK_RIGHT: Texture2D = preload("res://assets/sprites/sidekickshipbankingright.png")

# Mirrors Player.WeaponType ordering — must stay in sync.
enum WeaponType { PHASER, BEAM, MISSILE }

@export var ship_size: float = 48.0       ## Smaller than the main player; +15% over original 42
@export var follow_speed: float = 6.0  ## Tuned down from 10 — sidekick was zipping around too fast and its beam fire lagged visibly behind the ship
@export var side_offset: float = 80.0      ## Horizontal distance from player
@export var trail_offset: float = 18.0     ## Sits slightly behind the player

@export var max_hp: int = 6
@export var max_shield: int = 1
@export var shield_recharge_delay: float = 5.0
@export var shield_recharge_per_second: float = 0.35

var hp: int
var shield: float
var _shield_recharge_wait: float = 0.0
var power_level: int = 1
var weapon_type: int = WeaponType.PHASER

var _ship_sprite: Sprite2D
var _player: Node2D
var _last_x: float = 0.0
var _fire_cooldown: float = 0.0
var _beam: Node = null
var _dying: bool = false

# Free-roaming AI — sidekick wanders inside the bottom 25% of the screen,
# picking new wander targets periodically. Avoids enemies/bullets near it
# but otherwise drifts freely instead of bolting to the player.
var _viewport_size: Vector2
var _wander_target: Vector2
var _wander_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"sidekick")
	hp = max_hp
	shield = float(max_shield)
	_viewport_size = get_viewport().get_visible_rect().size
	_build_collision()
	_build_ship_sprite()
	area_entered.connect(_on_area_entered)
	_player = get_tree().get_first_node_in_group(&"player")
	if _player != null:
		# Spawn just to the right of the player so it reads as joining the formation.
		global_position = _player.global_position + Vector2(side_offset, trail_offset)
		_choose_weapon_for_player()
		_inherit_power_from_player()
	_pick_new_wander_target()
	queue_redraw()


## Pick a random target inside the bottom 25% of the screen. The sidekick
## will drift toward it; once it gets close (or after a few seconds) we
## pick a new one. This is what gives the sidekick its lazy patrol feel.
func _pick_new_wander_target() -> void:
	var pad: float = 60.0
	var x: float = randf_range(pad, _viewport_size.x - pad)
	# Bottom 25% of the screen
	var y_min: float = _viewport_size.y * 0.75
	var y_max: float = _viewport_size.y - pad
	var y: float = randf_range(y_min, y_max)
	_wander_target = Vector2(x, y)
	_wander_timer = randf_range(2.0, 4.0)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ship_size * 0.85, ship_size * 0.85)
	shape.shape = rect
	add_child(shape)


func _build_ship_sprite() -> void:
	_ship_sprite = Sprite2D.new()
	_ship_sprite.texture = SHIP_TEX_NEUTRAL
	var tex_size: float = float(_ship_sprite.texture.get_width())
	var s: float = ship_size / tex_size * 1.6
	_ship_sprite.scale = Vector2(s, s)
	# Slight tint so it reads as a friendly companion at a glance.
	_ship_sprite.modulate = Color(0.85, 1.0, 0.95)
	add_child(_ship_sprite)


## Pick a weapon type that differs from whatever the player currently holds,
## so the sidekick complements (rather than mirrors) the player's loadout.
func _choose_weapon_for_player() -> void:
	var player_weapon: int = 0
	if _player != null and "weapon_type" in _player:
		player_weapon = int(_player.weapon_type)
	# Prefer a weapon that contrasts with the player's:
	#   PHASER -> MISSILE, BEAM -> PHASER, MISSILE -> BEAM
	match player_weapon:
		0: weapon_type = WeaponType.MISSILE
		1: weapon_type = WeaponType.PHASER
		2: weapon_type = WeaponType.BEAM
		_: weapon_type = WeaponType.PHASER


func _inherit_power_from_player() -> void:
	if _player == null or not "power_level" in _player:
		power_level = 1
		return
	# Sidekick now matches the player's power level 1:1. Per-shot damage is
	# scaled to ~75% in the firing helpers below so it remains weaker overall.
	power_level = max(1, int(_player.power_level))


func _process(delta: float) -> void:
	if _dying:
		return
	# Wander timer — pick a new target periodically or when we're close enough.
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 40.0:
		_pick_new_wander_target()
	var prev_x: float = global_position.x
	global_position = global_position.lerp(_wander_target, clamp(follow_speed * delta, 0.0, 1.0))
	# Hard-clamp to bottom 25% so we never wander up into the playfield.
	global_position.y = clamp(global_position.y, _viewport_size.y * 0.75, _viewport_size.y - 30.0)
	global_position.x = clamp(global_position.x, 30.0, _viewport_size.x - 30.0)
	var h_vel: float = (global_position.x - prev_x) / max(delta, 0.0001)
	_update_banking(h_vel)

	# Shield slow-recharge after a quiet window.
	if _shield_recharge_wait > 0.0:
		_shield_recharge_wait -= delta
	elif shield < float(max_shield):
		shield = min(float(max_shield), shield + shield_recharge_per_second * delta)

	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire()
	queue_redraw()


func _update_banking(h_velocity: float) -> void:
	if _ship_sprite == null:
		return
	if h_velocity > 60.0:
		_ship_sprite.texture = SHIP_TEX_BANK_RIGHT
	elif h_velocity < -60.0:
		_ship_sprite.texture = SHIP_TEX_BANK_LEFT
	else:
		_ship_sprite.texture = SHIP_TEX_NEUTRAL


# --- Firing ---

func _fire() -> void:
	# Sidekick deals roughly 55% of the main player's DPS (dropped from 75%)
	# — it was feeling strong enough to carry stages on its own. Achieved via
	# lower fire-rate multipliers and reduced per-shot damage in the _fire_*
	# helpers below.
	match weapon_type:
		WeaponType.PHASER:
			_fire_phaser()
			# Player phaser cadence is fast_fire_rate + bonus*lvl ≈ 6.9 + 0.62*lvl.
			# Sidekick runs at 55% of that (was 75%). At L10 that's ~7/sec → ~4/sec
			# which reads as "support fire" not "second player."
			# Slope synced to the player's new 25-level scaling (0.62 → 0.49)
			# so the sidekick stays at ~55% of the player's fire rate instead
			# of accidentally overtaking it at high levels.
			var rate: float = (6.9 + 0.49 * (power_level - 1)) * 0.55
			_fire_cooldown = 1.0 / max(2.0, rate)
		WeaponType.MISSILE:
			_fire_missile()
			# 55% of player missile cadence. Missiles still feel punchy but
			# don't double-dip the player's high-damage pattern.
			_fire_cooldown = 1.0 / max(0.5, (1.43 + 0.18 * (power_level - 1)) * 0.55)
		WeaponType.BEAM:
			_fire_beam_pulse()
			# Beam pulses were back-to-back at 0.55 cadence which read as a
			# nearly continuous beam. 0.90 gives real breathing room between
			# pulses so each one reads as a distinct shot.
			_fire_cooldown = 0.90


func _fire_phaser() -> void:
	# Bullet count grows with power_level so the sidekick reads like a junior
	# version of the player's spread. Damage is set to ~75% of the player's
	# tier (player tier damage maxes at 3 → we use ceil(tier * 0.75) here).
	var color := Color(0.55, 1.0, 0.85)
	# Dropped from 0.75 → 0.55 per-shot so the sidekick adds pressure but
	# doesn't carry the fight. Combined with the slower fire rate above,
	# sidekick DPS is ~55% × 55% ≈ 30% of solo player DPS, which matches
	# the "flanking wingman" role better than the previous "second player".
	var dmg: int = max(1, int(ceil(_tier_damage() * 0.55)))
	# Spread thresholds stretched for the 25-level ladder. Triple spread now
	# unlocks at L7+ instead of L6+ so phaser scaling tracks the player curve.
	if power_level <= 3:
		_spawn_bullet(Vector2(0, -22), Vector2.UP, color, dmg)
	elif power_level <= 6:
		_spawn_bullet(Vector2(-8, -22), Vector2.UP, color, dmg)
		_spawn_bullet(Vector2(8, -22), Vector2.UP, color, dmg)
	else:
		_spawn_bullet(Vector2(0, -24), Vector2.UP, color, dmg)
		_spawn_bullet(Vector2(-12, -22), Vector2.UP, color, dmg)
		_spawn_bullet(Vector2(12, -22), Vector2.UP, color, dmg)


## Mirrors Player._bullet_tier_for_level damage values so the sidekick scales
## alongside the player's loadout instead of staying capped at 1.
func _tier_damage() -> int:
	# Thresholds stretched proportionally for the 25-level ladder so the
	# sidekick's damage tiers track the player's _bullet_tier_for_level
	# curve instead of peaking five levels early.
	if power_level <= 7:
		return 1
	elif power_level <= 11:
		return 2
	elif power_level <= 15:
		return 2
	else:
		return 3


func _spawn_bullet(local_offset: Vector2, dir: Vector2, color: Color, dmg: int) -> void:
	var bullet: Area2D = BulletScript.new()
	bullet.position = global_position + local_offset
	bullet.direction = dir
	bullet.bullet_color = color
	bullet.damage = dmg
	get_parent().add_child(bullet)


func _fire_missile() -> void:
	# Mirrors Player missile damage formula scaled to 75%.
	var dmg: int = max(2, int(ceil((6 + power_level * 2 + _tier_damage() * 2) * 0.75)))
	var m: Area2D = MissileScript.new()
	m.position = global_position + Vector2(0, -28)
	if "damage" in m:
		m.damage = dmg
	get_parent().add_child(m)


func _fire_beam_pulse() -> void:
	# Brief beam pulse. The beam is added as a CHILD of the sidekick so it
	# inherits the sidekick's transform — as the sidekick wanders the beam
	# moves with it, no more "beam hanging in midair" effect from when the
	# sidekick drifts sideways during the 0.35s pulse. Local position offsets
	# the beam's base up to the sidekick's nose.
	var b: Node = BeamScript.new()
	b.position = Vector2(0, -ship_size * 0.5)
	if "active" in b:
		b.active = true
	if "width" in b:
		# Beam width trimmed: was 6.0 + 0.8*L → 4.5 + 0.55*L. At L20 drops from
		# 22 px wide to ~15.5 px wide so it reads as a support pulse, not a
		# player-tier main beam.
		b.width = 4.5 + 0.55 * power_level
	add_child(b)
	_beam = b
	# Auto-cancel after a short pulse so the sidekick beam reads as bursts.
	var t := get_tree().create_timer(0.35)
	t.timeout.connect(_kill_beam.bind(b))


func _kill_beam(b: Node) -> void:
	if is_instance_valid(b):
		if "active" in b:
			b.active = false
		b.queue_free()
	if _beam == b:
		_beam = null


# --- Damage ---

func take_damage(amount: int) -> void:
	if _dying:
		return
	_shield_recharge_wait = shield_recharge_delay
	if shield > 0.0:
		var absorbed: float = min(shield, float(amount))
		shield -= absorbed
		amount -= int(absorbed)
		if amount <= 0:
			return
	hp -= amount
	if hp <= 0:
		_die()


func _die() -> void:
	_dying = true
	# Kill any in-flight beam pulse — beams live on the parent node, not
	# under the sidekick, so queue_free()-ing the sidekick alone leaves them
	# painted on the screen until the level ends.
	if _beam != null and is_instance_valid(_beam):
		if "active" in _beam:
			_beam.active = false
		_beam.queue_free()
		_beam = null
	var explosion: Node2D = preload("res://scripts/Explosion.gd").new()
	explosion.position = global_position
	explosion.radius = 140.0
	get_parent().add_child(explosion)
	AudioManager.play_sfx(AudioManager.SFX_SPACESHIP_EXPLODING, -4.0)
	queue_free()


## Called when the player picks up a HEALTH pickup. Heals the sidekick by the
## same percentage as the player got, and tops the shield off too. Cheap way to
## let pickups feel "shared" without forcing the sidekick to chase orbs itself.
func receive_heal_pct(pct: float) -> void:
	if _dying:
		return
	hp = min(max_hp, hp + max(1, int(round(float(max_hp) * pct))))
	shield = float(max_shield)


## Called when the player picks up a POWER pickup. Sidekick mirrors the
## player's level (capped at the player's max), so its damage / spread / fire
## cadence step up alongside the player.
func receive_power_up() -> void:
	if _dying:
		return
	power_level = min(16, power_level + 1)


func _on_area_entered(area: Area2D) -> void:
	if _dying:
		return
	if area.is_in_group(&"enemy_bullets"):
		var dmg: int = area.damage if "damage" in area else 1
		take_damage(dmg)
		area.queue_free()
	elif area.is_in_group(&"enemies"):
		var dmg2: int = area.contact_damage if "contact_damage" in area else 1
		take_damage(dmg2)
		if area.has_method("take_damage"):
			area.take_damage(999)


# --- Draw — shield bubble + small power dots ---

func _draw() -> void:
	if shield > 0.0:
		var pct: float = shield / float(max_shield)
		var r: float = ship_size * 0.5 + 16.0
		draw_circle(Vector2.ZERO, r + 4.0, Color(0.55, 1.0, 0.85, 0.10 + pct * 0.10))
		draw_circle(Vector2.ZERO, r, Color(0.55, 1.0, 0.85, 0.18 + pct * 0.10))
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(0.7, 1.0, 0.9, 0.7), 1.5, true)

	# Tiny power pip stack so the player can see how strong the sidekick is.
	var dots: int = clamp(power_level, 1, 8)
	var spacing: float = 5.0
	var start_x: float = -((dots - 1) * spacing) * 0.5
	var y: float = -ship_size * 0.5 - 10.0
	for i in dots:
		draw_circle(Vector2(start_x + i * spacing, y), 1.8, Color(0.8, 1.0, 0.9, 0.95))
