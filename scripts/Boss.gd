extends Area2D
class_name Boss
## Heavy mid-level encounter. Bosses are fully procedural — no sprite assets, so
## there is never a white-background problem to scrub. They share the &"enemies"
## group so the player's existing weapons / score / drop logic all "just work".
##
## Each Boss type has its own _draw routine, attack pattern, HP pool, and
## drop loadout. Defeating a boss showers the player with goodies (multiple
## power-ups + cash + a torpedo) so the run feels meaningfully rewarded.

enum Type { BOSS1, BOSS2, BOSS3, BOSS4, BOSS5, FINAL }

const EnemyBulletScript := preload("res://scripts/EnemyBullet.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const EnemyExplosionScript := preload("res://scripts/EnemyExplosion.gd")
const ScorePopupScript := preload("res://scripts/ScorePopup.gd")

# Boss textures — backgrounds already stripped by removewhite.ps1
const TEX_BOSS1 := preload("res://assets/sprites/boss1.png")
const TEX_BOSS2 := preload("res://assets/sprites/boss2.png")
const TEX_BOSS3 := preload("res://assets/sprites/boss3.png")
const TEX_BOSS4 := preload("res://assets/sprites/boss4.png")
const TEX_BOSS5 := preload("res://assets/sprites/boss5.png")
const TEX_BOSSF := preload("res://assets/sprites/finalboss.png")

@export var type: Type = Type.BOSS1

# Configured per-type in _configure()
var max_hp: int = 100
var hp: int = 100
var boss_size: float = 220.0
var primary_color: Color = Color(0.85, 0.20, 0.25)
var accent_color: Color = Color(1.0, 0.85, 0.30)
var armor: int = 1   ## Subtracted from incoming damage (min 1 dmg always lands)
var contact_damage: int = 12
var reward: int = 500
var boss_name: String = "Boss"

# Movement
var _viewport_size: Vector2
var _time: float = 0.0
var _entry_done: bool = false
var _target_y: float = 200.0
var _drift_speed: float = 110.0
var _drift_dir: int = 1

# Firing — bosses have multiple alternating attack patterns
var _fire_timer: float = 1.5
var _pattern_idx: int = 0
var _phase: int = 0   ## 0=full HP, 1=below 66%, 2=below 33% — fire faster

# Visual
var _hit_flash: float = 0.0
var _smoke: Array = []
var _smoke_emit_timer: float = 0.0

# HP bar — bosses get a health bar at top of screen so the player feels progress
var _hp_bar: ColorRect = null
var _hp_bar_bg: ColorRect = null
var _hp_label: Label = null

# Sprite-based body. When set, the procedural _draw_bossN routine is skipped
# and the texture is shown instead. Hit flash modulates the sprite directly.
var _sprite: Sprite2D = null


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_configure()
	_build_collision()
	_build_sprite()
	_build_hp_bar()
	add_to_group(&"enemies")
	add_to_group(&"bosses")
	z_index = 3
	area_entered.connect(_on_area_entered)
	queue_redraw()


## Pick the texture for this boss type and add a Sprite2D scaled so the
## largest dimension matches boss_size. Falls back to procedural _draw if
## no texture is configured.
func _build_sprite() -> void:
	var tex: Texture2D = null
	match type:
		Type.BOSS1: tex = TEX_BOSS1
		Type.BOSS2: tex = TEX_BOSS2
		Type.BOSS3: tex = TEX_BOSS3
		Type.BOSS4: tex = TEX_BOSS4
		Type.BOSS5: tex = TEX_BOSS5
		Type.FINAL: tex = TEX_BOSSF
	if tex == null:
		return
	_sprite = Sprite2D.new()
	# boss2.png's opaque background is baked out to alpha offline
	# (scripts/tools/strip_backgrounds.gd), so every type uses its PNG as is.
	_sprite.texture = tex
	# Draw the sprite BEHIND the parent so the parent's _draw smoke/effects
	# layer on top of the boss body rather than getting covered by it.
	_sprite.show_behind_parent = true
	var src: Vector2 = tex.get_size()
	if src.x > 0 and src.y > 0:
		var max_side: float = max(src.x, src.y)
		var s: float = boss_size / max_side
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)


