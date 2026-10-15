class_name TransitionOverlay
extends Control
## Screen change and loading cover: `await cover()`, swap the screen, `await reveal()`.
## Two shutters close to a bright phosphor line and open again (shaders/transition.gdshader).
## While covered, `show_loading("LOADING")` adds a readout with a blinking cursor.
## Blocks mouse and keyboard/gamepad input while any part of it is visible.

signal finished

const SHADER := preload("res://ui/shaders/transition.gdshader")

var amount := 0.0:
	set(v):
		amount = v
		_mat.set_shader_parameter("amount", v)
		visible = v > 0.0

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _label := Label.new()
var _t := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_rect)
	_label.theme_type_variation = &"Readout"
	_label.add_theme_font_size_override(&"font_size", 28)
	_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	_label.grow_horizontal = GROW_DIRECTION_BOTH
	_label.grow_vertical = GROW_DIRECTION_BOTH
	_label.position.y += 48
	_label.visible = false
	add_child(_label)
	amount = 0.0
	set_process(false)


func cover(duration := 0.16) -> void:
	await _to(1.0, duration)


func reveal(duration := 0.22) -> void:
	_label.visible = false
	set_process(false)
	await _to(0.0, duration)


func show_loading(text := "LOADING") -> void:
	_label.text = text + " _"
	_label.visible = true
	_t = 0.0
	set_process(true)


func _to(target: float, duration: float) -> void:
	if is_equal_approx(amount, target):
		return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if target > amount else Tween.EASE_OUT)
	tw.tween_property(self, "amount", target, duration)
	await tw.finished
	finished.emit()


func _process(dt: float) -> void:
	_t += dt
	var base := _label.text.trim_suffix(" _").trim_suffix("  ")
	_label.text = base + (" _" if fmod(_t, 0.8) < 0.45 else "  ")


func _input(event: InputEvent) -> void:
	if visible and not (event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()
