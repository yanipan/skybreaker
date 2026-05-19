extends Node2D
class_name ScorePopup
## Floating "+N" number that drifts upward and fades. Spawned by Enemy on death
## for arcade-y kill feedback. Self-destructs when its lifetime expires.

@export var amount: int = 0
@export var lifetime: float = 0.9
@export var rise: float = 60.0  ## Pixels it floats up over its lifetime
@export var text_color: Color = Color(1, 1, 1)

var _label: Label
var _age: float = 0.0
var _start_pos: Vector2


func _ready() -> void:
	_start_pos = position
	_label = Label.new()
	_label.text = "+%d" % amount
	_label.add_theme_font_size_override("font_size", _font_size_for_amount())
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	# Center the label on this node by sizing it and offsetting half its width.
	_label.size = Vector2(120, 36)
	_label.position = Vector2(-60, -18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _process(delta: float) -> void:
	_age += delta
	var k: float = _age / lifetime
	if k >= 1.0:
		queue_free()
		return
	# Ease-out rise: fast at first, slows toward the top
	var ease_k: float = 1.0 - pow(1.0 - k, 2.0)
	position.y = _start_pos.y - rise * ease_k
	# Hold full alpha for the first 60%, then fade
	var a: float = 1.0 if k < 0.6 else (1.0 - (k - 0.6) / 0.4)
	if _label != null:
		_label.modulate = Color(1, 1, 1, a)
		# Slight scale punch on spawn
		var s: float = 1.0 + 0.4 * (1.0 - clamp(_age / 0.12, 0.0, 1.0))
		_label.scale = Vector2(s, s)


## Bigger numbers print bigger so a tank kill feels chunkier than a grunt.
func _font_size_for_amount() -> int:
	if amount >= 60:
		return 36
	elif amount >= 25:
		return 30
	return 24