func _configure() -> void:
	# Base stats per boss type. Final boss is the wall — everything else
	# scales between mini-boss (Boss1) and serious encounter (Boss5).
	match type:
		Type.BOSS1:
			boss_name = "HORNET QUEEN"
			max_hp = 320
			boss_size = 320.0
			primary_color = Color(1.0, 0.55, 0.20)
			accent_color = Color(1.0, 0.95, 0.40)
			armor = 2
			contact_damage = 14
			reward = 400
			_drift_speed = 140.0
		Type.BOSS2:
			boss_name = "IRON TORTOISE"
			max_hp = 560
			boss_size = 360.0
			primary_color = Color(0.45, 0.50, 0.55)
			accent_color = Color(0.90, 0.30, 0.20)
			armor = 4
			contact_damage = 18
			reward = 700
			_drift_speed = 80.0
		Type.BOSS3:
			boss_name = "HIVE MOTHER"
			max_hp = 780
			boss_size = 380.0
			primary_color = Color(0.40, 0.85, 0.35)
			accent_color = Color(0.90, 1.0, 0.50)
			armor = 4
			contact_damage = 18
			reward = 900
			_drift_speed = 110.0
		Type.BOSS4:
			boss_name = "CRYSTAL PRISM"
			max_hp = 1050
			boss_size = 360.0
			primary_color = Color(0.65, 0.80, 1.0)
			accent_color = Color(1.0, 0.85, 1.0)
			armor = 5
			contact_damage = 20
			reward = 1200
			_drift_speed = 130.0
		Type.BOSS5:
			boss_name = "VOID REAPER"
			max_hp = 1350
			boss_size = 400.0
			primary_color = Color(0.55, 0.20, 0.85)
			accent_color = Color(1.0, 0.40, 0.95)
			armor = 6
			contact_damage = 22
			reward = 1600
			_drift_speed = 150.0
		Type.FINAL:
			boss_name = "THE SKYBREAKER"
			max_hp = 2200
			boss_size = 480.0
			primary_color = Color(1.0, 0.30, 0.25)
			accent_color = Color(1.0, 0.95, 0.40)
			armor = 8
			contact_damage = 26
			reward = 3000
			_drift_speed = 120.0
	# Scale meaningfully by current level so a boss met later is much meaner
	var lvl: int = clamp(GameState.current_level, 1, GameState.MAX_LEVEL)
	var t: float = float(lvl - 1) / float(GameState.MAX_LEVEL - 1)
	max_hp = int(round(float(max_hp) * lerp(1.0, 1.60, t)))
	hp = max_hp


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(boss_size * 0.85, boss_size * 0.75)
	shape.shape = rect
	add_child(shape)


func _build_hp_bar() -> void:
	# Background
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.color = Color(0, 0, 0, 0.65)
	_hp_bar_bg.size = Vector2(_viewport_size.x * 0.7, 22)
	_hp_bar_bg.position = Vector2(_viewport_size.x * 0.15, 150)
	_hp_bar_bg.top_level = true
	add_child(_hp_bar_bg)
	# Fill
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color(0.95, 0.25, 0.25)
	_hp_bar.size = Vector2(_viewport_size.x * 0.7, 22)
	_hp_bar.position = Vector2(_viewport_size.x * 0.15, 150)
	_hp_bar.top_level = true
	add_child(_hp_bar)
	# Label
	_hp_label = Label.new()
	_hp_label.text = boss_name
	_hp_label.add_theme_font_size_override("font_size", 24)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 4)
	_hp_label.size = Vector2(_viewport_size.x, 30)
	_hp_label.position = Vector2(0, 118)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.top_level = true
	add_child(_hp_label)


func _process(delta: float) -> void:
	_time += delta
	_update_hit_flash(delta)
	_update_movement(delta)
	_update_smoke(delta)
	_update_phase()
	_update_firing(delta)
	_update_hp_bar()
	queue_redraw()


