@tool
class_name KeyButton
extends Button
## A key on the bottom bar. The key itself is 3D (MenuFrame); this is its label and hit area.
## Selected keys get an italic label and a green outline glow; the green LED is lit by the menu.
## Text style: theme type "KeyButton" (italic: "KeyButtonSelected").

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
	var r := Rect2(Vector2.ZERO, size)
	if button_pressed:
		for k in 3: # soft outer glow from stacked strokes, then the crisp line
			draw_rect(r.grow(2.0 + k * 2.0), Color(GLOW, 0.05), false, 2.0)
		draw_rect(r.grow(1.0), GLOW, false, 2.0)
	elif _hover or has_focus():
		draw_rect(r.grow(1.0), Color(0.8, 1.0, 0.95, 0.35), false, 1.5)
