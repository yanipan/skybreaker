extends SceneTree
## One-shot offline chroma-key strip. Bakes the corner-sample background
## removal that ParallaxBg / Main / StarbaseShop / Boss / Enemy used to run per
## pixel at runtime straight into the source PNGs, so the game just loads
## already-transparent art.
##
## Run headless from the project root (back up the PNGs first, the files are
## overwritten in place):
##   Godot --headless --path <project> -s res://scripts/tools/strip_backgrounds.gd
## then re-import:  Godot --headless --path <project> --import
##
## Pixels come from the IMPORTED texture (load().get_image()), exactly like the
## old runtime code, so the result is identical to what the game used to show.
## Not idempotent: running it twice re-keys the already-stripped art (corners
## become transparent black). Restore from backup before re-running.

## path -> squared RGB distance tolerance, copied from each old call site.
const JOBS: Dictionary = {
	# ParallaxBg._load_and_strip (tol 0.20)
	"res://assets/sprites/bg/ringed_gas_giant.png": 0.20,
	"res://assets/sprites/bg/cracked_red_dwarf.png": 0.20,
	"res://assets/sprites/bg/ice_moon_aurora.png": 0.20,
	"res://assets/sprites/bg/shattered_moon.png": 0.20,
	"res://assets/sprites/bg/derelict_cruiser.png": 0.20,
	"res://assets/sprites/bg/asteroid_cluster.png": 0.20,
	"res://assets/sprites/bg/crystalline_shard_cluster.png": 0.20,
	"res://assets/sprites/bg/bioluminescent_jellyfish.png": 0.20,
	"res://assets/sprites/bg/warp_gate_ruins.png": 0.20,
	"res://assets/sprites/bg/crystal_sentinel_vortex.png": 0.20,
	"res://assets/sprites/bg/nebula_cyan_magenta.png": 0.20,
	"res://assets/sprites/bg/dust_pillars.png": 0.20,
	# Main._strip_white_bg (tol 0.20)
	"res://assets/sprites/ui/gamelogo.png": 0.20,
	# StarbaseShop._get_alien_texture (tol 0.18)
	"res://assets/sprites/shop/alien1.png": 0.18,
	"res://assets/sprites/shop/alien2.png": 0.18,
	"res://assets/sprites/shop/alien3.png": 0.18,
	"res://assets/sprites/shop/alien4.png": 0.18,
	# Boss._strip_background, BOSS2 only (tol 0.18)
	"res://assets/sprites/boss2.png": 0.18,
	# Enemy._stripped_tex (tol 0.20)
	"res://assets/sprites/enemy_swarmer.png": 0.20,
	"res://assets/sprites/enemy_lancer.png": 0.20,
	"res://assets/sprites/enemy_brooder.png": 0.20,
	"res://assets/sprites/enemy_reaper.png": 0.20,
}


func _initialize() -> void:
	var failed: int = 0
	for path in JOBS:
		if not _strip(path, float(JOBS[path])):
			failed += 1
	print("strip_backgrounds: done, %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _strip(path: String, tol: float) -> bool:
	var raw: Texture2D = load(path) as Texture2D
	if raw == null:
		push_error("strip_backgrounds: cannot load " + path)
		return false
	var img: Image = raw.get_image()
	if img == null:
		push_error("strip_backgrounds: no image for " + path)
		return false
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 2 or h <= 2:
		push_error("strip_backgrounds: too small " + path)
		return false
	var c00: Color = img.get_pixel(0, 0)
	var c10: Color = img.get_pixel(w - 1, 0)
	var c01: Color = img.get_pixel(0, h - 1)
	var c11: Color = img.get_pixel(w - 1, h - 1)
	var key := Color(
		(c00.r + c10.r + c01.r + c11.r) * 0.25,
		(c00.g + c10.g + c01.g + c11.g) * 0.25,
		(c00.b + c10.b + c01.b + c11.b) * 0.25,
		1.0
	)
	var erased: int = 0
	for y in h:
		for x in w:
			var p: Color = img.get_pixel(x, y)
			var dr: float = p.r - key.r
			var dg: float = p.g - key.g
			var db: float = p.b - key.b
			if dr * dr + dg * dg + db * db < tol:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				erased += 1
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("strip_backgrounds: save failed %s (%d)" % [path, err])
		return false
	print("stripped %s %dx%d key=%s erased=%.1f%%" % [path, w, h, key.to_html(false), 100.0 * erased / float(w * h)])
	return true
