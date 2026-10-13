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
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssr_enabled = hangar
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = hangar
	env.fog_light_color = Color(0.05, 0.06, 0.07)
	env.fog_density = 0.05
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
	rim.light_specular = 0.0 # it faces the camera; full specular glares off the floor
	_viewport.add_child(rim)
	_viewport.add_child(_pivot)
	_cam.fov = 40.0
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
	RwModel.apply_frames(node)
	var box := _aabb(node)
	# stand the model on the floor (y = 0), centred on the turntable axis
	node.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	var radius := box.size.length() * 0.5
	var dist := radius / sin(deg_to_rad(_cam.fov * 0.5))
	# close and low so the vehicle fills the pane (the target fills ~85% of the height)
	_cam.position = Vector3(0, box.size.y * 0.35, dist * 0.8)
	_cam.look_at(Vector3(0, box.size.y * 0.5, 0))
	_pivot.rotation_degrees.y = 200.0
	return radius


func _build_hangar(r: float) -> void:
	# A deep service bay: wet steel floor, a ceiling grid of lamps receding into the haze,
	# girder walls with amber work lights, a lit blast door at the back, hazard striping.
	var floor_mat := _cc0_mat("Metal038", 0.5 / r)
	floor_mat.albedo_color = Color(0.42, 0.43, 0.45)
	floor_mat.metallic = 0.35
	floor_mat.roughness = 0.42 # wet sheen: SSR picks up the lamps
	floor_mat.normal_scale = 0.35
	_box(Vector3(0, -0.05, -r * 2.0), Vector3(r * 9, 0.1, r * 12), floor_mat)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.075, 0.08)
	dark.metallic = 0.6
	dark.roughness = 0.55
	var steel := _cc0_mat("Metal009", 0.8 / r)
	steel.albedo_color = Color(0.5, 0.5, 0.52)
	var lamp := _emissive(Color(1.0, 0.97, 0.9), 2.0) # strips, not floodlights: they must not blow out
	var amber := _emissive(Color(1.0, 0.55, 0.15), 2.2)
	var hz := StandardMaterial3D.new()
	hz.albedo_color = Color(0.8, 0.62, 0.08)
	hz.roughness = 0.5
	var w := r * 2.6 # half width of the bay
	var h := r * 2.1 # ceiling height
	var back := -r * 7.0
	# walls, ceiling
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * w, h * 0.5, back * 0.5), Vector3(0.2, h, -back + r * 4), dark)
		for k in 6: # girder columns with an amber light each
			var z := r * 1.5 - k * r * 1.6
			_box(Vector3(sx * (w - r * 0.15), h * 0.5, z), Vector3(r * 0.25, h, r * 0.25), steel)
			_box(Vector3(sx * (w - r * 0.3), r * 1.1, z + r * 0.3), Vector3(r * 0.04, r * 0.14, r * 0.04), amber)
		for y in [r * 0.9, r * 2.2]: # horizontal rails
			_box(Vector3(sx * (w - r * 0.25), y, back * 0.5), Vector3(r * 0.08, r * 0.08, -back + r * 4), steel)
		# hazard stripe along the bay edge, a couple of crates
		_box(Vector3(sx * r * 1.7, 0.004, back * 0.4), Vector3(r * 0.1, 0.008, -back), hz)
		_box(Vector3(sx * r * 2.1, r * 0.22, r * 0.6), Vector3(r * 0.6, r * 0.44, r * 0.5), hz)
		_box(Vector3(sx * r * 2.2, r * 0.15, -r * 0.4), Vector3(r * 0.4, r * 0.3, r * 0.4), dark)
	_box(Vector3(0, h, back * 0.5), Vector3(w * 2, 0.2, -back + r * 4), dark)
	for i in 4: # ceiling lamp rows receding into the haze
		var z := r * 1.0 - i * r * 1.8
		for j in [-1.5, -0.5, 0.5, 1.5]:
			_box(Vector3(j * r * 1.0, h - 0.12, z), Vector3(r * 0.22, 0.03, r * 0.05), lamp)
		_box(Vector3(0, h - 0.2, z), Vector3(w * 2, r * 0.1, r * 0.1), dark)
	# back wall: blast door with a lit sill
	_box(Vector3(0, h * 0.5, back), Vector3(w * 2, h, 0.2), dark)
	_box(Vector3(0, r * 1.1, back + 0.15), Vector3(r * 3.0, r * 2.2, 0.1), steel)
	_box(Vector3(0, r * 0.05, back + 0.25), Vector3(r * 3.0, r * 0.06, 0.06), amber)
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * r * 1.6, r * 1.1, back + 0.2), Vector3(r * 0.15, r * 2.3, 0.15), hz)
	var spot := SpotLight3D.new() # key light straight down on the vehicle
	spot.position = Vector3(0, h - 0.3, r * 0.3)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_range = h * 1.5
	spot.spot_angle = 35.0
	spot.light_energy = 3.0
	spot.shadow_enabled = true
	_viewport.add_child(spot)
	var door := OmniLight3D.new()
	door.position = Vector3(0, r * 0.4, back + r * 0.8)
	door.light_color = Color(1.0, 0.6, 0.25)
	door.light_energy = 1.0
	door.omni_range = r * 4
	door.light_specular = 0.1
	_viewport.add_child(door)
	for x in [-1.2, 1.2]:
		var l := OmniLight3D.new()
		l.position = Vector3(x * r, h * 0.8, r * 0.4)
		l.light_energy = 0.7
		l.omni_range = r * 4
		l.light_specular = 0.15
		_viewport.add_child(l)


func _cc0_mat(set_name: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.6
	for map in ["Color", "NormalGL", "Roughness"]:
		var p := CC0 % [set_name, set_name, map]
		if not ResourceLoader.exists(p):
			continue
		match map:
			"Color": m.albedo_texture = load(p)
			"NormalGL":
				m.normal_enabled = true
				m.normal_texture = load(p)
			"Roughness": m.roughness_texture = load(p)
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


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
