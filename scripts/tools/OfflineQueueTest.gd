extends Node
## LIVE: run ends made offline are queued (several, none overwritten) and
## delivered once the connection is back. Throwaway player id.
## Run: godot --headless --path . res://scenes/tools/OfflineQueueTest.tscn
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	var real_id: String = Telemetry.player_id
	Telemetry.player_id = "00000000-0000-4000-8000-000000000021"
	Online.allow_debug = true
	var path: String = ProjectSettings.globalize_path(Online.PENDING_PATH)
	if FileAccess.file_exists(Online.PENDING_PATH):
		DirAccess.remove_absolute(path)
	var tokens: Array = []
	for i in 2:
		GameState.begin_run(5000 + i)
		Online.endpoint = Online.ENDPOINT
		var s: Dictionary = await Online.start_run()
		_check(s.get("success", false), "run %d registered online" % (i + 1))
		tokens.append(GameState.run_token)
		GameState.current_level = 1
		GameState.run_score = 100 + i
		Online.endpoint = "https://127.0.0.1:9/lb.php"   # the phone goes offline
		var got: Array = []
		Online.run_finished.connect(func(r: Dictionary) -> void: got.append(r), CONNECT_ONE_SHOT)
		await Online.finish_run(false)
		_check(got.size() == 1 and got[0].get("queued", false), "run %d end queued, game-over not blocked" % (i + 1))
	_check(Online.pending_count() == 2, "both offline runs waiting (none overwritten): %d" % Online.pending_count())
	await Online.retry_pending()
	_check(Online.pending_count() == 2, "still offline: nothing lost by a failed retry")
	# 1.0.1 legacy single slot migrates into the queue
	var f := FileAccess.open(Online.LEGACY_PENDING_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"action": "run_end", "run_token": "legacy-token-x", "score": 1, "sector": 1, "cleared": 0, "sectors": []}))
	f = null
	Online._migrate_legacy_pending()
	_check(Online.pending_count() == 3 and not FileAccess.file_exists(Online.LEGACY_PENDING_PATH), "legacy pending file moved into the queue")
	Online.endpoint = Online.ENDPOINT   # back online
	await Online.retry_pending()
	_check(Online.pending_count() == 0, "back online: queue delivered and emptied")
	var b: Dictionary = await Online.board("all")
	_check(b.get("me") is Dictionary and int(b["me"].get("score", 0)) >= 100, "late run is on the board: %s" % [b.get("me")])
	Online.allow_debug = false
	Telemetry.player_id = real_id
	print("OFFLINE QUEUE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
