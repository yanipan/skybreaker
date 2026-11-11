extends RefCounted
class_name QRCode
## Small QR Code encoder (ISO/IEC 18004 model 2) for the co-op invite screen.
## Byte mode over UTF-8, error correction level M, versions 1-10 (up to 213
## bytes), mask chosen by the standard penalty score. No nodes, no plugins.
##   var m: Array = QRCode.encode("https://.../join/AB3K9X")   # rows of PackedByteArray, 1 = dark
##   var img: Image = QRCode.to_image(m, 8, 4)
## Checked by scenes/tools/QRCodeTest.tscn: every code is decoded back with zbarimg.

const MAX_VERSION: int = 10
## Level M, index = version (0 unused).
const ECC_PER_BLOCK: Array = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const NUM_BLOCKS: Array = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const RAW_CODEWORDS: Array = [0, 26, 44, 70, 100, 134, 172, 196, 242, 292, 346]
const ALIGN: Array = [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]


static func data_codewords(version: int) -> int:
	return int(RAW_CODEWORDS[version]) - int(ECC_PER_BLOCK[version]) * int(NUM_BLOCKS[version])


static func version_of(matrix: Array) -> int:
	return 0 if matrix.is_empty() else (matrix.size() - 17) / 4


static func encode(text: String) -> Array:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	if bytes.is_empty():
		return []
	var version: int = 0
	for v in range(1, MAX_VERSION + 1):
		var count_bits: int = 8 if v <= 9 else 16
		if 4 + count_bits + bytes.size() * 8 <= data_codewords(v) * 8:
			version = v
			break
	if version == 0:
		return []
	# --- Bit stream: mode 0100, length, data, terminator, pad bytes ---
	var bits: Array = []
	_push_bits(bits, 0b0100, 4)
	_push_bits(bits, bytes.size(), 8 if version <= 9 else 16)
	for b in bytes:
		_push_bits(bits, b, 8)
	var capacity: int = data_codewords(version) * 8
	_push_bits(bits, 0, mini(4, capacity - bits.size()))
	_push_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad: int = 0xEC
	while bits.size() < capacity:
		_push_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var data := PackedByteArray()
	data.resize(bits.size() / 8)
	for i in bits.size():
		data[i >> 3] = data[i >> 3] | (int(bits[i]) << (7 - (i & 7)))
	var codewords: PackedByteArray = _add_ecc_and_interleave(data, version)
	# --- Matrix ---
	# Internally the grid is two FLAT Arrays of ints (index y * size + x).
	# Arrays are shared by reference; writing through a PackedByteArray taken
	# out of another array changes a copy and the write is lost.
	var size: int = version * 4 + 17
	var modules: Array = []
	var is_function: Array = []
	modules.resize(size * size)
	modules.fill(0)
	is_function.resize(size * size)
	is_function.fill(0)
	_draw_function_patterns(modules, is_function, version)
	_draw_codewords(modules, is_function, codewords)
	# --- Mask with the lowest penalty ---
	var best_mask: int = 0
	var best_penalty: int = 1 << 30
	for mask in 8:
		_apply_mask(modules, is_function, mask)
		_draw_format_bits(modules, is_function, mask)
		var p: int = _penalty(modules)
		if p < best_penalty:
			best_penalty = p
			best_mask = mask
		_apply_mask(modules, is_function, mask)   # XOR again = undo
	_apply_mask(modules, is_function, best_mask)
	_draw_format_bits(modules, is_function, best_mask)
	var rows: Array = []
	for y in size:
		var row := PackedByteArray()
		row.resize(size)
		for x in size:
			row[x] = int(modules[y * size + x])
		rows.append(row)
	return rows


static func to_image(matrix: Array, scale: int = 8, quiet: int = 4) -> Image:
	if matrix.is_empty():
		return null
	var n: int = matrix.size()
	var side: int = (n + quiet * 2) * scale
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in n:
		var row: PackedByteArray = matrix[y]
		for x in n:
			if row[x] == 1:
				img.fill_rect(Rect2i((x + quiet) * scale, (y + quiet) * scale, scale, scale), Color.BLACK)
	return img


# --- Bits ---

static func _push_bits(bits: Array, value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


# --- Reed-Solomon over GF(256), polynomial 0x11D ---

static func _gf_mul(x: int, y: int) -> int:
	var z: int = 0
	for i in range(7, -1, -1):
		z = ((z << 1) ^ ((z >> 7) * 0x11D)) & 0xFFFF
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root: int = 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] = result[j] ^ result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var n: int = divisor.size()
	var result := PackedByteArray()
	result.resize(n)
	for b in data:
		var factor: int = b ^ result[0]
		for i in n - 1:
			result[i] = result[i + 1]
		result[n - 1] = 0
		for i in n:
			result[i] = result[i] ^ _gf_mul(divisor[i], factor)
	return result


## Split the data into blocks, add each block's error-correction codewords,
## and interleave them the way the standard reads them back.
static func _add_ecc_and_interleave(data: PackedByteArray, version: int) -> PackedByteArray:
	var num_blocks: int = NUM_BLOCKS[version]
	var ecc_len: int = ECC_PER_BLOCK[version]
	var raw: int = RAW_CODEWORDS[version]
	var num_short: int = num_blocks - raw % num_blocks
	var short_len: int = raw / num_blocks
	var divisor: PackedByteArray = _rs_divisor(ecc_len)
	var blocks: Array = []
	var k: int = 0
	for i in num_blocks:
		var dat_len: int = short_len - ecc_len + (0 if i < num_short else 1)
		var dat: PackedByteArray = data.slice(k, k + dat_len)
		k += dat_len
		var ecc: PackedByteArray = _rs_remainder(dat, divisor)
		if i < num_short:
			dat.append(0)   # placeholder so every block has the same length
		dat.append_array(ecc)
		blocks.append(dat)
	var result := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= num_short:   # skip the placeholder
				result.append((blocks[j] as PackedByteArray)[i])
	return result


