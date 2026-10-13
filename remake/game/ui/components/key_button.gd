@tool
class_name KeyButton
extends Button
## A key on the bottom bar. The key itself is 3D (MenuFrame); this is its face plate's hit area
## and label (the label sits low on the plate, below the LED slot; see theme "KeyButton").
## Selected keys get an italic label and a thin green outline along the plate's edge; the green
## LED is lit by the menu. Keyboard/gamepad focus and hover show a faint pale outline.

const GLOW := Color(0.25, 0.9, 0.42)

@export var status_text := ""

var _hover := false


func _init() -> void:
	theme_type_variation = &"KeyButton"
	toggle_mode = true
	focus_mode = FOCUS_ALL
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(on): theme_type_variation = &"KeyButtonSelected" if on else &"KeyButton"; queue_redraw())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-3.0)
	if button_pressed:
		for k in 3: # soft outer glow from stacked strokes, then the crisp line
			draw_rect(r.grow(1.5 + k * 2.0), Color(GLOW, 0.05), false, 2.0)
		draw_rect(r, GLOW, false, 1.5)
	elif _hover or has_focus():
		draw_rect(r, Color(0.8, 1.0, 0.95, 0.4), false, 1.5)
