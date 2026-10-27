extends Area2D
class_name Player
## Player ship. Drag-to-move with thumb offset so the finger doesn't cover the ship.
## Self-constructs its visual + collision shape on _ready (no .tscn needed yet).

@export var follow_speed: float = 16.0       ## How quickly the ship catches up to the target (higher = snappier)
## Movement speed tier — 0..3. Each tier scales follow_speed by 1.35x, bought at the Starbase shop.
## Baseline tier 0 is intentionally a touch slow to make speed upgrades meaningful.
var speed_tier: int = 0
const SPEED_TIER_MAX: int = 3
@export var thumb_offset: float = 60.0       ## Pixels above the finger so the ship is visible while dragging
@export var screen_padding: float = 40.0     ## Keep the ship this far from screen edges
@export var ship_size: float = 74.0          ## Width/height of placeholder square (+15% over the original 64)
@export var ship_color: Color = Color(0.3, 0.85, 1.0)

# --- Health ---
@export var max_hp: int = 20
@export var invulnerability_time: float = 0.8   ## Seconds of i-frames after a hit
@export var heal_per_pickup: int = 5

# --- Shield ---
## Absorbs incoming damage before HP. Regenerates after a quiet window.
## Baseline is intentionally weak — one absorbed hit, slow recharge.
## Capacity and recharge speed will be upgradeable in the between-level shop.
@export var max_shield: int = 1
@export var shield_recharge_delay: float = 5.0     ## Seconds without taking a hit before regen kicks in
@export var shield_recharge_per_second: float = 0.4   ## ~2.5s to refill one pip after the delay

# --- Weapon ---
## Base shots per second at power level 1. Bumped from 5.4 → 6.4 so the
## basic phaser at L1 doesn't feel anaemic before the player has any
## weapon-specific pickups stacked up — about 18% more raw DPS at the floor
## without changing the L20 ceiling much (the per-level bonus does most of
## the late-game work).
@export var fast_fire_rate: float = 6.9       ## +8% phaser baseline — small QoL buff
@export var slow_fire_rate: float = 2.1       ## Shots per second when overheated (charge depleted)
## Extra shots/sec gained per power level above 1. Bumped 0.57 → 0.62 so the
## L20 ceiling lifts a touch (~17.7 shots/sec) and mid-tier phaser feels punchier.
@export var fire_rate_bonus_per_level: float = 0.49  ## Was 0.62 for 20-level ladder — dropped to 0.49 so L25 fire rate ≈ old L20 (~18.68 shots/sec)
@export var max_charge: float = 100.0        ## Total charge pool (base, before energy cells)
## Energy cells purchased from the shop. Each cell adds +50% to base max_charge.
## Hard cap at 4 cells = base x 3.0 (300 max_charge from 100 baseline).
const ENERGY_CELL_MAX: int = 4
const ENERGY_CELL_BONUS_PCT: float = 0.5
var energy_cells_bought: int = 0
var _base_max_charge: float = 100.0   ## Snapshot of original max_charge for cell math
@export var charge_drain_per_second: float = 50.0   ## How fast charge drains while fast-firing (~2s of fast fire)
@export var recharge_per_second: float = 40.0       ## How fast charge regenerates when not firing (~2.5s to refill)
@export var max_power_level: int = 25  ## 20→25: five extra climb levels without raising the top-end power ceiling (all per-level formulas were rescaled to match the old L20 values at the new L25)

# --- Torpedo ---
@export var max_torpedoes: int = 2
@export var starting_torpedoes: int = 1
@export var torpedo_fire_grace: float = 0.25  ## Tiny gap so right-clicks don't double-fire

const BulletScript := preload("res://scripts/Bullet.gd")
const TorpedoScript := preload("res://scripts/Torpedo.gd")
const MissileScript := preload("res://scripts/Missile.gd")
const BeamScript := preload("res://scripts/Beam.gd")

## Weapon types — cycled by WEAPON_CHANGE pickups.
##   PHASER  — bullets, baseline rate, baseline charge
##   BEAM    — continuous laser, drains charge ~3x faster
##   MISSILE — slower fire, slower charge regen, homing
enum WeaponType { PHASER, BEAM, MISSILE }

# Ship sprites — neutral + bank left + bank right
const SHIP_TEX_NEUTRAL: Texture2D = preload("res://assets/sprites/playership.png")
const SHIP_TEX_BANK_LEFT: Texture2D = preload("res://assets/sprites/playerbankingleft.png")
const SHIP_TEX_BANK_RIGHT: Texture2D = preload("res://assets/sprites/playerbankingright.png")

## Horizontal velocity (px/s) above which we swap to a banking sprite
const BANK_VELOCITY_THRESHOLD: float = 60.0

var _target_position: Vector2
var _is_dragging: bool = false  ## Touch only — true while finger is on screen
var _is_firing: bool = false    ## True while fire button (mouse left or touch) is held
var _touch_index: int = -1      ## Touch only — index of the finger steering the ship, -1 = none
var _mouse_active: bool = false ## True once we've seen any mouse motion (desktop)
var _screen_size: Vector2
var _fire_cooldown: float = 0.0
var _current_charge: float

var hp: int
var shield: float          ## Float so partial recharge ticks accumulate cleanly
var _shield_recharge_wait: float = 0.0   ## Counts down before recharge resumes after a hit
var _shield_break_flicker: float = 0.0   ## Counts down a brief flicker after shield drops to zero
## power_level is now a DERIVED mirror of weapon_levels[weapon_type]. All the
## firing code still reads it directly so the math stays untouched, but the
## ground truth lives in weapon_levels and gets copied into power_level any
## time the active weapon or its slot changes (see _refresh_derived_power).
var power_level: int = 1
## Per-weapon level slots — every weapon levels independently now. Pickups
## drop in three colored variants (POWER_PHASER / BEAM / MISSILE) and only
## bump their matching slot. Switching weapons swaps which slot is "active".
var weapon_levels: Dictionary = {
	WeaponType.PHASER: 1,
	WeaponType.BEAM: 1,
	WeaponType.MISSILE: 1,
}
var _i_frame_timer: float = 0.0
var torpedo_count: int
var _torpedo_grace_timer: float = 0.0

var _ship_sprite: Sprite2D
var _last_x: float = 0.0   ## Used to compute horizontal velocity each frame

# Active weapon — cycled with middle mouse button (desktop) or by future
# mobile control. Reads from weapon_levels[weapon_type] for its current level.
var weapon_type: int = WeaponType.PHASER
## Active beam instances. Beam progression mirrors phaser progression — higher
## power_level adds parallel beams (and widens / brightens existing ones), so
## a maxed beam loadout sweeps a wide column instead of a single line.
var _beams: Array = []
var _beam_audio_active: bool = false  ## Tracks beam SFX so it only retriggers on press

# Damage smoke — emitted while hp < max_hp, cleared when fully healed.
# Each puff: {pos, age, life, radius, drift}
var _smoke: Array = []
var _smoke_emit_timer: float = 0.0


