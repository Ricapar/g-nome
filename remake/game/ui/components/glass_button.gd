@tool
class_name GlassButton
extends Button
## A slot button in a pillar collar: smoky glass with pale text, glossy blue when empty,
## neon green with chevron markers when selected. Text style: theme type "GlassButton".

const SHADER := preload("res://ui/shaders/glass.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")
const MARK := Color(0.3, 0.95, 0.45)

## Status-line help text shown while hovered or focused.
@export var status_text := ""
## Draw as hovered/focused (gallery and screenshots).
@export var preview_hover := false:
	set(v): preview_hover = v; _refresh()

var _face := Control.new()
var _mat := ShaderMaterial.new()
var _hover := false
var _flash := 0.0:
	set(v): _flash = v; _mat.set_shader_parameter("flash", v)


func _init() -> void:
	theme_type_variation = &"GlassButton"
	toggle_mode = true
	focus_mode = FOCUS_ALL
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise", NOISE)
	_face.material = _mat
	_face.mouse_filter = MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	_face.set_anchors_preset(PRESET_FULL_RECT)
	_face.draw.connect(func(): _face.draw_rect(Rect2(Vector2.ZERO, _face.size), Color.WHITE))
	_face.resized.connect(func(): _mat.set_shader_parameter("size", _face.size))
	add_child(_face, false, INTERNAL_MODE_FRONT)
	mouse_entered.connect(func(): _hover = true; _refresh())
	mouse_exited.connect(func(): _hover = false; _refresh())
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	toggled.connect(func(_on): _refresh())
	pressed.connect(_on_pressed)


func _ready() -> void:
	_refresh()


## Empty slots show blue glass and can't be used.
func set_entry(label: String, status: String = "") -> void:
	text = label
	status_text = status
	disabled = label == ""
	focus_mode = FOCUS_NONE if disabled else FOCUS_ALL
	if disabled:
		button_pressed = false
	_refresh()


func _refresh() -> void:
	var state := 0
	if text != "":
		var lit := _hover or has_focus(true) or preview_hover
		state = (4 if lit else 3) if button_pressed else (2 if lit else 1)
	_mat.set_shader_parameter("state", state)
	queue_redraw()


func _draw() -> void:
	if not button_pressed or text == "":
		return
	# chevron markers pointing in from both ends
	var h := size.y * 0.16
	var cy := size.y * 0.5
	for side: float in [-1.0, 1.0]:
		var x := size.x * 0.5 + side * (size.x * 0.5 - 7.0)
		var tip := x - side * h * 0.9
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - h), Vector2(tip, cy), Vector2(x, cy + h)]), MARK)


func _on_pressed() -> void:
	var tw := create_tween()
	_flash = 1.0
	tw.tween_property(self, "_flash", 0.0, 0.18)
