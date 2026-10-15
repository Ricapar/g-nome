class_name SafeArea
extends MarginContainer
## Keeps a screen's content inside a centred area no wider than `max_aspect` (16:9 by default),
## so on ultrawide displays (the user's 3840x1600 is 12:5) controls don't stretch across the
## whole screen. Backgrounds and decoration go outside it and reach the edges. `margin` is the
## base inset on every side, in design pixels.

@export var max_aspect := 16.0 / 9.0
@export var margin := Vector4(64, 26, 64, 22) # left, top, right, bottom


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(_apply)


func _ready() -> void:
	_apply()


func _apply() -> void:
	var extra := maxf(0.0, size.x - size.y * max_aspect) * 0.5
	add_theme_constant_override(&"margin_left", int(margin.x + extra))
	add_theme_constant_override(&"margin_top", int(margin.y))
	add_theme_constant_override(&"margin_right", int(margin.z + extra))
	add_theme_constant_override(&"margin_bottom", int(margin.w))