func _ready() -> void:
	_screen_size = get_viewport_rect().size
	_target_position = position
	_base_max_charge = max_charge
	_apply_energy_cells()
	_current_charge = max_charge
	# Restore from a level-complete carry, a mid-life respawn, or start fresh.
	# Respawn takes priority over carry — if both are set (shouldn't happen,
	# but be defensive) the respawn slot wins because it's the more recent event.
	if GameState.respawn_pending:
		max_shield = max(max_shield, GameState.respawn_max_shield)
		max_torpedoes = max(max_torpedoes, GameState.respawn_max_torpedoes)
		hp = max_hp
		shield = float(max_shield)
		_load_weapon_levels(GameState.respawn_weapon_levels, GameState.respawn_power_level)
		torpedo_count = clamp(GameState.respawn_torpedo_count, 0, max_torpedoes)
		weapon_type = clamp(GameState.respawn_weapon_type, 0, 2)
		_refresh_derived_power()
		speed_tier = clamp(GameState.respawn_speed_tier, 0, SPEED_TIER_MAX)
		energy_cells_bought = clamp(GameState.respawn_energy_cells, 0, ENERGY_CELL_MAX)
		_apply_energy_cells()
		GameState.clear_respawn()
	elif GameState.carry_active:
		# Raise the caps BEFORE clamping into them, so shop-bought shield and
		# torpedo capacity come back fully charged/stocked.
		max_shield = max(max_shield, GameState.carry_max_shield)
		max_torpedoes = max(max_torpedoes, GameState.carry_max_torpedoes)
		hp = clamp(GameState.carry_hp, 1, max_hp)
		shield = clamp(GameState.carry_shield, 0.0, float(max_shield))
		_load_weapon_levels(GameState.carry_weapon_levels, GameState.carry_power_level)
		torpedo_count = clamp(GameState.carry_torpedo_count, 0, max_torpedoes)
		weapon_type = clamp(GameState.carry_weapon_type, 0, 2)
		_refresh_derived_power()
		speed_tier = clamp(GameState.carry_speed_tier, 0, SPEED_TIER_MAX)
		energy_cells_bought = clamp(GameState.carry_energy_cells, 0, ENERGY_CELL_MAX)
		_apply_energy_cells()
		GameState.clear_carry()
	else:
		hp = max_hp
		shield = float(max_shield)
		torpedo_count = starting_torpedoes
	add_to_group(&"player")
	area_entered.connect(_on_area_entered)
	_build_collision()
	_build_ship_sprite()
	_last_x = position.x
	set_process(true)
	queue_redraw()
	print("Player _ready: pos=", position, " size=", ship_size)


func _on_area_entered(area: Area2D) -> void:
	# Friendly starbase — touching it opens the shop, no damage taken.
	# Starbase handles the actual menu open via its own area_entered hook.
	if area.is_in_group(&"starbases"):
		return
	if area.is_in_group(&"pickups"):
		_consume_pickup(area)
		return
	if area.is_in_group(&"enemy_bullets"):
		var dmg: int = area.damage if "damage" in area else 1
		_take_damage(dmg)
		area.queue_free()
		return
	if area.is_in_group(&"enemies"):
		var dmg2: int = area.contact_damage if "contact_damage" in area else 1
		_take_damage(dmg2)
		# Enemy also takes a chunk of damage from the collision. Bosses only
		# take a fixed ram hit, otherwise one touch (shield up = 0 hull
		# damage) would delete a 320 HP boss.
		if area.has_method("take_damage"):
			area.take_damage(25 if area.is_in_group(&"bosses") else 999)
		return


func _take_damage(amount: int) -> void:
	if _i_frame_timer > 0.0:
		return
	_i_frame_timer = invulnerability_time
	# Any incoming hit pauses shield recharge for a window
	_shield_recharge_wait = shield_recharge_delay

	# Shield fully negates the hit — any hit while the shield is up drops the
	# whole shield bar to zero, but the hull takes nothing for that strike.
	var remaining: int = amount
	if shield > 0.0:
		shield = 0.0
		remaining = 0
		_shield_break_flicker = 1.0
		if AudioManager.SFX_SHIELD_HIT != null:
			AudioManager.play_sfx(AudioManager.SFX_SHIELD_HIT, -4.0)
		else:
			AudioManager.play_sfx(AudioManager.SFX_TAKING_IMPACT, -8.0)
		AudioManager.haptic_light()
		if OS.is_debug_build():
			print("Shield absorbed hit (full negate)")

	# Anything left bleeds into the hull
	if remaining > 0:
		hp -= remaining
		AudioManager.play_sfx(AudioManager.SFX_TAKING_IMPACT, -3.0)
		AudioManager.haptic_medium()
		EventBus.screen_shake_requested.emit(8.0, 0.18)
		if OS.is_debug_build():
			print("Hull hit! HP=", hp)

	if hp <= 0:
		_die()


var _dying: bool = false


func _die() -> void:
	# Guard against multi-trigger — once dying, ignore further hits/calls.
	if _dying:
		return
	_dying = true
	print("Player DIED — lives left=", GameState.lives - 1)
	AudioManager.play_sfx(AudioManager.SFX_SPACESHIP_EXPLODING, 0.0)
	AudioManager.haptic_heavy()
	# Spawn a death explosion at the player's position so the wipe is visible
	var explosion: Node2D = preload("res://scripts/Explosion.gd").new()
	explosion.position = global_position
	explosion.radius = 240.0
	get_parent().add_child(explosion)
	EventBus.screen_shake_requested.emit(22.0, 0.55)
	# Disable collision/firing immediately — let the dramatic animation play
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	# Notify Main to run the death sequence (slow-mo + camera dwell + restart)
	EventBus.player_died.emit()
	# Hide the ship visually after a short delay
	visible = false
	set_process(false)


## Recompute max_charge from base + energy cells. Called whenever a cell is
## purchased so the gauge reflects the new ceiling. Also tops the current
## charge up to the NEW max — without this, restoring from a carry slot
## (or a respawn) leaves _current_charge pinned at the base 100 even though
## max_charge has grown to 150/200/250/300, so the bar reads as partially
## empty even though the player bought the upgrade.
func _apply_energy_cells() -> void:
	var bonus: float = 1.0 + float(energy_cells_bought) * ENERGY_CELL_BONUS_PCT
	max_charge = _base_max_charge * bonus
	_current_charge = max_charge


## Called from the StarbaseShop when the player buys an energy cell. Returns
## false (and the shop refuses the sale) if the player has already maxed out.
func buy_energy_cell() -> bool:
	if energy_cells_bought >= ENERGY_CELL_MAX:
		return false
	energy_cells_bought += 1
	_apply_energy_cells()
	_current_charge = max_charge   # Top off so the upgrade feels immediate
	return true


