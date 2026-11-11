extends Node
## Headless: every .gd under res://scripts must COMPILE inside the running
## project (autoloads present). `godot --import` does not report a script that
## fails to parse when nothing has loaded it yet: on 11/11 a new lobby script
## redeclared a member of its parent class, the start screen stopped
## compiling, and the import step said nothing.
## Run: godot --headless --path . res://scenes/tools/ScriptLoadTest.tscn

var _bad: Array = []
var _count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		var p: String = dir_path + "/" + f
		if d.current_is_dir():
			if not f.begins_with("."):
				_walk(p)
		elif f.ends_with(".gd"):
			_count += 1
			var res = load(p)
			if res == null or not (res is GDScript) or not (res as GDScript).can_instantiate():
				_bad.append(p)
		f = d.get_next()
	d.list_dir_end()


func _run() -> void:
	_walk("res://scripts")
	for p in _bad:
		print("FAIL  does not compile: ", p)
	print("ScriptLoadTest: %d passed, %d failed" % [_count - _bad.size(), _bad.size()])
	get_tree().quit(1 if not _bad.is_empty() else 0)
