@tool
class_name StatusBar
extends Control
## The help line under the screen: a yellow double chevron and left-aligned yellow text.

const YELLOW := Color(1.0, 0.82, 0.15)

var text := "":
	set(v):
		text = v
		if _label:
			_label.text = v

## Shown while nothing watched is hovered or focused.
var base_text := "":
	set(v):
		base_text = v
		if _hot == null:
			text = v

var _label := Label.new()
var _hot: Control = null


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


## Show the help text of whatever is hovered or focused under `root`: the nearest non-empty
## `status_text` up the parent chain (components export one; plain controls can carry a
## "status_text" meta), else the control's tooltip.
## Call after the screen has built its controls.
func watch(root: Node) -> void:
	for c: Control in root.find_children("*", "Control", true, false):
		if c.focus_mode == FOCUS_NONE and not c is BaseButton:
			continue
		if c.has_meta(&"status_watched"):
			continue
		c.set_meta(&"status_watched", true)
		c.mouse_entered.connect(_enter.bind(c))
		c.focus_entered.connect(_enter.bind(c))
		c.mouse_exited.connect(_leave.bind(c))
		c.focus_exited.connect(_leave.bind(c))


static func status_of(c: Node) -> String:
	var n := c
	while n:
		if "status_text" in n and n.status_text != "":
			return n.status_text
		if n.has_meta(&"status_text"):
			return n.get_meta(&"status_text")
		n = n.get_parent()
	return c.tooltip_text if c is Control else ""


func _enter(c: Control) -> void:
	var s := status_of(c)
	if s != "":
		_hot = c
		text = s


func _leave(c: Control) -> void:
	if _hot == c:
		_hot = null
		text = base_text
