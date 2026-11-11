extends Node
class_name AiPilot
## An AI partner: a pilot that lives inside the room server and takes a seat
## like a phone does (docs/MULTIPLAYER_PLAN.md, phase 7). It flies, shoots,
## gets hit, loses lives, goes down and is rescued, rescues its partner,
## grabs pickups, docks and shops with its own money.
##
## Each pilot rolls four traits (0-1) that drive all of that:
##   aggression  flies higher, chases bosses, sits under targets
##   greed       goes for pickups (also the ones nearer the human), docks more, shops longer
##   caution     gives enemy fire a wider berth, hangs lower
##   skill       reacts faster, flies faster, lands more of its shots
##
## Half of the pilots are DISGUISED (a human-looking name, no tag), half are
## LABELLED (callsign + "AI"): an experiment decided by Yaniv on 11/11.
##
## The server owns enemy shots as real nodes (phones fly their own copies), so
## the pilot dodges and is hit by the server's copies.

const NAMES_HUMAN: Array = ["Mika92", "DaniK", "xNova", "Tomer", "LunaB", "Jonas", "Rafa_7", "Noa", "Kenji", "Zoe.R",
		"Mateo", "Ines", "StarLad", "Piotr", "Aya", "Marco88", "Lior", "Sam_T", "Elif", "Hugo"]
const NAMES_AI: Array = ["VIPER", "FALCON", "ORION", "NOVA", "ECHO", "TALON", "ATLAS", "LYNX", "RAVEN", "COMET"]

const MAX_HP: int = 20
const MAX_LEVEL: int = 30
const HALF: float = 22.0            ## The ship's own hit radius
const STATE_EVERY: float = 1.0 / 30.0
const RESPAWN_SECS: float = 2.5
const X_MIN: float = 40.0
const X_MAX: float = 776.0
const Y_MIN: float = 650.0          ## Phones show less height than the server field: stay in view
const Y_MAX: float = 1300.0

var sw: Node = null                 ## The ServerWorld
var peer: int = 0
var pilot_name: String = "PILOT"
var labelled: bool = false          ## true = shown as an AI, false = disguised
var aggression: float = 0.5
var greed: float = 0.5
var caution: float = 0.5
var skill: float = 0.5
var rng := RandomNumberGenerator.new()   ## Own generator: never touches the sector seed

var pos: Vector2 = Vector2(520, 1150)
var vel: Vector2 = Vector2.ZERO
var hp: int = MAX_HP
var shield: int = 2
var shield_max: int = 2
var lives: int = 3
var level: int = 1
var money: int = 0
var score: int = 0
var down: bool = false
var firing: bool = false
var goal: String = "patrol"
var stats := {"hits_taken": 0, "deaths": 0, "kills": 0, "pickups": 0, "bought": 0, "docks": 0, "rescues": 0}

var _dead_t: float = -1.0
var _frail_t: float = -1.0
var _invuln: float = 2.0
var _dmg_acc: float = 0.0
var _state_t: float = 0.0
var _shield_t: float = 0.0
var _wander_t: float = 0.0
var _wander_x: float = 408.0
var _dock_choice: Dictionary = {}    ## starbase id -> bool (decided once per base)
# Shop
var _shop_t: float = 0.0
var _shop_leave_at: float = 0.0
var _shop_wait_human: bool = false
var _shop_linger: float = -1.0
var _shop_next_buy: float = 0.0
var _shop_done: bool = false


func setup(world: Node, peer_id: int, seed_value: int) -> void:
	sw = world
	peer = peer_id
	rng.seed = int(seed_value) ^ 0x5bd1e995
	aggression = rng.randf()
	greed = rng.randf()
	caution = rng.randf()
	skill = rng.randf_range(0.25, 1.0)
	labelled = rng.randf() < 0.5
	if labelled:
		pilot_name = str(NAMES_AI[rng.randi() % NAMES_AI.size()]) + " · AI"
	else:
		pilot_name = str(NAMES_HUMAN[rng.randi() % NAMES_HUMAN.size()])
	_wander_x = rng.randf_range(200.0, 620.0)
	for arg in OS.get_cmdline_user_args():
		if arg == "--bot_frail":   # test hook: one hit and it is down
			hp = 1
			shield = 0
			shield_max = 0
			lives = 1
			_invuln = 0.0
			_frail_t = 6.0
	print("AiPilot ", pilot_name, ": aggression ", snappedf(aggression, 0.01), " greed ", snappedf(greed, 0.01),
			" caution ", snappedf(caution, 0.01), " skill ", snappedf(skill, 0.01), " labelled ", labelled)


