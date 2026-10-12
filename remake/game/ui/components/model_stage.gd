class_name ModelStage
extends Control
## A small 3D scene drawn inside a 2D control: one model on a slow turntable, optionally in a
## hangar bay. Renders at the window's physical resolution so it stays sharp at 4K.
## Uses the imported original model (res://_import, gitignored) as a placeholder.

const MODELS := "res://_import/models/"
const CC0 := "res://art_cc0/%s/%s_2K-JPG_%s.jpg"

@export var model_id := 2583 # Union Prowler HAWC
@export var spin_speed := 14.0 # degrees per second
@export var hangar := true

var _viewport := SubViewport.new()
var _pivot := Node3D.new()
var _cam := Camera3D.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport, false, INTERNAL_MODE_FRONT)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.5)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = hangar
	env.fog_light_color = Color(0.05, 0.06, 0.07)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.85, 1.0)
	rim.light_specular = 0.08 # it faces the camera; full specular glares off the floor
	_viewport.add_child(rim)
	_viewport.add_child(_pivot)
	_cam.fov = 32.0
	_viewport.add_child(_cam)
	var radius := _load_model()
	if hangar:
		_build_hangar(radius)
	resized.connect(_fit)
	visibility_changed.connect(func(): _viewport.render_target_update_mode = 		SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)
	_fit()


func _fit() -> void:
	var s := get_global_transform_with_canvas().get_scale()
	_viewport.size = Vector2i(maxi(int(size.x * s.x), 2), maxi(int(size.y * s.y), 2))


func _load_model() -> float:
	var path := ProjectSettings.globalize_path("%smodl_%05d.gltf" % [MODELS, model_id])
	if not FileAccess.file_exists(path):
		_cam.position = Vector3(0, 1, 6)
		return 2.0
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return 2.0
	var node: Node3D = doc.generate_scene(state)
	_pivot.add_child(node)
	var box := _aabb(node)
	# stand the model on the floor (y = 0), centred on the turntable axis
	node.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	var radius := box.size.length() * 0.5
	var dist := radius / sin(deg_to_rad(_cam.fov * 0.5))
	_cam.position = Vector3(0, box.size.y * 0.62, dist)
	_cam.look_at(Vector3(0, box.size.y * 0.45, 0))
	_pivot.rotation_degrees.y = 200.0
	return radius


func _build_hangar(r: float) -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE * (0.6 / r)
	floor_mat.albedo_color = Color(0.35, 0.36, 0.38)
	floor_mat.metallic = 0.1
	floor_mat.roughness = 0.85
	for map in ["Color", "NormalGL", "Roughness"]:
		var p := CC0 % ["Metal038", "Metal038", map]
		if not ResourceLoader.exists(p):
			continue
		match map:
			"Color": floor_mat.albedo_texture = load(p)
			"NormalGL":
				floor_mat.normal_enabled = true
				floor_mat.normal_texture = load(p)
			"Roughness": floor_mat.roughness_texture = load(p)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 12, r * 12)
	floor_mi.mesh = pm
	floor_mi.material_override = floor_mat
	_viewport.add_child(floor_mi)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.065, 0.07)
	dark.roughness = 0.7
	var lamp := StandardMaterial3D.new()
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.97, 0.9)
	lamp.emission_energy_multiplier = 6.0
	# back wall with pillars, ceiling light strips, a hazard line on the floor
	_box(Vector3(0, r * 1.6, -r * 2.2), Vector3(r * 10, r * 3.2, 0.2), dark)
	for k in range(-3, 4):
		_box(Vector3(k * r * 1.4, r * 1.6, -r * 2.0), Vector3(r * 0.18, r * 3.2, r * 0.3), dark)
		_box(Vector3(k * r * 1.4, r * 2.9, -r * 0.6), Vector3(r * 0.35, r * 0.03, r * 0.06), lamp)
	var hz := StandardMaterial3D.new()
	hz.albedo_color = Color(0.75, 0.6, 0.1)
	hz.roughness = 0.6
	_box(Vector3(0, 0.005, r * 1.1), Vector3(r * 6, 0.01, r * 0.06), hz)
	for x in [-1.2, 1.2]:
		var l := OmniLight3D.new()
		l.position = Vector3(x * r, r * 2.6, r * 0.4)
		l.light_energy = 1.5
		l.omni_range = r * 4
		l.light_specular = 0.15
		_viewport.add_child(l)


func _box(pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	_viewport.add_child(mi)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(dt: float) -> void:
	_pivot.rotation_degrees.y += spin_speed * dt
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
