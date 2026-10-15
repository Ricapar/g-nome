class_name SliderRow
extends HBoxContainer
## A labelled slider with a phosphor readout of its value (volumes, sensitivity, FOV).
## Keyboard/gamepad: left/right change the value while focused, up/down leave the row.
## Emits `changed(value)`. The slider's look is the theme's HSlider (SVG grabbers).

signal changed(value: float)

@export var label := "VOLUME"
@export var min_value := 0.0
@export var max_value := 100.0
@export var step := 5.0
@export var value := 80.0:
	set(v):
		value = v
		if slider.value != v:
			slider.set_value_no_signal(v)
		_readout.text = format % v
## Readout format, e.g. "%d%%" or "%.1f".
@export var format := "%d%%"
@export var disabled := false:
	set(v):
		disabled = v
		slider.editable = not v
		slider.focus_mode = FOCUS_NONE if v else FOCUS_ALL
		modulate.a = 0.4 if v else 1.0
@export var label_width := 260.0
@export var status_text := ""

var slider := HSlider.new()
var _readout := Label.new()


func _ready() -> void:
	add_theme_constant_override(&"separation", 18)
	var l := Label.new()
	l.theme_type_variation = &"RowLabel"
	l.text = label
	l.custom_minimum_size.x = label_width
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 34)
	slider.focus_mode = FOCUS_ALL
	slider.value_changed.connect(_on_changed)
	add_child(slider)
	_readout.theme_type_variation = &"Readout"
	_readout.custom_minimum_size.x = 84
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_readout)
	value = value
	disabled = disabled
	if has_node(^"/root/UiSfx"):
		slider.mouse_entered.connect(func(): if not disabled: UiSfx.play(&"hover"))
		slider.focus_entered.connect(func(): if slider.has_focus(true): UiSfx.play(&"hover"))


func _on_changed(v: float) -> void:
	value = v
	changed.emit(v)
	if has_node(^"/root/UiSfx"):
		UiSfx.play(&"hover")