func _consume_pickup(pickup: Area2D) -> void:
	if not "type" in pickup:
		return
	var sidekick: Node = get_tree().get_first_node_in_group(&"sidekick")
	match pickup.type:
		Pickup.Type.HEALTH_SMALL:
			hp = min(max_hp, hp + int(round(max_hp * 0.25)))
			if sidekick != null and sidekick.has_method("receive_heal_pct"):
				sidekick.receive_heal_pct(0.25)
			if OS.is_debug_build():
				print("Picked up HEALTH_SMALL. HP=", hp)
		Pickup.Type.HEALTH_MEDIUM:
			hp = min(max_hp, hp + int(round(max_hp * 0.5)))
			if sidekick != null and sidekick.has_method("receive_heal_pct"):
				sidekick.receive_heal_pct(0.5)
			if OS.is_debug_build():
				print("Picked up HEALTH_MEDIUM. HP=", hp)
		Pickup.Type.HEALTH_FULL:
			hp = max_hp
			if sidekick != null and sidekick.has_method("receive_heal_pct"):
				sidekick.receive_heal_pct(1.0)
			if OS.is_debug_build():
				print("Picked up HEALTH_FULL. HP=", hp)
		Pickup.Type.POWER:
			# Legacy generic power — boosts whichever weapon is currently active.
			# Drop tables now use the per-weapon variants below; this branch
			# stays as a safety net for old saves / boss drops.
			add_power_to_weapon(weapon_type)
			if sidekick != null and sidekick.has_method("receive_power_up"):
				sidekick.receive_power_up()
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, -3.0)
			if OS.is_debug_build():
				print("Picked up POWER. Level=", power_level, " (weapon ", weapon_type, ")")
		Pickup.Type.POWER_PHASER:
			add_power_to_weapon(WeaponType.PHASER)
			if sidekick != null and sidekick.has_method("receive_power_up"):
				sidekick.receive_power_up()
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, -3.0)
			if OS.is_debug_build():
				print("Picked up POWER_PHASER. Phaser=", weapon_levels[WeaponType.PHASER])
		Pickup.Type.POWER_BEAM:
			add_power_to_weapon(WeaponType.BEAM)
			if sidekick != null and sidekick.has_method("receive_power_up"):
				sidekick.receive_power_up()
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, -3.0)
			if OS.is_debug_build():
				print("Picked up POWER_BEAM. Beam=", weapon_levels[WeaponType.BEAM])
		Pickup.Type.POWER_MISSILE:
			add_power_to_weapon(WeaponType.MISSILE)
			if sidekick != null and sidekick.has_method("receive_power_up"):
				sidekick.receive_power_up()
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, -3.0)
			if OS.is_debug_build():
				print("Picked up POWER_MISSILE. Missile=", weapon_levels[WeaponType.MISSILE])
		Pickup.Type.TORPEDO:
			torpedo_count = min(max_torpedoes, torpedo_count + 1)
			if OS.is_debug_build():
				print("Picked up TORPEDO. Ammo=", torpedo_count)
		Pickup.Type.MONEY:
			var coins: int = pickup.money_value if "money_value" in pickup else 1
			GameState.add_money(coins)
			AudioManager.play_sfx(AudioManager.SFX_COIN_PICKUP, -4.0)
			if OS.is_debug_build():
				print("Picked up MONEY +", coins, " (total=", GameState.money, ")")
		Pickup.Type.WEAPON_CHANGE:
			cycle_weapon()
		Pickup.Type.LIFE:
			GameState.lives = min(GameState.MAX_LIVES, GameState.lives + 1)
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, 0.0)
			if OS.is_debug_build():
				print("Picked up LIFE. Lives=", GameState.lives)
		Pickup.Type.SIDEKICK:
			_grant_sidekick()
			AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, 0.0)
			if OS.is_debug_build():
				print("Picked up SIDEKICK")
	AudioManager.haptic_light()
	pickup.queue_free()


func _draw() -> void:
	var half := ship_size * 0.5
	# Shield aura — animated energy bubble around the ship
	# - Soft outer halo + pulsing bright ring + rotating arc highlights
	# - Brief strobe-out for ~1s right after the shield breaks
	if shield > 0.0:
		var t: float = float(Time.get_ticks_msec()) / 1000.0
		var pct: float = shield / float(max_shield)
		var base_r: float = half + 22.0 + pct * 6.0
		var pulse: float = sin(t * 4.0) * 1.5
		var r: float = base_r + pulse

		# --- 3D bubble: layered concentric circles fading inward make a sphere ---
		# Outer atmospheric haze
		draw_circle(Vector2.ZERO, r + 10.0, Color(0.30, 0.70, 1.0, 0.06))
		draw_circle(Vector2.ZERO, r + 5.0,  Color(0.35, 0.75, 1.0, 0.10 + pct * 0.06))
		# Translucent body — slightly darker blue, gives the dome volume
		draw_circle(Vector2.ZERO, r,        Color(0.30, 0.65, 1.0, 0.14 + pct * 0.10))
		# Inner brighter shell — hints at the back wall of the sphere
		draw_circle(Vector2.ZERO, r * 0.92, Color(0.45, 0.80, 1.0, 0.10 + pct * 0.08))
		# Dim inner cavity so the center feels hollow rather than flat
		draw_circle(Vector2.ZERO, r * 0.78, Color(0.10, 0.30, 0.60, -0.05), false)

		# --- Specular highlights — these sell the spherical shape ---
		# Bright top-left "key" highlight as a small offset filled disc
		var hi_pos := Vector2(-r * 0.42, -r * 0.45)
		draw_circle(hi_pos, r * 0.18, Color(1.0, 1.0, 1.0, 0.55))
		draw_circle(hi_pos, r * 0.10, Color(1.0, 1.0, 1.0, 0.85))
		# A second smaller "fill" highlight further out
		draw_circle(Vector2(-r * 0.55, -r * 0.20), r * 0.06, Color(0.85, 0.95, 1.0, 0.55))
		# Bottom-right rim light — opposite the key, adds depth
		var rim_arc_color := Color(0.75, 0.95, 1.0, 0.65)
		draw_arc(Vector2.ZERO, r - 1.0, PI * 0.15, PI * 0.85, 22, rim_arc_color, 3.0, true)

		# --- Animated outer rim with intensity pulse ---
		var rim_alpha: float = 0.50 + 0.25 * sin(t * 8.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(0.75, 0.95, 1.0, rim_alpha * (0.5 + pct * 0.5)), 2.5, true)

		# --- Two rotating energy bands ---
		var spin: float = t * 2.2
		var band_color := Color(0.90, 1.0, 1.0, 0.85)
		draw_arc(Vector2.ZERO, r - 2.0, spin, spin + 0.7, 16, band_color, 2.5, true)
		draw_arc(Vector2.ZERO, r - 2.0, spin + PI, spin + PI + 0.5, 14, band_color, 2.5, true)
	elif _shield_break_flicker > 0.0:
		# Strobe at ~12 Hz so the player clearly sees the shield collapsing
		if int(_shield_break_flicker * 12.0) % 2 == 0:
			var fade: float = _shield_break_flicker  ## fades from 1.0 → 0.0
			var ring_radius2: float = half + 24.0
			var ring_color2 := Color(0.6, 0.85, 1.0, 0.55 * fade)
			draw_circle(Vector2.ZERO, ring_radius2, ring_color2)
	_draw_smoke()
	# Power-level dots and the small weapon-icon box used to live next to the
	# ship — those moved to the new left-edge weapon meters HUD in Main.gd.
	# Only the torpedo, charge, shield and health bars stay attached to the ship.
	_draw_torpedo_indicator()
	_draw_charge_bar()
	_draw_shield_bar()
	_draw_health_bar()


## Damage smoke. Emits while hp < max_hp; thicker and faster the more hurt
## the ship is. Healing to full snaps the existing puffs out so the player
## immediately sees they're back to clean.
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

	# Fully healed → clear remaining puffs immediately for clean visual feedback
	if hp >= max_hp:
		if not _smoke.is_empty():
			_smoke.clear()
			queue_redraw()
		return

	var damage_pct: float = 1.0 - (float(hp) / float(max_hp))
	# Only start smoking once meaningfully hurt — a single scratch shouldn't smoke
	if damage_pct < 0.15:
		return
	# Emission interval: 0.30s when lightly hurt → ~0.07s when nearly dead
	var interval: float = lerp(0.30, 0.07, clamp((damage_pct - 0.15) / 0.85, 0.0, 1.0))
	_smoke_emit_timer -= delta
	if _smoke_emit_timer > 0.0:
		return
	_smoke_emit_timer = interval
	var half: float = ship_size * 0.5
	var puff := {
		"pos": Vector2(randf_range(-half * 0.5, half * 0.5), randf_range(-half * 0.2, half * 0.4)),
		"age": 0.0,
		"life": randf_range(0.7, 1.2),
		"radius": randf_range(ship_size * 0.12, ship_size * 0.20) * (0.7 + damage_pct * 0.6),
		"drift": Vector2(randf_range(-15.0, 15.0), randf_range(-50.0, -25.0)),
	}
	_smoke.append(puff)
	queue_redraw()


