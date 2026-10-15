@tool
class_name ChoiceButton
extends Button
## One option of a ChoiceRow, after the original's options pages: a triangle marker before a
## caps label. Chosen: a filled green triangle with a soft glow. Not chosen: a hollow triangle
## that brightens on hover or keyboard/gamepad focus. Text style: theme type "ChoiceButton"
## (its left content margin makes room for the marker).

const ON := Color(0.35, 1.0, 0.5)
const OFF := Color(0.22, 0.6, 0.36)
const DISABLED := Color(0.18, 0.32, 0.25)

## Draw as hovered (gallery and screenshots).
@export var preview_hover := false:
	set(v):
		preview_hover = v
		for c in [[&"font_color", &"font_hover_color"], [&"font_pressed_color", &"font_hover_pressed_color"]]:
			if v:
				add_theme_color_override(c[0], get_theme_color(c[1]))
			else:
				remove_theme_color_override(c[0])
		queue_redraw()


func _init() -> void:
	theme_type_variation = &"ChoiceButton"
	toggle_mode = true
	focus_mode = FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_on): queue_redraw())


func _draw() -> void:
	var h := size.y * 0.2
	var cy := size.y * 0.5
	var x := 12.0
	var tri := PackedVector2Array([Vector2(x, cy - h), Vector2(x + h * 1.6, cy), Vector2(x, cy + h)])
	var lit := preview_hover or is_hovered() or has_focus(true)
	if disabled:
		tri.append(tri[0])
		draw_polyline(tri, DISABLED, 2.0, true)
	elif button_pressed:
		# soft glow from a slightly larger, faint copy, then the solid marker
		var c := Vector2(x + h * 0.55, cy)
		var glow := PackedVector2Array()
		for p in tri:
			glow.append(c + (p - c) * 1.6)
		draw_colored_polygon(glow, Color(ON, 0.12))
		draw_colored_polygon(tri, ON)
	else:
		tri.append(tri[0])
		draw_polyline(tri, OFF.lerp(ON, 0.6) if lit else OFF, 2.0, true)
