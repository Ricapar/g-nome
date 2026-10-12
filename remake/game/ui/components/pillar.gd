@tool
class_name Pillar
extends Control
## A side pillar of the menu machinery with four glass slots (remake/UI-DESIGN.md, "Frame").

signal slot_pressed(index: int)
signal slot_hovered(index: int)

## Mirror the decoration (pipe on the outer side) for the right-hand pillar.
@export var mirrored := false:
	set(v): mirrored = v; _layout()

@onready var slots: Array[GlassButton] = [%Slot0, %Slot1, %Slot2, %Slot3]


func _ready() -> void:
	_layout()
	if Engine.is_editor_hint():
		return
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in slots.size():
		var s := slots[i]
		s.button_group = group
		s.set_entry("")
		s.pressed.connect(slot_pressed.emit.bind(i))
		s.mouse_entered.connect(slot_hovered.emit.bind(i))
		s.focus_entered.connect(slot_hovered.emit.bind(i))


func _layout() -> void:
	if not is_node_ready():
		return
	var pipe: Control = $Pipe
	var col: Control = $Slots
	var frame: Control = $SlotFrame
	if mirrored:
		pipe.anchor_left = 0.88; pipe.anchor_right = 0.98
		col.anchor_left = 0.06; col.anchor_right = 0.86
		frame.anchor_left = 0.03; frame.anchor_right = 0.89
	else:
		pipe.anchor_left = 0.02; pipe.anchor_right = 0.12
		col.anchor_left = 0.14; col.anchor_right = 0.94
		frame.anchor_left = 0.11; frame.anchor_right = 0.97


## Fill the slots with [label, status] pairs; missing entries leave blue glass.
func set_entries(entries: Array) -> void:
	for i in slots.size():
		var e: Array = entries[i] if i < entries.size() else ["", ""]
		slots[i].set_entry(e[0], e[1])
	var pressed := slots[0].button_group.get_pressed_button()
	if pressed:
		pressed.button_pressed = false


func select(index: int) -> void:
	slots[index].button_pressed = true
