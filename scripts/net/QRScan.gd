extends RefCounted
class_name QRScan
## Reads the QR codes this game shows (QRCode.gd: byte mode, level M,
## versions 1-10) out of a camera frame. Built for one job: a friend's phone
## showing the invite QR on its screen, held roughly square to the camera.
##
## Limits, on purpose:
##  - No perspective correction (three finders -> an affine grid). A phone held
##    at a steep angle simply does not decode; the next frame is tried.
##  - No error CORRECTION. The Reed-Solomon bytes are used as a checksum: a
##    frame decodes only when every block matches exactly, so a wrong read
##    never comes back as text. A camera gives several frames a second.
## Returns "" when nothing was read.

const MAX_SIDE: int = 420          ## Frames are shrunk to this before scanning


## Camera frame (any format, any size) -> text, or "".
static func decode_image(src: Image) -> String:
	if src == null or src.is_empty():
		return ""
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	var big: int = maxi(img.get_width(), img.get_height())
	if big > MAX_SIDE:
		var k: float = float(MAX_SIDE) / float(big)
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var px: PackedByteArray = img.get_data()
	# Threshold halfway between the darkest and brightest of a coarse sample.
	var lo: int = 255
	var hi: int = 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var v: int = px[y * w + x]
			lo = mini(lo, v)
			hi = maxi(hi, v)
	if hi - lo < 60:
		return ""   # no contrast: not a screen with a code on it
	var thr: int = (lo + hi) / 2
	var finders: Array = _find_finders(px, w, h, thr)
	if finders.size() < 3:
		return ""
	# The three with the most row hits; the pair farthest apart is the diagonal.
	finders.sort_custom(func(a: Array, b: Array) -> bool: return int(a[3]) > int(b[3]))
	var f: Array = finders.slice(0, 3)
	var pts: Array = [f[0][0], f[1][0], f[2][0]]
	var d01: float = (pts[0] as Vector2).distance_to(pts[1])
	var d02: float = (pts[0] as Vector2).distance_to(pts[2])
	var d12: float = (pts[1] as Vector2).distance_to(pts[2])
	var tl: Vector2
	var a: Vector2
	var b: Vector2
	if d12 >= d01 and d12 >= d02:
		tl = pts[0]; a = pts[1]; b = pts[2]
	elif d02 >= d01 and d02 >= d12:
		tl = pts[1]; a = pts[0]; b = pts[2]
	else:
		tl = pts[2]; a = pts[0]; b = pts[1]
	# Image y points down: top-right x bottom-left must be a positive turn.
	var tr: Vector2 = a
	var bl: Vector2 = b
	if (a - tl).cross(b - tl) < 0.0:
		tr = b
		bl = a
	var unit: float = (float(f[0][1]) + float(f[1][1]) + float(f[2][1])) / 3.0
	if unit < 1.0:
		return ""
	var est: float = (tl.distance_to(tr) + tl.distance_to(bl)) * 0.5 / unit + 7.0
	var v0: int = int(round((est - 17.0) / 4.0))
	for dv in [0, -1, 1]:
		var version: int = v0 + dv
		if version < 1 or version > QRCode.MAX_VERSION:
			continue
		var size: int = version * 4 + 17
		var u: Vector2 = (tr - tl) / float(size - 7)
		var vv: Vector2 = (bl - tl) / float(size - 7)
		var modules: Array = []
		modules.resize(size * size)
		for my in size:
			for mx in size:
				var p: Vector2 = tl + u * float(mx - 3) + vv * float(my - 3)
				var sx: int = clampi(int(round(p.x)), 0, w - 1)
				var sy: int = clampi(int(round(p.y)), 0, h - 1)
				modules[my * size + mx] = 1 if px[sy * w + sx] < thr else 0
		var text: String = decode_matrix(modules)
		if text != "":
			return text
	return ""


