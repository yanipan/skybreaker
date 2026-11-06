extends Node
## LIVE test of Online.gd against the real server with a throwaway player id.
## Run: godot --headless --path . res://scenes/tools/OnlineTest.tscn
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _ready() -> void:
	var real_id: String = Telemetry.player_id
	Telemetry.player_id = "00000000-0000-4000-8000-000000000003"
	Online.allow_debug = true
	GameState.begin_run(424242)
	var r: Dictionary = await Online.start_run()
	_check(r.get("success", false) and GameState.run_token.length() == 32, "game-signed run_start accepted (HMAC matches server)")
	_check(GameState.run_seed == 424242, "normal run keeps its local seed")
	GameState.current_level = 1
	GameState.run_score = 777
	var got: Array = []
	Online.run_finished.connect(func(res: Dictionary) -> void: got.append(res), CONNECT_ONE_SHOT)
	await Online.finish_run(false)
	_check(got.size() == 1 and got[0].get("ranked", false) and int(got[0].get("rank_all", 0)) >= 1, "run ranked: %s" % [got])
	_check(not FileAccess.file_exists(Online.PENDING_PATH), "pending file cleared after the server answered")
	var n: Dictionary = await Online.set_pilot_name("GodotTest_3")
	_check(n.get("ok", false) and Online.has_custom_name(), "pilot name saved")
	var bad: Dictionary = await Online.set_pilot_name("sh1thead")
	_check(not bad.get("ok", true) and bad.get("reason") == "blocked", "rude name refused")
	var b: Dictionary = await Online.board("all")
	_check(b.get("success", false) and b.get("me") is Dictionary and b["me"]["name"] == "GodotTest_3", "board has me")
	var code: String = await Online.create_challenge(GameState.last_run["token"])
	_check(code.length() == 6, "challenge code %s" % code)
	var c: Dictionary = await Online.get_challenge(code.to_lower())
	_check(c.get("score", 0) == 777, "challenge lookup (lowercase typed) finds target 777")
	GameState.begin_run(0, code, 777, "GodotTest_3")
	var s: Dictionary = await Online.start_run(code)
	_check(s.get("success", false) and GameState.run_seed == 424242, "challenge run gets the challenger's seed")
	# Report flow: three other players report GodotTest_3 -> name resets.
	var me_id: String = Telemetry.player_id
	for i in 3:
		Telemetry.player_id = "00000000-0000-4000-8000-00000000001%d" % i
		var ok: bool = await Online.report_name("GodotTest_3")
		_check(ok, "report %d accepted" % (i + 1))
	Telemetry.player_id = me_id
	var b2: Dictionary = await Online.board("all")
	_check(b2.get("me") is Dictionary and str(b2["me"]["name"]).begins_with("Pilot-"), "3 reports reset the name to %s" % (b2.get("me", {}) as Dictionary).get("name", "?"))
	Online.allow_debug = false
	var off: Dictionary = await Online.call_api({"action": "board"})
	_check(off.is_empty(), "debug builds stay offline by default")
	Telemetry.player_id = real_id
	print("ONLINE TEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)