func _draw_smoke() -> void:
	for puff in _smoke:
		var k: float = 1.0 - (puff.age / puff.life)
		if k <= 0.0:
			continue
		var r: float = puff.radius * (0.7 + 1.1 * (1.0 - k))
		var a: float = clamp(k, 0.0, 1.0)
		# Light grey on the outside, denser core, hot ember while fresh
		draw_circle(puff.pos, r * 1.7, Color(0.78, 0.78, 0.82, a * 0.55))
		draw_circle(puff.pos, r, Color(0.92, 0.90, 0.90, a * 0.85))
		var ember: float = clamp(k * 1.4 - 0.2, 0.0, 1.0)
		if ember > 0.0:
			draw_circle(puff.pos, r * 0.5, Color(1.0, 0.55, 0.20, ember * 0.9))
			draw_circle(puff.pos, r * 0.25, Color(1.0, 0.95, 0.55, ember))


func _build_ship_sprite() -> void:
	_ship_sprite = Sprite2D.new()
	_ship_sprite.texture = SHIP_TEX_NEUTRAL
	# Sprites are 1024x1024; scale down to ship_size (~64px)
	var tex_size: float = float(_ship_sprite.texture.get_width())
	var s: float = ship_size / tex_size * 1.6   ## 1.6x so the readable ship area roughly equals ship_size
	_ship_sprite.scale = Vector2(s, s)
	add_child(_ship_sprite)


func _update_banking(h_velocity: float) -> void:
	if _ship_sprite == null:
		return
	if h_velocity > BANK_VELOCITY_THRESHOLD:
		_ship_sprite.texture = SHIP_TEX_BANK_RIGHT
	elif h_velocity < -BANK_VELOCITY_THRESHOLD:
		_ship_sprite.texture = SHIP_TEX_BANK_LEFT
	else:
		_ship_sprite.texture = SHIP_TEX_NEUTRAL


func _draw_power_indicator() -> void:
	# Small dots above the ship showing current power level. Dots and spacing
	# shrink slightly with the longer 20-level ladder so the row stays close
	# to the ship's width instead of sprawling across the HUD.
	var dot_size: float = 3.2
	var spacing: float = 7.2
	var total_width: float = (max_power_level - 1) * spacing
	var start_x: float = -total_width * 0.5
	var y: float = -(ship_size * 0.5) - 14.0
	var tier_color: Color = _bullet_tier_for_level(power_level)["color"]
	for i in max_power_level:
		var color: Color = tier_color if i < power_level else Color(1, 1, 1, 0.25)
		draw_circle(Vector2(start_x + i * spacing, y), dot_size, color)


func _draw_torpedo_indicator() -> void:
	# One slot per max torpedo, stacked vertically to the right of the ship.
	# Filled = ammo available, dim outline = empty.
	var icon_size: float = 14.0
	var spacing: float = 4.0
	var x: float = (ship_size * 0.5) + 14.0
	var total_h: float = max_torpedoes * icon_size + (max_torpedoes - 1) * spacing
	var start_y: float = -total_h * 0.5
	for i in max_torpedoes:
		var y: float = start_y + i * (icon_size + spacing)
		var slot := Rect2(x, y, icon_size, icon_size)
		draw_rect(slot, Color(0, 0, 0, 0.5), true)
		draw_rect(slot, Color(1, 1, 1, 0.4), false, 1.0)
		if i < torpedo_count:
			# Mini torpedo silhouette inside the slot
			draw_rect(Rect2(x + 2, y + 2, icon_size - 4, icon_size - 4), Color(1.0, 0.55, 0.1), true)


func _draw_weapon_indicator() -> void:
	# Small icon to the left of the ship showing the current weapon type.
	# PHASER = three vertical bars, BEAM = solid arrow line, MISSILE = capsule.
	var x: float = -(ship_size * 0.5) - 22.0
	var y: float = 0.0
	var box := Rect2(x - 9, y - 11, 18, 22)
	draw_rect(box, Color(0, 0, 0, 0.55), true)
	draw_rect(box, Color(1, 1, 1, 0.4), false, 1.0)
	match weapon_type:
		WeaponType.PHASER:
			# Three vertical pips
			var c := Color(0.55, 1.0, 0.85)
			for i in 3:
				var px: float = x - 4.0 + float(i) * 4.0
				draw_rect(Rect2(px - 0.8, y - 6, 1.8, 12), c, true)
			draw_circle(Vector2(x, y - 8), 1.4, Color(1, 1, 1, 0.95))
		WeaponType.BEAM:
			# Vertical beam line with halo and arrowhead
			var c2 := Color(0.55, 0.95, 1.0)
			draw_rect(Rect2(x - 2.5, y - 8, 5, 16), Color(c2.r, c2.g, c2.b, 0.35), true)
			draw_rect(Rect2(x - 1.0, y - 8, 2, 16), c2, true)
			draw_rect(Rect2(x - 0.4, y - 8, 0.8, 16), Color(1, 1, 1, 0.95), true)
			var arrow := PackedVector2Array([
				Vector2(x - 3, y - 6), Vector2(x + 3, y - 6), Vector2(x, y - 9),
			])
			draw_colored_polygon(arrow, c2)
		WeaponType.MISSILE:
			# Capsule with nose cone and tail flame
			var body := Color(0.85, 0.85, 0.90)
			draw_rect(Rect2(x - 2, y - 5, 4, 10), body, true)
			var nose := PackedVector2Array([
				Vector2(x - 2, y - 5), Vector2(x + 2, y - 5), Vector2(x, y - 8),
			])
			draw_colored_polygon(nose, Color(1.0, 0.55, 0.20))
			# Fins
			draw_rect(Rect2(x - 4, y + 3, 2, 3), Color(0.55, 0.55, 0.62), true)
			draw_rect(Rect2(x + 2, y + 3, 2, 3), Color(0.55, 0.55, 0.62), true)
			# Flame
			var flame := PackedVector2Array([
				Vector2(x - 2, y + 5), Vector2(x + 2, y + 5), Vector2(x, y + 9),
			])
			draw_colored_polygon(flame, Color(1.0, 0.75, 0.20, 0.95))