## Finder patterns: dark-light-dark-light-dark runs in the ratio 1:1:3:1:1,
## confirmed down the column through the middle. Returns clusters
## [center: Vector2, module_size: float, _, hits: int].
static func _find_finders(px: PackedByteArray, w: int, h: int, thr: int) -> Array:
	var found: Array = []
	for y in range(1, h, 2):
		var row: int = y * w
		var runs: Array = []      # [start, length] alternating, runs[0] is dark or light by `first_dark`
		var first_dark: bool = px[row] < thr
		var start: int = 0
		var dark: bool = first_dark
		for x in range(1, w):
			var d: bool = px[row + x] < thr
			if d != dark:
				runs.append([start, x - start])
				start = x
				dark = d
		runs.append([start, w - start])
		var i: int = 0 if first_dark else 1
		while i + 4 < runs.size():
			var r0: int = runs[i][1]
			var r1: int = runs[i + 1][1]
			var r2: int = runs[i + 2][1]
			var r3: int = runs[i + 3][1]
			var r4: int = runs[i + 4][1]
			var total: int = r0 + r1 + r2 + r3 + r4
			if total >= 14:
				var unit: float = float(total) / 7.0
				var tol: float = unit * 0.7
				if absf(r0 - unit) < tol and absf(r1 - unit) < tol and absf(r3 - unit) < tol and absf(r4 - unit) < tol \
						and absf(r2 - 3.0 * unit) < tol * 1.6:
					var cx: float = float(runs[i + 2][0]) + float(r2) * 0.5
					var col: Array = _column_check(px, w, h, thr, int(cx), y, unit)
					if not col.is_empty():
						_add_finder(found, Vector2(cx, float(col[0])), (unit + float(col[1])) * 0.5)
			i += 2
	var out: Array = []
	for c in found:
		if int(c[3]) >= 2:
			out.append(c)
	return out


## Walk up and down from (x, y) inside the finder's centre square and check
## the same 1:1:3:1:1 shape vertically. Returns [center_y, module_size] or [].
static func _column_check(px: PackedByteArray, w: int, h: int, thr: int, x: int, y: int, unit: float) -> Array:
	var limit: int = int(unit * 6.0) + 2
	var counts: Array = [0, 0, 0, 0, 0, 0]   # centre up, light up, dark up, centre down, light down, dark down
	for dir in 2:
		var step: int = -1 if dir == 0 else 1
		var yy: int = y if dir == 0 else y + 1
		var stage: int = 0
		while yy >= 0 and yy < h and stage < 3:
			var dark: bool = px[yy * w + x] < thr
			var want_dark: bool = stage != 1
			if dark == want_dark:
				counts[dir * 3 + stage] += 1
				if int(counts[dir * 3 + stage]) > limit:
					return []
				yy += step
			else:
				stage += 1
		if int(counts[dir * 3 + 1]) == 0 or int(counts[dir * 3 + 2]) == 0:
			return []
	var centre: int = int(counts[0]) + int(counts[3])
	var total: int = centre + int(counts[1]) + int(counts[2]) + int(counts[4]) + int(counts[5])
	var vunit: float = float(total) / 7.0
	if absf(vunit - unit) > unit * 0.5 or absf(float(centre) - 3.0 * vunit) > vunit * 1.2:
		return []
	var top: float = float(y - int(counts[0]) + 1)
	return [top + float(centre) * 0.5 - 0.5, vunit]


static func _add_finder(found: Array, p: Vector2, unit: float) -> void:
	for c in found:
		if (c[0] as Vector2).distance_to(p) < maxf(float(c[1]), unit) * 3.0:
			var n: int = int(c[3])
			c[0] = ((c[0] as Vector2) * float(n) + p) / float(n + 1)
			c[1] = (float(c[1]) * float(n) + unit) / float(n + 1)
			c[3] = n + 1
			return
	found.append([p, unit, 0, 1])