func _update_hit_flash(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = max(0.0, _hit_flash - delta * 6.0)


func _update_movement(delta: float) -> void:
	# Entry: descend to fighting position, then drift L/R
	if not _entry_done:
		position.y += 130.0 * delta
		if position.y >= _target_y:
			position.y = _target_y
			_entry_done = true
		return
	# Drift sideways, bounce off the screen edges
	position.x += _drift_speed * delta * float(_drift_dir)
	# Slow vertical bob
	position.y = _target_y + sin(_time * 1.4) * 18.0
	var margin: float = boss_size * 0.5 + 20.0
	if position.x < margin:
		position.x = margin
		_drift_dir = 1
	elif position.x > _viewport_size.x - margin:
		position.x = _viewport_size.x - margin
		_drift_dir = -1


func _update_phase() -> void:
	var pct: float = float(hp) / float(max_hp)
	var new_phase: int = 0
	if pct < 0.33:
		new_phase = 2
	elif pct < 0.66:
		new_phase = 1
	if new_phase != _phase:
		_phase = new_phase
		# Phase change kicks off an immediate volley
		_fire_timer = 0.4


func _update_firing(delta: float) -> void:
	if not _entry_done:
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	# Cycle through this boss's available patterns. Phase shortens cooldowns.
	# Bosses fire much more aggressively now — base interval roughly halved.
	var base_cd: float = 0.85
	if _phase == 1:
		base_cd = 0.55
	elif _phase == 2:
		base_cd = 0.35
	_fire_timer = base_cd
	_pattern_idx = (_pattern_idx + 1) % 3
	match type:
		Type.BOSS1:
			_pattern_aimed_burst() if _pattern_idx == 0 else _pattern_spread()
		Type.BOSS2:
			_pattern_shell_volley() if _pattern_idx == 0 else _pattern_fan()
		Type.BOSS3:
			if _pattern_idx == 0:
				_pattern_radial(8)
			elif _pattern_idx == 1:
				_pattern_aimed_burst()
			else:
				_pattern_spread()
		Type.BOSS4:
			if _pattern_idx == 0:
				_pattern_radial(12)
			elif _pattern_idx == 1:
				_pattern_spiral()
			else:
				_pattern_aimed_burst()
		Type.BOSS5:
			if _pattern_idx == 0:
				_pattern_spiral()
			elif _pattern_idx == 1:
				_pattern_radial(10)
			else:
				_pattern_fan()
		Type.FINAL:
			if _pattern_idx == 0:
				_pattern_radial(16)
			elif _pattern_idx == 1:
				_pattern_spiral()
			else:
				_pattern_shell_volley()


# --- Attack patterns ---

func _pattern_aimed_burst() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	var dir: Vector2 = (player.global_position - global_position).normalized()
	for off in [-0.18, 0.0, 0.18]:
		_spawn_bullet(dir.rotated(off), 5, EnemyBullet.Style.DART)


func _pattern_spread() -> void:
	for off in [-0.45, -0.22, 0.0, 0.22, 0.45]:
		_spawn_bullet(Vector2.DOWN.rotated(off), 6, EnemyBullet.Style.SHELL)


func _pattern_shell_volley() -> void:
	for off in [-0.30, -0.10, 0.10, 0.30]:
		_spawn_bullet(Vector2.DOWN.rotated(off), 7, EnemyBullet.Style.SHELL)


func _pattern_fan() -> void:
	for off in [-0.55, -0.33, -0.11, 0.11, 0.33, 0.55]:
		_spawn_bullet(Vector2.DOWN.rotated(off), 5, EnemyBullet.Style.PLASMA)


func _pattern_radial(count: int) -> void:
	for i in count:
		var ang: float = (TAU / float(count)) * float(i) + _time * 0.4
		_spawn_bullet(Vector2.RIGHT.rotated(ang), 5, EnemyBullet.Style.ORB)


func _pattern_spiral() -> void:
	# Tight rotating spiral — fewer bullets, but rotates each volley for sweep
	var arms: int = 5
	var base_ang: float = _time * 1.5
	for i in arms:
		var ang: float = base_ang + (TAU / float(arms)) * float(i)
		_spawn_bullet(Vector2.RIGHT.rotated(ang), 4, EnemyBullet.Style.SPARK)


func _spawn_bullet(dir: Vector2, dmg: int, style: int) -> void:
	var bullet: EnemyBullet = EnemyBulletScript.new()
	bullet.position = global_position + dir * (boss_size * 0.45)
	bullet.direction = dir
	bullet.damage = dmg
	bullet.style = style
	bullet.from_boss = true   # Beam can't vaporize boss fire
	get_parent().add_child(bullet)


# --- Damage / death ---

func take_damage(amount: int) -> void:
	# Armor reduces incoming damage but minimum 1 still chips through
	var net: int = max(1, amount - armor)
	hp -= net
	_hit_flash = 1.0
	if hp <= 0:
		_die()


func _die() -> void:
	GameState.add_score(reward)
	GameState.mission_kills += 1
	# Big multi-stage explosion
	for i in 5:
		var burst: EnemyExplosion = EnemyExplosionScript.new()
		burst.position = global_position + Vector2(randf_range(-60, 60), randf_range(-40, 40))
		burst.burst_radius = boss_size * 0.55
		burst.spark_count = 22
		burst.debris_count = 12
		burst.smoke_count = 10
		burst.base_color = primary_color
		get_parent().add_child(burst)
	# Score popup — extra big
	var popup: ScorePopup = ScorePopupScript.new()
	popup.amount = reward
	popup.position = global_position + Vector2(0, -boss_size * 0.4)
	get_parent().add_child(popup)
	# Reward shower — multiple drops so the player feels it
	# Boss reward shower — one POWER pickup of EACH weapon type so the kill
	# meaningfully levels the player regardless of which weapon they're
	# currently using. WEAPON_CHANGE pickup is gone (player switches manually
	# now via middle mouse button).
	_drop(Pickup.Type.HEALTH_FULL, Vector2(-60, 20))
	_drop(Pickup.Type.POWER_PHASER, Vector2(-20, 20))
	_drop(Pickup.Type.POWER_BEAM, Vector2(20, 20))
	_drop(Pickup.Type.POWER_MISSILE, Vector2(40, -10))
	_drop(Pickup.Type.TORPEDO, Vector2(60, 20))
	_drop_money(120, Vector2(20, 40))
	_drop_money(120, Vector2(-40, 40))
	EventBus.screen_shake_requested.emit(18.0, 0.8)
	# Cleanup HUD bits
	if _hp_bar != null: _hp_bar.queue_free()
	if _hp_bar_bg != null: _hp_bar_bg.queue_free()
	if _hp_label != null: _hp_label.queue_free()
	queue_free()


func _drop(t: int, off: Vector2) -> void:
	var pickup: Pickup = PickupScript.new()
	pickup.type = t
	pickup.position = global_position + off
	# Deferred: drops usually spawn from inside an area_entered callback
	# (bullet / ram kill), where adding an Area2D trips "Can't change this
	# state while flushing queries".
	get_parent().add_child.call_deferred(pickup)


func _drop_money(value: int, off: Vector2) -> void:
	var pickup: Pickup = PickupScript.new()
	pickup.type = Pickup.Type.MONEY
	pickup.money_value = value
	pickup.position = global_position + off
	# Deferred: drops usually spawn from inside an area_entered callback
	# (bullet / ram kill), where adding an Area2D trips "Can't change this
	# state while flushing queries".
	get_parent().add_child.call_deferred(pickup)


func _on_area_entered(_area: Area2D) -> void:
	pass


# --- HUD bar ---

func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	var pct: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_bar.size.x = (_viewport_size.x * 0.7) * pct
	# Color shifts red→orange as boss is hurt
	if pct > 0.66:
		_hp_bar.color = Color(0.95, 0.25, 0.25)
	elif pct > 0.33:
		_hp_bar.color = Color(1.0, 0.55, 0.20)
	else:
		_hp_bar.color = Color(1.0, 0.85, 0.20)


# --- Smoke (reuses Enemy's idea but bigger) ---

func _update_smoke(delta: float) -> void:
	if not _smoke.is_empty():
		var alive: Array = []
		for puff in _smoke:
			puff.age += delta
			if puff.age < puff.life:
				puff.pos += puff.drift * delta
				alive.append(puff)
		_smoke = alive
	if hp <= 0 or hp >= max_hp:
		return
	var damage_pct: float = 1.0 - (float(hp) / float(max_hp))
	var interval: float = lerp(0.20, 0.05, damage_pct)
	_smoke_emit_timer -= delta
	if _smoke_emit_timer > 0.0:
		return
	_smoke_emit_timer = interval
	var half: float = boss_size * 0.4
	_smoke.append({
		"pos": Vector2(randf_range(-half, half), randf_range(-half * 0.6, half * 0.4)),
		"age": 0.0,
		"life": randf_range(0.8, 1.4),
		"radius": randf_range(boss_size * 0.06, boss_size * 0.12) * (0.7 + damage_pct * 0.7),
		"drift": Vector2(randf_range(-15, 15), randf_range(-50, -25)),
	})


# --- Drawing ---

func _draw() -> void:
	var body_color: Color = primary_color.lerp(Color(1, 1, 1), _hit_flash)
	if _sprite != null:
		# Sprite handles the body — just keep hit flash + smoke overlay alive.
		_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.5, 2.5, 2.5), _hit_flash)
	else:
		match type:
			Type.BOSS1:
				_draw_boss1(body_color)
			Type.BOSS2:
				_draw_boss2(body_color)
			Type.BOSS3:
				_draw_boss3(body_color)
			Type.BOSS4:
				_draw_boss4(body_color)
			Type.BOSS5:
				_draw_boss5(body_color)
			Type.FINAL:
				_draw_final(body_color)
	# Smoke overlay
	for puff in _smoke:
		var k: float = 1.0 - (puff.age / puff.life)
		if k <= 0.0:
			continue
		var r: float = puff.radius * (0.7 + 1.1 * (1.0 - k))
		var a: float = clamp(k, 0.0, 1.0)
		draw_circle(puff.pos, r * 1.7, Color(0.78, 0.78, 0.82, a * 0.55))
		draw_circle(puff.pos, r, Color(0.92, 0.90, 0.90, a * 0.85))
		var ember: float = clamp(k * 1.4 - 0.2, 0.0, 1.0)
		if ember > 0.0:
			draw_circle(puff.pos, r * 0.5, Color(1.0, 0.55, 0.20, ember * 0.9))


