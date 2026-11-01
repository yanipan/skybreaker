extends Node
## Headless check: CONTINUE never replays the intro and runs the countdown.
## Run: godot --headless --path . res://scenes/tools/ResumeTest.tscn

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(preload("res://scripts/tools/ResumeRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
