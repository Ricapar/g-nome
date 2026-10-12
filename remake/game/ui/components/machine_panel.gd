@tool
class_name MachinePanel
extends Control
## A piece of the menu machinery drawn with ui/shaders/machine.gdshader: vector shape,
## procedural material. Purely decorative; it ignores the mouse.

enum Look { RED, STEEL, IRON, BEZEL, BLUE }
enum Finish { PAINT, BRUSHED, CAST }
enum Cylinder { FLAT, DRUM, PIPE }

const SHADER := preload("res://ui/shaders/machine.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")

@export var look := Look.RED:
	set(v): look = v; _update()
@export var finish := Finish.PAINT:
	set(v): finish = v; _update()
@export var cylinder := Cylinder.FLAT:
	set(v): cylinder = v; _update()
@export var chamfer := 10.0:
	set(v): chamfer = v; _update()
@export var bevel := 5.0:
	set(v): bevel = v; _update()
@export_range(0.0, 1.0) var wear := 0.3:
	set(v): wear = v; _update()
@export var rivet_inset := 0.0:
	set(v): rivet_inset = v; _update()
## Hazard stripe band and recess, as fractions of the panel (position and size, 0..1).
@export var hazard := Rect2():
	set(v): hazard = v; _update()
@export var recess := Rect2():
	set(v): recess = v; _update()
@export var vents := 0:
	set(v): vents = v; _update()

var _mat := ShaderMaterial.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise", NOISE)
	material = _mat
	resized.connect(_update)


func _ready() -> void:
	_update()


func _update() -> void:
	if not is_inside_tree():
		return
	var cols: Array = [UIPalette.RED, UIPalette.STEEL, UIPalette.IRON, UIPalette.BEZEL, UIPalette.BLUE][look]
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("hi_color", cols[0])
	_mat.set_shader_parameter("base_color", cols[1])
	_mat.set_shader_parameter("lo_color", cols[2])
	_mat.set_shader_parameter("finish", finish)
	_mat.set_shader_parameter("cylinder", cylinder)
	_mat.set_shader_parameter("chamfer", minf(chamfer, minf(size.x, size.y) * 0.5))
	_mat.set_shader_parameter("bevel", bevel)
	_mat.set_shader_parameter("wear", wear)
	_mat.set_shader_parameter("rivet_inset", rivet_inset)
	_mat.set_shader_parameter("hazard", _frac_rect(hazard))
	_mat.set_shader_parameter("recess", _frac_rect(recess))
	_mat.set_shader_parameter("vents", vents)
	queue_redraw()


func _frac_rect(r: Rect2) -> Vector4:
	if r.size == Vector2.ZERO:
		return Vector4.ZERO
	return Vector4(r.position.x * size.x, r.position.y * size.y, r.end.x * size.x, r.end.y * size.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