# --- Per-boss draw routines (all procedural, no sprite assets) ---

func _draw_boss1(c: Color) -> void:
	# Hornet Queen — wide insectoid frame, twin wing fins, glowing eye row
	var w: float = boss_size
	var h: float = boss_size * 0.7
	# Wings
	var wing_l := PackedVector2Array([
		Vector2(-w * 0.15, 0), Vector2(-w * 0.55, -h * 0.35),
		Vector2(-w * 0.55, h * 0.05), Vector2(-w * 0.20, h * 0.20),
	])
	var wing_r := PackedVector2Array([
		Vector2(w * 0.15, 0), Vector2(w * 0.55, -h * 0.35),
		Vector2(w * 0.55, h * 0.05), Vector2(w * 0.20, h * 0.20),
	])
	draw_colored_polygon(wing_l, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6))
	draw_colored_polygon(wing_r, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6))
	# Body
	draw_circle(Vector2.ZERO, w * 0.22, c)
	draw_circle(Vector2(0, h * 0.20), w * 0.18, Color(c.r * 0.85, c.g * 0.85, c.b * 0.85))
	draw_circle(Vector2(0, h * 0.35), w * 0.13, Color(c.r * 0.7, c.g * 0.7, c.b * 0.7))
	# Eye row — five glowing eyes
	for i in 5:
		var ex: float = (-2.0 + float(i)) * w * 0.06
		draw_circle(Vector2(ex, -w * 0.05), 5, Color(1.0, 1.0, 0.5))
		draw_circle(Vector2(ex, -w * 0.05), 2.5, Color.WHITE)
	# Mandibles
	draw_line(Vector2(-w * 0.08, h * 0.40), Vector2(-w * 0.18, h * 0.50), accent_color, 4)
	draw_line(Vector2(w * 0.08, h * 0.40), Vector2(w * 0.18, h * 0.50), accent_color, 4)


