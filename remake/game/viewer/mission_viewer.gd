extends Node3D
## Mission preview: places the original models from a campaign mission's layout table.
##
## Data comes from tools/export_gamedata.py + tools/export_models.py (res://_import).
## Coordinates: game units / 100 = model units (600-unit ground tiles are 6 model units).
## Headings are hundredths of a degree.
## Orientation (R1, verified against the original): raw game x/z map to Godot X/Z unmirrored,
## a heading h is rotation_degrees.y = h/100, and objects face local +Z, so the camera looks
## along +Z rotated by the heading (Godot yaw = h/100 + 180).
## Controls: PgUp/PgDn = mission, WASD/QE + right-drag = fly, Shift = fast, Home = player start.
## Screenshot mode: godot --path remake/game res://viewer/mission_viewer.tscn -- \
##                  --shots <outdir> <mission-code>[,...] [--top]
## Orientation experiments (R1): --forward <+1|-1> (model forward along local +Z or -Z),
## --heading-sign <+1|-1>, --mirror-z, --fov <deg>, --eye <model units>, --size <w>x<h>,
## --turn <deg> (look right of the start heading), --top-at <x>,<z> and --top-height <h> (with --top).

const DATA := "res://_import/data/"
const MODELS := "res://_import/models/"
const TEX := "res://_import/textures/"
const SCALE := 0.01
const GROUND_PREFIX := ["dgrd1000", "igrd1000", "ggrd1000", "mgrd2000"]

var missions: Array = []
var units := {}
var layouts := {}
var worlds: Array = []
var _model_cache := {}
var _index := 0
var _root: Node3D
var _cam := Camera3D.new()
var _env := Environment.new()
var _info := Label.new()
var _yaw := 0.0
var _pitch := -15.0
var _start := Vector3.ZERO
var _start_heading := 0.0
var _rock_tex: Texture2D
# Orientation convention (see docs/analysis.md "Orientation and camera"): overridable for experiments.
var _forward := 1.0
var _heading_sign := 1.0
var _mirror_z := false
var _eye := 0.44  # cockpit camera: AttachCamera(player, 0, 0, 44, 0)


func _ready() -> void:
	missions = _json("missions.json")
	for u in _json("units.json"):
		units[int(u["row"])] = u
	layouts = _json("layouts.json")
	worlds = _json("worlds.json")["rows"]
	var we := WorldEnvironment.new()
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.6, 0.6)
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	we.environment = _env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_cam.far = 400.0
	_cam.fov = 50.0  # vertical; fitted to the original's 640x480 start view (R1)
	add_child(_cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	_info.position = Vector2(8, 8)
	layer.add_child(_info)
	var args := OS.get_cmdline_user_args()
	_forward = float(_arg(args, "--forward", str(_forward)))
	_heading_sign = float(_arg(args, "--heading-sign", str(_heading_sign)))
	_mirror_z = args.has("--mirror-z")
	_eye = float(_arg(args, "--eye", str(_eye)))
	_cam.fov = float(_arg(args, "--fov", str(_cam.fov)))
	var size := _arg(args, "--size", "")
	if size != "":
		var wh := size.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		get_window().content_scale_size = get_window().size
	var i := args.find("--shots")
	if i >= 0 and args.size() > i + 2:
		_run_shots(args[i + 1], args[i + 2].split(","), args.has("--top"))
	else:
		_load_mission(0)


func _arg(args: PackedStringArray, name: String, default: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default


func _json(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA + name))


func _model(id: int) -> Node3D:
	if not _model_cache.has(id):
		var path := ProjectSettings.globalize_path("%smodl_%05d.gltf" % [MODELS, id])
		if not FileAccess.file_exists(path):
			path = ProjectSettings.globalize_path("%smprt_%05d.gltf" % [MODELS, id])
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			_model_cache[id] = null
		else:
			_model_cache[id] = doc.generate_scene(state)
	var n: Node3D = _model_cache[id]
	return n.duplicate() if n else null


func _load_mission(i: int) -> void:
	_index = wrapi(i, 0, missions.size())
	if _root:
		_root.queue_free()
	_root = Node3D.new()
	if _mirror_z:
		_root.scale.z = -1
	add_child(_root)
	var m: Dictionary = missions[_index]
	var w: Dictionary = worlds[int(m.get("world_row", 0))]
	_setup_world(w)
	var ri := Image.load_from_file(ProjectSettings.globalize_path(TEX + "rock_w%d.png" % (int(w["world"]) % 4)))
	_rock_tex = ImageTexture.create_from_image(ri) if ri else null
	var placed := 0
	var lay: Array = layouts.get(str(int(m["layout_array"])), [])
	var first := true
	for e in lay:
		var u: Dictionary = units.get(int(e["unit_row"]), {})
		var props: Array = u.get("template_props", [])
		if props.size() < 2:
			continue
		# level_flag 1 raises the object to height G1846 (never set by a script; unknown), so 0 here
		var pos := Vector3(e["x"], 0, e["z"]) * SCALE
		if int(u["category"]) == 252:
			pos += _corner_offset(int(e["heading"])) * SCALE
		var heading := float(e["heading"]) / 100.0
		if first:
			_start = pos
			_start_heading = heading
			first = false
		var node := _model(int(props[1]))
		if node == null:
			continue
		if int(u["category"]) == 250 and _rock_tex:
			_retexture(node, _rock_tex)
		node.position = pos
		node.rotation_degrees.y = heading * _heading_sign
		_root.add_child(node)
		placed += 1
	_info.text = "%s  %s   world %s   objects %d   (PgUp/PgDn, WASD, right-drag)\n%s" % [
		m["code"], m["name"], m.get("world_row"), placed, "\n".join(m["objectives"])]
	_goto_start()


## script_2524: category-252 pieces (1200x1200, origin at a corner) are listed by their centre;
## the spawner moves the origin to the corner that the heading puts at local (0, 0).
func _corner_offset(heading: int) -> Vector3:
	match heading:
		9000: return Vector3(-600, 0, 600)
		18000, -18000: return Vector3(600, 0, 600)
		-9000, 27000: return Vector3(600, 0, -600)
	return Vector3(-600, 0, -600)


func _retexture(n: Node, tex: Texture2D) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 1.0
		mi.material_override = mat


func _setup_world(w: Dictionary) -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEX + "backdrop_%d.png" % int(w["backdrop"])))
	if img:
		# the backdrop is a 360-degree strip of the horizon; pad it into an equirectangular map
		var pano := Image.create(img.get_width(), img.get_width() / 2, false, Image.FORMAT_RGB8)
		var top := img.get_pixel(0, 0)
		var bottom := img.get_pixel(0, img.get_height() - 1)
		pano.fill_rect(Rect2i(0, 0, pano.get_width(), pano.get_height() / 2), top)
		pano.fill_rect(Rect2i(0, pano.get_height() / 2, pano.get_width(), pano.get_height() / 2), bottom)
		pano.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, pano.get_height() / 2 - img.get_height()))
		sky_mat.panorama = ImageTexture.create_from_image(pano)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.sky = sky
	var fog := Color8(int(w["fog_r"]), int(w["fog_g"]), int(w["fog_b"]))
	_env.fog_light_color = fog
	_env.fog_density = 0.0
	_env.fog_depth_begin = 10.0
	_env.fog_depth_end = max(float(w["fog_depth"]) * SCALE * 1.5, 30.0)
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_sky_affect = 0.0
	# flat ground, tiled with the world's base ground texture (6 model units per tile)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	var wi := int(w["world"]) % 4
	var gname: String = GROUND_PREFIX[wi] + ("__w%d" % wi if wi > 0 else "")
	var gi := Image.load_from_file(ProjectSettings.globalize_path(TEX + gname + ".png"))
	if gi:
		mat.albedo_texture = ImageTexture.create_from_image(gi)
		mat.uv1_scale = Vector3(100, 100, 1)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 1.0
	ground.material_override = mat
	_root.add_child(ground)


