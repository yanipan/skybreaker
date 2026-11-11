extends Node
## Headless: the QR encoder is proven by DECODING. Every code is saved as a
## PNG and read back with zbarimg; the text must come back exactly.
## Run: godot --headless --path . res://scenes/tools/QRCodeTest.tscn
## Needs /opt/homebrew/bin/zbarimg (brew install zbar).

const ZBAR: String = "/opt/homebrew/bin/zbarimg"
var _fails: int = 0
var _passes: int = 0

func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("PASS  ", what)
	else:
		_fails += 1
		print("FAIL  ", what)


func _ready() -> void:
	call_deferred("_run")


## Exactly n characters (ASCII, so n bytes): the invite link prefix when it
## fits, then letters and digits.
func _long(n: int) -> String:
	var s: String = "https://shimonster.com/skybreaker/join/".left(n)
	var chars: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	var i: int = 0
	while s.length() < n:
		s += chars[i % chars.length()]
		i += 7
	return s


func _decode(matrix: Array, n: int) -> String:
	var path: String = ProjectSettings.globalize_path("user://qr_test_%d.png" % n)
	QRCode.to_image(matrix, 8, 4).save_png(path)
	var out: Array = []
	var code: int = OS.execute(ZBAR, ["--raw", "-q", path], out, true)
	if code != 0 or out.is_empty():
		return "<zbarimg exit %d>" % code
	return str(out[0]).trim_suffix("\n")


func _run() -> void:
	if not FileAccess.file_exists(ZBAR):
		print("FAIL  zbarimg is not installed at ", ZBAR, " (brew install zbar): nothing can be proven")
		get_tree().quit(1)
		return
	var texts: Array = [
		"HELLO",
		"AB3K9X",
		"https://yanipan.github.io/skybreaker/join/?c=AB3K9X",
		"https://yanipan.github.io/skybreaker/join/?c=ZZ9PQ4&from=VIPER",
		_long(100),
		_long(200),
		"Pilot Zoë ✈ 24 sectors",
		_long(14), _long(15), _long(26), _long(27), _long(42), _long(43), _long(62), _long(63), _long(84), _long(85),
		_long(106), _long(107), _long(122), _long(123), _long(152), _long(153), _long(180), _long(181), _long(213),
	]
	var versions: Dictionary = {}
	for i in texts.size():
		var t: String = texts[i]
		var m: Array = QRCode.encode(t)
		var v: int = QRCode.version_of(m)
		versions[v] = int(versions.get(v, 0)) + 1
		var square: bool = not m.is_empty() and m.size() == 17 + 4 * v
		for row in m:
			if (row as PackedByteArray).size() != m.size():
				square = false
			for c in (row as PackedByteArray):
				if c != 0 and c != 1:
					square = false
		var got: String = _decode(m, i) if square else "<no matrix>"
		_check(square and got == t, "%2d. %3d bytes, version %2d, decodes back exactly%s" % [i + 1, t.to_utf8_buffer().size(), v, "" if got == t else "  GOT: " + got.left(60)])
	_check(versions.size() == 10, "every version 1-10 was exercised (%s)" % [versions.keys()])
	_check(QRCode.encode("").is_empty() and QRCode.encode(_long(230)).is_empty() and QRCode.encode(_long(214)).is_empty(), "empty text and texts over 213 bytes give no code")
	# Byte capacity at level M: 14, 26, 42, 62, 84, 106, 122, 152, 180, 213.
	var caps: Array = [14, 26, 42, 62, 84, 106, 122, 152, 180, 213]
	var fit_ok: bool = true
	for v in range(1, 11):
		if QRCode.version_of(QRCode.encode(_long(int(caps[v - 1])))) != v:
			fit_ok = false
		if v < 10 and QRCode.version_of(QRCode.encode(_long(int(caps[v - 1]) + 1))) != v + 1:
			fit_ok = false
	_check(fit_ok, "smallest version that fits, at every capacity edge (14 -> 1, 15 -> 2, ... 213 -> 10)")
	var img: Image = QRCode.to_image(QRCode.encode("AB3K9X"), 8, 4)
	_check(img != null and img.get_width() == (21 + 8) * 8 and img.get_height() == img.get_width(), "image: (21 + 2 x 4 quiet) x 8 = 232 px square")
	_check(QRCode.to_image([]) == null, "no image for an empty matrix")
	var m1: Array = QRCode.encode("HELLO")
	var finder_ok: bool = true
	for y in 7:
		for x in 7:
			var want: int = 1 if (x == 0 or x == 6 or y == 0 or y == 6 or (x >= 2 and x <= 4 and y >= 2 and y <= 4)) else 0
			if (m1[y] as PackedByteArray)[x] != want:
				finder_ok = false
	_check(finder_ok, "top-left 7x7 is the standard finder pattern")
	# Format bits, level M, masks 0-7, from the table in ISO/IEC 18004 (Annex C).
	var table: Array = ["101010000010010", "101000100100101", "101111001111100", "101101101001011",
			"100010111111001", "100000011001110", "100111110010111", "100101010100000"]
	var fmt_ok: bool = true
	for mask in 8:
		if QRCode.format_bits(mask) != (table[mask] as String).bin_to_int():
			fmt_ok = false
	_check(fmt_ok, "format bits for all 8 masks match the standard's table exactly")
	print("QRCodeTest: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