func _draw_boss2(c: Color) -> void:
	# Iron Tortoise — armored hex shell with rivets and central cannon
	var r: float = boss_size * 0.45
	# Outer hex shell
	var hex := PackedVector2Array()
	for i in 6:
		var a: float = TAU / 6.0 * float(i) + PI / 6.0
		hex.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(hex, Color(c.r * 0.7, c.g * 0.7, c.b * 0.7))
	# Inner hex highlight
	var hex2 := PackedVector2Array()
	for i in 6:
		var a2: float = TAU / 6.0 * float(i) + PI / 6.0
		hex2.append(Vector2(cos(a2), sin(a2)) * r * 0.78)
	draw_colored_polygon(hex2, c)
	# Rivets
	for i in 6:
		var a3: float = TAU / 6.0 * float(i) + PI / 6.0
		var p: Vector2 = Vector2(cos(a3), sin(a3)) * r * 0.88
		draw_circle(p, 5, Color(0.2, 0.2, 0.22))
	# Central armored core
	draw_circle(Vector2.ZERO, r * 0.40, Color(0.3, 0.3, 0.35))
	draw_circle(Vector2.ZERO, r * 0.32, accent_color)
	draw_circle(Vector2.ZERO, r * 0.18, Color(1, 1, 1, 0.85))
	# Cannon barrels (4)
	for ang in [-0.45, -0.15, 0.15, 0.45]:
		var d: Vector2 = Vector2.DOWN.rotated(ang)
		draw_line(d * r * 0.4, d * r * 0.95, Color(0.25, 0.25, 0.28), 8)
		draw_circle(d * r * 0.95, 6, accent_color)


