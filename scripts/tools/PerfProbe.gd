extends Node
## Frame-cost probe of the real single-player game (run WINDOWED so drawing is
## measured): plays sectors at normal speed with an untouchable ship and prints
## the script time per frame, node count and draw calls.
## Run: godot --path . res://scenes/tools/PerfProbe.tscn -- --probe_sectors=13,20 --probe_secs=40
func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/tools/PerfProbeRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
