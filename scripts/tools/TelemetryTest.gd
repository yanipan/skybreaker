extends Node
## Headless: id format, queue, disable, snapshot shape, and one live batch.
## Run: godot --headless --path . res://scenes/tools/TelemetryTest.tscn -- --live
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	var T: Node = Telemetry
	_check(T._valid_uuid(T.player_id), "player id is a v4 uuid (%s)" % T.player_id)
	var ids := {}
	for i in 200:
		ids[T.new_uuid()] = true
	_check(ids.size() == 200, "200 fresh ids are unique")
	_check(T._valid_uuid(T.new_uuid()), "new_uuid passes the server regex")
	var was: bool = T.enabled
	T.set_enabled(false)
	var n0: int = T._queue.size()
	T.track("death", {})
	_check(T._queue.size() == 0 and n0 >= 0, "disabled: nothing queued, queue cleared")
	T.set_enabled(true)
	T.start_run("new")
	_check(T.run_id.length() == 16, "run id set on new run")
	var rid: String = T.run_id
	T.start_run("continue")
	_check(T.run_id == rid, "continue keeps the run id")
	T.add_fire_time(1, 2.5)
	T.torps_fired = 2
	var p: Node = load("res://scripts/Player.gd").new()
	add_child(p)
	await get_tree().process_frame
	var s: Dictionary = T.snapshot(p)
	_check(s["w"].size() == 3 and s["fire"][1] == 2.5 and s["torps"] == 2 and s.has("torp_max") and s.has("cells"), "snapshot has levels, fire time, torps, slots, cells")
	T.track("sector_complete", s)
	_check(T._queue.back()["name"] == "sector_complete" and T._queue.back()["run_id"] == rid, "event queued with run id")
	_check(FileAccess.file_exists(T.QUEUE_PATH), "queue persisted to disk")
	var q0: int = T._queue.size()
	T.flush()
	_check(T._in_flight == 0 and T._queue.size() == q0, "debug build does not send by default")
	if "--live" in OS.get_cmdline_user_args():
		T.player_id = "00000000-0000-4000-8000-000000000000"
		T.allow_debug_send = true
		var before: int = T._queue.size()
		T.flush()
		var t := 0.0
		while T._in_flight > 0 and t < 20.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		_check(T._queue.size() == 0 and before > 0, "live batch accepted, queue drained (%d sent)" % before)
		T.allow_debug_send = false
		T._load_cfg()
	T.set_enabled(was)
	print("TELEMETRY TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
