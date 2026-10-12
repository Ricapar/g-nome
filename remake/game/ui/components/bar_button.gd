@tool
class_name BarButton
extends Button
## A steel push-button on the bottom bar, with an LED that lights when its menu is open.
## Text style comes from the theme type "BarButton".

const SHADER := preload("res://ui/shaders/machine.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")

@export var status_text := ""

var _face := Control.new()
var _mat := ShaderMaterial.new()
var _press := 0.0


func _init() -> void:
	theme_type_variation = &"BarButton"
	toggle_mode = true
	focus_mode = FOCUS_ALL
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise", NOISE)
	_mat.set_shader_parameter("finish", 1)
	_mat.set_shader_parameter("cylinder", 1)
	_mat.set_shader_parameter("chamfer", 6.0)
	_mat.set_shader_parameter("bevel", 3.0)
	_mat.set_shader_parameter("hi_color", UIPalette.STEEL[0])
	_mat.set_shader_parameter("base_color", UIPalette.STEEL[1])
	_mat.set_shader_parameter("lo_color", UIPalette.STEEL[2])
	_face.material = _mat
	_face.mouse_filter = MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	_face.set_anchors_preset(PRESET_FULL_RECT)
	_face.draw.connect(func(): _face.draw_rect(Rect2(Vector2.ZERO, _face.size), Color.WHITE))
	_face.resized.connect(func(): _mat.set_shader_parameter("size", _face.size))
	add_child(_face, false, INTERNAL_MODE_FRONT)
	toggled.connect(func(_on): queue_redraw())
	button_down.connect(func(): _face.position.y = 2; _face.modulate = Color(0.85, 0.85, 0.85))
	button_up.connect(func(): _face.position.y = 0; _face.modulate = Color.WHITE)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	# LED slot above the label
	var w := size.x * 0.28
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.13), Vector2(w, size.y * 0.085))
	draw_rect(r.grow(2), Color(0.08, 0.08, 0.07))
	draw_rect(r, UIPalette.LED_ON if button_pressed else UIPalette.LED_OFF)
	if has_focus():
		draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(0.3, 1.6, 0.5, 0.8), false, 2.0)