func _goto_start() -> void:
	# The start pose is in game space; map it through the world root (which may mirror).
	_cam.position = _root.transform * (_start + Vector3(0, _eye, 0))
	var fwd := _root.basis * (Basis(Vector3.UP, deg_to_rad(_start_heading * _heading_sign)) * Vector3(0, 0, _forward))
	_yaw = rad_to_deg(atan2(-fwd.x, -fwd.z))
	_pitch = 0.0
	_apply_cam()


func _apply_cam() -> void:
	_cam.rotation_degrees = Vector3(_pitch, _yaw, 0)


func _process(dt: float) -> void:
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v.z -= 1
	if Input.is_key_pressed(KEY_S): v.z += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_E): v.y += 1
	if Input.is_key_pressed(KEY_Q): v.y -= 1
	var speed := 40.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	_cam.position += _cam.global_transform.basis * v * speed * dt


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= ev.relative.x * 0.3
		_pitch = clampf(_pitch - ev.relative.y * 0.3, -89, 89)
		_apply_cam()
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_PAGEDOWN: _load_mission(_index + 1)
			KEY_PAGEUP: _load_mission(_index - 1)
			KEY_HOME: _goto_start()


func _run_shots(outdir: String, codes: PackedStringArray, top: bool) -> void:
	DirAccess.make_dir_recursive_absolute(outdir)
	for code in codes:
		for k in missions.size():
			if missions[k]["code"] == code:
				_load_mission(k)
		if top:
			_env.fog_enabled = false
			var c := _arg(OS.get_cmdline_user_args(), "--top-at", "")
			var at := _start
			if c != "":
				var xz := c.split(",")
				at = _root.transform * (Vector3(float(xz[0]), 0, float(xz[1])) * SCALE)
			_cam.position = at + Vector3(0, float(_arg(OS.get_cmdline_user_args(), "--top-height", "120")), 0)
			_cam.rotation_degrees = Vector3(-90, 0, 0)
		else:
			# --turn <deg>: look right (positive) or left (negative) of the start heading
			_yaw -= float(_arg(OS.get_cmdline_user_args(), "--turn", "0"))
			_apply_cam()
		for f in 4:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s%s.png" % [outdir, code, "_top" if top else ""])
	get_tree().quit()
