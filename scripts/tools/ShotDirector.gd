extends Node
## Dev-only store screenshot director. Drives the real game with no human
## input through 8 store beats and saves a master PNG per beat (plus
## alternates for the action beats) at the full native framebuffer size.
##
## Run (the window must be borderless so macOS does not clamp it to the
## screen height; the borderless flag goes in a temporary override.cfg):
##   printf '[display]\nwindow/size/borderless=true\n' > override.cfg
##   Godot --path . --resolution 1290x2796 --position 0,0 -- --shots=phone
##   Godot --path . --resolution 2048x2732 --position 0,0 -- --shots=tablet
##   rm override.cfg
## Add `--beats=boss,shop` after --shots to re-shoot only those beats.
## Android tablet is captured natively too: --resolution 1600x2560 --shots=tablet_android
##
## Output: res://assets/store/screenshots/master_gameplay/<phone|tablet>/NN_<slug>[_x].png
## scripts/tools/compose_store_shots.py turns the masters into the store set.
##
## Mounted in debug builds only by the DevTools autoload. Without a
## --shots=<name> user arg it frees itself on the first frame, so normal
## debug runs are untouched. It writes a fake mid-run into GameState, so it
## backs up user://savegame.* first and puts the originals back at the end.

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const START_SCENE: String = "res://scenes/main/StartScreen.tscn"
const OUT_ROOT: String = "res://assets/store/screenshots/master_gameplay/"

