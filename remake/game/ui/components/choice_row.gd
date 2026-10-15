class_name ChoiceRow
extends HBoxContainer
## A labelled row of mutually exclusive options: difficulty, detail level, or an on/off toggle
## (options ["ON", "OFF"]), like the original's OPTIONS pages. Emits `changed(index)` when the
## player picks another option. Children are built at runtime from the exported fields.

signal changed(index: int)

@export var label := "OPTION"
@export var options := PackedStringArray(["ON", "OFF"])
@export var selected := 0:
	set(v):
		selected = v
		# set_pressed_no_signal doesn't unpress the rest of the group, so set every option
		for i in buttons.size():
			buttons[i].set_pressed_no_signal(i == v)
			buttons[i].queue_redraw()
@export var disabled := false:
	set(v):
		disabled = v
		for b in buttons:
			b.disabled = v
			b.focus_mode = FOCUS_NONE if v else FOCUS_ALL
		if _label:
			_label.modulate.a = 0.4 if v else 1.0
## Width reserved for the label, so rows in a column line up.
@export var label_width := 260.0
## Status-line help text (StatusBar.watch).
@export var status_text := ""

var buttons: Array[ChoiceButton] = []
var _label: Label
var _group := ButtonGroup.new()


func _ready() -> void:
	add_theme_constant_override(&"separation", 14)
	_label = Label.new()
	_label.theme_type_variation = &"RowLabel"
	_label.text = label
	_label.custom_minimum_size.x = label_width
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	for i in options.size():
		var b := ChoiceButton.new()
		b.text = options[i]
		b.button_group = _group
		b.pressed.connect(_on_pressed.bind(i))
		add_child(b)
		buttons.append(b)
		if has_node(^"/root/UiSfx"):
			UiSfx.bind(b, &"toggle")
	selected = selected
	disabled = disabled


func _on_pressed(i: int) -> void:
	if i != selected:
		selected = i
		changed.emit(i)
