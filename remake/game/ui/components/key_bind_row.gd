class_name KeyBindRow
extends HBoxContainer
## One function of the key-mapping grid: a label and three binding cells (the original's
## INTERFACE page allows three mappings per function). Press a cell, then a key, mouse button,
## gamepad button or stick/trigger to bind it; Escape cancels, Delete or Backspace clears.
## Emits `rebound(slot, event)` (event null = cleared). Applying the binding to the InputMap
## and checking conflicts is the screen's job (R14).

signal rebound(slot: int, event: InputEvent)

const SLOTS := 3
const JOY_BUTTONS := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "L-STICK", "R-STICK", "LB", "RB",
	"D-UP", "D-DOWN", "D-LEFT", "D-RIGHT"]
const JOY_AXES := ["L-STICK X", "L-STICK Y", "R-STICK X", "R-STICK Y", "LT", "RT"]
const MOUSE_BUTTONS := ["", "MOUSE L", "MOUSE R", "MOUSE M", "WHEEL UP", "WHEEL DOWN", "WHEEL LEFT",
	"WHEEL RIGHT", "MOUSE 4", "MOUSE 5"]

@export var label := "FUNCTION"
## InputMap action to read the initial bindings from (optional).
@export var action := &""
@export var label_width := 220.0
@export var cell_width := 170.0
@export var status_text := ""

var events: Array = [null, null, null]
var cells: Array[Button] = []
var capturing := -1
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override(&"separation", 12)
	var l := Label.new()
	l.theme_type_variation = &"RowLabel"
	l.text = label
	l.custom_minimum_size.x = label_width
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	if action != &"" and InputMap.has_action(action):
		var evs := InputMap.action_get_events(action)
		for i in mini(evs.size(), SLOTS):
			events[i] = evs[i]
	for i in SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(cell_width, 44)
		b.clip_text = true
		b.focus_mode = FOCUS_ALL
		b.pressed.connect(begin_capture.bind(i))
		add_child(b)
		cells.append(b)
		if has_node(^"/root/UiSfx"):
			UiSfx.bind(b, &"slot")
	set_process_input(false)
	set_process(false)
	_refresh()


## A header row lining up with KeyBindRows of the same widths.
static func make_header(first: String, label_w: float, cell_w: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	var titles := [first]
	for i in SLOTS:
		titles.append("MAPPING %d" % (i + 1))
	for i in titles.size():
		var l := Label.new()
		l.theme_type_variation = &"SectionLabel"
		l.text = titles[i]
		l.custom_minimum_size.x = label_w if i == 0 else cell_w
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(l)
	return h


func set_event(slot: int, event: InputEvent) -> void:
	events[slot] = event
	_refresh()


## Wait for the next key/button/axis and bind it to `slot`.
func begin_capture(slot: int) -> void:
	capturing = slot
	_t = 0.0
	set_process_input(true)
	set_process(true)
	_refresh()


## Show a cell in the capture state without listening for input (gallery and screenshots).
func preview_capture(slot: int) -> void:
	capturing = slot
	_refresh()


func _end_capture() -> void:
	var slot := capturing
	capturing = -1
	set_process_input(false)
	set_process(false)
	if slot >= 0:
		cells[slot].modulate.a = 1.0
	_refresh()


func _process(dt: float) -> void:
	_t += dt
	if capturing >= 0:
		cells[capturing].modulate.a = 0.7 + 0.3 * cos(_t * 7.0)


## Runs before the GUI and the screens, so the bound key never navigates or backs out.
func _input(event: InputEvent) -> void:
	if capturing < 0 or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	var slot := capturing
	if event is InputEventKey:
		match event.keycode:
			KEY_ESCAPE:
				_end_capture()
				return
			KEY_DELETE, KEY_BACKSPACE:
				events[slot] = null
				_end_capture()
				rebound.emit(slot, null)
				return
	var ev: InputEvent = event.duplicate()
	if ev is InputEventJoypadMotion:
		ev.axis_value = signf(ev.axis_value)
	events[slot] = ev
	_end_capture()
	rebound.emit(slot, ev)


static func event_text(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		var kc: Key = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
		return OS.get_keycode_string(kc).to_upper()
	if ev is InputEventMouseButton:
		return MOUSE_BUTTONS[ev.button_index] if ev.button_index < MOUSE_BUTTONS.size() else "MOUSE %d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "PAD " + (JOY_BUTTONS[ev.button_index] if ev.button_index < JOY_BUTTONS.size() else str(ev.button_index))
	if ev is InputEventJoypadMotion:
		var name: String = JOY_AXES[ev.axis] if ev.axis < JOY_AXES.size() else "AXIS %d" % ev.axis
		return name if ev.axis >= JOY_AXIS_TRIGGER_LEFT else name + ("+" if ev.axis_value > 0.0 else "-")
	return ev.as_text().to_upper()


func _refresh() -> void:
	for i in cells.size():
		var b := cells[i]
		if i == capturing:
			b.text = "PRESS A KEY"
			b.theme_type_variation = &"BindCellCapture"
		else:
			b.text = event_text(events[i])
			b.theme_type_variation = &"BindCell" if events[i] != null else &"BindCellEmpty"