func _draw_charge_bar() -> void:
	# Charge bar — first bar below the ship (energy). The bar PHYSICALLY
	# extends per purchased energy cell so the upgrade is visible at a
	# glance: 0 cells = base width, +14px per cell up to 4 cells (base + 56).
	# Divider ticks mark each cell's contribution so the player can count.
	var base_width: float = ship_size + 12.0
	var cell_extension: float = 14.0
	var bar_width: float = base_width + cell_extension * float(energy_cells_bought)
	var bar_height: float = 6.0
	var bar_y: float = (ship_size * 0.5) + 10.0
	var bg_rect := Rect2(-bar_width * 0.5, bar_y, bar_width, bar_height)
	draw_rect(bg_rect, Color(0, 0, 0, 0.5), true)
	draw_rect(bg_rect, Color(1, 1, 1, 0.4), false, 1.0)

	var fill_pct: float = clamp(_current_charge / max_charge, 0.0, 1.0)
	var fill_color: Color
	if fill_pct > 0.5:
		fill_color = Color(0.3, 0.9, 1.0)
	elif fill_pct > 0.2:
		fill_color = Color(1.0, 0.7, 0.2)
	else:
		fill_color = Color(1.0, 0.3, 0.2)
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width * fill_pct, bar_height), fill_color, true)

	# Segment dividers — one vertical tick per cell boundary. With 0 cells
	# the bar has no ticks (it's the base); with 4 cells there are 4 ticks
	# splitting the bar into 5 equal "pips".
	if energy_cells_bought > 0:
		var segments: int = energy_cells_bought + 1
		for i in range(1, segments):
			var tick_x: float = -bar_width * 0.5 + bar_width * (float(i) / float(segments))
			draw_rect(
				Rect2(tick_x - 0.6, bar_y, 1.2, bar_height),
				Color(0.05, 0.15, 0.25, 0.85),
				true
			)


func _draw_shield_bar() -> void:
	# Shield bar — between charge and health, blue tint
	var bar_width: float = ship_size + 12.0
	var bar_height: float = 6.0
	var bar_y: float = (ship_size * 0.5) + 20.0
	var bg_rect := Rect2(-bar_width * 0.5, bar_y, bar_width, bar_height)
	draw_rect(bg_rect, Color(0, 0, 0, 0.5), true)
	draw_rect(bg_rect, Color(1, 1, 1, 0.4), false, 1.0)
	var pct: float = clamp(shield / float(max_shield), 0.0, 1.0)
	var fill_color := Color(0.4, 0.75, 1.0)
	# Dim the fill while recharge is paused so the player feels the cooldown
	if _shield_recharge_wait > 0.0:
		fill_color = Color(0.3, 0.5, 0.85)
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width * pct, bar_height), fill_color, true)


func _draw_health_bar() -> void:
	# Health bar — third bar below the ship, stacked under the shield bar
	var bar_width: float = ship_size + 12.0
	var bar_height: float = 6.0
	var bar_y: float = (ship_size * 0.5) + 30.0
	var bg_rect := Rect2(-bar_width * 0.5, bar_y, bar_width, bar_height)
	draw_rect(bg_rect, Color(0, 0, 0, 0.5), true)
	draw_rect(bg_rect, Color(1, 1, 1, 0.4), false, 1.0)

	var pct: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	var fill_color: Color
	if pct > 0.6:
		fill_color = Color(0.3, 1.0, 0.4)
	elif pct > 0.3:
		fill_color = Color(1.0, 0.8, 0.2)
	else:
		fill_color = Color(1.0, 0.3, 0.2)
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width * pct, bar_height), fill_color, true)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ship_size, ship_size)
	shape.shape = rect
	add_child(shape)


func _unhandled_input(event: InputEvent) -> void:
	# --- Touch (mobile) ---
	# On touch devices there's no hover, so finger-down = both move and fire.
	# Only the first finger down steers; a stray second finger is ignored so
	# it can neither hijack movement nor stop the ship when it lifts.
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index != -1 and event.index != _touch_index:
				return
			_touch_index = event.index
			_is_dragging = true
			_is_firing = true
			_update_target(event.position)
		elif event.index == _touch_index:
			_touch_index = -1
			_is_dragging = false
			_is_firing = false
		return
	if event is InputEventScreenDrag:
		if _is_dragging and event.index == _touch_index:
			_update_target(event.position)
		return

	# --- Mouse (desktop) ---
	# Ship tracks mouse position always. Left click = fire only.
	if event is InputEventMouseMotion:
		_mouse_active = true
		_update_target(event.position)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_firing = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_fire_torpedo()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			# Scroll-wheel CLICK cycles to the next weapon. Mobile gets its
			# own control later — for now desktop is the only switch path.
			cycle_weapon()
		return


func _notification(what: int) -> void:
	# A release that happens while paused or unfocused never reaches us, so
	# drop the tracked finger instead of leaving the ship stuck on it.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		_is_dragging = false
		_is_firing = false


func _update_target(finger_pos: Vector2) -> void:
	var t: Vector2 = finger_pos
	t.y -= thumb_offset
	t.x = clamp(t.x, screen_padding, _screen_size.x - screen_padding)
	t.y = clamp(t.y, screen_padding, _screen_size.y - screen_padding)
	_target_position = t


func _process(delta: float) -> void:
	# Thruster tiers were barely noticeable at 1.35x per step — players paid a
	# fortune at the shop and couldn't feel the upgrade. 1.60x gives each tier
	# real bite: T0 16, T1 25.6, T2 41, T3 65.5 — the ship genuinely darts
	# across the screen at max tier, which is what the shop price deserves.
	var effective_follow: float = follow_speed * pow(1.60, float(speed_tier))
	position = position.lerp(_target_position, clamp(effective_follow * delta, 0.0, 1.0))
	# Compute horizontal velocity and pick the matching banking sprite
	var h_vel: float = (position.x - _last_x) / max(delta, 0.0001)
	_last_x = position.x
	_update_banking(h_vel)
	# Flash white during invulnerability frames (modulate the sprite, not _draw)
	if _ship_sprite != null:
		if _i_frame_timer > 0.0 and int(_i_frame_timer * 20.0) % 2 == 0:
			_ship_sprite.modulate = Color(2.0, 2.0, 2.0)
		else:
			_ship_sprite.modulate = Color.WHITE
	if _i_frame_timer > 0.0:
		_i_frame_timer = max(0.0, _i_frame_timer - delta)
	if _torpedo_grace_timer > 0.0:
		_torpedo_grace_timer = max(0.0, _torpedo_grace_timer - delta)
	# Shield break flicker — independent of recharge timing
	if _shield_break_flicker > 0.0:
		_shield_break_flicker = max(0.0, _shield_break_flicker - delta)
	# Shield recharge: wait out the cooldown after a hit, then regenerate
	if _shield_recharge_wait > 0.0:
		_shield_recharge_wait = max(0.0, _shield_recharge_wait - delta)
	elif shield < float(max_shield):
		shield = min(float(max_shield), shield + shield_recharge_per_second * delta)
	_handle_firing(delta)
	_update_smoke(delta)
	queue_redraw()  # Repaint UI elements each frame


func _try_fire_torpedo() -> void:
	if _torpedo_grace_timer > 0.0:
		return
	# If a torpedo is already in flight, a second click manually detonates it
	# (mid-air burst — useful for catching enemies the player wants to hit early).
	var in_flight := get_tree().get_nodes_in_group(&"player_torpedoes")
	for t in in_flight:
		if is_instance_valid(t) and t.has_method("detonate_now"):
			t.detonate_now()
			_torpedo_grace_timer = torpedo_fire_grace
			return
	if torpedo_count <= 0:
		return
	torpedo_count -= 1
	_torpedo_grace_timer = torpedo_fire_grace
	var torpedo: Torpedo = TorpedoScript.new()
	torpedo.position = global_position + Vector2(0, -40)
	get_parent().add_child(torpedo)
	AudioManager.play_sfx(AudioManager.SFX_TORPEDO_FIRE, -4.0)
	AudioManager.haptic_medium()


