class_name MenuFrame
extends SubViewport
## The menu machinery as a lit 3D scene (remake/UI-DESIGN.md, "Target look").
## The model comes from remake/art/ui/frame/build_frame.py; materials use frame_material.gdshader
## with CC0 PBR sets and an HDRI for reflections, fetched by tools/fetch_cc0.py (res://art_cc0;
## plain colours if missing). It renders at the window's physical resolution so it stays sharp;
## the menu draws it with a TextureRect. Anchors (empties named anchor_*) tell the 2D layer
## where its controls go.

const FRAME := preload("res://ui/frame/menu_frame.glb")
const SHADER := preload("res://ui/frame/frame_material.gdshader")
const CC0 := "res://art_cc0/%s/%s_2K-JPG_%s.jpg"
const HDRI := "res://art_cc0/hdri/studio_small_09_1k.hdr"
const EMBLEM := preload("res://ui/frame/emblem.svg")
const SAIRA := preload("res://ui/fonts/Saira-VF.ttf")
const STENCILS := {"text_L": "UIA-07", "text_R": "BAY 3"}
const FRAME_HEIGHT := 11.3 # model units (1 = 100 design px); a margin so the pillars nearer the camera fit
const FOV := 24.0
const KEY_TRAVEL := Vector3(0, -0.015, -0.09) # into the bar, a little down the slope

static var _KEY_PART := RegEx.create_from_string("^(?:key_(?:body|plate|led)|anchor_key)_([0-9])$")

var camera := Camera3D.new()
var _anchors := {}
var _leds := {}
var _materials := {}
var _slot_lights := {}
var _key_parts := {} # key index -> [[node, rest position], ...]: travels when pressed


func _init() -> void:
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
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
		elif n.name.begins_with("decal_"):
			_add_decal(n)
		elif STENCILS.has(String(n.name)):
			_add_stencil(n, STENCILS[String(n.name)])
		var m := _KEY_PART.search(String(n.name))
		if m:
			var i := int(m.get_string(1))
			if not _key_parts.has(i):
				_key_parts[i] = []
			_key_parts[i].append([n, n.position])
	camera.fov = FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0, 0, 1.2 + (FRAME_HEIGHT * 0.5) / tan(deg_to_rad(FOV * 0.5)))
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
		m.emission_energy_multiplier = 2.5 if on else 0.0
		m.albedo_color = Color(0.2, 1.0, 0.35) if on else Color(0.02, 0.05, 0.03)


## Push key i in and let it spring back (its label anchor travels with it).
func press_key(i: int) -> void:
	for part: Array in _key_parts.get(i, []):
		var n: Node3D = part[0]
		var tw := n.create_tween()
		tw.tween_property(n, "position", part[1] + KEY_TRAVEL, 0.05).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "position", part[1], 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Green light spill from a selected slot (side "L"/"R", index 0..3).
func set_slot_glow(side: String, index: int, on: bool) -> void:
	var l: OmniLight3D = _slot_lights.get("%s%d" % [side, index])
	if l:
		l.visible = on


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.009, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.32, 0.35)
	env.ambient_light_energy = 0.35
	if ResourceLoader.exists(HDRI):
		# the HDRI is only reflected by the metal; the background stays dark
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = load(HDRI)
		sky_mat.energy_multiplier = 0.55
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.sky_rotation = Vector3(deg_to_rad(-10), deg_to_rad(200), 0)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 3.0
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# key light from the upper left front, a cool fill from the right, a top light for rims
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -28, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.94, 0.86)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 60.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 40, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.65, 0.8, 1.0)
	add_child(fill)
	var top := DirectionalLight3D.new()
	top.rotation_degrees = Vector3(-80, 10, 0)
	top.light_energy = 0.7
	add_child(top)
	# the screen glows faintly onto the bezel slope
	var screen := OmniLight3D.new()
	screen.position = Vector3(0, 1.3, 1.0)
	screen.light_color = Color(0.3, 0.9, 0.75)
	screen.light_energy = 0.8
	screen.light_specular = 0.2
	screen.omni_range = 8.0
	add_child(screen)


## Painted insignia projected onto the armour (the empty's scale x/y = width/height).
func _add_decal(n: Node3D) -> void:
	var d := Decal.new()
	d.texture_albedo = EMBLEM
	d.modulate = Color(0.86, 0.85, 0.82)
	d.albedo_mix = 0.92
	d.size = Vector3(n.scale.x, 0.8, n.scale.y)
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	add_child(d)
	# decals project along their local -Y; turn that toward -Z (into the plate)
	d.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), n.global_position)


## Stencilled lettering on the lower armour, lit like paint.
func _add_stencil(n: Node3D, text: String) -> void:
	var font := FontVariation.new()
	font.base_font = SAIRA
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wdth"): 110,
		TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 72
	l.pixel_size = 0.0034
	l.outline_size = 0
	l.modulate = Color(0.85, 0.84, 0.8, 0.7)
	l.shaded = true
	l.double_sided = false
	add_child(l)
	l.global_position = n.global_position + Vector3(0, 0, 0.06)
	l.rotation_degrees.y = 4.5 if n.global_position.x < 0 else -4.5


