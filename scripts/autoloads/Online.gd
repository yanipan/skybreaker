extends Node
## Pilot names, leaderboards and friend challenges (1.0.1).
## Every request is signed: X-SB-Ts + X-SB-Sig = HMAC-SHA256(key, ts + "." + body).
## The server also issues a single-use run token at run start and checks the
## final score against real elapsed time, per-sector ceilings and the sector
## log, so copying the URL or replaying a request does not get a score on the
## board. Nothing here ever blocks play: failures just mean "not ranked".

signal run_finished(result: Dictionary)
signal _retry_done

const ENDPOINT: String = "https://englishapp.shimonster.com/skybreaker/api/lb.php"
const KEYS := preload("res://config/online_keys.gd")
## Run ends that did not reach the server yet (offline, timeout, server down),
## a JSON array, oldest first. Sent again on launch, on app resume, after any
## call that did reach the server, and every RETRY_SECS while not empty.
const PENDING_PATH: String = "user://pending_runs.json"
const LEGACY_PENDING_PATH: String = "user://pending_run_end.json"   ## 1.0.1: one slot
const MAX_PENDING: int = 20
const RETRY_SECS: float = 120.0
const TIMEOUT: float = 10.0

## Test hook: point at a dead host to simulate being offline.
var endpoint: String = ENDPOINT
var _retrying: bool = false
var _retry_timer: Timer = null

var allow_debug: bool = false   ## Debug builds stay offline unless a test turns this on
var pilot_name: String = "":
	set(v):
		if v != pilot_name:
			pilot_name = v
			var cfg := ConfigFile.new()
			cfg.load(NAME_PATH)
			cfg.set_value("p", "name", v)
			cfg.save(NAME_PATH)
const NAME_PATH: String = "user://pilot.cfg"


## Set once the first-launch name prompt has been shown (saved in pilot.cfg
## next to the name, so a reinstall asks again and an update does not).
var name_asked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(NAME_PATH) == OK:
		pilot_name = str(cfg.get_value("p", "name", ""))
		name_asked = bool(cfg.get_value("p", "asked", false))
	_migrate_legacy_pending()
	_retry_timer = Timer.new()
	_retry_timer.wait_time = RETRY_SECS
	_retry_timer.timeout.connect(retry_pending)
	add_child(_retry_timer)
	_retry_timer.start()
	call_deferred("retry_pending")


func _notification(what: int) -> void:
	# Back from the background: the phone may have its connection again.
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		call_deferred("retry_pending")


## First launch only: no custom name yet and never asked. Debug builds are
## offline, so the prompt would only ever say "No connection": skip them.
func should_ask_name() -> bool:
	return online_ok() and not name_asked and not has_custom_name()


func mark_name_asked() -> void:
	name_asked = true
	var cfg := ConfigFile.new()
	cfg.load(NAME_PATH)
	cfg.set_value("p", "name", pilot_name)
	cfg.set_value("p", "asked", true)
	cfg.save(NAME_PATH)


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
	var err: int = http.request(endpoint, [
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
	if not j is Dictionary:
		return {}
	# The server answered: a good moment to send anything still waiting.
	if not _retrying and str(body.get("action", "")) != "run_end" and FileAccess.file_exists(PENDING_PATH):
		call_deferred("retry_pending")
	return j


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
	_queue_pending(body)
	var r: Dictionary = await call_api(body)
	if _answered(r):
		_drop_pending(str(body["run_token"]))
	if r.get("success", false):
		result["ranked"] = bool(r.get("counted", false))
		result["rank_all"] = int(r.get("rank_all", 0))
		result["rank_week"] = int(r.get("rank_week", 0))
		if r.has("challenge"):
			result["challenge_beat"] = bool(r["challenge"].get("beat", false))
	elif _answered(r):
		result["refused"] = true      # server looked and said no
	else:
		result["queued"] = true       # no answer: waits in the pending queue
	GameState.last_run = result
	run_finished.emit(result)


## The server looked at it (counted or refused): never send it again.
## No answer at all ({}): keep it for the next try.
static func _answered(r: Dictionary) -> bool:
	return r.has("success") or r.has("error")


func _load_pending() -> Array:
	if not FileAccess.file_exists(PENDING_PATH):
		return []
	var f := FileAccess.open(PENDING_PATH, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	return (j as Array).filter(func(e): return e is Dictionary and e.has("run_token")) if j is Array else []


func _store_pending(q: Array) -> void:
	if q.is_empty():
		if FileAccess.file_exists(PENDING_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PATH))
		return
	var tmp: String = PENDING_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(q))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PENDING_PATH))


func pending_count() -> int:
	return _load_pending().size()


func _queue_pending(body: Dictionary) -> void:
	var q: Array = _load_pending().filter(func(e): return str(e["run_token"]) != str(body["run_token"]))
	q.append(body)
	if q.size() > MAX_PENDING:
		q = q.slice(q.size() - MAX_PENDING)
	_store_pending(q)


func _drop_pending(token: String) -> void:
	_store_pending(_load_pending().filter(func(e): return str(e["run_token"]) != token))


## 1.0.1 kept one pending run in its own file: move it into the queue.
func _migrate_legacy_pending() -> void:
	if not FileAccess.file_exists(LEGACY_PENDING_PATH):
		return
	var f := FileAccess.open(LEGACY_PENDING_PATH, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	f = null
	if j is Dictionary and j.has("run_token"):
		_queue_pending(j)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_PENDING_PATH))


## Send every waiting run end, oldest first. Stops at the first one that gets
## no answer (still offline) and leaves it and the rest for the next try.
func retry_pending() -> void:
	if not online_ok():
		return
	if _retrying:
		await _retry_done   # one pass at a time; callers wait for it
		return
	_retrying = true
	for body in _load_pending():
		var r: Dictionary = await call_api(body)
		if OS.is_debug_build():
			print("Online retry ", str(body["run_token"]).left(8), " -> ", r)
		if not _answered(r):
			break
		_drop_pending(str(body["run_token"]))
	_retrying = false
	_retry_done.emit()


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


func report_name(n: String) -> bool:
	var r: Dictionary = await call_api({"action": "report", "name": n})
	return r.get("success", false)


func has_custom_name() -> bool:
	return pilot_name != "" and not pilot_name.begins_with("Pilot-")
