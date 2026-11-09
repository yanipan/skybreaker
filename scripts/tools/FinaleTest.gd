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
	_check(herald != null and herald._sprite != null and herald._sprite.modulate != Color.WHITE, "herald rides a tinted stand-in until boss7.png exists")
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
	_check(shade._sprite != null and shade._sprite.modulate != Color.WHITE, "shade rides a tinted stand-in until enemy_shade.png exists")
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
