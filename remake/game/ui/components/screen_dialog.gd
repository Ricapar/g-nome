class_name ScreenDialog
extends Control
## A modal prompt (quit confirm, abort mission, overwrite save): dims everything behind it and
## shows a title, body text and a row of ScreenButtons. Focus stays inside the dialog; cancel
## (Escape, pad B) picks `cancel_index`. Normally opened with `await UiRouter.confirm(...)`.
## `build_panel()` returns the bare panel (the gallery shows one inline).

signal closed(index: int)

const ALERT := preload("res://ui/icons/alert.svg")

var cancel_index := -1
var buttons: Array[Button] = []
var _panel: PanelContainer
var _done := false


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	# UI screens blend in linear light (HDR 2D), where 60% black only looks lightly dimmed
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)


## The panel on its own: an alert icon and title, the body, and the buttons (right-aligned,
## in the order given). The buttons are in the panel's "buttons" meta.
static func build_panel(title: String, body: String, labels: PackedStringArray, icon := true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 16)
	if icon:
		var ic := TextureRect.new()
		ic.texture = ALERT
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		head.add_child(ic)
	var t := Label.new()
	t.theme_type_variation = &"DialogTitle"
	t.text = title
	head.add_child(t)
	v.add_child(head)
	var sep := HSeparator.new()
	v.add_child(sep)
	var b := Label.new()
	b.theme_type_variation = &"BodyText"
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 520
	v.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 16)
	var list: Array[Button] = []
	for l in labels:
		var btn := Button.new()
		btn.theme_type_variation = &"ScreenButton"
		btn.text = l
		btn.custom_minimum_size.x = 150
		row.add_child(btn)
		list.append(btn)
	v.add_child(row)
	panel.set_meta(&"buttons", list)
	# focus stays on the button row: left/right between buttons, up/down nowhere
	for i in list.size():
		var me := list[i]
		me.focus_neighbor_top = ^"."
		me.focus_neighbor_bottom = ^"."
		me.focus_neighbor_left = me.get_path_to(list[maxi(i - 1, 0)]) if i > 0 else ^"."
		me.focus_neighbor_right = me.get_path_to(list[i + 1]) if i + 1 < list.size() else ^"."
	return panel


func open(title: String, body: String, labels: PackedStringArray, default_index := 0, cancel := -1) -> void:
	cancel_index = cancel if cancel >= 0 else labels.size() - 1
	_panel = build_panel(title, body, labels)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(_panel)
	add_child(center)
	buttons.assign(_panel.get_meta(&"buttons"))
	for i in buttons.size():
		buttons[i].pressed.connect(_close.bind(i))
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[i])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[i])
		if has_node(^"/root/UiSfx"):
			UiSfx.bind(buttons[i], &"toggle" if i != cancel_index else &"back")
	# focus ring only when the dialog was opened from keyboard/gamepad
	var hide := has_node(^"/root/UiRouter") and UiRouter.using_pointer
	buttons[clampi(default_index, 0, buttons.size() - 1)].grab_focus.call_deferred(hide)
	modulate.a = 0.0
	_panel.resized.connect(func(): _panel.pivot_offset = _panel.size * 0.5)
	_panel.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.14)


func cancel() -> void:
	if has_node(^"/root/UiSfx"):
		UiSfx.play(&"back")
	_close(cancel_index)


func _input(event: InputEvent) -> void:
	if not _done and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


func _close(i: int) -> void:
	if _done:
		return
	_done = true
	closed.emit(i)