func _handle_firing(delta: float) -> void:
	_fire_cooldown -= delta
	# Beam follows its own logic — handle and bail
	if weapon_type == WeaponType.BEAM:
		_handle_beam_firing(delta)
		return

	if _is_firing:
		# Choose rate based on whether we still have charge.
		# Missile is intentionally slower than phaser at every tier.
		var has_charge: bool = _current_charge > 0.0
		var rate: float
		if weapon_type == WeaponType.MISSILE:
			# Missiles are punchy but come out a bit faster now — a low-tier
			# single launch should feel snappy enough to rely on, and the
			# higher-tier volleys gradually accelerate into a proper barrage.
			# Phaser base rate was lowered, so the missile multiplier is higher
			# to keep (and slightly improve) the absolute cadence.
			var missile_fast: float = (fast_fire_rate * 0.30) + (power_level - 1) * (fire_rate_bonus_per_level * 0.22)
			# Early-game boost threshold stretched L4 → L5 to proportionally
			# match the new 25-level ladder (was ~20% of ladder; still ~20%).
			# Boost ramps 1.35 -> 1.0 linearly over L5-L9 instead of a step at
			# L6. A shorter L5-L7 ramp still dipped DPS at L6-L7; over four
			# levels the per-missile damage growth outpaces the rate loss, so
			# no missile pickup lowers DPS.
			missile_fast *= lerpf(1.35, 1.0, clampf((power_level - 5) / 4.0, 0.0, 1.0))
			rate = missile_fast if has_charge else (slow_fire_rate * 0.45)
		else:
			var effective_fast_rate: float = fast_fire_rate + (power_level - 1) * fire_rate_bonus_per_level
			rate = effective_fast_rate if has_charge else slow_fire_rate

		if _fire_cooldown <= 0.0:
			_fire_cooldown = 1.0 / rate
			if weapon_type == WeaponType.MISSILE:
				_fire_missile_pattern()
				AudioManager.play_sfx(AudioManager.SFX_MISSILE_LAUNCH, -4.0)
			else:
				_fire_bullet()
				AudioManager.play_player_shot()

		# Drain charge while firing — higher firepower costs slightly more energy.
		# Phaser gets a gentler scaling (0.08 → 0.04 per level) plus a 0.80
		# base multiplier so sustained fire actually produces more shots per
		# charge pool at every tier, not just at L1. Math check:
		#   L1:  0.80 * 50 = 40/sec drain → pool lasts 2.5s × 6.9 shots = ~17 shots
		#   L10: 0.80 * 1.36 * 50 = 54/sec → lasts 1.85s × 12.5 = ~23 shots
		#   L20: 0.80 * 1.76 * 50 = 70/sec → lasts 1.43s × 17.7 = ~25 shots
		# (Before this change it was ~14 shots per pool at every level.)
		# Missile keeps the original 1.0 + L*0.08 scaling — it's a burst weapon,
		# not a sustained one, so its drain curve was fine.
		if has_charge:
			var drain_mul: float
			if weapon_type == WeaponType.MISSILE:
				# 0.08 → 0.063 to keep L25 drain ≈ old L20 (2.52×).
				drain_mul = 1.0 + float(power_level - 1) * 0.063
			else:
				# 0.04 → 0.032 to keep L25 drain ≈ old L20 (0.80 × 1.76 = 1.41×).
				drain_mul = 0.80 * (1.0 + float(power_level - 1) * 0.032)
			_current_charge = max(0.0, _current_charge - charge_drain_per_second * drain_mul * delta)
	else:
		# Missile recharges slower so its homing advantage costs more downtime
		var regen: float = recharge_per_second
		if weapon_type == WeaponType.MISSILE:
			regen *= 0.65
		_current_charge = min(max_charge, _current_charge + regen * delta)
		if _fire_cooldown < 0.0:
			_fire_cooldown = 0.0


## Beam: continuous fire while button held, no per-shot cooldown.
## Drains charge ~3x faster than phaser; auto-cuts off if charge hits zero so
## the player gets feedback to release.
func _handle_beam_firing(delta: float) -> void:
	# How many parallel beams should be active for this power level. Mirrors the
	# phaser bullet-count ramp so beam upgrades feel as impactful as phaser ones.
	var desired_count: int = _beam_count_for_level(power_level)
	# Lazily build beams up to the desired count, reusing existing instances
	while _beams.size() < desired_count:
		var b: Beam = BeamScript.new()
		add_child(b)
		_beams.append(b)
	# If we somehow have too many (e.g. weapon_type was switched and back), trim
	while _beams.size() > desired_count:
		var dead: Beam = _beams.pop_back()
		if is_instance_valid(dead):
			dead.queue_free()

	# Per-power tier (color/damage class) and per-beam stats. Beams compensate
	# for having no side spread by being WIDE — at max power the central beam
	# is wider than the player ship itself.
	var tier := _bullet_tier_for_level(power_level)
	# DPS dropped from 32+L*6.5 → 22+L*4.5 (~30% nerf). Beam was still trivializing
	# stages even after the area cut.
	# Round-4 retune (user-directed +20% DPS): 28+L*5.8 → 34+L*7.0 across the
	# ladder. Still under the original 32+L*6.5 at low levels but overtakes it
	# past L2, matching user's "stronger but not broken" target.
	# Slope dropped from 7.0 → 5.6 so L25 DPS ≈ old L20 (34 + 20×7 = 174).
	var per_beam_dps: float = 34.0 + float(power_level) * 5.6
	# Width nudged back up a bit (7.8+L*2.8 → 9.0+L*3.2) so swept beams catch
	# more dodgers without becoming a wall again.
	# Slope 3.2 → 2.56 so L25 width ≈ old L20 (9 + 20×3.2 = 73 px).
	var width: float = 9.0 + float(power_level) * 2.56
	var offsets: Array = _beam_offsets_for_count(desired_count)

	# Cutoff loosened from 30% → 22% so the player isn't constantly locked
	# out between waves — they still hit empty if they hold the trigger but
	# short bursts no longer stall on the gate.
	var charge_pct: float = _current_charge / max_charge if max_charge > 0.0 else 0.0
	var want_active: bool = _is_firing and charge_pct >= 0.22
	for i in _beams.size():
		var beam: Beam = _beams[i]
		beam.position.x = offsets[i]
		beam.beam_color = tier["color"]
		beam.dps = per_beam_dps
		beam.beam_width = width
		# Hit column widened slightly (16/12 → 18/14) so the beam lands the
		# hits its visual already implies. Still tighter than the OG 22/17.
		beam.hit_tolerance = 18.0 if i == 0 else 14.0
		beam.active = want_active

	if want_active:
		# Beam start sound — only fires once per activation, retriggered when the
		# player releases and re-fires. Polled via _beam_audio_active flag.
		if not _beam_audio_active:
			AudioManager.play_sfx(AudioManager.SFX_BEAM, -4.0)
			_beam_audio_active = true
		# Total drain scales with beam COUNT (more beams = more energy) plus the
		# existing per-power multiplier so high-tier beams cost meaningfully more.
		# Base drain reduced 33% from the previous tuning so committing to beam
		# weapons feels sustainable.
		# Per-level drain scaling pulled back from 0.08 → 0.05 so top-end
		# beam loadouts (L15+) don't drain dramatically faster than the base
		# rate. At L20 this drops total drain from 2.52× to 1.95× — about a
		# 23% cost cut where the player complained the most, unchanged at L1.
		# 0.05 → 0.04 so L25 beam drain ≈ old L20 (1 + 19×0.05 = 1.95×).
		var beam_drain_mul: float = 1.0 + float(power_level - 1) * 0.04
		var count_mul: float = 1.0 + float(desired_count - 1) * 0.55
		# Drain lowered another 10% (1.85× → 1.67×) per user tuning. Still
		# thirstier than phaser (1.0×) so beam commitment has a real cost,
		# but the pool now lasts through a full wave more comfortably.
		_current_charge = max(0.0, _current_charge - charge_drain_per_second * 1.67 * beam_drain_mul * count_mul * delta)
	else:
		_beam_audio_active = false
		# Regen restored to parity (was 0.85× of phaser) so committing to beam
		# doesn't punish you on the recovery side too — the drain rate already
		# carries the cost.
		_current_charge = min(max_charge, _current_charge + recharge_per_second * 1.0 * delta)


