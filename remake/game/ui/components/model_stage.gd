class_name ModelStage
extends SubViewportContainer
## A small 3D scene inside a 2D screen: one model on a slow turntable, lit for the UI.
## Uses the imported original model (res://_import, gitignored) as a placeholder; shows an
## empty stage if it is missing.

const MODELS := "res://_import/models/"

@export var model_id := 2583 # Union Prowler HAWC
@export var spin_speed := 18.0 # degrees per second

var _viewport := SubViewport.new()
var _pivot := Node3D.new()
var _cam := Camera3D.new()


func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.transparent_bg = true
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.42)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.95, 0.88)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.55, 1.0, 0.65) # faint phosphor rim light
	_viewport.add_child(rim)
	_viewport.add_child(_pivot)
	_cam.fov = 30.0
	_viewport.add_child(_cam)
	_load_model()


func _load_model() -> void:
	var path := ProjectSettings.globalize_path("%smodl_%05d.gltf" % [MODELS, model_id])
	if not FileAccess.file_exists(path):
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return
	var node: Node3D = doc.generate_scene(state)
	_pivot.add_child(node)
	# frame the model: centre it on the pivot and back the camera off to fit
	var box := _aabb(node)
	node.position = -box.get_center()
	var radius := box.size.length() * 0.5
	var dist := radius / sin(deg_to_rad(_cam.fov * 0.5)) * 1.05
	_cam.position = Vector3(0, radius * 0.2, dist)
	_cam.look_at(Vector3.ZERO)
	_pivot.rotation_degrees.y = 210.0


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(dt: float) -> void:
	_pivot.rotation_degrees.y += spin_speed * dt
