extends Area2D
class_name Starbase
## Friendly drifting shop. Cannot be hit by player or enemy bullets — touching it
## once opens the StarbaseShop overlay where the player spends money on upgrades.
## After the player closes the shop, the Starbase fades out and despawns. Each Starbase grants exactly one shopping session.
##
## Spawned by EnemySpawner on a random chance every few stages.

const TEX_STARBASE: Texture2D = preload("res://assets/sprites/starbase.png")
const StarbaseShopScript := preload("res://scripts/StarbaseShop.gd")

@export var drift_speed: float = 60.0
@export var visual_size: float = 220.0   ## Footprint width on screen

var _viewport_size: Vector2
var _used: bool = false             ## True once the player has opened the shop
## CO-OP: on a phone the starbase is a server puppet. Touching it only asks
## the server to DOCK; the server freezes the world and opens the shop on
## BOTH phones (scripts/net/CoopShop.gd).
var net_puppet: bool = false
var net_id: int = 0
var _dock_cd: float = 0.0
var _shop_open: bool = false        ## Pause drift while the menu is up
var _sprite: Sprite2D = null
var _time: float = 0.0
var _label: Label = null


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	add_to_group(&"starbases")
	# Friendly group — Player checks this in _on_area_entered to open the shop
	# without taking damage. Bullets and enemies do NOT touch this group, so the
	# Starbase is effectively invulnerable.
	z_index = 4
	_build_sprite()
	_build_collision()
	_build_floating_label()
	area_entered.connect(_on_area_entered)


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = TEX_STARBASE
	var s: float = visual_size / float(TEX_STARBASE.get_width())
	_sprite.scale = Vector2(s, s)
	add_child(_sprite)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(visual_size * 0.85, visual_size * 0.75)
	shape.shape = rect
	add_child(shape)


## Floating "SHOP — TOUCH TO ENTER" hint above the starbase so the player
## immediately understands what it is the first time one shows up.
func _build_floating_label() -> void:
	_label = Label.new()
	_label.text = "★ SHOP — TOUCH TO ENTER ★"
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.size = Vector2(360, 32)
	_label.position = Vector2(-180, -visual_size * 0.65)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	# Drift downward unless the shop is open (then it hovers in place)
	_dock_cd = maxf(0.0, _dock_cd - delta)
	if not _shop_open and not net_puppet:
		position.y += drift_speed * delta
	# Gentle horizontal sway and label pulse
	if _sprite != null:
		_sprite.position.x = sin(_time * 1.2) * 6.0
	if _label != null and not _used:
		# Pulse the hint label so it draws the eye
		var k: float = 0.7 + 0.3 * sin(_time * 4.0)
		_label.modulate = Color(1, 1, 1, k)
	# Despawn after fully scrolling off
	if position.y > _viewport_size.y + visual_size and not net_puppet:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _used:
		return
	if not area.is_in_group(&"player"):
		return
	if net_id > 0 and Net.is_client():
		if _dock_cd <= 0.0:
			_dock_cd = 1.5   # ask again if the server did not take it
			Net.send(0, [Net.M.DOCK, net_id])
		return
	_used = true
	_open_shop(area)


func _open_shop(player: Node) -> void:
	_shop_open = true
	if _label != null:
		_label.queue_free()
		_label = null
	# Pause the world while the shop is up — feels like a true menu beat.
	get_tree().paused = true
	var shop: CanvasLayer = StarbaseShopScript.new()
	shop.player_ref = player
	shop.process_mode = Node.PROCESS_MODE_ALWAYS
	shop.closed.connect(_on_shop_closed)
	get_tree().root.add_child(shop)


func _on_shop_closed() -> void:
	# Playtest 9/11: leaving the shop dropped the player straight back into
	# the fight. The game now stays frozen behind the same GET READY 3-2-1
	# countdown CONTINUE uses, and Main unpauses when it ends. Without a
	# Main scene (tool scenes) it just resumes.
	var main: Node = get_tree().current_scene
	if main != null and main.has_method("begin_resume_countdown"):
		main.begin_resume_countdown()
	else:
		get_tree().paused = false
	_farewell()


## CO-OP: the server opened the shop at this station.
func net_shop_opened() -> void:
	_used = true
	_shop_open = true
	if _label != null:
		_label.queue_free()
		_label = null


## "SAFE TRAVELS", then the used station shrinks, fades and frees itself.
func _farewell() -> void:
	_shop_open = false
	# Pop a friendly "thanks for shopping" hint label that fades as it floats
	var bye := Label.new()
	bye.text = "SAFE TRAVELS"
	bye.add_theme_font_size_override("font_size", 22)
	bye.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	bye.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bye.add_theme_constant_override("outline_size", 4)
	bye.size = Vector2(260, 30)
	bye.position = Vector2(-130, -visual_size * 0.65)
	bye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(bye)
	# 6/11: the used station no longer lingers on screen. It shrinks and
	# fades out (warping away) right after the shop closes, then frees.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.9).set_delay(0.5)
	if _sprite != null:
		tw.tween_property(_sprite, "scale", _sprite.scale * 0.35, 0.9).set_delay(0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