const PlayerScript := preload("res://scripts/Player.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const BossScript := preload("res://scripts/Boss.gd")
const CutsceneScript := preload("res://scripts/Cutscene.gd")
const ShopScript := preload("res://scripts/StarbaseShop.gd")

var _mode: String = ""
## Optional `--beats=boss,shop` filter to re-shoot only some beats.
var _only: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _main: Node = null
var _player: Node = null
## Keeps the charge pool full and the camera still while a beat is staged.
var _keep_alive: bool = false
var _sweep_t: float = 0.0
var _sweep_enabled: bool = false
var _sweep_center: Vector2 = Vector2.ZERO
var _sweep_amp: float = 0.0
## Boss HP is pinned to this fraction so player fire never kills it mid-beat.
var _boss_hp_frac: float = -1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_mode = a.substr(8)
		elif a.begins_with("--beats="):
			_only = a.substr(8).split(",")
	if _mode == "" or not OS.is_debug_build():
		set_process(false)
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_out_dir = OUT_ROOT + _mode + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	# Silent capture; nothing here is heard by players.
	AudioServer.set_bus_mute(0, true)
	_backup_save()
	call_deferred("_run")


func _process(delta: float) -> void:
	if not _keep_alive:
		return
	if _player != null and is_instance_valid(_player):
		_player._current_charge = _player.max_charge
		_player._is_firing = true
		if _sweep_enabled:
			_sweep_t += delta
			_player._target_position = _sweep_center + Vector2(sin(_sweep_t * 1.6) * _sweep_amp, sin(_sweep_t * 0.9) * 30.0)
	if _main != null and is_instance_valid(_main):
		# Main opens its pause overlay when the window loses focus (it treats
		# that like a phone going to the background). Close it straight away
		# so a capture never shows PAUSED or a frozen field.
		if _main._pause_layer != null or _main._pause_pending:
			_main._pause_pending = false
			_main._close_pause()
		_main._shake_time_left = 0.0
		if _main._camera != null:
			_main._camera.offset = Vector2.ZERO
	if _boss_hp_frac > 0.0:
		for b in get_tree().get_nodes_in_group(&"bosses"):
			if is_instance_valid(b):
				b.hp = int(b.max_hp * _boss_hp_frac)


# --- Sequence ---

func _run() -> void:
	await _frames(30)
	var img: Image = get_viewport().get_texture().get_image()
	print("ShotDirector: mode=%s framebuffer=%s visible=%s" % [_mode, img.get_size(), get_viewport().get_visible_rect().size])
	if _mode == "probe":
		get_tree().quit()
		return
	for beat in ["title", "combat", "chaos", "beam", "torpedo", "boss", "shop", "story"]:
		if _only.is_empty() or _only.has(beat):
			await call("_beat_" + beat)
	_keep_alive = false
	# Free Main first: on quit the window loses focus and Main's focus-out
	# handler would save the fake run after the restore.
	get_tree().paused = false
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	_main = null
	_player = null
	await _frames(3)
	_restore_save()
	print("=== ShotDirector DONE (%s) ===" % _mode)
	get_tree().quit()


func _beat_title() -> void:
	GameState.has_active_run = true
	GameState.high_score = 128450
	get_tree().paused = false
	get_tree().change_scene_to_file(START_SCENE)
	await _frames(4)
	await _wait(3.0)
	await _snap("01_title")


func _beat_combat() -> void:
	# Low-level phaser so enemies survive long enough to fill the screen.
	await _enter_main(6, PlayerScript.WeaponType.PHASER, 3)
	_sweep(0.16)
	var names: Array = ["02_combat_a", "02_combat_b", "02_combat_c"]
	for n in names:
		for i in 3:
			_spawner()._spawn_wave()
			await _wait(0.5)
		# Keep the frame with the most enemies in the part of the screen the
		# store headline band does not cover.
		var vs: Vector2 = get_viewport().get_visible_rect().size
		var best: Image = null
		var best_n: int = -1
		for k in 10:
			await _wait(0.12)
			if k == 6:
				_pop_enemies(1)
			await RenderingServer.frame_post_draw
			var cnt: int = 0
			for e in get_tree().get_nodes_in_group(&"enemies"):
				if is_instance_valid(e) and e.global_position.y > vs.y * 0.24 and e.global_position.y < vs.y * 0.70:
					cnt += 1
			if k >= 7 and cnt > best_n:
				best_n = cnt
				best = get_viewport().get_texture().get_image()
		best.save_png(_out_dir + n + ".png")
		print("ShotDirector: %s %s (%d enemies in view)" % [n, best.get_size(), best_n])


func _beat_chaos() -> void:
	await _enter_main(17, PlayerScript.WeaponType.PHASER, 18)
	_player._grant_sidekick()
	_sweep(0.14)
	for i in 4:
		_spawner()._spawn_wave()
		await _wait(0.7)
	var names: Array = ["03_chaos_a", "03_chaos_b", "03_chaos_c"]
	for n in names:
		_spawner()._spawn_wave()
		_drop_pickups(3)
		await _wait(0.8)
		_pop_enemies(2)
		await _wait(0.14)
		await _snap(n)


func _beat_beam() -> void:
	# Beam level 7 = one wide beam; higher tiers become three solid pillars
	# that hide the enemies they hit.
	await _enter_main(14, PlayerScript.WeaponType.BEAM, 7)
	_sweep(0.12)
	for i in 4:
		_spawner()._spawn_wave()
		await _wait(0.5)
	var names: Array = ["04_beam_a", "04_beam_b", "04_beam_c"]
	for n in names:
		_spawner()._spawn_wave()
		await _wait(0.5)
		_spawner()._spawn_wave()
		await _wait(0.7)
		await _snap(n)


func _beat_torpedo() -> void:
	await _enter_main(10, PlayerScript.WeaponType.PHASER, 3)
	_player.max_torpedoes = 5
	_player.torpedo_count = 5
	_sweep(0.0)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var names: Array = ["05_torpedo_a", "05_torpedo_b", "05_torpedo_c"]
	var delays: Array = [0.08, 0.16, 0.24]
	for i in names.size():
		for k in 4:
			_spawner()._spawn_wave()
			await _wait(0.45)
		await _wait(0.9)
		_player._torpedo_grace_timer = 0.0
		_player._try_fire_torpedo()
		# Burst it mid-screen the way a player does with a second tap.
		var guard: int = 0
		while guard < 240:
			var ts: Array = get_tree().get_nodes_in_group(&"player_torpedoes")
			if ts.is_empty():
				break
			if ts[0].position.y < vs.y * 0.42:
				ts[0].detonate_now()
				break
			await _frames(1)
			guard += 1
		await _wait(delays[i])
		await _snap(names[i])
		await _wait(1.2)


func _beat_boss() -> void:
	# Three bosses, one alternate each: Brood (BOSS3, L12), Crystal (BOSS4, L16),
	# and the Skybreaker itself (FINAL, L20).
	var plan: Array = [
		{"level": 12, "boss": 2, "name": "06_boss_a"},
		{"level": 16, "boss": 3, "name": "06_boss_b"},
		{"level": 20, "boss": 5, "name": "06_boss_c"},
	]
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for p in plan:
		await _enter_main(int(p.level), PlayerScript.WeaponType.PHASER, 6)
		var sp: Node = _spawner()
		sp._boss_type_idx = int(p.boss)
		sp._spawn_boss()
		# Pinned at full HP: any damage makes the boss emit white smoke puffs that hide its art.
		_boss_hp_frac = 1.0
		_sweep(0.10)
		var boss: Node = get_tree().get_first_node_in_group(&"bosses")
		# Fight line lower than the default 200 px so the whole hull
		# clears the HUD and the store headline band in a still.
		boss._target_y = vs.y * 0.30
		var guard: int = 0
		while not boss._entry_done and guard < 600:
			await _frames(1)
			guard += 1
		await _wait(1.6)
		boss.position.x = vs.x * 0.5
		boss._drift_speed = 30.0
		# Sample a few seconds of the fight and keep the frame with the most
		# boss bullets in the air, so the pattern actually reads.
		var best: Image = null
		var best_n: int = -1
		for i in 16:
			await _wait(0.15)
			if _main._camera != null:
				_main._camera.offset = Vector2.ZERO
			await RenderingServer.frame_post_draw
			var n: int = get_tree().get_nodes_in_group(&"enemy_bullets").size()
			if n > best_n:
				best_n = n
				best = get_viewport().get_texture().get_image()
		var path: String = _out_dir + String(p.name) + ".png"
		best.save_png(path)
		print("ShotDirector: %s %s -> %s (%d bullets)" % [p.name, best.get_size(), path, best_n])
		_boss_hp_frac = -1.0


func _beat_shop() -> void:
	await _enter_main(7, PlayerScript.WeaponType.PHASER, 9)
	GameState.money = 18450
	EventBus.money_changed.emit(GameState.money)
	await _wait(0.5)
	_keep_alive = false
	get_tree().paused = true
	var shop: CanvasLayer = ShopScript.new()
	shop.player_ref = _player
	shop.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(shop)
	await _wait(1.0)
	await _snap("07_shop")
	shop.queue_free()
	get_tree().paused = false


func _beat_story() -> void:
	var picks: Array = [
		{"key": &"act1", "idx": 0, "name": "08_story_a"},
		{"key": &"act4", "idx": 1, "name": "08_story_b"},
		{"key": &"intro", "idx": 3, "name": "08_story_c"},
	]
	await _enter_main(5, PlayerScript.WeaponType.PHASER, 8)
	_keep_alive = false
	for p in picks:
		var beats: Array = CutsceneData.beats_for(p.key)
		var beat: Dictionary = beats[int(p.idx)].duplicate()
		beat["duration"] = 30.0
		var cs: CanvasLayer = CutsceneScript.new()
		_main.add_child(cs)
		cs.play([beat])
		await _wait(1.6)
		await _snap(String(p.name))
		cs.queue_free()
		get_tree().paused = false
		await _frames(2)


# --- Staging helpers ---

## Load Main at `level` with a mid-run loadout and make the player a
## capture puppet: invulnerable, always firing, no mouse steering.
func _enter_main(level: int, weapon: int, weapon_lvl: int) -> void:
	_keep_alive = false
	_sweep_enabled = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.current_level = level
	GameState.lives = 3
	GameState.money = 14250
	GameState.intro_seen = true
	GameState.has_active_run = true
	GameState.pending_warp_entry = false
	GameState.high_score = 128450
	GameState.clear_respawn()
	GameState.clear_carry()
	GameState.carry_active = true
	GameState.carry_hp = 20
	GameState.carry_max_shield = 2
	GameState.carry_shield = 2.0
	GameState.carry_max_torpedoes = 3
	GameState.carry_torpedo_count = 3
	GameState.carry_weapon_type = weapon
	GameState.carry_weapon_levels = {0: weapon_lvl, 1: weapon_lvl, 2: weapon_lvl}
	GameState.carry_power_level = weapon_lvl
	GameState.carry_energy_cells = 2
	GameState.carry_speed_tier = 1
	get_tree().change_scene_to_file(MAIN_SCENE)
	await _frames(3)
	_main = get_tree().current_scene
	_player = get_tree().get_first_node_in_group(&"player")
	GameState.mission_score = 20000 + level * 2150
	if _main.has_method("_refresh_hud"):
		_main._refresh_hud()
	# Level banner would sit across the middle of every frame.
	if _main._level_banner != null:
		_main._level_banner.queue_free()
		_main._level_banner = null
		_main._banner_time_left = 0.0
	# Shake moves the camera off the playfield edge; stills don't need it.
	if EventBus.screen_shake_requested.is_connected(_main._on_screen_shake_requested):
		EventBus.screen_shake_requested.disconnect(_main._on_screen_shake_requested)
	var sp: Node = _spawner()
	sp._starbase_enabled = false
	sp._boss_enabled = false
	sp._life_enabled = false
	sp._sidekick_enabled = false
	sp._timer = 999.0   # we spawn the waves ourselves
	_show_mobile_controls()
	_make_puppet()
	_keep_alive = true
	await _frames(2)


func _make_puppet() -> void:
	if _player == null:
		return
	if _player.area_entered.is_connected(_player._on_area_entered):
		_player.area_entered.disconnect(_player._on_area_entered)
	var p: Node = _player
	_player.area_entered.connect(func(area: Area2D) -> void:
		if is_instance_valid(p) and area.is_in_group(&"pickups"):
			p._consume_pickup(area)
	)
	_player.set_process_unhandled_input(false)
	_player._is_firing = true


## Desktop hides the touch layer; a phone player always sees it.
func _show_mobile_controls() -> void:
	for c in _main.get_children():
		if c is MobileControls and not c.visible:
			c.force_visible = true
			c._ready()
			# Same right-column shift Main applies on mobile for the pause button.
			_main._score_label.position.x -= 112.0
			_main._high_score_label.position.x -= 112.0


func _sweep(amp_frac: float) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_sweep_center = Vector2(vs.x * 0.5, vs.y * 0.74)
	_sweep_amp = vs.x * amp_frac
	_sweep_t = 0.0
	_sweep_enabled = true
	_player.position = _sweep_center
	_player._target_position = _sweep_center


func _spawner() -> Node:
	return _main._spawner


## Kill the `n` enemies nearest the upper-middle playfield so their burst is
## mid-bloom in the next capture.
func _pop_enemies(n: int) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var cands: Array = []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or e.is_in_group(&"bosses"):
			continue
		var pos: Vector2 = e.global_position
		if pos.y > vs.y * 0.18 and pos.y < vs.y * 0.58 and pos.x > vs.x * 0.12 and pos.x < vs.x * 0.88:
			cands.append(e)
	cands.shuffle()
	for i in min(n, cands.size()):
		cands[i].take_damage(99999)


func _drop_pickups(n: int) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var types: Array = [Pickup.Type.POWER_PHASER, Pickup.Type.MONEY, Pickup.Type.TORPEDO, Pickup.Type.POWER_BEAM, Pickup.Type.HEALTH_MEDIUM]
	for i in n:
		var pk: Area2D = PickupScript.new()
		pk.type = types[randi() % types.size()]
		if pk.type == Pickup.Type.MONEY:
			pk.money_value = 50
		pk.position = Vector2(randf_range(vs.x * 0.2, vs.x * 0.8), randf_range(vs.y * 0.25, vs.y * 0.45))
		_main.add_child(pk)


func _snap(name: String) -> void:
	if _main != null and is_instance_valid(_main) and _main._camera != null:
		_main._camera.offset = Vector2.ZERO
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir + name + ".png"
	var err: int = img.save_png(path)
	print("ShotDirector: %s %s -> %s (err %d)" % [name, img.get_size(), path, err])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


const SAVE_FILES: Array = ["user://savegame.dat", "user://savegame.tmp", "user://savegame.bak"]
const SAVE_BACKUP_DIR: String = "user://shotdirector_backup/"


## The capture writes a fake run into GameState and some paths save it, so
## the player's real save is parked before and restored after.
func _backup_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_BACKUP_DIR))
	for f in SAVE_FILES:
		var dst: String = SAVE_BACKUP_DIR + String(f).get_file()
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
		if FileAccess.file_exists(f):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(f), ProjectSettings.globalize_path(dst))


func _restore_save() -> void:
	for f in SAVE_FILES:
		var src: String = SAVE_BACKUP_DIR + String(f).get_file()
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(f))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_BACKUP_DIR))
	print("ShotDirector: save files restored")
