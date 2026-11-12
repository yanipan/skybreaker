extends Node
## A fast enemy (a Strafer, 360 px/s) drawn through NetClient's clock and
## snapshot interpolation over a simulated REAL network: jittered latency,
## late spikes, lost packets. On a phone the old clock estimate jumped with
## every early or late packet and the Strafers moved in jerks.
## Run: godot --headless --path . res://scenes/tools/ClockSmoothTest.tscn
const SPEED: float = 360.0
const FRAME: float = 1.0 / 60.0
var _fails: int = 0
var _passes: int = 0


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if ok: _passes += 1
	else: _fails += 1


## Returns [worst px off the ideal step, frames more than 2 px off, frames moving backwards, delay at the end]
func _run(seed_v: int, snap_every: float, base_lag: float, jitter: float, spike_chance: float, loss: float, hitch_at: float = -1.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var nc: NetClient = NetClient.new()
	nc._buf[1] = []
	var local0: float = 1000.0           # the phone's clock starts somewhere else entirely
	var queue: Array = []                # [arrival local time, server t, x]
	var st: float = 0.0
	var last_arrival: float = 0.0
	var server_x_t: float = 0.0          # the enemy's own time (keeps moving through a hitch)
	while st < 20.0:
		st += snap_every
		server_x_t = st
		var stamp: float = st
		if hitch_at >= 0.0 and st >= hitch_at:
			stamp = st - 0.5             # the server clock lost half a second in a hitch
		if rng.randf() < loss:
			continue
		var lag: float = base_lag + rng.randf() * jitter
		if rng.randf() < spike_chance:
			lag += rng.randf_range(0.04, 0.09)
		var arr: float = maxf(local0 + st + lag, last_arrival)   # in order, like ENet's sequenced channel
		last_arrival = arr
		queue.append([arr, stamp, SPEED * stamp])
	var now: float = local0
	var prev_x: float = NAN
	var worst: float = 0.0
	var off: int = 0
	var back: int = 0
	var ids := PackedInt32Array([1])
	while now < local0 + 19.5:
		now += FRAME
		nc.test_now = now
		while not queue.is_empty() and float(queue[0][0]) <= now:
			var q: Array = queue.pop_front()
			nc._snap(float(q[1]), ids, PackedFloat32Array([float(q[2]), 0.0]), PackedByteArray([0]), PackedByteArray([255]))
		nc._advance_clock(FRAME)
		var b: Array = nc._buf[1]
		if b.is_empty():
			continue
		var x: float = NetClient._sample(b, nc.render_time()).x
		var settled: bool = now > local0 + 3.0 and (hitch_at < 0.0 or now < local0 + hitch_at or now > local0 + hitch_at + 3.0)
		if not is_nan(prev_x) and settled:
			var d: float = x - prev_x
			worst = maxf(worst, absf(d - SPEED * FRAME))
			if absf(d - SPEED * FRAME) > 2.0: off += 1
			if d < -0.01: back += 1
		prev_x = x
	var delay: float = nc.interp_delay()
	nc.free()
	return [worst, off, back, delay]


func _ready() -> void:
	# Ideal step is 6 px a frame. "Jerk" = a frame more than 2 px off that.
	var r: Array = _run(1, 0.05, 0.004, 0.001, 0.0, 0.0)
	_check(r[0] < 0.5 and r[1] == 0 and r[2] == 0, "local network: smooth (worst %.2f px off, %d jerks)" % [r[0], r[1]])
	_check(absf(r[3] - 0.10) < 0.005, "local network: delay stays at the minimum (%.0f ms)" % [r[3] * 1000.0])
	r = _run(2, 0.05, 0.045, 0.025, 0.0, 0.0)
	_check(r[0] < 1.0 and r[1] == 0 and r[2] == 0, "home Wi-Fi to the cloud (45 ms + 25 ms jitter): smooth (worst %.2f px off, %d jerks)" % [r[0], r[1]])
	r = _run(3, 0.05, 0.045, 0.025, 0.10, 0.02)
	_check(r[0] < 1.0 and r[1] == 0 and r[2] == 0, "late spikes on 10%% of packets + 2%% lost: smooth (worst %.2f px off, %d jerks, %d backwards)" % [r[0], r[1], r[2]])
	_check(r[3] > 0.13, "bad link: the delay grows to cover it (%.0f ms)" % [r[3] * 1000.0])
	r = _run(4, 0.05, 0.080, 0.050, 0.15, 0.05)
	_check(r[1] <= 3 and r[2] == 0, "mobile data (80 ms + 50 ms jitter, 15%% spikes, 5%% lost): at most a rare jerk (%d in 16 s, worst %.2f px)" % [r[1], r[0]])
	_check(r[3] <= NetClient.INTERP_MAX + 0.0001, "the delay never exceeds its cap (%.0f ms)" % [r[3] * 1000.0])
	r = _run(5, 0.066, 0.045, 0.025, 0.10, 0.02)
	_check(r[1] == 0 and r[2] == 0, "an older server sending every 66 ms is drawn smoothly too (%d jerks)" % [r[1]])
	r = _run(6, 0.05, 0.045, 0.025, 0.0, 0.0, 8.0)
	_check(r[1] == 0 and r[2] == 0, "a server hitch (clock loses 0.5 s): smooth again within 3 s (%d jerks after)" % [r[1]])
	print("ClockSmoothTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