# --- Function patterns ---

static func _side(modules: Array) -> int:
	return int(round(sqrt(float(modules.size()))))


static func _set_fn(modules: Array, is_function: Array, x: int, y: int, dark: bool) -> void:
	var size: int = _side(modules)
	modules[y * size + x] = 1 if dark else 0
	is_function[y * size + x] = 1


static func _draw_function_patterns(modules: Array, is_function: Array, version: int) -> void:
	var size: int = _side(modules)
	for i in size:   # timing
		_set_fn(modules, is_function, 6, i, i % 2 == 0)
		_set_fn(modules, is_function, i, 6, i % 2 == 0)
	_draw_finder(modules, is_function, 3, 3)
	_draw_finder(modules, is_function, size - 4, 3)
	_draw_finder(modules, is_function, 3, size - 4)
	var pos: Array = ALIGN[version]
	var n: int = pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue   # those corners are finders
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_fn(modules, is_function, int(pos[i]) + dx, int(pos[j]) + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format_bits(modules, is_function, 0)   # reserves the area; real bits after masking
	if version >= 7:
		var rem: int = version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var vbits: int = (version << 12) | rem
		for i in 18:
			var bit: bool = ((vbits >> i) & 1) != 0
			var a: int = size - 11 + i % 3
			var b: int = i / 3
			_set_fn(modules, is_function, a, b, bit)
			_set_fn(modules, is_function, b, a, bit)


static func _draw_finder(modules: Array, is_function: Array, cx: int, cy: int) -> void:
	var size: int = _side(modules)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or x >= size or y < 0 or y >= size:
				continue
			var dist: int = maxi(absi(dx), absi(dy))
			_set_fn(modules, is_function, x, y, dist != 2 and dist != 4)


## The 15 format bits for level M (00) and `mask`: 5 data bits, BCH(15,5)
## remainder, XOR 0x5412. Public so the test can compare it with the table in
## the standard (a scanner corrects up to 3 wrong bits here, so decoding
## alone cannot prove these are exact).
static func format_bits(mask: int) -> int:
	var data: int = (0 << 3) | mask
	var rem: int = data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	return ((data << 10) | rem) ^ 0x5412


## Format information, two copies.
static func _draw_format_bits(modules: Array, is_function: Array, mask: int) -> void:
	var size: int = _side(modules)
	var fbits: int = format_bits(mask)
	for i in 6:
		_set_fn(modules, is_function, 8, i, ((fbits >> i) & 1) != 0)
	_set_fn(modules, is_function, 8, 7, ((fbits >> 6) & 1) != 0)
	_set_fn(modules, is_function, 8, 8, ((fbits >> 7) & 1) != 0)
	_set_fn(modules, is_function, 7, 8, ((fbits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_fn(modules, is_function, 14 - i, 8, ((fbits >> i) & 1) != 0)
	for i in 8:
		_set_fn(modules, is_function, size - 1 - i, 8, ((fbits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_fn(modules, is_function, 8, size - 15 + i, ((fbits >> i) & 1) != 0)
	_set_fn(modules, is_function, 8, size - 8, true)   # the dark module


# --- Data ---

## Zigzag from the bottom-right corner, two columns at a time, skipping column 6.
static func _draw_codewords(modules: Array, is_function: Array, data: PackedByteArray) -> void:
	var size: int = _side(modules)
	var i: int = 0
	var total: int = data.size() * 8
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
					modules[y * size + x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


static func _apply_mask(modules: Array, is_function: Array, mask: int) -> void:
	var size: int = _side(modules)
	for y in size:
		for x in size:
			if int(is_function[y * size + x]) == 1:
				continue
			var invert: bool = false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y * size + x] = int(modules[y * size + x]) ^ 1


# --- Penalty score (the four standard rules) ---

static func _penalty(modules: Array) -> int:
	var size: int = _side(modules)
	var result: int = 0
	var dark: int = 0
	var finder_a: Array = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
	var finder_b: Array = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
	for pass_i in 2:   # 0 = rows, 1 = columns
		for a in size:
			var run_color: int = -1
			var run_len: int = 0
			var line := PackedByteArray()
			line.resize(size)
			for b in size:
				var v: int = int(modules[a * size + b]) if pass_i == 0 else int(modules[b * size + a])
				line[b] = v
				if pass_i == 0:
					dark += v
				if v == run_color:
					run_len += 1
					if run_len == 5:
						result += 3
					elif run_len > 5:
						result += 1
				else:
					run_color = v
					run_len = 1
			for s in range(0, size - 10):   # 1:1:3:1:1 with four light modules on one side
				var is_a: bool = true
				var is_b: bool = true
				for k in 11:
					if line[s + k] != finder_a[k]:
						is_a = false
					if line[s + k] != finder_b[k]:
						is_b = false
					if not is_a and not is_b:
						break
				if is_a:
					result += 40
				if is_b:
					result += 40
	for y in size - 1:   # 2x2 blocks of one colour
		for x in size - 1:
			var c: int = int(modules[y * size + x])
			if c == int(modules[y * size + x + 1]) and c == int(modules[(y + 1) * size + x]) and c == int(modules[(y + 1) * size + x + 1]):
				result += 3
	var total: int = size * size   # balance of dark and light
	var k5: int = int(ceil(absf(float(dark) * 20.0 - float(total) * 10.0) / float(total))) - 1
	result += maxi(0, k5) * 10
	return result
