@tool
class_name StatusBar
extends Control
## The help line under the screen: a yellow double chevron and left-aligned yellow text.

const YELLOW := Color(1.5, 1.2, 0.15)

var text := "":
	set(v):
		text = v
		if _label:
			_label.text = v

var _label := Label.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"StatusLabel"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_label, false, INTERNAL_MODE_FRONT)
	resized.connect(func(): _label.offset_left = size.y * 2.6; queue_redraw())


func _draw() -> void:
	var h := size.y * 0.42
	var cy := size.y * 0.5
	var x0 := size.y * 0.7
	for k in 2:
		var x := x0 + k * h * 0.75
		draw_polyline(PackedVector2Array([Vector2(x, cy - h * 0.6), Vector2(x + h * 0.6, cy), Vector2(x, cy + h * 0.6)]),
			YELLOW, maxf(size.y * 0.09, 2.0), true)
