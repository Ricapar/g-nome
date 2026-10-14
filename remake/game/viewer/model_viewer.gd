extends Node3D
## Model viewer for the original G-Nome models exported by tools/export_models.py.
##
## Loads glTF files from res://_import/models at runtime, so they need no Godot import step.
## Controls: Up/Down or the list = select model, left-drag = orbit, wheel = zoom,
## C = toggle back-face culling, X = mirror Z (handedness check).
##
## Screenshot mode, for automated review:
##   godot --path remake/game -- --shots <outdir> <model>[,<model>...]
## renders each model and saves <outdir>/<model>.png, then quits.

const MODEL_DIR := "res://_import/models"

var _files: PackedStringArray = []
var _index := 0
var _model: Node3D
var _pivot := Node3D.new()
var _cam := Camera3D.new()
var _yaw := -35.0
var _pitch := -20.0
var _dist := 4.0
var _cull := true
var _mirror := false
var _list := ItemList.new()
var _info := Label.new()


func _ready() -> void:
	_setup_scene()
	_setup_ui()
	var dir := DirAccess.open(MODEL_DIR)
	if dir == null:
		_info.text = "No models in %s. Run tools/export_models.py first." % MODEL_DIR
		return
	for f in dir.get_files():
		if f.ends_with(".gltf"):
			_files.append(f.get_basename())
	_files.sort()
	for f in _files:
		_list.add_item(f)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and args.size() > i + 2:
		_run_shots(args[i + 1], args[i + 2].split(","))
	elif _files.size() > 0:
		_select(0)


func _setup_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	add_child(_pivot)
	_pivot.add_child(_cam)
	_cam.near = 0.01


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_list.position = Vector2(8, 8)
	_list.size = Vector2(220, 700)
	_list.item_selected.connect(_select)
	layer.add_child(_list)
	_info.position = Vector2(240, 8)
	layer.add_child(_info)


func _select(i: int) -> void:
	_index = clampi(i, 0, _files.size() - 1)
	_list.select(_index)
	_list.ensure_current_is_visible()
	_load(_files[_index])


func _load(name: String) -> void:
	if _model:
		_model.queue_free()
		_model = null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var path := ProjectSettings.globalize_path("%s/%s.gltf" % [MODEL_DIR, name])
	if doc.append_from_file(path, state) != OK:
		_info.text = "failed to load " + name
		return
	_model = doc.generate_scene(state)
	RwModel.apply_frames(_model) # frame 0 of stacked textures (normal paint), not the whole stack
	add_child(_model)
	_apply_view_options()
	var aabb := _aabb(_model)
	_pivot.position = aabb.get_center()
	_dist = max(aabb.size.length() * 1.1, 0.5)
	_update_cam()
	var tags: PackedStringArray = []
	_collect_tags(_model, tags)
	_info.text = "%s   size %.2f x %.2f x %.2f   parts: %s\ncull=%s mirrorZ=%s" % [
		name, aabb.size.x, aabb.size.y, aabb.size.z, ", ".join(tags), _cull, _mirror]


func _collect_tags(n: Node, out: PackedStringArray) -> void:
	if n.name.begins_with("clump_"):
		out.append(n.name.substr(6))
	for c in n.get_children():
		_collect_tags(c, out)


func _apply_view_options() -> void:
	if not _model:
		return
	_model.scale = Vector3(1, 1, -1 if _mirror else 1)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m:
				m.cull_mode = BaseMaterial3D.CULL_BACK if _cull else BaseMaterial3D.CULL_DISABLED
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _update_cam() -> void:
	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0)
	_cam.position = Vector3(0, 0, _dist)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= ev.relative.x * 0.4
		_pitch = clampf(_pitch - ev.relative.y * 0.4, -89, 89)
		_update_cam()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.9
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist *= 1.1
		_update_cam()
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_DOWN: _select(_index + 1)
			KEY_UP: _select(_index - 1)
			KEY_C:
				_cull = not _cull
				_load(_files[_index])
			KEY_X:
				_mirror = not _mirror
				_load(_files[_index])


func _run_shots(outdir: String, names: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(outdir)
	_list.visible = false
	for n in names:
		if n.begins_with("cull="):
			_cull = n.ends_with("1")
			continue
		if n.begins_with("mirror="):
			_mirror = n.ends_with("1")
			continue
		_load(n)
		for k in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, n])
	get_tree().quit()
