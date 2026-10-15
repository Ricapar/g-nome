class_name ListPicker
extends ScrollContainer
## A scrolling list of selectable rows: save/load slots, mission select, network sessions.
## Items are [title] or [title, detail]; the detail sits on the right in the mono face.
## Up/down (keyboard, d-pad) move between rows and the list scrolls to follow focus.
## The first press on a row selects it (`item_selected`); pressing the selected row again,
## or accept on it, activates it (`item_activated`).

signal item_selected(index: int)
signal item_activated(index: int)

@export var row_height := 54.0
@export var status_text := ""

var selected := -1
var rows: Array[Button] = []
var _box := VBoxContainer.new()
var _group := ButtonGroup.new()


func _init() -> void:
	follow_focus = true
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 0)
	add_child(_box)


func set_items(items: Array) -> void:
	for r in rows:
		r.queue_free()
	rows.clear()
	selected = -1
	for i in items.size():
		var item: Array = items[i] if items[i] is Array else [str(items[i])]
		var row := Button.new()
		row.theme_type_variation = &"ListRow"
		row.toggle_mode = true
		row.button_group = _group
		row.focus_mode = FOCUS_ALL
		row.custom_minimum_size.y = row_height
		row.pressed.connect(_on_row.bind(i))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		h.offset_left = 20
		h.offset_right = -16
		h.mouse_filter = MOUSE_FILTER_IGNORE
		var t := Label.new()
		t.theme_type_variation = &"ListRowText"
		t.text = item[0]
		t.size_flags_horizontal = SIZE_EXPAND_FILL
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(t)
		if item.size() > 1:
			var d := Label.new()
			d.theme_type_variation = &"ListRowDetail"
			d.text = item[1]
			d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			d.mouse_filter = MOUSE_FILTER_IGNORE
			h.add_child(d)
		row.add_child(h)
		_box.add_child(row)
		rows.append(row)
		if has_node(^"/root/UiSfx"):
			UiSfx.bind(row, &"slot")


func select(i: int, emit := false) -> void:
	selected = i
	if i >= 0 and i < rows.size():
		rows[i].set_pressed_no_signal(true)
		for j in rows.size():
			if j != i:
				rows[j].set_pressed_no_signal(false)
	if emit:
		item_selected.emit(i)


func _on_row(i: int) -> void:
	if i == selected:
		item_activated.emit(i)
	else:
		select(i, true)
