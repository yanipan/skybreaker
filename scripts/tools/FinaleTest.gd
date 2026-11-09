extends Node
## Headless check of the 9/11 playtest changes: finale boss pair + end-on-kill,
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
	# --- Sector 20: Prism Warden then THE SKYBREAKER, stage ends on the kill ---
	var sp: Node = _spawner_for(20)
	await get_tree().process_frame
	_check(sp.ends_on_boss(), "sector 20 ends on the last boss")
	_check(sp._boss_queue.size() == 2, "sector 20 queues two bosses, got %d" % sp._boss_queue.size())
	_check(not sp.boss_sequence_done(), "sequence not done before any boss")
	sp._mission_time = sp.get_level_duration()   # timer over, no boss yet
	_check(not sp.boss_sequence_done(), "timer alone cannot finish a boss stage")
	sp._spawn_boss()
	await get_tree().process_frame
	var warden: Node = _bosses()[0] if not _bosses().is_empty() else null
	_check(warden != null and warden.type == 3, "first boss is the Crystal Prism hull")
	_check(warden != null and warden.boss_name == "PRISM WARDEN", "first boss is named PRISM WARDEN, got %s" % (warden.boss_name if warden else "none"))
	_check(warden != null and warden.max_hp == int(round(1050.0 * 1.6 * 0.7)), "warden HP = 70%% of a sector-20 Prism (%d)" % (warden.max_hp if warden else -1))
	_check(sp._boss_phase(), "boss phase while the warden lives")
	_check(not sp.boss_sequence_done(), "sequence not done while the warden lives")
	_kill_bosses()
	await get_tree().process_frame
	_check(sp._boss_phase(), "boss phase holds between the two bosses")
	_check(not sp.boss_sequence_done(), "warden down, Skybreaker pending: not done")
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
	# --- Sector 19: single boss, timer still rules ---
	var sp19: Node = _spawner_for(19)
	await get_tree().process_frame
	_check(not sp19.ends_on_boss(), "sector 19 still runs its timer")
	_check(sp19._boss_queue.size() == 1, "sector 19 has one boss")
	sp19._spawn_boss()
	await get_tree().process_frame
	_check(_bosses().size() == 1 and _bosses()[0].type == 4, "sector 19 boss is the Void Reaper")
	_kill_bosses()
	await get_tree().process_frame
	_check(sp19.boss_sequence_done(), "sector 19 done after its boss")
	var sp3: Node = _spawner_for(3)
	await get_tree().process_frame
	_check(sp3.boss_sequence_done(), "no-boss stage reports done")
	sp3.queue_free()
	sp19.queue_free()

	# --- Missiles: 10% softer on bosses only ---
	GameState.current_level = 20
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

	# --- Late sectors: +8% hull and ram damage, sector 18 untouched ---
	var tank20: int = enemy.max_hp
	_check(tank20 == int(round(16.0 * 2.90 * 1.08)), "sector 20 tank HP %d (was %d)" % [tank20, int(round(16.0 * 2.90))])
	GameState.current_level = 19
	var e19: Node = load("res://scripts/Enemy.gd").new(); e19.type = 2; add_child(e19)
	GameState.current_level = 18
	var e18: Node = load("res://scripts/Enemy.gd").new(); e18.type = 2; add_child(e18)
	await get_tree().process_frame
	var t19: float = 18.0 / 19.0
	var t18: float = 17.0 / 19.0
	_check(e19.max_hp == int(round(16.0 * lerp(0.70, 2.90, t19) * 1.08)), "sector 19 tank gets the bonus (%d)" % e19.max_hp)
	_check(e18.max_hp == int(round(16.0 * lerp(0.70, 2.90, t18))), "sector 18 tank unchanged (%d)" % e18.max_hp)
	_check(e19.contact_damage > e18.contact_damage, "sector 19 ram damage above sector 18")

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
