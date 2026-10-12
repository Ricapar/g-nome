@tool
class_name GlassButton
extends Button
## A pillar slot: blue glass when empty, a green phosphor button when it holds an entry.
## Text and states come from the theme type "GlassButton"; the face is ui/shaders/glass.gdshader.

const SHADER := preload("res://ui/shaders/glass.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")

## Status-line help text shown while hovered or focused.
@export var status_text := ""

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
		var lit := _hover or has_focus()
		state = (4 if lit else 3) if button_pressed else (2 if lit else 1)
	_mat.set_shader_parameter("state", state)


func _on_pressed() -> void:
	var tw := create_tween()
	_flash = 1.0
	tw.tween_property(self, "_flash", 0.0, 0.18)
