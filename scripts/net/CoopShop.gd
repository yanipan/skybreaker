extends Node
class_name CoopShop
## CO-OP shared shop, phone side (docs/MULTIPLAYER_PLAN.md, "Co-op shop").
## Rule (Yaniv 11/11): when one enters both enter; the one who leaves first
## waits for the other. The server freezes the world for the whole visit.
##
## SHOP_OPEN  -> pause, open the normal StarbaseShop for this phone's ship
## LEAVE      -> tell the server READY, show "WAITING FOR <partner>" with a
##               BACK TO SHOP button (changing your mind is allowed)
## SHOP_CLOSE -> everything shut, Main's GET READY 3-2-1, the world runs
## A strip on top shows the partner: shopping / ready, what they bought, and
## the countdown when a matched game puts the slower player on the clock.

const StarbaseShopScript := preload("res://scripts/StarbaseShop.gd")
const ITEM_NAMES: Dictionary = {}   ## kind -> nicer text (falls back to the kind itself)

var main: Node = null
var client: Node = null
var open: bool = false            ## Between SHOP_OPEN and SHOP_CLOSE
var ready_sent: bool = false      ## This phone has left the shop
var partner_ready: bool = false
var _shop: CanvasLayer = null
var _wait: CanvasLayer = null
var _strip: CanvasLayer = null
var _strip_label: Label = null
var _wait_label: Label = null
var _last_buy: String = ""
var _timer_left: float = -1.0
var _base_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(m: Node, c: Node) -> void:
	main = m
	client = c
	c.shop_opened.connect(_on_opened)
	c.shop_state.connect(_on_state)
	c.shop_bought.connect(_on_bought)
	c.shop_timer.connect(_on_timer)
	c.shop_closed.connect(_on_closed)


func _exit_tree() -> void:
	# Main is reloading (respawn, sector jump): take the overlays with it.
	for n in [_shop, _wait, _strip]:
		if n != null and is_instance_valid(n):
			n.queue_free()


func _process(delta: float) -> void:
	if open and _timer_left >= 0.0:
		_timer_left = maxf(0.0, _timer_left - delta)
		_refresh_text()


func _partner_name() -> String:
	if main != null and "_partners" in main:
		for p in main._partners.values():
			if is_instance_valid(p) and str(p.pilot_name) != "":
				return str(p.pilot_name)
	return "PARTNER"


func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


# --- Server events ---

func _on_opened(base_id: int, docker: int) -> void:
	if open:
		return
	open = true
	ready_sent = false
	partner_ready = false
	_last_buy = ""
	_timer_left = -1.0
	_base_id = base_id
	get_tree().paused = true
	var sb = client.puppets.get(base_id)
	if sb != null and is_instance_valid(sb) and sb.has_method("net_shop_opened"):
		sb.net_shop_opened()
	_build_strip()
	if docker != Net.my_peer:
		_last_buy = "%s docked at the starbase" % _partner_name()
	if _player() == null:
		# No ship to shop for (down): nothing to buy, do not hold the partner up.
		_leave()
		return
	_open_shop()
	_refresh_text()


func _on_state(peer: int, ready: bool) -> void:
	if peer == Net.my_peer:
		return
	partner_ready = ready
	_refresh_text()


func _on_bought(peer: int, item: String) -> void:
	if peer == Net.my_peer:
		return
	_last_buy = "%s bought %s" % [_partner_name(), str(ITEM_NAMES.get(item, item)).to_upper().replace("_", " ")]
	_refresh_text()


func _on_timer(seconds: float) -> void:
	_timer_left = seconds
	_refresh_text()


func _on_closed() -> void:
	if not open:
		return
	open = false
	if _shop != null and is_instance_valid(_shop):
		if _shop.closed.is_connected(_leave):
			_shop.closed.disconnect(_leave)
		_shop.queue_free()
	_shop = null
	for n in [_wait, _strip]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_wait = null
	_strip = null
	var sb = client.puppets.get(_base_id)
	if sb != null and is_instance_valid(sb) and sb.has_method("_farewell"):
		sb._farewell()
	# The same GET READY 3-2-1 as single-player; Main unpauses when it ends.
	if main != null and is_instance_valid(main) and main.has_method("begin_resume_countdown"):
		main.begin_resume_countdown()
	else:
		get_tree().paused = false


# --- This phone ---

func _open_shop() -> void:
	if _wait != null and is_instance_valid(_wait):
		_wait.queue_free()
	_wait = null
	_shop = StarbaseShopScript.new()
	_shop.player_ref = _player()
	_shop.process_mode = Node.PROCESS_MODE_ALWAYS
	_shop.closed.connect(_leave)
	get_tree().root.add_child(_shop)


## LEAVE pressed (the shop frees itself): this phone is ready, now it waits.
func _leave() -> void:
	_shop = null
	if not open:
		return
	ready_sent = true
	Net.send(0, [Net.M.SHOP_READY, true])
	_build_wait()
	_refresh_text()


func _back_to_shop() -> void:
	if not open or _player() == null:
		return
	ready_sent = false
	Net.send(0, [Net.M.SHOP_READY, false])
	_open_shop()
	_refresh_text()


# --- Overlays ---

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.HEADLINE)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_strip() -> void:
	_strip = CanvasLayer.new()
	_strip.layer = 110   # above the shop (100)
	_strip.process_mode = Node.PROCESS_MODE_ALWAYS
	var size: Vector2 = get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.10, 0.85)
	bg.size = Vector2(size.x, 58)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(bg)
	_strip_label = _label("", 20, Color(0.65, 0.95, 1.0))
	_strip_label.size = Vector2(size.x, 58)
	_strip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip.add_child(_strip_label)
	get_tree().root.add_child(_strip)


func _build_wait() -> void:
	if _wait != null and is_instance_valid(_wait):
		return
	_wait = CanvasLayer.new()
	_wait.layer = 105
	_wait.process_mode = Node.PROCESS_MODE_ALWAYS
	var size: Vector2 = get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.size = size
	_wait.add_child(dim)
	_wait_label = _label("", 40, Color(1, 1, 1))
	_wait_label.size = Vector2(size.x, 120)
	_wait_label.position = Vector2(0, size.y * 0.36)
	_wait.add_child(_wait_label)
	if _player() != null:
		var b := Button.new()
		b.name = "BackToShop"
		b.text = "BACK TO SHOP"
		b.add_theme_font_override("font", Fonts.HEADLINE)
		b.add_theme_font_size_override("font_size", 28)
		b.size = Vector2(360, 84)
		b.position = Vector2((size.x - 360) * 0.5, size.y * 0.52)
		b.pressed.connect(_back_to_shop)
		_wait.add_child(b)
	get_tree().root.add_child(_wait)


func _refresh_text() -> void:
	var who: String = _partner_name()
	var clock: String = "   %d" % int(ceil(_timer_left)) if _timer_left >= 0.0 else ""
	if _strip_label != null and is_instance_valid(_strip_label):
		var state: String = "%s: READY" % who if partner_ready else "%s: SHOPPING" % who
		var extra: String = ("\n" + _last_buy) if _last_buy != "" else ""
		_strip_label.text = state + clock + extra
	if _wait_label != null and is_instance_valid(_wait_label):
		_wait_label.text = ("GET READY..." if partner_ready else "WAITING FOR %s..." % who) + clock
