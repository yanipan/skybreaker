extends Node
## Headless check: leaving the starbase shop does not resume the fight at once.
## The tree stays paused behind the GET READY 3-2-1 countdown, then unpauses.
## Run: godot --headless --path . res://scenes/tools/ShopExitTest.tscn
## The runner lives on the root because change_scene frees the current scene.

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/tools/ShopExitRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
