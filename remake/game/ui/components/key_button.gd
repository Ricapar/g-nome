@tool
class_name KeyButton
extends Button
## A key on the bottom bar. The key itself is 3D (MenuFrame); this is its face plate's hit area
## and label (the label sits low on the plate, below the LED slot; see theme "KeyButton").
## The face is seen in perspective, so `face` holds its four projected corners (local pixels)
## and the outlines follow that trapezoid. Selected keys get a brighter, larger label and a thin green
## outline along the plate's edge; the green LED is lit by the menu. Keyboard/gamepad focus
## and hover show a faint pale outline.

const GLOW := Color(0.25, 0.9, 0.42)

@export var status_text := ""

## Projected corners of the face plate (top-left, top-right, bottom-right, bottom-left), in
## local pixels; empty = use the control's rect.
var face := PackedVector2Array():
	set(v):
		if v != face:
			face = v
			queue_redraw()

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


## The face outline shrunk (inset > 0) or grown toward/away from its centre, closed.
func _outline(inset: float) -> PackedVector2Array:
	var pts := face
	if pts.size() != 4:
		var r := Rect2(Vector2.ZERO, size)
		pts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= 4.0
	var out := PackedVector2Array()
	for p in pts:
		var d := p - c
		out.append(c + d * (1.0 - inset / maxf(d.length(), 1.0)))
	out.append(out[0])
	return out


func _draw() -> void:
	if button_pressed:
		for k in 3: # soft outer glow from stacked strokes, then the crisp line
			draw_polyline(_outline(3.0 - 1.5 - k * 2.0), Color(GLOW, 0.05), 2.0, true)
		draw_polyline(_outline(3.0), GLOW, 1.5, true)
	elif _hover or has_focus():
		draw_polyline(_outline(3.0), Color(0.8, 1.0, 0.95, 0.4), 1.5, true)