## Phaser-style ramp: 1 beam → 5 beams across the power ladder.
## Stretched for the 25-level ladder so the five-beam loadout unlocks at
## L20+ (was L16+ on the old 20-ladder). Thresholds slid proportionally.
func _beam_count_for_level(level: int) -> int:
	if level <= 4:
		return 1
	elif level <= 8:
		return 2
	elif level <= 13:
		return 3
	elif level <= 19:
		return 4
	else:
		return 5


## Symmetric x-offsets for N parallel beams. Center beam stays at x=0; flankers
## sit at increasingly wide gaps so a 5-beam loadout sweeps a real column.
func _beam_offsets_for_count(count: int) -> Array:
	match count:
		1:
			return [0.0]
		2:
			return [-14.0, 14.0]
		3:
			return [0.0, -22.0, 22.0]
		4:
			return [-10.0, 10.0, -28.0, 28.0]
		_:
			return [0.0, -16.0, 16.0, -32.0, 32.0]


## Spawn 1-3 missiles per shot depending on power_level. Missiles are slow,
## non-homing, high-damage projectiles — much rarer than phaser bullets so the
## salvo feels weighty rather than overwhelming.
func _fire_missile_pattern() -> void:
	# Missiles fire slowly and (at low tiers) one at a time, so each shot has
	# to land hard to feel worth waiting for. Damage scales aggressively with
	# power_level so a fully-upgraded missile loadout decisively beats phaser
	# DPS in trade for the slower cadence.
	# Damage per missile — scales gentler across the longer 20-level ladder so
	# the L20 ceiling lands near the old L16 peak instead of overshooting it.
	# Old: 5 + round(power*1.5) + tier*2  →  L16 = 35
	# New: 5 + round(power*1.2) + tier*2  →  L20 ≈ 35
	var tier := _bullet_tier_for_level(power_level)
	# 1.45 → 1.16 so L25 missile damage ≈ old L20 (6 + round(20×1.45) = 35 base).
	var dmg: int = 6 + int(round(power_level * 1.16)) + int(tier["damage"]) * 2
	# Missile count ramp — stretched to 5 tiers across the new 25-level
	# ladder. The 5-missile barrage now shows up at L21+ (was L17+),
	# preserving the "feels maxed" moment at the top of the climb.
	if power_level <= 3:
		_spawn_missile(Vector2(0, -36), Vector2.UP, dmg)
	elif power_level <= 8:
		_spawn_missile(Vector2(-10, -34), Vector2.UP, dmg)
		_spawn_missile(Vector2(10, -34), Vector2.UP, dmg)
	elif power_level <= 14:
		_spawn_missile(Vector2(0, -40), Vector2.UP, dmg)
		_spawn_missile(Vector2(-12, -32), Vector2.UP, dmg)
		_spawn_missile(Vector2(12, -32), Vector2.UP, dmg)
	elif power_level <= 20:
		_spawn_missile(Vector2(-6, -40), Vector2.UP, dmg)
		_spawn_missile(Vector2(6, -40), Vector2.UP, dmg)
		_spawn_missile(Vector2(-18, -30), Vector2.UP, dmg)
		_spawn_missile(Vector2(18, -30), Vector2.UP, dmg)
	else:
		_spawn_missile(Vector2(0, -42), Vector2.UP, dmg)
		_spawn_missile(Vector2(-12, -36), Vector2.UP, dmg)
		_spawn_missile(Vector2(12, -36), Vector2.UP, dmg)
		_spawn_missile(Vector2(-22, -28), Vector2.UP, dmg)
		_spawn_missile(Vector2(22, -28), Vector2.UP, dmg)


func _spawn_missile(local_offset: Vector2, dir: Vector2, dmg: int) -> void:
	var m: Missile = MissileScript.new()
	m.position = global_position + local_offset
	m.direction = dir
	m.damage = dmg
	get_parent().add_child(m)


## Spawn a friendly Sidekick companion. If one already exists, just refresh
## its loadout (heal + re-pick weapon to contrast the player's current weapon)
## so the pickup is never wasted.
func _grant_sidekick() -> void:
	var SidekickScript := preload("res://scripts/Sidekick.gd")
	var existing := get_tree().get_first_node_in_group(&"sidekick")
	if existing != null and is_instance_valid(existing):
		if "hp" in existing and "max_hp" in existing:
			existing.hp = existing.max_hp
		if "shield" in existing and "max_shield" in existing:
			existing.shield = float(existing.max_shield)
		if existing.has_method("_choose_weapon_for_player"):
			existing._choose_weapon_for_player()
		if existing.has_method("_inherit_power_from_player"):
			existing._inherit_power_from_player()
		return
	var sk: Area2D = SidekickScript.new()
	sk.position = global_position + Vector2(80, 18)
	get_parent().add_child(sk)


## Cycle to the next weapon type. Called by middle-mouse-button click on
## desktop (see _unhandled_input). Mobile control TBD.
func cycle_weapon() -> void:
	# Cancel any active beams so the visual doesn't linger after we switch
	for b in _beams:
		if is_instance_valid(b):
			b.active = false
	weapon_type = (weapon_type + 1) % 3
	_refresh_derived_power()
	# Reset cooldown so the new weapon's first shot is immediate instead of
	# inheriting whatever the previous weapon was mid-cycle on.
	_fire_cooldown = 0.0
	if OS.is_debug_build():
		print("Weapon switched to ", weapon_type, " (level ", power_level, ")")
	AudioManager.play_sfx(AudioManager.SFX_POWERUP_ZAP, -3.0)
	AudioManager.haptic_medium()


## Sync the derived `power_level` field with whichever slot is currently
## active. Called any time weapon_type or weapon_levels changes — keeps the
## existing fire/draw code (which reads power_level directly) in sync without
## a property setter dance.
func _refresh_derived_power() -> void:
	var lvl: int = int(weapon_levels.get(weapon_type, 1))
	power_level = clamp(lvl, 1, max_power_level)


## Bump a specific weapon's slot by one (capped at max). Called by the per-
## weapon power pickups. Refreshes the derived power_level afterward so if
## the bumped slot happens to be the active one, fire rates immediately
## reflect the new level.
func add_power_to_weapon(wt: int) -> void:
	if not weapon_levels.has(wt):
		return
	var current: int = int(weapon_levels[wt])
	weapon_levels[wt] = min(max_power_level, current + 1)
	_refresh_derived_power()