func _draw_boss3(c: Color) -> void:
	# Hive Mother — bulbous abdomen with orbiting drone-eggs
	var r: float = boss_size * 0.40
	# Abdomen (large oval)
	for i in 5:
		var k: float = 1.0 - float(i) * 0.15
		draw_circle(Vector2(0, float(i) * 6), r * k, Color(c.r * (0.7 + float(i) * 0.05), c.g * (0.7 + float(i) * 0.05), c.b * (0.7 + float(i) * 0.05)))
	# Glowing brood spots
	for i in 7:
		var ang: float = float(i) * 0.9 + _time * 0.3
		var d: float = r * 0.55
		var p: Vector2 = Vector2(cos(ang) * d, sin(ang) * d * 0.7 + 6)
		draw_circle(p, 8, accent_color)
		draw_circle(p, 4, Color(1, 1, 1, 0.95))
	# Mandible head
	draw_circle(Vector2(0, -r * 0.85), r * 0.35, Color(c.r * 0.8, c.g * 0.8, c.b * 0.8))
	draw_circle(Vector2(-r * 0.12, -r * 0.85), 5, Color(1, 0.4, 0.4))
	draw_circle(Vector2(r * 0.12, -r * 0.85), 5, Color(1, 0.4, 0.4))
	# Orbiting drone-eggs (cosmetic, animated)
	for i in 4:
		var oang: float = _time * 1.2 + float(i) * (TAU / 4.0)
		var op: Vector2 = Vector2(cos(oang), sin(oang)) * r * 1.25
		draw_circle(op, 9, accent_color)
		draw_circle(op, 5, c)


