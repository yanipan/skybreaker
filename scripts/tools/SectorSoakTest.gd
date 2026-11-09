extends Node
## Headless soak of the real gameplay scene on the late sectors: loads Main at
## each sector in SECTORS, lets the spawner run SOAK_SECONDS of game time at
## high time scale (waves, the new SHADE / ARTILLERY types, mortar bursts,
## boss entry), and fails on any missing enemy type or a dead scene.
## Run: godot --headless --path . res://scenes/tools/SectorSoakTest.tscn
## The runner lives on the root because change_scene frees the current scene.

const SECTORS: Array = [20, 21, 22, 23, 24]
const SOAK_SECONDS: float = 50.0

func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/tools/SectorSoakRunner.gd"))
	runner.sectors = SECTORS
	runner.soak_seconds = SOAK_SECONDS
	get_tree().root.add_child.call_deferred(runner)