## Restore weapon_levels from a saved Dictionary (carry/respawn). Falls back
## to populating every slot with the legacy single power_level value if the
## dict is empty (old saves) so we never end up with a slot at zero.
func _load_weapon_levels(saved: Dictionary, fallback_level: int) -> void:
	var fallback: int = clamp(fallback_level, 1, max_power_level)
	for wt in [WeaponType.PHASER, WeaponType.BEAM, WeaponType.MISSILE]:
		if saved.has(wt):
			weapon_levels[wt] = clamp(int(saved[wt]), 1, max_power_level)
		elif saved.has(str(wt)):
			# Dictionary keys may have been serialized as strings somewhere
			weapon_levels[wt] = clamp(int(saved[str(wt)]), 1, max_power_level)
		else:
			weapon_levels[wt] = fallback


func _fire_bullet() -> void:
	# Multi-shot pattern based on power_level. Stretched across 20 levels so
	# the climb to max feels gradual — most tiers now span 2 levels each and
	# the maximum 8-bullet fan doesn't unlock until L17+.
	if power_level <= 1:
		_spawn_bullet(Vector2(0, -36), Vector2.UP)
	elif power_level <= 3:
		# L2-3 — two parallel
		_spawn_bullet(Vector2(-14, -32), Vector2.UP)
		_spawn_bullet(Vector2(14, -32), Vector2.UP)
	elif power_level <= 5:
		# L4-5 — pure forward triple
		_spawn_bullet(Vector2(0, -36), Vector2.UP)
		_spawn_bullet(Vector2(-16, -32), Vector2.UP)
		_spawn_bullet(Vector2(16, -32), Vector2.UP)
	elif power_level <= 7:
		# L6-7 — pure forward quad, last "all-forward" tier
		_spawn_bullet(Vector2(-6, -36), Vector2.UP)
		_spawn_bullet(Vector2(6, -36), Vector2.UP)
		_spawn_bullet(Vector2(-20, -32), Vector2.UP)
		_spawn_bullet(Vector2(20, -32), Vector2.UP)
	elif power_level <= 8:
		# L8 — forward pair + angled pair introduces side coverage. Was 3
		# bullets, which dropped volley damage below L6-7's 4.
		_spawn_bullet(Vector2(-6, -36), Vector2.UP)
		_spawn_bullet(Vector2(6, -36), Vector2.UP)
		_spawn_bullet(Vector2(-18, -30), Vector2.UP.rotated(-0.18))
		_spawn_bullet(Vector2(18, -30), Vector2.UP.rotated(0.18))
	elif power_level <= 10:
		# L9-10 — 4-bullet spread
		_spawn_bullet(Vector2(-10, -36), Vector2.UP)
		_spawn_bullet(Vector2(10, -36), Vector2.UP)
		_spawn_bullet(Vector2(-22, -28), Vector2.UP.rotated(-0.22))
		_spawn_bullet(Vector2(22, -28), Vector2.UP.rotated(0.22))
	elif power_level <= 12:
		# L11-12 — 5-bullet spread
		_spawn_bullet(Vector2(0, -36), Vector2.UP)
		_spawn_bullet(Vector2(-14, -34), Vector2.UP.rotated(-0.12))
		_spawn_bullet(Vector2(14, -34), Vector2.UP.rotated(0.12))
		_spawn_bullet(Vector2(-26, -28), Vector2.UP.rotated(-0.28))
		_spawn_bullet(Vector2(26, -28), Vector2.UP.rotated(0.28))
	elif power_level <= 14:
		# L13-14 — 6-bullet spread
		_spawn_bullet(Vector2(-8, -36), Vector2.UP)
		_spawn_bullet(Vector2(8, -36), Vector2.UP)
		_spawn_bullet(Vector2(-18, -32), Vector2.UP.rotated(-0.16))
		_spawn_bullet(Vector2(18, -32), Vector2.UP.rotated(0.16))
		_spawn_bullet(Vector2(-28, -26), Vector2.UP.rotated(-0.32))
		_spawn_bullet(Vector2(28, -26), Vector2.UP.rotated(0.32))
	elif power_level <= 16:
		# L15-16 — 7-bullet spread
		_spawn_bullet(Vector2(0, -38), Vector2.UP)
		_spawn_bullet(Vector2(-12, -34), Vector2.UP.rotated(-0.10))
		_spawn_bullet(Vector2(12, -34), Vector2.UP.rotated(0.10))
		_spawn_bullet(Vector2(-22, -30), Vector2.UP.rotated(-0.22))
		_spawn_bullet(Vector2(22, -30), Vector2.UP.rotated(0.22))
		_spawn_bullet(Vector2(-30, -24), Vector2.UP.rotated(-0.38))
		_spawn_bullet(Vector2(30, -24), Vector2.UP.rotated(0.38))
	else:
		# L17+ — maximum spread, 8 bullets across a wide arc
		_spawn_bullet(Vector2(-6, -38), Vector2.UP)
		_spawn_bullet(Vector2(6, -38), Vector2.UP)
		_spawn_bullet(Vector2(-16, -34), Vector2.UP.rotated(-0.12))
		_spawn_bullet(Vector2(16, -34), Vector2.UP.rotated(0.12))
		_spawn_bullet(Vector2(-26, -30), Vector2.UP.rotated(-0.26))
		_spawn_bullet(Vector2(26, -30), Vector2.UP.rotated(0.26))
		_spawn_bullet(Vector2(-32, -24), Vector2.UP.rotated(-0.42))
		_spawn_bullet(Vector2(32, -24), Vector2.UP.rotated(0.42))


func _spawn_bullet(local_offset: Vector2, dir: Vector2) -> void:
	var tier := _bullet_tier_for_level(power_level)
	var bullet: Area2D = BulletScript.new()
	bullet.position = global_position + local_offset
	bullet.direction = dir
	bullet.bullet_color = tier["color"]
	bullet.damage = int(tier["damage"])
	# Add to parent (the Main scene), not to self — bullets must not move with the ship
	get_parent().add_child(bullet)


## Maps a power level to a weapon tier { color, damage }.
## Pattern saturates at L9, but tier keeps climbing so high-level pickups still feel meaningful.
func _bullet_tier_for_level(level: int) -> Dictionary:
	# Damage ramp is intentionally flat — most of the power-up benefit comes from
	# bullet COUNT, not per-shot damage. Otherwise a few power-ups make the player
	# one-shot everything. Top tier caps at 3.
	# Rescaled for 25 power levels — tier thresholds stretched proportionally
	# from the 20-level version. Top "white-hot" tier now arrives at L24
	# instead of L19, giving the player five more climb steps before peak.
	if level <= 5:
		# Cyan tier — bumped from 1 → 2 damage so the early phaser actually
		# chips meaningfully into grunts/dodgers before the player has any
		# weapon-specific pickups. Doubles per-shot punch at the floor.
		return {"color": Color(0.55, 0.95, 1.00), "damage": 2}    # cyan
	elif level <= 10:
		# Green was 1 → 2: per-shot damage must never drop on a pickup
		# (L5 3x2=6 per volley fell to L6 4x1=4).
		return {"color": Color(0.55, 1.00, 0.55), "damage": 2}    # green
	elif level <= 15:
		return {"color": Color(1.00, 0.95, 0.35), "damage": 2}    # yellow
	elif level <= 19:
		return {"color": Color(1.00, 0.55, 0.20), "damage": 2}    # orange
	elif level <= 23:
		return {"color": Color(1.00, 0.35, 0.65), "damage": 3}    # pink
	else:
		return {"color": Color(1.00, 1.00, 1.00), "damage": 3}    # white-hot
