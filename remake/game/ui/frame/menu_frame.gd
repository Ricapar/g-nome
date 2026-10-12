class_name MenuFrame
extends SubViewport
## The menu machinery as a lit 3D scene (remake/UI-DESIGN.md, "Target look").
## The model comes from remake/art/ui/frame/build_frame.py; materials are CC0 PBR sets fetched
## by tools/fetch_cc0.py (res://art_cc0, flat colours if missing). It renders at the window's
## physical resolution so it stays sharp; the menu draws it with a TextureRect.
## Anchors (empties named anchor_*) tell the 2D layer where its controls go.

const FRAME := preload("res://ui/frame/menu_frame.glb")
const CC0 := "res://art_cc0/%s/%s_2K-JPG_%s.jpg"
const FRAME_HEIGHT := 10.8 # model units; 1 unit = 100 design px
const FOV := 24.0

var camera := Camera3D.new()
var _anchors := {}
var _leds := {}
var _materials := {}
var _slot_lights := {}


func _init() -> void:
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	use_hdr_2d = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	_build_environment()
	var frame: Node3D = FRAME.instantiate()
	add_child(frame)
	_apply_materials(frame)
	for n in frame.find_children("*", "Node3D", true, false):
		if n.name.begins_with("anchor_"):
			_anchors[String(n.name).trim_prefix("anchor_")] = n
		elif n.name.begins_with("light_"):
			_add_lamp_light(n)
	camera.fov = FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0, 0, 1.0 + (FRAME_HEIGHT * 0.5) / tan(deg_to_rad(FOV * 0.5)))
	camera.far = 200.0
	add_child(camera)
	camera.current = true


## Rect of anchor `name` in this viewport's pixels.
func anchor_rect(name: String) -> Rect2:
	var a: Node3D = _anchors.get(name)
	if a == null:
		return Rect2()
	var p := a.global_position
	var half := Vector3(a.scale.x, a.scale.y, 0) * 0.5
	var tl := camera.unproject_position(p + Vector3(-half.x, half.y, 0))
	var br := camera.unproject_position(p + Vector3(half.x, -half.y, 0))
	return Rect2(tl, br - tl)


func has_anchor(name: String) -> bool:
	return _anchors.has(name)


## Light key LED i (the green lamp above a key on the bottom bar).
func set_led(i: int, on: bool) -> void:
	var m: StandardMaterial3D = _leds.get(i)
	if m:
		m.emission_energy_multiplier = 7.0 if on else 0.0
		m.albedo_color = Color(0.2, 1.0, 0.35) if on else Color(0.02, 0.05, 0.03)


## Green light spill from a selected slot (side "L"/"R", index 0..3).
func set_slot_glow(side: String, index: int, on: bool) -> void:
	var l: OmniLight3D = _slot_lights.get("%s%d" % [side, index])
	if l:
		l.visible = on


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.36)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.5
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# key light from the upper left front, a cool fill from the right, a rim from above
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.95, 0.9)
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 35, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.7, 0.85, 1.0)
	add_child(fill)
	var top := DirectionalLight3D.new()
	top.rotation_degrees = Vector3(-75, 0, 0)
	top.light_energy = 0.5
	add_child(top)
	# the screen glows faintly onto the bezel lip
	var screen := OmniLight3D.new()
	screen.position = Vector3(0, 1.3, 2.0)
	screen.light_color = Color(0.3, 0.9, 0.7)
	screen.light_energy = 0.5
	screen.omni_range = 7.0
	screen.light_specular = 0.0
	add_child(screen)


func _add_lamp_light(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.position = n.global_position if n.is_inside_tree() else n.position
	var red := String(n.name).begins_with("light_header") and absf(n.position.x) > 2.0
	l.light_color = Color(1.0, 0.25, 0.1) if red else Color(1.0, 0.55, 0.15)
	l.light_energy = 0.9
	l.omni_range = 1.2
	l.omni_attenuation = 1.6
	add_child(l)
	if String(n.name).begins_with("light_slot_"):
		# a green spill light above each slot lamp, shown while that slot is selected
		var g := OmniLight3D.new()
		g.position = l.position + Vector3(0, 0.46, 0.3)
		g.light_color = Color(0.3, 1.0, 0.45)
		g.light_energy = 2.0
		g.omni_range = 1.6
		g.visible = false
		add_child(g)
		_slot_lights[String(n.name).trim_prefix("light_slot_")] = g


func _apply_materials(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var name := src.resource_name if src else ""
			mi.set_surface_override_material(s, _material(name))


func _material(name: String) -> Material:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	match name:
		"red_paint":
			_pbr(m, "PaintedMetal004", 0.28, Color(0.36, 0.12, 0.11))
		"white_paint":
			_pbr(m, "PaintedMetal004", 0.28, Color(1, 1, 1), false)
			m.albedo_color = Color(0.82, 0.82, 0.80)
		"steel_dark":
			_pbr(m, "Metal038", 0.3, Color(0.55, 0.56, 0.58))
		"steel_brushed":
			_pbr(m, "Metal009", 0.35, Color(0.9, 0.9, 0.92))
		"black_coat":
			_pbr(m, "Metal027", 0.3, Color(0.6, 0.6, 0.6))
		"hazard":
			_pbr(m, "PaintedMetal016", 0.5, Color(1, 1, 1))
		"rubber":
			_pbr(m, "Rubber004", 0.6, Color(0.5, 0.5, 0.5))
		"glass_dark":
			m.albedo_color = Color(0.01, 0.03, 0.032)
			m.roughness = 0.35
			m.metallic_specular = 0.8
		"lamp_orange", "lamp_red":
			m.albedo_color = Color(1.0, 0.5, 0.1) if name == "lamp_orange" else Color(1.0, 0.15, 0.08)
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 1.6
		_:
			if name.begins_with("led_"):
				m.emission_enabled = true
				m.emission = Color(0.25, 1.0, 0.4)
				m.emission_energy_multiplier = 0.0
				m.albedo_color = Color(0.02, 0.05, 0.03)
				_leds[int(name.trim_prefix("led_"))] = m
	_materials[name] = m
	return m


## Fill a material from a CC0 set with world-triplanar mapping (no UVs needed).
func _pbr(m: StandardMaterial3D, set_id: String, scale: float, tint: Color, use_albedo := true) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.albedo_color = tint
	var tex := func(map: String) -> Texture2D:
		var p := CC0 % [set_id, set_id, map]
		return load(p) if ResourceLoader.exists(p) else null
	if use_albedo:
		m.albedo_texture = tex.call("Color")
	var n: Texture2D = tex.call("NormalGL")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	m.roughness_texture = tex.call("Roughness")
	m.roughness = 1.0
	var metal: Texture2D = tex.call("Metalness")
	if metal:
		m.metallic_texture = metal
		m.metallic = 1.0
	else:
		m.metallic = 0.0