func _draw_boss4(c: Color) -> void:
	# Crystal Prism — rotating diamond facets with rainbow inner glow
	var r: float = boss_size * 0.45
	var spin: float = _time * 0.7
	# Outer shards (8 facets)
	for i in 8:
		var a1: float = spin + TAU / 8.0 * float(i)
		var a2: float = spin + TAU / 8.0 * float(i + 1)
		var p1: Vector2 = Vector2(cos(a1), sin(a1)) * r
		var p2: Vector2 = Vector2(cos(a2), sin(a2)) * r
		var poly := PackedVector2Array([Vector2.ZERO, p1, p2])
		var shade: float = 0.6 + 0.4 * sin(_time * 2.0 + float(i))
		draw_colored_polygon(poly, Color(c.r * shade, c.g * shade, c.b * shade, 0.85))
	# Inner core
	draw_circle(Vector2.ZERO, r * 0.45, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.95))
	draw_circle(Vector2.ZERO, r * 0.30, Color.WHITE)
	# Outline
	for i in 8:
		var a3: float = spin + TAU / 8.0 * float(i)
		var p: Vector2 = Vector2(cos(a3), sin(a3)) * r
		draw_line(Vector2.ZERO, p, accent_color, 2)


func _draw_boss5(c: Color) -> void:
	# Void Reaper — sinister scythe-shaped silhouette with red eye
	var r: float = boss_size * 0.45
	# Cloak/body
	var cloak := PackedVector2Array([
		Vector2(-r * 0.7, -r * 0.5),
		Vector2(r * 0.7, -r * 0.5),
		Vector2(r * 0.95, r * 0.4),
		Vector2(0, r * 0.85),
		Vector2(-r * 0.95, r * 0.4),
	])
	draw_colored_polygon(cloak, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5))
	# Inner cloak
	var cloak2 := PackedVector2Array([
		Vector2(-r * 0.55, -r * 0.35),
		Vector2(r * 0.55, -r * 0.35),
		Vector2(r * 0.75, r * 0.30),
		Vector2(0, r * 0.65),
		Vector2(-r * 0.75, r * 0.30),
	])
	draw_colored_polygon(cloak2, c)
	# Hood opening (dark)
	draw_circle(Vector2(0, -r * 0.10), r * 0.32, Color(0.05, 0.0, 0.10))
	# Single glowing red eye
	draw_circle(Vector2(0, -r * 0.10), r * 0.13, Color(1, 0.15, 0.15))
	draw_circle(Vector2(0, -r * 0.10), r * 0.06, Color(1, 0.6, 0.6))
	# Scythe blades on each side (curved arcs)
	draw_arc(Vector2(-r * 0.85, 0), r * 0.55, -PI * 0.3, PI * 0.6, 22, accent_color, 6, true)
	draw_arc(Vector2(r * 0.85, 0), r * 0.55, PI * 0.4, PI * 1.3, 22, accent_color, 6, true)


func _draw_final(c: Color) -> void:
	# The Skybreaker — massive multi-ring battle station
	var r: float = boss_size * 0.48
	# Outer ring
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5), 8, true)
	draw_arc(Vector2.ZERO, r * 0.92, 0, TAU, 64, Color(c.r * 0.7, c.g * 0.7, c.b * 0.7), 4, true)
	# Spokes (8) — rotating
	var spin: float = _time * 0.4
	for i in 8:
		var a: float = spin + TAU / 8.0 * float(i)
		var p1: Vector2 = Vector2(cos(a), sin(a)) * r * 0.40
		var p2: Vector2 = Vector2(cos(a), sin(a)) * r * 0.92
		draw_line(p1, p2, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6), 10)
		# Turret at the end
		draw_circle(p2, 9, Color(0.3, 0.3, 0.32))
		draw_circle(p2, 5, accent_color)
	# Core hub
	draw_circle(Vector2.ZERO, r * 0.40, Color(c.r * 0.8, c.g * 0.8, c.b * 0.8))
	draw_circle(Vector2.ZERO, r * 0.32, c)
	draw_circle(Vector2.ZERO, r * 0.22, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3))
	# Pulsing core eye
	var pulse: float = 0.85 + 0.15 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, r * 0.13 * pulse, accent_color)
	draw_circle(Vector2.ZERO, r * 0.07 * pulse, Color.WHITE)
	# Counter-rotating outer shards
	var spin2: float = -_time * 0.6
	for i in 6:
		var a4: float = spin2 + TAU / 6.0 * float(i)
		var sp: Vector2 = Vector2(cos(a4), sin(a4)) * r * 1.10
		draw_circle(sp, 7, accent_color)
