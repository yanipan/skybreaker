extends Node
## Always-shipped stub that mounts dev-only tools in debug builds.
##
## scripts/tools/* is excluded from every export preset, so registering
## ScreenshotCapture directly as an autoload made the exported game log
## "Failed to instantiate an autoload" at every launch. This stub ships
## instead and only loads the tool when it is actually present (editor and
## local debug runs).

## Dev tool scripts to mount as children when available.
const DEV_TOOL_SCRIPTS: Array = [
	"res://scripts/tools/ScreenshotCapture.gd",
]


func _ready() -> void:
	if not OS.is_debug_build():
		return
	for path in DEV_TOOL_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var script: Script = load(path) as Script
		if script == null:
			continue
		var node: Node = script.new() as Node
		if node == null:
			continue
		node.name = String(path.get_file().get_basename())
		add_child(node)
