extends Node
## The pause menu in a single-player run: MAIN MENU leaves the run, and where
## the app cannot close itself (iOS) there is no QUIT / EXIT button to press
## in vain. Run: godot --headless --path . res://scenes/tools/PauseMenuTest.tscn
func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/tools/PauseMenuRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