func _add_lamp_light(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.position = n.global_position
	var red := String(n.name).begins_with("light_header") and absf(n.global_position.x) > 2.0
	l.light_color = Color(1.0, 0.25, 0.1) if red else Color(1.0, 0.55, 0.18)
	l.light_energy = 0.8
	l.light_specular = 0.6
	l.omni_range = 1.3
	l.omni_attenuation = 1.8
	add_child(l)
	if String(n.name).begins_with("light_slot_"):
		# green spill above each slot lamp, shown while that slot is selected
		var g := OmniLight3D.new()
		g.position = l.position + Vector3(0, 0.45, 0.25)
		g.light_color = Color(0.3, 1.0, 0.45)
		g.light_energy = 0.9
		g.omni_range = 1.7
		g.visible = false
		add_child(g)
		_slot_lights[String(n.name).trim_prefix("light_slot_")] = g


func _apply_materials(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			mi.set_surface_override_material(s, _material(src.resource_name if src else ""))


func _material(name: String) -> Material:
	if _materials.has(name):
		return _materials[name]
	var m: Material
	match name:
		"red_paint":
			m = _layered("PaintedMetal004", 0.32, Color(0.3, 0.075, 0.065), "Metal009", Color(0.75, 0.75, 0.78))
		"white_paint":
			m = _layered("PaintedMetal004", 0.32, Color(0.45, 0.45, 0.44), "Metal009", Color(0.75, 0.75, 0.78), false)
			m.set_shader_parameter("base_metallic", 0.0)
		"steel_dark":
			m = _layered("Metal038", 0.45, Color(0.3, 0.31, 0.33), "Metal009", Color(0.9, 0.9, 0.92))
		"steel_brushed":
			m = _layered("Metal009", 0.45, Color(0.5, 0.51, 0.53), "Metal009", Color(0.95, 0.95, 0.95))
		"steel_face": # key faces: bright brushed steel, labels engraved on top
			m = _layered("Metal009", 0.6, Color(0.66, 0.67, 0.69), "Metal009", Color(0.95, 0.95, 0.95))
			m.set_shader_parameter("grime_amount", 0.5)
		"black_coat":
			m = _layered("Metal027", 0.5, Color(0.4, 0.4, 0.42), "Metal038", Color(0.7, 0.7, 0.7))
		"hazard":
			m = _layered("PaintedMetal016", 0.9, Color(1, 1, 1), "Metal038", Color(0.9, 0.9, 0.9))
		"rubber_red":
			m = _layered("Rubber004", 0.9, Color(0.42, 0.06, 0.05), "Rubber004", Color(0.4, 0.05, 0.04))
			m.set_shader_parameter("wear_amount", 0.0)
		"rubber":
			m = _layered("Rubber004", 0.9, Color(0.4, 0.4, 0.42), "Rubber004", Color(0.4, 0.4, 0.42))
			m.set_shader_parameter("wear_amount", 0.0)
		"glass_dark":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.01, 0.03, 0.033)
			g.roughness = 0.25
			g.metallic_specular = 0.7
			m = g
		"lamp_orange", "lamp_red", "lamp_yellow":
			var e := StandardMaterial3D.new()
			e.albedo_color = {"lamp_orange": Color(1.0, 0.5, 0.12), "lamp_red": Color(1.0, 0.15, 0.08),
				"lamp_yellow": Color(1.0, 0.8, 0.2)}[name]
			e.emission_enabled = true
			e.emission = e.albedo_color
			e.emission_energy_multiplier = 2.2
			m = e
		_:
			var e := StandardMaterial3D.new()
			if name.begins_with("led_"):
				e.emission_enabled = true
				e.emission = Color(0.25, 1.0, 0.4)
				e.emission_energy_multiplier = 0.0
				e.albedo_color = Color(0.02, 0.05, 0.03)
				_leds[int(name.trim_prefix("led_"))] = e
			m = e
	_materials[name] = m
	return m


func _tex(set_id: String, map: String) -> Texture2D:
	var p := CC0 % [set_id, set_id, map]
	return load(p) if ResourceLoader.exists(p) else null


## Frame material: base layer `base` (tinted) wearing through to `wear` on convex edges.
func _layered(base: String, scale: float, tint: Color, wear: String, wear_tint: Color, use_albedo := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("base_tint", tint)
	m.set_shader_parameter("use_base_albedo", use_albedo)
	m.set_shader_parameter("base_albedo", _tex(base, "Color"))
	m.set_shader_parameter("base_normal", _tex(base, "NormalGL"))
	m.set_shader_parameter("base_rough", _tex(base, "Roughness"))
	var metal := _tex(base, "Metalness")
	m.set_shader_parameter("base_metal", metal)
	m.set_shader_parameter("base_metallic", 1.0 if metal else 0.0)
	m.set_shader_parameter("wear_albedo", _tex(wear, "Color"))
	m.set_shader_parameter("wear_rough", _tex(wear, "Roughness"))
	m.set_shader_parameter("wear_tint", wear_tint)
	return m
