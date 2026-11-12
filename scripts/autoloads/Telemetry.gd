extends Node
## Anonymous gameplay stats (6/11). One random player id per install (UUID v4
## from the crypto RNG, never a device or advertising id). Events queue in
## memory and on disk and go out as ONE batched POST at natural breaks (sector
## end, death, game over, app to background, back to menu, launch), because
## the SiteGround host captcha-blocks bursts from one IP. Failed sends stay
## queued for the next break. Player can switch it off on the Settings page.
## Server: englishapp.shimonster.com/skybreaker/api/track.php (+ stats.php).

const ENDPOINT: String = "https://englishapp.shimonster.com/skybreaker/api/track.php"
const KEYS := preload("res://config/online_keys.gd")
var APP_KEY: String:
	get: return KEYS.APP_KEY
const CFG_PATH: String = "user://telemetry.cfg"
const QUEUE_PATH: String = "user://telemetry_queue.json"
const MAX_QUEUE: int = 300
const MAX_BATCH: int = 100

var enabled: bool = true
## Editor / headless test runs are debug builds: they never send, so dev
## sessions don't pollute the stats. Tests flip this to exercise the wire.
var allow_debug_send: bool = false
var player_id: String = ""
var run_id: String = ""
var _queue: Array = []
var _in_flight: int = 0          ## Events in the batch currently being sent
var _http: HTTPRequest
## Per-sector counters, reset when a sector/death snapshot is taken.
var fire_secs: Array = [0.0, 0.0, 0.0]
var torps_fired: int = 0
var sector_secs: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cfg()
	_load_queue()
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_done)
	add_child(_http)
	track("session_start", {
		"side": "right" if GameState.controls_side == GameState.ControlsSide.RIGHT else "left",
		"joystick": GameState.joystick_enabled,
	})
	call_deferred("flush")


func _process(delta: float) -> void:
	if not get_tree().paused:
		sector_secs += delta


# --- Identity / settings ---

func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	player_id = str(cfg.get_value("t", "player_id", ""))
	run_id = str(cfg.get_value("t", "run_id", ""))
	enabled = bool(cfg.get_value("t", "enabled", true))
	if not _valid_uuid(player_id):
		player_id = new_uuid()
		_save_cfg()


func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("t", "player_id", player_id)
	cfg.set_value("t", "run_id", run_id)
	cfg.set_value("t", "enabled", enabled)
	cfg.save(CFG_PATH)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_queue.clear()
		_save_queue()
	_save_cfg()


static func new_uuid() -> String:
	var b: PackedByteArray = Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h: String = b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


static func _valid_uuid(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	return re.search(s) != null


# --- Events ---

func track(event_name: String, data: Dictionary = {}) -> void:
	if not enabled or OS.has_feature("dedicated_server"):
		return
	var e: Dictionary = {
		"name": event_name,
		"run_id": run_id,
		"sector": GameState.current_level,
		"score": GameState.run_score,
		"money": GameState.money,
		"ts": int(Time.get_unix_time_from_system()),
	}
	if not data.is_empty():
		e["data"] = data
	_queue.append(e)
	if _queue.size() > MAX_QUEUE:
		_queue = _queue.slice(_queue.size() - MAX_QUEUE)
		_in_flight = 0
	_save_queue()


func start_run(kind: String) -> void:
	if kind == "new" or run_id == "":
		run_id = new_uuid().replace("-", "").substr(0, 16)
		_save_cfg()
	reset_sector_counters()
	track("run_start", {"kind": kind, "lives": GameState.lives})


func end_run() -> void:
	run_id = ""
	_save_cfg()


## Loadout + per-sector counters, attached to sector_complete / death / quit.
func snapshot(player: Node) -> Dictionary:
	var d: Dictionary = {
		"fire": [snappedf(fire_secs[0], 0.1), snappedf(fire_secs[1], 0.1), snappedf(fire_secs[2], 0.1)],
		"torps": torps_fired,
		"t": int(sector_secs),
		"lives": GameState.lives,
		"kills": GameState.mission_kills,
		"dmg": GameState.mission_damage_taken,
		"earned": GameState.mission_money,
		"fb": GameState.hit_fallbacks,
		"stalls": GameState.physics_stalls,
		"fps": Engine.get_frames_per_second(),
	}
	if player != null and is_instance_valid(player):
		var wl: Dictionary = player.weapon_levels if "weapon_levels" in player else {}
		d["w"] = [int(wl.get(0, 1)), int(wl.get(1, 1)), int(wl.get(2, 1))]
		d["wt"] = int(player.weapon_type)
		d["hp"] = int(player.hp)
		d["hp_max"] = int(player.max_hp)
		d["torp"] = int(player.torpedo_count)
		d["torp_max"] = int(player.max_torpedoes)
		d["cells"] = int(player.energy_cells_bought)
		d["shield_max"] = int(player.max_shield)
		d["speed"] = int(player.speed_tier)
		d["sidekick"] = player.get_tree().get_first_node_in_group(&"sidekick") != null
	return d


func reset_sector_counters() -> void:
	fire_secs = [0.0, 0.0, 0.0]
	torps_fired = 0
	sector_secs = 0.0


func add_fire_time(wt: int, delta: float) -> void:
	if wt >= 0 and wt < 3:
		fire_secs[wt] += delta


# --- Transport ---

func flush() -> void:
	if not enabled or _queue.is_empty() or _in_flight > 0 or _http == null:
		return
	if OS.is_debug_build() and not allow_debug_send:
		return
	if OS.has_feature("dedicated_server"):
		return   # a room server is not an install: it sends no telemetry
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var batch: Array = _queue.slice(0, MAX_BATCH)
	var body: Dictionary = {
		"player_id": player_id,
		"platform": OS.get_name(),
		"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"os_version": OS.get_version(),
		"model": OS.get_model_name(),
		"locale": OS.get_locale_language(),
		"events": batch,
	}
	var err: int = _http.request(ENDPOINT, ["Content-Type: application/json", "X-SB-Key: " + APP_KEY],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err == OK:
		_in_flight = batch.size()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var sent: int = _in_flight
	_in_flight = 0
	# SiteGround's captcha answers 202 with HTML, so only a JSON success counts.
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var j: Variant = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary and j.get("success", false):
			_queue = _queue.slice(mini(sent, _queue.size()))
			_save_queue()
			if not _queue.is_empty():
				call_deferred("flush")


func _save_queue() -> void:
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))


func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var f := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if f == null:
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	if j is Array:
		_queue = j
