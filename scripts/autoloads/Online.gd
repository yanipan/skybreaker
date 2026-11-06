extends Node
## Pilot names, leaderboards and friend challenges (1.0.1).
## Every request is signed: X-SB-Ts + X-SB-Sig = HMAC-SHA256(key, ts + "." + body).
## The server also issues a single-use run token at run start and checks the
## final score against real elapsed time, per-sector ceilings and the sector
## log, so copying the URL or replaying a request does not get a score on the
## board. Nothing here ever blocks play: failures just mean "not ranked".

signal run_finished(result: Dictionary)

const ENDPOINT: String = "https://englishapp.shimonster.com/skybreaker/api/lb.php"
const KEYS := preload("res://config/online_keys.gd")
const PENDING_PATH: String = "user://pending_run_end.json"
const TIMEOUT: float = 10.0

var allow_debug: bool = false   ## Debug builds stay offline unless a test turns this on
var pilot_name: String = "":
	set(v):
		if v != pilot_name:
			pilot_name = v
			var cfg := ConfigFile.new()
			cfg.set_value("p", "name", v)
			cfg.save(NAME_PATH)
const NAME_PATH: String = "user://pilot.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(NAME_PATH) == OK:
		pilot_name = str(cfg.get_value("p", "name", ""))
	call_deferred("retry_pending")


func _sig_key() -> PackedByteArray:
	return KEYS.SIG_KEY.to_utf8_buffer()


func _sign(ts: int, body: String) -> String:
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, _sig_key())
	h.update((str(ts) + "." + body).to_utf8_buffer())
	return h.finish().hex_encode()


func online_ok() -> bool:
	return not OS.is_debug_build() or allow_debug


## POST one action. Returns the parsed JSON dictionary, or {} on any failure.
func call_api(body: Dictionary) -> Dictionary:
	if not online_ok():
		return {}
	body["player_id"] = Telemetry.player_id
	var raw: String = JSON.stringify(body)
	var ts: int = int(Time.get_unix_time_from_system())
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var err: int = http.request(ENDPOINT, [
		"Content-Type: application/json",
		"X-SB-Key: " + Telemetry.APP_KEY,
		"X-SB-Ts: " + str(ts),
		"X-SB-Sig: " + _sign(ts, raw),
	], HTTPClient.METHOD_POST, raw)
	if err != OK:
		http.queue_free()
		return {}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {}
	var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return j if j is Dictionary else {}


# --- Runs ---

## Register the run. Normal runs keep the local seed; challenges take the
## challenger's seed from the server (caller waits for that).
func start_run(code: String = "") -> Dictionary:
	var body: Dictionary = {"action": "run_start"}
	if code != "":
		body["challenge_code"] = code
	else:
		body["seed"] = GameState.run_seed
	var r: Dictionary = await call_api(body)
	if r.get("success", false):
		GameState.run_token = str(r.get("run_token", ""))
		if code != "":
			GameState.run_seed = int(r.get("seed", GameState.run_seed))
		if r.has("name"):
			pilot_name = str(r["name"])
		GameState.save_run_state()
	return r


## Call while GameState still holds the run (before the game-over wipe).
func record_sector(sector: int, secs: float) -> void:
	GameState.run_sectors.append({"sector": sector, "score": GameState.run_score, "t": snappedf(secs, 0.1)})


func finish_run(won: bool) -> void:
	var cleared: int = GameState.run_sectors.size()
	var result: Dictionary = {
		"score": GameState.run_score,
		"sector": GameState.current_level,
		"won": won,
		"ranked": false,
		"token": GameState.run_token,
		"challenge_name": GameState.challenge_name,
		"challenge_target": GameState.challenge_target,
	}
	GameState.last_run = result
	if GameState.run_token == "":
		run_finished.emit(result)
		return
	var body: Dictionary = {
		"action": "run_end", "run_token": GameState.run_token,
		"score": GameState.run_score, "sector": GameState.current_level,
		"cleared": cleared, "sectors": GameState.run_sectors.duplicate(),
	}
	_save_pending(body)
	var r: Dictionary = await call_api(body)
	if r.has("success") or r.has("error"):
		_clear_pending()
	if r.get("success", false):
		result["ranked"] = bool(r.get("counted", false))
		result["rank_all"] = int(r.get("rank_all", 0))
		result["rank_week"] = int(r.get("rank_week", 0))
		if r.has("challenge"):
			result["challenge_beat"] = bool(r["challenge"].get("beat", false))
	GameState.last_run = result
	run_finished.emit(result)


func _save_pending(body: Dictionary) -> void:
	var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(body))


func _clear_pending() -> void:
	if FileAccess.file_exists(PENDING_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PATH))


## A run that ended offline is sent at the next launch (still one try per token).
func retry_pending() -> void:
	if not FileAccess.file_exists(PENDING_PATH):
		return
	var f := FileAccess.open(PENDING_PATH, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not j is Dictionary:
		_clear_pending()
		return
	var r: Dictionary = await call_api(j)
	if r.has("success") or r.has("error"):
		_clear_pending()


# --- Names / boards / challenges ---

func set_pilot_name(n: String) -> Dictionary:
	var r: Dictionary = await call_api({"action": "name", "name": n})
	if r.get("ok", false):
		pilot_name = str(r.get("name", n))
	return r


func board(kind: String) -> Dictionary:
	var r: Dictionary = await call_api({"action": "board", "board": kind})
	if r.has("my_name"):
		pilot_name = str(r["my_name"])
	return r


func create_challenge(token: String) -> String:
	var r: Dictionary = await call_api({"action": "challenge_create", "run_token": token})
	return str(r.get("code", ""))


func get_challenge(code: String) -> Dictionary:
	return await call_api({"action": "challenge_get", "code": code.strip_edges().to_upper()})


func has_custom_name() -> bool:
	return pilot_name != "" and not pilot_name.begins_with("Pilot-")
