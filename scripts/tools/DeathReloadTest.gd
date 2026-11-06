extends Node
## Headless check: death reload / game-over must not crash Main._process.
## Body of the test lives on DeathReloadRunner, parented to the tree root so
## change_scene_to_file() / reload_current_scene() do not free it mid-await.
## Run: godot --headless --path . res://scenes/tools/DeathReloadTest.tscn

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(preload("res://scripts/tools/DeathReloadRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
