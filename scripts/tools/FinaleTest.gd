extends Node
## Headless check of the 9/11 playtest + 24-sector expansion: finale boss pair + end-on-kill,
## new SHADE / ARTILLERY enemies, Null Archon + Herald, stretched ladder and upgrade caps,
## missiles vs bosses, sidekick first-hit shield, late-sector enemies, the
## first-launch name prompt gate and the cutscene audio hooks.
## Run: godot --headless --path . res://scenes/tools/FinaleTest.tscn

var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _spawner_for(level: int) -> Node:
	GameState.current_level = level
	var sp: Node = load("res://scripts/EnemySpawner.gd").new()
	add_child(sp)
	sp._timer = 99999.0   # no fodder waves during the test
	return sp

func _bosses() -> Array:
	return get_tree().get_nodes_in_group(&"bosses")

func _kill_bosses() -> void:
	for b in _bosses():
		b.remove_from_group(&"bosses")
		b.queue_free()

func _ready() -> void:
	var saved_lvl: int = GameState.current_level
	# --- Sector 24: THE HERALD then THE SKYBREAKER, stage ends on the kill ---
	_check(GameState.MAX_LEVEL == 24 and Levels.count() == 24, "24 sectors")
	var sp: Node = _spawner_for(24)
	await get_tree().process_frame
	_check(sp.ends_on_boss(), "sector 24 ends on the last boss")
	_check(sp._boss_queue.size() == 2, "sector 24 queues two bosses, got %d" % sp._boss_queue.size())
	_check(not sp.boss_sequence_done(), "sequence not done before any boss")
	sp._mission_time = sp.get_level_duration()   # timer over, no boss yet
	_check(not sp.boss_sequence_done(), "timer alone cannot finish a boss stage")
	sp._spawn_boss()
	await get_tree().process_frame
	var herald: Node = _bosses()[0] if not _bosses().is_empty() else null
	_check(herald != null and herald.type == 7, "first boss is THE HERALD hull")
	_check(herald != null and herald.boss_name == "THE HERALD", "first boss is named THE HERALD, got %s" % (herald.boss_name if herald else "none"))
	_check(herald != null and herald.max_hp == int(round(1500.0 * 1.6 * 0.75)), "herald HP = 75%% of a sector-24 Herald (%d)" % (herald.max_hp if herald else -1))
	_check(herald != null and herald._sprite != null and (herald._sprite.modulate == Color.WHITE) == ResourceLoader.exists(Boss.PATH_HERALD), "herald: own art untinted, stand-in tinted")
	_check(sp._boss_phase(), "boss phase while the herald lives")
	_check(not sp.boss_sequence_done(), "sequence not done while the herald lives")
	_kill_bosses()
	await get_tree().process_frame
	_check(sp._boss_phase(), "boss phase holds between the two bosses")
	_check(not sp.boss_sequence_done(), "herald down, Skybreaker pending: not done")
	for i in 40:
		sp._process(0.1)   # 4 s > BOSS_FOLLOWUP_DELAY
	await get_tree().process_frame
	var final_boss: Node = _bosses()[0] if not _bosses().is_empty() else null
	_check(final_boss != null and final_boss.type == 5, "THE SKYBREAKER enters after the beat")
	_check(final_boss != null and final_boss.boss_name == "THE SKYBREAKER", "final boss keeps its own name")
	_check(final_boss != null and final_boss.max_hp == int(round(2200.0 * 1.6)), "final boss HP unscaled (%d)" % (final_boss.max_hp if final_boss else -1))
	_check(sp.bosses_spawned() == 2, "two bosses spawned in total")
	_kill_bosses()
	await get_tree().process_frame
	_check(sp.boss_sequence_done(), "sequence done once the Skybreaker dies")
	_check(not sp._boss_phase(), "boss phase over after the last boss")
	sp.queue_free()
	# --- Sector 22: NULL ARCHON alone, timer still rules ---
	var sp22: Node = _spawner_for(22)
	await get_tree().process_frame
	_check(not sp22.ends_on_boss(), "sector 22 still runs its timer")
	_check(sp22._boss_queue.size() == 1, "sector 22 has one boss")
	sp22._spawn_boss()
	await get_tree().process_frame
	var archon: Node = _bosses()[0] if not _bosses().is_empty() else null
	_check(archon != null and archon.type == 6 and archon.boss_name == "NULL ARCHON", "sector 22 boss is the Null Archon")
	_check(archon != null and archon.fire_cd_mul < 1.0, "archon fires faster than the ladder bosses")
	_kill_bosses()
	await get_tree().process_frame
	_check(sp22.boss_sequence_done(), "sector 22 done after its boss")
	sp22.queue_free()
	var sp19: Node = _spawner_for(19)
	await get_tree().process_frame
	_check(sp19._boss_queue.size() == 1 and int(sp19._boss_queue[0]["type"]) == 4, "sector 19 boss is still the Void Reaper")
	sp19.queue_free()
	var sp20: Node = _spawner_for(20)
	await get_tree().process_frame
	_check(sp20.boss_sequence_done(), "sector 20 is a regular stage now")
	_check(20 not in CutsceneData.TRIGGERS and CutsceneData.TRIGGERS[21] == CutsceneData.ACT_5_KEY and CutsceneData.TRIGGERS[24] == CutsceneData.ENDING_KEY, "story: act 5 after 21, ending after 24")
	_check(CutsceneData.beats_for(CutsceneData.ACT_5_KEY).size() == 3, "act 5 has three beats")
	sp20.queue_free()

	# --- New enemies: SHADE phases, ARTILLERY holds and lobs mortars ---
	GameState.current_level = 20
	var shade: Node = load("res://scripts/Enemy.gd").new()
	shade.type = 9
	shade.position = Vector2(400, 300)
	add_child(shade)
	await get_tree().process_frame
	_check(not shade.cloaked and shade.monitorable, "shade starts visible")
	_check(shade._sprite != null and (shade._sprite_tint == Color.WHITE) == ResourceLoader.exists(Enemy.PATH_SHADE), "shade: own art untinted, stand-in tinted")
	var shade_hp: int = shade.hp
	for i in 18:
		shade._process(0.1)   # 1.8 s > visible window
	_check(shade.cloaked and not shade.monitorable, "shade cloaks after its visible window")
	shade.take_damage(5)
	_check(shade.hp == shade_hp, "cloaked shade ignores damage")
	_check(shade._sprite.modulate.a < 0.5, "cloaked shade is drawn faded (a=%.2f)" % shade._sprite.modulate.a)
	var probe := Node2D.new()
	probe.position = shade.position
	add_child(probe)
	_check(HitCheck.enemy_at(probe, Vector2(10, 10)) == null, "hit safety net skips a cloaked shade")
	for i in 13:
		shade._process(0.1)   # 1.3 s > cloak
	_check(not shade.cloaked and shade.monitorable, "shade reappears")
	_check(shade._fire_timer <= 0.25, "shade fires right after reappearing")
	shade.take_damage(5)
	_check(shade.hp == shade_hp - 5, "visible shade takes damage")
	probe.position = shade.position   # it kept flying while cloaked
	await get_tree().process_frame    # HitCheck flattens the enemy list once per frame
	probe.position = shade.position
	_check(HitCheck.enemy_at(probe, Vector2(10, 10)) == shade, "hit safety net sees the visible shade")
	shade.queue_free()
	probe.queue_free()
	var art: Node = load("res://scripts/Enemy.gd").new()
	art.type = 10
	art.position = Vector2(400, -60)
	add_child(art)
	await get_tree().process_frame
	art._fire_timer = 999.0
	var hold_y: float = art._viewport_size.y * 0.22
	for i in 200:
		art._process(0.1)   # 20 s at 60 px/s is plenty to reach the line
		if art._hold_elapsed > 0.0:
			break
	_check(is_equal_approx(art.position.y, hold_y), "artillery stops on the hold line (y=%.0f)" % art.position.y)
	for i in 30:
		art._process(0.1)
	_check(is_equal_approx(art.position.y, hold_y) and art._hold_elapsed > 3.0, "artillery holds the line")
	for i in 60:
		art._process(0.1)
	_check(art.position.y > hold_y + 50.0, "artillery leaves after its hold time")
	art.position = Vector2(400, 200)
	var before: int = get_child_count()
	art._fire()
	var shell: Node = get_child(get_child_count() - 1)
	_check(get_child_count() == before + 1 and shell is EnemyBullet and shell.burst_after > 0.0, "mortar fires one fused shell")
	shell._process_motion(1.1)
	await get_tree().process_frame
	await get_tree().process_frame
	var pellets: int = 0
	for c in get_children():
		if c is EnemyBullet and c.style == EnemyBullet.Style.PELLET and c.burst_after == 0.0:
			pellets += 1
	_check(pellets == 6 and not is_instance_valid(shell), "shell bursts into six pellets and is gone")
	art.queue_free()
	for c in get_children():
		if c is EnemyBullet:
			c.free()

	# --- Wave two of new enemies: MINELAYER, SPLITTER + SHARD, PULSAR, HUNTER, BEAMER ---
	var EN2 = load("res://scripts/Enemy.gd")
	var ship := Area2D.new()   # stand-in target for aimed / homing shots
	ship.monitoring = false    # bullets' own hit safety net skips a non-monitoring ship
	ship.add_to_group(&"player")
	ship.position = Vector2(700, 1100)
	add_child(ship)
	var art2: Node = EN2.new(); art2.type = 10; art2.position = Vector2(400, 200); add_child(art2)
	await get_tree().process_frame
	art2._fire()
	var sh2: Node = get_child(get_child_count() - 1)
	await get_tree().process_frame
	_check(sh2 is EnemyBullet and is_equal_approx(sh2.speed, 240.0), "mortar shell keeps its slow speed (%.0f)" % sh2.speed)
	sh2.free(); art2.free()
	var ml: Node = EN2.new(); ml.type = 11; ml.position = Vector2(300, 250); add_child(ml)
	await get_tree().process_frame
	_check(ml.movement == &"horizontal", "minelayer crosses sideways")
	ml._fire()
	var mine: Node = get_child(get_child_count() - 1)
	await get_tree().process_frame
	_check(mine is EnemyBullet and mine.burst_after > 0.0 and mine.burst_count == 5 and is_equal_approx(mine.speed, 85.0), "minelayer drops a slow fused mine")
	mine.free(); ml.free()
	var spl: Node = EN2.new(); spl.type = 12; spl.position = Vector2(400, 300); add_child(spl)
	await get_tree().process_frame
	spl.take_damage(9999)
	await get_tree().process_frame
	await get_tree().process_frame
	var shards: Array = []
	for c in get_children():
		if c is Enemy and c.type == Enemy.Type.SHARD:
			shards.append(c)
	_check(shards.size() == 2, "dead splitter leaves two shards (%d)" % shards.size())
	_check(shards.size() == 2 and shards[0]._kick_x * shards[1]._kick_x < 0.0, "shards fly apart")
	_check(shards.size() == 2 and shards[0].fire_pattern == &"none" and shards[0].enemy_size < 60.0, "shards are small and unarmed")
	if shards.size() == 2:
		var x0: float = shards[0].position.x
		shards[0]._process(0.1)
		_check(not is_equal_approx(shards[0].position.x, x0), "shard is flung sideways")
	for c in shards:
		c.free()
	for c in get_children():
		if c is Pickup or c is EnemyExplosion or c is ScorePopup:
			c.free()
	var pul: Node = EN2.new(); pul.type = 13; pul.position = Vector2(400, 400); add_child(pul)
	await get_tree().process_frame
	var nb: int = get_child_count()
	pul._fire()
	var ring: Array = get_children().slice(nb)
	await get_tree().process_frame
	_check(ring.size() == 8, "pulsar fires a ring of eight (%d)" % ring.size())
	_check(ring.size() == 8 and is_equal_approx(ring[0].speed, 300.0), "ring pellets keep their own speed")
	var turn0: float = pul._ring_turn
	pul._fire()
	_check(pul._ring_turn > turn0, "the ring turns between volleys")
	for c in get_children():
		if c is EnemyBullet:
			c.free()
	pul.free()
	var hun: Node = EN2.new(); hun.type = 15; hun.position = Vector2(200, 200); add_child(hun)
	await get_tree().process_frame
	nb = get_child_count()
	hun._fire()
	var missiles: Array = get_children().slice(nb)
	await get_tree().process_frame
	_check(missiles.size() == 2 and missiles[0].homing_turn_rate > 0.0, "sector-20 hunter launches two homing missiles (%d)" % missiles.size())
	if not missiles.is_empty():
		var hm: Node = missiles[0]
		var want: Vector2 = (ship.global_position - hm.global_position).normalized()
		var dot0: float = hm.direction.dot(want)
		for i in 20:
			hm._process_motion(0.05)   # 1 s of flight inside the homing window
		var dot1: float = hm.direction.dot((ship.global_position - hm.global_position).normalized())
		_check(dot1 > dot0 and dot1 > 0.9, "missile curves onto the ship (%.2f -> %.2f)" % [dot0, dot1])
		for i in 50:
			hm._process_motion(0.05)   # past homing_secs
		var d_before: Vector2 = hm.direction
		ship.position = Vector2(50, 50)
		if is_instance_valid(hm) and not hm.is_queued_for_deletion():
			hm._process_motion(0.05)
			_check(hm.direction.is_equal_approx(d_before), "missile flies straight after its homing window")
	ship.position = Vector2(700, 1100)
	for c in get_children():
		if c is EnemyBullet:
			c.free()
	hun.free()
	GameState.current_level = 24
	var bm: Node = EN2.new(); bm.type = 16; bm.position = Vector2(300, -60); add_child(bm)
	await get_tree().process_frame
	_check(bm.fire_interval >= Enemy.BEAMER_MIN_INTERVAL, "beamer never cycles faster than %.1fs even at sector 24 (%.2f)" % [Enemy.BEAMER_MIN_INTERVAL, bm.fire_interval])
	for i in 200:
		bm._process(0.1)
		if bm._hold_elapsed > 0.0:
			break
	var bx: float = bm.position.x
	bm._fire_timer = 999.0
	for i in 10:
		bm._process(0.1)
	_check(bm.position.x > bx, "beamer lines itself up over the ship")
	bm._fire_timer = 0.0
	bm._process(0.05)
	_check(bm._beam_live(), "beamer starts a beam from the hold line")
	var beam: Node = bm._beam
	await get_tree().process_frame
	_check(beam is EnemyBeam and not beam.is_firing() and not beam.monitorable, "beam is harmless while it charges")
	var bx2: float = bm.position.x
	bm._process(0.1)
	_check(is_equal_approx(bm.position.x, bx2), "beamer stands still while its beam is out")
	for i in 10:
		beam._process(0.1)   # past charge_secs
	await get_tree().process_frame
	_check(beam.is_firing() and beam.monitorable and beam.is_in_group(&"enemy_bullets"), "beam turns live after the warning")
	for i in 8:
		if is_instance_valid(beam):
			beam._process(0.1)
	await get_tree().process_frame
	_check(not is_instance_valid(beam) or beam.is_queued_for_deletion(), "beam ends after its fire time")
	await get_tree().process_frame
	bm._fire_timer = 0.0
	bm._process(0.05)
	var beam2: Node = bm._beam
	_check(bm._beam_live(), "beamer charges a second beam")
	bm.free()
	if is_instance_valid(beam2):
		beam2._process(0.1)
	await get_tree().process_frame
	_check(not is_instance_valid(beam2) or beam2.is_queued_for_deletion(), "killing the beamer during the wind-up cancels the beam")
	# Bosses: Archon beam (one at a time), Herald homing volley
	var ar: Node = load("res://scripts/Boss.gd").new(); ar.type = 6; add_child(ar)
	var he: Node = load("res://scripts/Boss.gd").new(); he.type = 7; add_child(he)
	await get_tree().process_frame
	ar._pattern_beam()
	var first_beam: Node = ar._beam
	ar._pattern_beam()
	_check(first_beam is EnemyBeam and ar._beam == first_beam and first_beam.from_boss, "archon fires one sweeping beam at a time")
	nb = get_child_count()
	he._pattern_homing(3)
	var volley: Array = get_children().slice(nb)
	_check(volley.size() == 3 and volley[0].from_boss and volley[0].homing_turn_rate > 0.0, "herald launches three homing missiles")
	for c in get_children():
		if c is EnemyBullet or c is EnemyBeam:
			c.free()
	ar.remove_from_group(&"bosses"); he.remove_from_group(&"bosses")
	ar.free(); he.free()
	ship.free()

	# --- Ladder: 1-20 unchanged, 21-24 keep climbing ---
	var EN = load("res://scripts/Enemy.gd")
	GameState.current_level = 20
	var t20: Node = EN.new(); t20.type = 2; add_child(t20)
	GameState.current_level = 24
	var t24: Node = EN.new(); t24.type = 2; add_child(t24)
	GameState.current_level = 22
	var t22: Node = EN.new(); t22.type = 2; add_child(t22)
	await get_tree().process_frame
	_check(t20.max_hp == int(round(16.0 * 2.90)), "sector 20 tank HP unchanged (%d)" % t20.max_hp)
	GameState.current_level = 20
	var g20: Node = EN.new(); g20.type = 0; add_child(g20)
	await get_tree().process_frame
	_check(is_equal_approx(g20.fire_interval, 2.8 * 0.45), "sector 20 grunt fire rate unchanged")
	_check(t22.max_hp == int(round(16.0 * (0.70 + 2.2 * 21.0 / 19.0))), "sector 22 tank above the old ceiling (%d)" % t22.max_hp)
	_check(t24.max_hp == int(round(16.0 * (0.70 + 2.2 * 23.0 / 19.0) * 1.08)), "sector 24 tank HP %d (ladder + late bonus)" % t24.max_hp)
	_check(is_equal_approx(t24.fire_interval, t20.fire_interval * 0.88), "sector 24 fires 12%% faster than sector 20 (%.3f vs %.3f)" % [t24.fire_interval, t20.fire_interval])
	_check(t24.speed > t20.speed and t24.contact_damage > t20.contact_damage, "sector 24 faster and harder-hitting than 20")

	# --- Upgrades stretched ---
	var pl: Node = load("res://scripts/Player.gd").new()
	pl.position = Vector2(400, 1000)
	add_child(pl)
	await get_tree().process_frame
	_check(pl.max_power_level == 30 and Player.ENERGY_CELL_MAX == 8 and Player.TORPEDO_CAP == 10, "caps: power 30, cells 8, torpedoes 10")
	_check(int(pl._bullet_tier_for_level(27)["damage"]) == 3 and int(pl._bullet_tier_for_level(28)["damage"]) == 4, "void bullet tier from L28")
	pl.power_level = 27
	var pb: int = get_child_count()
	pl._fire_phaser_pattern() if pl.has_method("_fire_phaser_pattern") else pl._spawn_bullet(Vector2.ZERO, Vector2.UP)
	var phaser_shots: int = get_child_count() - pb
	_check(phaser_shots == 9 or not pl.has_method("_fire_phaser_pattern"), "L27 phaser spreads 9 bullets (%d)" % phaser_shots)
	var mb: int = get_child_count()
	pl._fire_missile_pattern()
	_check(get_child_count() - mb == 6, "L27 fires a six-missile salvo (%d)" % (get_child_count() - mb))
	pl.queue_free()

	# --- Starfield acts ---
	var SF = load("res://scripts/Starfield.gd")
	var sf21: Node = SF.new(); sf21.level = 21; add_child(sf21)
	var sf24: Node = SF.new(); sf24.level = 24; add_child(sf24)
	await get_tree().process_frame
	_check(sf21._backdrop_color.b > sf21._backdrop_color.r, "sectors 20-22 get the cold Heart palette")
	_check(sf24._backdrop_color.r > sf24._backdrop_color.b, "sectors 23-24 keep the blood-red finale palette")
	sf21.queue_free(); sf24.queue_free()

	# --- Missiles: 10% softer on bosses only ---
	GameState.current_level = 24
	var m: Node = load("res://scripts/Missile.gd").new()
	m.damage = 30
	add_child(m)
	var boss: Node = load("res://scripts/Boss.gd").new()
	boss.type = 5
	add_child(boss)
	var enemy: Node = load("res://scripts/Enemy.gd").new()
	enemy.type = 2
	add_child(enemy)
	await get_tree().process_frame
	_check(m.damage_against(boss) == 27, "missile vs boss 30 -> 27, got %d" % m.damage_against(boss))
	_check(m.damage_against(enemy) == 30, "missile vs enemy stays 30")
	m.damage = 5
	_check(m.damage_against(boss) == 5, "small missile rounds to 5 (4.5 -> 5)")

	# --- Sector 18 untouched by any late bonus ---
	GameState.current_level = 18
	var e18: Node = load("res://scripts/Enemy.gd").new(); e18.type = 2; add_child(e18)
	await get_tree().process_frame
	_check(e18.max_hp == int(round(16.0 * lerp(0.70, 2.90, 17.0 / 19.0))), "sector 18 tank unchanged (%d)" % e18.max_hp)

	# --- Sidekick: a charged shield eats the whole first hit ---
	var sk: Node = load("res://scripts/Sidekick.gd").new()
	add_child(sk)
	await get_tree().process_frame
	var hp0: int = sk.hp
	sk.take_damage(5)
	_check(sk.hp == hp0 and sk.shield == 0.0, "first 5-point hit fully absorbed (hp %d/%d)" % [sk.hp, hp0])
	sk.take_damage(5)
	_check(sk.hp == hp0 - 5, "second hit lands in full (hp %d)" % sk.hp)
	sk._shield_recharge_wait = 0.0
	for i in 60:
		sk._process(0.1)   # 6 s at 0.35/s refills the 1-point shield
	_check(sk.shield >= 1.0, "shield recharges after the quiet window (%.2f)" % sk.shield)
	sk.take_damage(3)
	_check(sk.hp == hp0 - 5, "recharged shield blocks again")

	# --- First-launch name prompt gate ---
	var cfg_backup: String = ""
	if FileAccess.file_exists(Online.NAME_PATH):
		cfg_backup = FileAccess.get_file_as_string(Online.NAME_PATH)
	var saved_name: String = Online.pilot_name
	var saved_asked: bool = Online.name_asked
	var saved_debug: bool = Online.allow_debug
	Online.allow_debug = true
	Online.pilot_name = ""
	Online.name_asked = false
	_check(Online.should_ask_name(), "fresh install with no name asks")
	Online.pilot_name = "Pilot-1234"
	_check(Online.should_ask_name(), "server default Pilot-#### still asks")
	Online.pilot_name = "Yaniv"
	_check(not Online.should_ask_name(), "a custom name never asks")
	Online.pilot_name = ""
	Online.mark_name_asked()
	_check(not Online.should_ask_name(), "LATER is remembered")
	var cfg := ConfigFile.new()
	cfg.load(Online.NAME_PATH)
	_check(bool(cfg.get_value("p", "asked", false)), "asked flag persisted in pilot.cfg")
	Online.allow_debug = false
	Online.name_asked = false
	_check(not Online.should_ask_name(), "debug builds (offline) never ask")
	# restore the real pilot.cfg
	Online.allow_debug = saved_debug
	Online.name_asked = saved_asked
	Online.pilot_name = saved_name
	if cfg_backup != "":
		var f := FileAccess.open(Online.NAME_PATH, FileAccess.WRITE)
		f.store_string(cfg_backup)
		f.close()
	elif FileAccess.file_exists(Online.NAME_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Online.NAME_PATH))

	# --- Cutscene audio hooks ---
	var music: AudioStream = AudioManager.CUTSCENE_MUSIC
	_check(music != null and music.get_length() > 60.0, "cutscene music loads (%.1fs)" % (music.get_length() if music else 0.0))
	var line: AudioStream = AudioManager.narration_for("cutscene_00_intro_03_decoded_sigil")
	_check(line != null, "narration clip found for a known beat")
	_check(AudioManager.narration_for("no_such_beat") == null, "unknown beat has no narration")
	var missing: int = 0
	for key in [CutsceneData.INTRO_KEY, CutsceneData.ACT_1_KEY, CutsceneData.ACT_2_KEY, CutsceneData.ACT_3_KEY, CutsceneData.ACT_4_KEY, CutsceneData.ENDING_KEY]:
		for beat in CutsceneData.beats_for(key):
			if AudioManager.narration_for(String(beat["image_file"])) == null:
				missing += 1
	_check(missing == 0, "every story beat has a narration clip (%d missing)" % missing)
	var spoken: float = AudioManager.play_voice(line)
	_check(spoken > 0.5 and spoken < 4.0, "play_voice returns the clip length (%.2fs)" % spoken)
	_check(AudioManager._ducked, "music ducks while the line plays")
	AudioManager.play_cutscene_music()
	_check(AudioManager._cutscene_music_on and AudioManager._music_player.stream == music, "cutscene music takes the live deck")
	AudioManager.end_cutscene_music()
	_check(not AudioManager._cutscene_music_on and not AudioManager._ducked, "end restores game music and lifts the duck")
	_check(AudioManager.process_mode == Node.PROCESS_MODE_ALWAYS, "audio keeps running while the tree is paused")
	_check(Engine.max_fps == 60, "frame cap 60 (got %d)" % Engine.max_fps)

	GameState.current_level = saved_lvl
	print("FinaleTest: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