func alive() -> bool:
	return not down and _dead_t < 0.0


## One step of the running world (never called while the shop has it frozen).
func tick(delta: float) -> void:
	var seat: Dictionary = sw.seats[peer]
	if down:
		if not bool(seat["down"]):
			# Rescued by the partner, or a new sector began.
			down = false
			lives = 1
			_respawn()
		else:
			_send_state(delta)
			return
	if _dead_t >= 0.0:
		_dead_t -= delta
		if _dead_t < 0.0:
			_respawn()
		_send_state(delta)
		return
	_invuln = maxf(0.0, _invuln - delta)
	if _frail_t > 0.0:
		_frail_t -= delta
		if _frail_t <= 0.0:
			_hurt(99, 0.0)   # test hook: shot down 6 s in
			_send_state(delta)
			return
	if shield < shield_max:
		_shield_t += delta
		if _shield_t >= 7.0:
			_shield_t = 0.0
			shield += 1
	_fly(delta)
	_shoot(delta)
	_touch()
	_send_state(delta)


func _respawn() -> void:
	_dead_t = -1.0
	hp = MAX_HP
	shield = mini(1, shield_max)
	_invuln = 2.5
	pos = Vector2(clampf(pos.x, 160.0, 656.0), _home_y())
	vel = Vector2.ZERO


func _human_ship() -> Node2D:
	for p in sw.ships:
		if p != peer and bool(sw.seats[p]["alive"]):
			return sw.ships[p]
	return null


func _home_y() -> float:
	var h: Node2D = _human_ship()
	var base: float = h.position.y if h != null else sw.FIELD.y * 0.63
	return clampf(base - 40.0 - 220.0 * aggression + 110.0 * caution, Y_MIN, Y_MAX)


static func _is_target(n) -> bool:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return false
	if n is Pickup or n is Starbase or n is RevivePod or not n.has_method("take_damage"):
		return false
	if "alive" in n and not n.alive:
		return false
	if "cloaked" in n and n.cloaked:
		return false
	return true


static func _half_width(n) -> float:
	if "radius" in n:
		return maxf(30.0, float(n.radius))
	if n is Boss:
		return 90.0
	return 46.0


# --- Flying ---