## A sampled grid (flat Array of 0/1, index y * size + x) -> text, or "".
static func decode_matrix(modules: Array) -> String:
	var size: int = int(round(sqrt(float(modules.size()))))
	if size * size != modules.size() or (size - 17) % 4 != 0:
		return ""
	var version: int = (size - 17) / 4
	if version < 1 or version > QRCode.MAX_VERSION:
		return ""
	# Which modules carry data: the encoder's own function-pattern map.
	var scratch: Array = []
	var is_function: Array = []
	scratch.resize(size * size)
	scratch.fill(0)
	is_function.resize(size * size)
	is_function.fill(0)
	QRCode._draw_function_patterns(scratch, is_function, version)
	# Format bits (copy around the top-left finder) -> mask, level M only.
	var fbits: int = 0
	for i in 6:
		fbits |= int(modules[i * size + 8]) << i
	fbits |= int(modules[7 * size + 8]) << 6
	fbits |= int(modules[8 * size + 8]) << 7
	fbits |= int(modules[8 * size + 7]) << 8
	for i in range(9, 15):
		fbits |= int(modules[8 * size + (14 - i)]) << i
	var mask: int = -1
	var best: int = 4
	for m in 8:
		var diff: int = _bit_count(fbits ^ QRCode.format_bits(m))
		if diff < best:
			best = diff
			mask = m
	if mask < 0:
		return ""
	var grid: Array = modules.duplicate()
	QRCode._apply_mask(grid, is_function, mask)
	# Codewords, in the encoder's zigzag order.
	var raw_len: int = QRCode.RAW_CODEWORDS[version]
	var raw := PackedByteArray()
	raw.resize(raw_len)
	var i: int = 0
	var total: int = raw_len * 8
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = size - 1 - vert if upward else vert
				if int(is_function[y * size + x]) == 0 and i < total:
					if int(grid[y * size + x]) == 1:
						raw[i >> 3] = raw[i >> 3] | (1 << (7 - (i & 7)))
					i += 1
		right -= 2
	# Undo the block interleave, then demand that every block's check bytes match.
	var num_blocks: int = QRCode.NUM_BLOCKS[version]
	var ecc_len: int = QRCode.ECC_PER_BLOCK[version]
	var num_short: int = num_blocks - raw_len % num_blocks
	var short_len: int = raw_len / num_blocks
	var blocks: Array = []
	for b in num_blocks:
		blocks.append([])
	var k: int = 0
	for pos in short_len + 1:
		for b in num_blocks:
			if pos != short_len - ecc_len or b >= num_short:
				(blocks[b] as Array).append(raw[k])
				k += 1
	var divisor: PackedByteArray = QRCode._rs_divisor(ecc_len)
	var data := PackedByteArray()
	for b in num_blocks:
		var blk := PackedByteArray(blocks[b] as Array)
		var dat: PackedByteArray = blk.slice(0, blk.size() - ecc_len)
		if QRCode._rs_remainder(dat, divisor) != blk.slice(blk.size() - ecc_len):
			return ""
		data.append_array(dat)
	# Byte mode: 0100, length, bytes.
	if data.size() < 2 or (data[0] >> 4) != 0b0100:
		return ""
	var bit: int = 4
	var count_bits: int = 8 if version <= 9 else 16
	var count: int = 0
	for n in count_bits:
		count = (count << 1) | ((data[bit >> 3] >> (7 - (bit & 7))) & 1)
		bit += 1
	if count <= 0 or bit + count * 8 > data.size() * 8:
		return ""
	var bytes := PackedByteArray()
	bytes.resize(count)
	for n in count:
		var v: int = 0
		for q in 8:
			v = (v << 1) | ((data[bit >> 3] >> (7 - (bit & 7))) & 1)
			bit += 1
		bytes[n] = v
	return bytes.get_string_from_utf8()


static func _bit_count(v: int) -> int:
	var n: int = 0
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## The room code inside an invite link (…/join/?c=AB3K9X or …/join/AB3K9X), or "".
static func room_code(text: String) -> String:
	var re := RegEx.new()
	re.compile("join/?(?:\\?c=)?([A-Za-z0-9]{6})(?:[^A-Za-z0-9]|$)")
	var m: RegExMatch = re.search(text)
	return m.get_string(1).to_upper() if m != null else ""
