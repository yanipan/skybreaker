extends Node2D
## Windowed look-check of the starbase shop icons at their real size: two
## shots (top of the list, scrolled to the bottom) to user://shop_shot_*.png.
## Run (needs a window): godot --path . res://scenes/tools/ShopShot.tscn

func _ready() -> void:
	GameState.current_level = 7
	GameState.money = 18450
	var pl: Node = load("res://scripts/Player.gd").new()
	pl.position = Vector2(-500, -500)
	add_child(pl)
	await get_tree().process_frame
	var shop: CanvasLayer = load("res://scripts/StarbaseShop.gd").new()
	shop.player_ref = pl
	add_child(shop)
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shop_shot_1.png")
	var sc: ScrollContainer = _find_scroll(shop)
	if sc != null:
		sc.scroll_vertical = 100000
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shop_shot_2.png")
	print("saved ", ProjectSettings.globalize_path("user://shop_shot_1.png"))
	get_tree().quit()


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null