func _fly(delta: float) -> void:
	var tx: float = _wander_x
	var ty: float = _home_y()
	goal = "patrol"
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = rng.randf_range(1.5, 4.0)
		_wander_x = rng.randf_range(140.0, 676.0)
	# What to go for, least to most important.
	var best = null
	var best_cost: float = INF
	var human: Node2D = _human_ship()
	for id in sw.entities:
		var n = sw.entities[id]
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if _is_target(n):
			var np: Vector2 = n.global_position
			if np.y < 20.0 or np.y > pos.y - 40.0 or np.x < 0.0 or np.x > sw.FIELD.x:
				continue
			var cost: float = absf(np.x - pos.x) + (pos.y - np.y) * 0.3
			if n is Boss or n is BossPart:
				cost -= 260.0 * aggression
			if cost < best_cost:
				best_cost = cost
				best = n
	if best != null:
		tx = best.global_position.x
		goal = "attack"
	for id in sw.entities:
		var n = sw.entities[id]
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n is Pickup and not n.has_meta("granted"):
			var d: float = pos.distance_to(n.position)
			if d < 70.0:
				_take_pickup(id, n)
				continue
			var need: bool = hp <= 12 and n.type in [Pickup.Type.HEALTH_SMALL, Pickup.Type.HEALTH_MEDIUM, Pickup.Type.HEALTH_FULL]
			var mine: bool = human == null or d < human.position.distance_to(n.position) or greed > 0.6
			if n.position.y > 60.0 and n.position.y < Y_MAX + 80.0 and (need or (mine and d < 220.0 + 480.0 * greed)):
				tx = n.position.x
				ty = clampf(n.position.y, Y_MIN, Y_MAX)
				goal = "pickup"
		elif n is Starbase and not n._used and n.position.y > 150.0:
			if not _dock_choice.has(id):
				var want: bool = money >= 150 or hp <= 10
				_dock_choice[id] = want and rng.randf() < 0.35 + 0.5 * greed
			if _dock_choice[id]:
				tx = n.position.x
				ty = clampf(n.position.y, Y_MIN, Y_MAX)
				goal = "dock"
				if pos.distance_to(n.position) < 95.0 or (absf(pos.x - n.position.x) < 80.0 and n.position.y > Y_MAX):
					stats.docks += 1
					sw._dock(peer, id)
		elif n is RevivePod and int(n.for_peer) != peer and not n.claimed:
			tx = n.position.x
			ty = clampf(n.position.y, Y_MIN - 200.0, Y_MAX)
			goal = "rescue"
			if pos.distance_to(n.position) < 70.0:
				stats.rescues += 1
				sw._claim_pod(n, peer)
	# Get out of the way of enemy fire and bodies.
	var push: float = 0.0
	var reach: float = 300.0 + 220.0 * caution
	for b in get_tree().get_nodes_in_group(&"enemy_bullets"):
		if not is_instance_valid(b):
			continue
		var bp: Vector2 = b.global_position
		var dx: float = pos.x - bp.x
		if b is EnemyBeam:
			if bp.y < pos.y and absf(dx) < 130.0:
				push += (1.0 if dx >= 0.0 else -1.0) * (130.0 - absf(dx)) * 5.0
			continue
		var dy: float = pos.y - bp.y
		if dy < -30.0 or dy > reach or absf(dx) > 85.0:
			continue
		push += (1.0 if dx >= 0.0 else -1.0) * (85.0 - absf(dx)) * (1.0 - dy / (reach + 200.0)) * 6.0
	for id in sw.entities:
		var n = sw.entities[id]
		if _is_target(n):
			var d2: Vector2 = pos - n.global_position
			var r: float = _half_width(n) + 70.0
			if d2.y > -20.0 and d2.y < 190.0 and absf(d2.x) < r:
				push += (1.0 if d2.x >= 0.0 else -1.0) * (r - absf(d2.x)) * 5.0
				ty = minf(Y_MAX, ty + 60.0)
	push *= (0.45 + 0.75 * caution) * (0.5 + 0.5 * skill)
	if pos.x < 110.0 and push < 0.0 or pos.x > 706.0 and push > 0.0:
		push = -push   # cornered: go back through rather than hug the wall
	var top: float = 380.0 + 260.0 * skill
	var want := Vector2(clampf((tx - pos.x) * 4.0 + push, -top, top), clampf((ty - pos.y) * 3.0, -top * 0.7, top * 0.7))
	vel = vel.lerp(want, clampf(delta * (4.0 + 8.0 * skill), 0.0, 1.0))
	pos += vel * delta
	pos.x = clampf(pos.x, X_MIN, X_MAX)
	pos.y = clampf(pos.y, Y_MIN - 200.0 if goal == "rescue" else Y_MIN, Y_MAX)


# --- Shooting: straight up, the first thing in the column takes it ---

func dps() -> float:
	return (6.9 + 0.49 * float(level - 1)) * 2.0 * (1.0 + 0.10 * float(level - 1)) * (0.5 + 0.4 * skill)


func _shoot(delta: float) -> void:
	var hit = null
	var hit_y: float = -INF
	var any: bool = false
	for id in sw.entities:
		var n = sw.entities[id]
		if not _is_target(n):
			continue
		var np: Vector2 = n.global_position
		if np.y < 0.0 or np.y > pos.y:
			continue
		any = true
		if absf(np.x - pos.x) <= _half_width(n) and np.y > hit_y:
			hit_y = np.y
			hit = n
	firing = any
	if hit == null:
		return
	_dmg_acc += dps() * delta
	if _dmg_acc >= 1.0:
		var d: int = int(_dmg_acc)
		_dmg_acc -= float(d)
		hit.set_meta("last_hitter", peer)
		if "boss" in hit and hit.boss != null and is_instance_valid(hit.boss):
			hit.boss.set_meta("last_hitter", peer)
		hit.take_damage(d)
		sw.stats.hits += 1


## The server credits a kill to this pilot.
func on_kill(reward: int) -> void:
	score += maxi(0, reward)
	stats.kills += 1


# --- Being hit ---

func _touch() -> void:
	if _invuln > 0.0:
		return
	for b in get_tree().get_nodes_in_group(&"enemy_bullets"):
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var bp: Vector2 = b.global_position
		if b is EnemyBeam:
			if b._firing and bp.y < pos.y and absf(bp.x - pos.x) < HALF + 24.0:
				_hurt(int(b.damage), 0.6)
				return
			continue
		if bp.distance_to(pos) < HALF + float(b.bullet_radius):
			var d: int = int(b.damage)
			b.queue_free()
			_hurt(d, 0.25)
			return
	for id in sw.entities:
		var n = sw.entities[id]
		if _is_target(n) and n.global_position.distance_to(pos) < HALF + _half_width(n) * 0.7:
			_hurt(6, 1.0)
			return


