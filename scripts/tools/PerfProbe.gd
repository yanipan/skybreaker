extends Node
## CPU cost of a gameplay frame on a heavy sector, for before/after comparisons.
## Run with a fixed timestep so every frame simulates exactly 1/60 s and the
## wall clock per frame is the real CPU cost (no vsync / fps-cap sleeping):
##   godot --headless --fixed-fps 60 --path . res://scenes/tools/PerfProbe.tscn [-- sector=24 frames=2400]
## Headless has no GPU, so this measures scripts + physics + canvas command
## building (every _draw call still runs), not fill rate. The ship is
## untouchable and holds its fire button so both shot pools are busy.

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/tools/PerfProbeRunner.gd"))
	get_tree().root.add_child.call_deferred(runner)
