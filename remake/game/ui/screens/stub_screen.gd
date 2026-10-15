class_name StubScreen
extends Control
## Placeholder for a screen another backlog item builds (briefing R13, options R14, Lab R15):
## the screen glass, a title, a note and BACK. Push it with
##   UiRouter.push(StubScreen.make("LOAD GAME", "Arrives with R13."))

const GLASS := preload("res://ui/shaders/screen_glass.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")

var title := "SCREEN"
var note := ""


static func make(t: String, n: String) -> StubScreen:
	var s := StubScreen.new()
	s.title = t
	s.note = n
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = GLASS
	mat.set_shader_parameter("noise", NOISE)
	mat.set_shader_parameter("cut", Vector2(0.03, 0.02))
	bg.material = mat
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.resized.connect(func(): mat.set_shader_parameter("size", bg.size))
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 24)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var t := Label.new()
	t.theme_type_variation = &"ScreenTitle"
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := Label.new()
	n.theme_type_variation = &"BodyText"
	n.text = note
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var back := Button.new()
	back.theme_type_variation = &"ScreenButton"
	back.text = "BACK"
	back.icon = preload("res://ui/icons/arrow_left.svg")
	back.size_flags_horizontal = SIZE_SHRINK_CENTER
	back.pressed.connect(func(): UiRouter.back())
	v.add_child(back)
	back.grab_focus.call_deferred(UiRouter.using_pointer)