func _hurt(damage: int, grace: float) -> void:
	stats.hits_taken += 1
	_invuln = grace
	if shield > 0:
		shield -= 1
		return
	hp -= maxi(1, damage)
	if hp > 0:
		return
	stats.deaths += 1
	lives -= 1
	firing = false
	if lives <= 0:
		down = true
		sw._go_down(peer, pos)   # may end the run (everyone down)
	else:
		_dead_t = RESPAWN_SECS


# --- Pickups ---

func _take_pickup(id: int, p: Pickup) -> void:
	p.set_meta("granted", peer)
	Net.broadcast([Net.M.GRANT, id, peer])
	sw.stats.grants += 1
	stats.pickups += 1
	match p.type:
		Pickup.Type.MONEY:
			money += int(p.money_value)
		Pickup.Type.POWER, Pickup.Type.POWER_PHASER, Pickup.Type.POWER_BEAM, Pickup.Type.POWER_MISSILE:
			level = mini(MAX_LEVEL, level + 1)
		Pickup.Type.HEALTH_SMALL:
			hp = mini(MAX_HP, hp + 5)
		Pickup.Type.HEALTH_MEDIUM:
			hp = mini(MAX_HP, hp + 10)
		Pickup.Type.HEALTH_FULL:
			hp = MAX_HP
		Pickup.Type.LIFE:
			lives = mini(5, lives + 1)
	p.queue_free()


# --- Shop (the world is frozen; the server calls these instead of tick) ---

func shop_opened() -> void:
	_shop_t = 0.0
	_shop_done = false
	_shop_next_buy = rng.randf_range(0.8, 1.8)
	_shop_leave_at = lerpf(2.0, 8.0, clampf(rng.randf() * 0.5 + greed * 0.5, 0.0, 1.0))
	# Half of the visits it is ready on its own clock; the other half it waits
	# for the human and then lingers a moment longer.
	_shop_wait_human = rng.randf() < 0.5
	_shop_linger = -1.0
	if down:
		_shop_leave_at = 0.5   # nothing to buy for a ship that is not flying
		_shop_wait_human = false


func _price(item: String) -> int:
	match item:
		"repair": return 5 * (MAX_HP - hp)
		"shield": return 220 + 60 * (shield_max - 2)
		_: return 180 + 30 * level   # power_phaser (the real shop asks $210 at level 1)


func _want() -> String:
	if hp <= 12:
		return "repair"
	if shield_max < 4 and caution > 0.55 and rng.randf() < 0.5:
		return "shield"
	return "power_phaser" if level < MAX_LEVEL else ""


func shop_tick(delta: float) -> void:
	if _shop_done:
		return
	_shop_t += delta
	if not down and _shop_t >= _shop_next_buy:
		_shop_next_buy = _shop_t + rng.randf_range(0.9, 1.8)
		var item: String = _want()
		if item != "" and money >= _price(item):
			money -= _price(item)
			stats.bought += 1
			match item:
				"repair": hp = MAX_HP
				"shield":
					shield_max += 1
					shield = shield_max
				_: level += 1
			Net.broadcast([Net.M.SHOP_BOUGHT, peer, item])
	if _shop_t < _shop_leave_at:
		return
	if _shop_wait_human:
		if not sw.humans_shop_ready():
			return
		if _shop_linger < 0.0:
			_shop_linger = _shop_t + rng.randf_range(0.5, 4.0)
		if _shop_t < _shop_linger:
			return
	_shop_done = true
	sw.bot_shop_ready(peer)


# --- What the partner's phone sees ---

func _send_state(delta: float) -> void:
	var ok: bool = alive()
	var ship: Node = sw.ships.get(peer)
	if ship != null:
		ship.position = pos
		if ok != ship.is_in_group(&"player"):
			if ok: ship.add_to_group(&"player")
			else: ship.remove_from_group(&"player")
	sw.seats[peer]["alive"] = ok
	sw.seats[peer]["score"] = score
	_state_t += delta
	if _state_t < STATE_EVERY:
		return
	_state_t = 0.0
	Net.broadcast([Net.M.PARTNER, peer, {"p": pos, "a": ok, "n": pilot_name, "sc": score, "w": 0, "l": level, "f": firing and ok}], false)
