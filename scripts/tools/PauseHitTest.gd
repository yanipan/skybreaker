extends Node
## Headless pause/hit overlap probe. Does not modify game code.
## Run: godot --headless --path . res://scenes/tools/PauseHitTest.tscn

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(preload("res://scripts/tools/PauseHitRunner.gd"))
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(runner)
