extends Node
## Headless: a swipe that starts on a shop card (icon / BUY button) scrolls
## the list on the first try (events are sent in window space: headless
## runs at a different window size, so canvas points go through the
## viewport final transform) and does not buy anything; a plain tap still buys.
var _fails: int = 0

func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = get_viewport().get_final_transform() * pos
	e.relative = get_viewport().get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)

func _ready() -> void:
	GameState.money = 50000
	var shop: CanvasLayer = load("res://scripts/StarbaseShop.gd").new()
	add_child(shop)
	for i in 3:
		await get_tree().process_frame
	var scroll: ScrollContainer = shop._scroll
	_check(scroll != null, "shop has a scroll area")
	var row: Dictionary = shop._item_rows[2]   # PHASER POWER UP, first-row-ish card
	var icon: Control = row["icon_btn"]
	var start: Vector2 = icon.get_global_rect().get_center()
	_check(scroll.get_global_rect().has_point(start), "swipe starts on a card icon inside the list")
	var money0: int = GameState.money
	# Swipe up 320 px starting on the icon button.
	_touch(0, start, true)
	await get_tree().process_frame
	var p: Vector2 = start
	for i in 16:
		p += Vector2(0, -20)
		_drag(0, p, Vector2(0, -20))
		await get_tree().process_frame
	_touch(0, p, false)
	await get_tree().process_frame
	_check(scroll.scroll_vertical > 150, "first swipe on a button scrolls the list (%d px)" % scroll.scroll_vertical)
	_check(GameState.money == money0, "the swipe did not buy anything")
	_check(shop._buy_blocked(), "right after the swipe a BUY on release is blocked")
	# A clean tap after the block window buys.
	await get_tree().create_timer(0.3).timeout
	shop._fling_v = 0.0
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var buy: Button = row["button"]
	var c: Vector2 = buy.get_global_rect().get_center()
	if scroll.get_global_rect().has_point(c):
		_touch(1, c, true)
		await get_tree().process_frame
		_touch(1, c, false)
		await get_tree().process_frame
		# Headless buttons ignore injected touches, so check the guard itself:
		# a tap without movement must leave BUY unblocked.
		_check(not shop._buy_blocked(), "a plain tap on BUY is not blocked as a scroll")
		_check(scroll.scroll_vertical == 0, "a plain tap does not scroll (%d, fling %.0f)" % [scroll.scroll_vertical, shop._fling_v])
	else:
		print("SKIP  BUY button scrolled out of view")
	print("ShopScrollTest done, fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
