extends Node
## Headless: QRScan reads back what QRCode draws, as a camera would see it:
## inside a bigger frame, scaled, rotated, blurred, noisy. A damaged code must
## come back as "" (never as wrong text).
## Run: godot --headless --path . res://scenes/tools/QRScanTest.tscn

var _fails: int = 0
var _passes: int = 0
var _n: int = 0


func _check(ok: bool, what: String) -> void:
	_n += 1
	if ok:
		_passes += 1
		print("PASS  %d. %s" % [_n, what])
	else:
		_fails += 1
		print("FAIL  %d. %s" % [_n, what])


func _ready() -> void:
	call_deferred("_run")


## The code drawn into a grey "camera frame": centre offset, size, rotation
## (degrees), optional noise and blur.
func _frame(text: String, px_per_module: float, angle: float, noise: int = 0, blur: bool = false, fw: int = 640, fh: int = 480) -> Image:
	var qr: Image = QRCode.to_image(QRCode.encode(text), 8, 4)
	qr.convert(Image.FORMAT_L8)
	var side: int = qr.get_width()
	var out := Image.create(fw, fh, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scale: float = px_per_module / 8.0
	var c := Vector2(fw * 0.52, fh * 0.47)
	var ca: float = cos(deg_to_rad(angle))
	var sa: float = sin(deg_to_rad(angle))
	for y in fh:
		for x in fw:
			var d := Vector2(x, y) - c
			var s := Vector2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca) / scale + Vector2(side, side) * 0.5
			var v: float = 0.42   # the desk behind the phone
			if s.x >= 0.0 and s.y >= 0.0 and s.x < side - 1 and s.y < side - 1:
				v = qr.get_pixel(int(s.x), int(s.y)).r * 0.82 + 0.08   # a screen is never pure black or white
			v += float(rng.randi_range(-noise, noise)) / 255.0
			out.set_pixel(x, y, Color(v, v, v))
	if blur:
		out.resize(fw / 2, fh / 2, Image.INTERPOLATE_BILINEAR)
		out.resize(fw, fh, Image.INTERPOLATE_BILINEAR)
	return out


func _run() -> void:
	var url: String = "https://yanipan.github.io/skybreaker/join/?c=AB3K9X"
	# 1. The grid itself, no image.
	for t in ["A", "HELLO WORLD", url, url + "&from=VIPER", "x".repeat(150)]:
		var m: Array = QRCode.encode(t)
		var flat: Array = []
		for row in m:
			for v in (row as PackedByteArray):
				flat.append(int(v))
		_check(QRScan.decode_matrix(flat) == t, "grid of a %d-byte text (version %d) reads back" % [t.length(), QRCode.version_of(m)])
	# 2. As a camera sees it.
	_check(QRScan.decode_image(_frame(url, 6.0, 0.0)) == url, "straight, 6 px per module")
	_check(QRScan.decode_image(_frame(url, 3.2, 0.0)) == url, "small in the frame, 3.2 px per module")
	_check(QRScan.decode_image(_frame(url, 9.0, 0.0, 0, false, 1280, 960)) == url, "big 1280x960 frame (shrunk first)")
	for a in [90.0, 180.0, 270.0, 8.0, -14.0, 33.0, 127.0]:
		_check(QRScan.decode_image(_frame(url, 6.0, a)) == url, "rotated %d degrees" % int(a))
	_check(QRScan.decode_image(_frame(url, 6.0, 5.0, 18)) == url, "with sensor noise")
	_check(QRScan.decode_image(_frame(url, 7.0, -6.0, 8, true)) == url, "slightly out of focus")
	_check(QRScan.decode_image(_frame("https://yanipan.github.io/skybreaker/join/?c=ZZ9PQ4", 6.0, 21.0, 6)) == "https://yanipan.github.io/skybreaker/join/?c=ZZ9PQ4", "another room code")
	# 3. Nothing there, or damaged: "" and never wrong text.
	var blank := Image.create(640, 480, false, Image.FORMAT_L8)
	blank.fill(Color(0.4, 0.4, 0.4))
	_check(QRScan.decode_image(blank) == "", "a blank frame reads nothing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var noise := Image.create(320, 240, false, Image.FORMAT_L8)
	for y in 240:
		for x in 320:
			var v: float = rng.randf()
			noise.set_pixel(x, y, Color(v, v, v))
	_check(QRScan.decode_image(noise) == "", "pure noise reads nothing")
	var m2: Array = QRCode.encode(url)
	var flat2: Array = []
	for row in m2:
		for v in (row as PackedByteArray):
			flat2.append(int(v))
	var size: int = int(sqrt(float(flat2.size())))
	var wrong: int = 0
	for trial in 40:
		var bad: Array = flat2.duplicate()
		for k in 1 + trial % 4:
			var idx: int = rng.randi_range(9, size - 2) * size + rng.randi_range(9, size - 2)
			bad[idx] = 1 - int(bad[idx])
		var got: String = QRScan.decode_matrix(bad)
		if got != "" and got != url:
			wrong += 1
	_check(wrong == 0, "40 damaged grids: none read as wrong text")
	# 4. Room code from the link.
	_check(QRScan.room_code(url) == "AB3K9X", "room code out of the invite link")
	_check(QRScan.room_code("https://x.y/skybreaker/join/zz9pq4") == "ZZ9PQ4", "room code out of the short link form, upper-cased")
	_check(QRScan.room_code("https://example.com/menu") == "" and QRScan.room_code("https://x.y/join/?c=AB3K9XYZ") == "", "other links give no room code")
	print("QRScanTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
