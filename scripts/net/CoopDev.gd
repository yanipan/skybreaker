extends Node
## DEV launcher for co-op (phase 2; the real lobby is phase 4). Starts a fresh
## co-op run against a room server and loads the normal Main scene.
##   godot --path . res://scenes/net/CoopDev.tscn --position 40,60 --resolution 408x726 -- --host=127.0.0.1 --port=24620 --name=A [--autopilot] [--coopshots=4] [--lag=80]
## --autopilot flies and fires the ship by itself (two windows cannot both
## have the mouse); --coopshots=N saves a screenshot every N seconds to
## user://coop_<name>_<n>.png.
## NEVER name an argument --shots or --beats here: scripts/tools/ShotDirector.gd
## (store screenshots) starts on `--shots=<anything>` in every debug run, takes
## over the game and swaps the save files. Two instances at once (as on
## 11/11) restore over each other and the local save is deleted.

var host: String = "127.0.0.1"
var port: int = Net.DEFAULT_PORT
var pilot: String = "Pilot"
var autopilot: bool = false
var shot_every: float = 0.0
var die_at: float = -1.0  ## --die_at=T: the autopilot loses its last life T s in (DOWN / rescue demo)
var god: bool = false   ## --god: this ship cannot be hit
var solo: bool = false  ## --solo [--sector=N]: plain SINGLE-PLAYER run with the same helper (perf baseline)
var solo_sector: int = 1
var perf: bool = false  ## --perf: print script time per frame while flying
var no_rescue: bool = false  ## --no_rescue: the autopilot ignores the partner's pod
var dev_money: int = -1   ## --money=N: start the co-op run with N credits (solo money is restored after)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		match kv[0]:
			"host": host = kv[1]
			"port": port = int(kv[1])
			"name": pilot = kv[1]
			"autopilot": autopilot = true
			"coopshots": shot_every = float(kv[1])
			"money": dev_money = int(kv[1])
			"die_at": die_at = float(kv[1])
			"no_rescue": no_rescue = true
			"perf": perf = true
			"god": god = true
			"solo": solo = true
			"sector": solo_sector = int(kv[1])
			"lag": Net.fake_lag_ms = int(kv[1])
			"loss": Net.fake_loss = float(kv[1])
	if solo:
		# Single-player baseline: no network at all. The solo save is parked the
		# same way so a dev run never touches it.
		SaveSystem.begin_coop_hold()
		CoopSession.begin_run(solo_sector)
		await get_tree().process_frame   # the root is still adding this scene
		var hs: Node = load("res://scripts/net/CoopDevPilot.gd").new()
		hs.pilot = pilot
		hs.autopilot = autopilot
		hs.shot_every = shot_every
		hs.perf = perf
		hs.god = god
		get_tree().root.add_child(hs)
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
		return
	# The solo state is frozen FIRST (start_coop takes the hold), then the
	# run fields are reset for a fresh co-op run.
	var err: int = Net.start_coop(host, port, pilot)
	print("CoopDev ", pilot, ": connecting ", host, ":", port, " err=", err)
	if err != OK:
		get_tree().quit(2)
		return
	CoopSession.begin_run(1)
	if dev_money >= 0:
		GameState.money = dev_money
	var c: Node = Net.client
	var waited: float = 0.0
	while Net.my_peer == 0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > 10.0 or not Net.is_client():
			print("CoopDev ", pilot, ": no answer from the server")
			Net.leave_coop()
			get_tree().quit(3)
			return
	GameState.current_level = c.start_sector
	print("CoopDev ", pilot, ": peer ", Net.my_peer, " seat ", Net.seat, " start sector ", c.start_sector)
	if autopilot or shot_every > 0.0 or perf:
		var h: Node = load("res://scripts/net/CoopDevPilot.gd").new()
		h.pilot = pilot
		h.autopilot = autopilot
		h.shot_every = shot_every
		h.die_at = die_at
		h.no_rescue = no_rescue
		h.perf = perf
		h.god = god
		get_tree().root.add_child(h)   # outlives the per-sector scene reloads
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
