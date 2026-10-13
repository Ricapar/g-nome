class_name TacticalMap
extends Control
## Briefing map drawn from a mission's layout (R13 preview): rock formations become shaded
## terrain with contour lines, plus waypoints, the player start and hostile units.
## Data: res://_import/data (gitignored); draws an empty map if it is missing.
## Orientation: game +x to the right, game -z up (the 1-1 start faces -z, see analysis.md).

const DATA := "res://_import/data/"
const SHADER := preload("res://ui/shaders/tactical_map.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")
const GREEN := Color(0.35, 1.0, 0.5)
const YELLOW := Color(1.0, 0.82, 0.12)
const ROCKS := [250, 252, 253]
const MASK_SIZE := 384

@export var mission_code := "1-1"

var _bounds := Rect2(-10000, -10000, 20000, 20000) # game x, z
var _waypoints: Array[Vector2] = []
var _hostiles: Array[Vector2] = []
var _start := Vector2.ZERO
var _start_heading := 0.0
var _terrain := ColorRect.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise", NOISE)
	_terrain.material = mat
	_terrain.mouse_filter = MOUSE_FILTER_IGNORE
	_terrain.show_behind_parent = true # markers (_draw) go on top
	add_child(_terrain, false, INTERNAL_MODE_FRONT)
	resized.connect(_fit)
	_load()
	_fit()


func _json(name: String) -> Variant:
	var p := DATA + name
	return JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null


func _load() -> void:
	var missions = _json("missions.json")
	var layouts = _json("layouts.json")
	var units_list = _json("units.json")
	if missions == null or layouts == null or units_list == null:
		return
	var units := {}
	for u in units_list:
		units[int(u["row"])] = u
	var lay: Array = []
	for m in missions:
		if m["code"] == mission_code:
			lay = layouts.get(str(int(m["layout_array"])), [])
	if lay.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in lay:
		var p := Vector2(e["x"], e["z"])
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	var half := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 + 1500.0
	_bounds = Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
	# terrain mask: a soft blob per rock formation / scenery piece
	var img := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RF)
	var acc := PackedFloat32Array()
	acc.resize(MASK_SIZE * MASK_SIZE)
	var player_faction := ""
	var first := true
	for e in lay:
		var u: Dictionary = units.get(int(e["unit_row"]), {})
		var cat := int(u.get("category", 0))
		var p := Vector2(e["x"], e["z"])
		if first:
			_start = p
			_start_heading = float(e["heading"]) / 100.0
			player_faction = str(u.get("faction", ""))
			first = false
			continue
		if cat in ROCKS:
			_splat(acc, p, 900.0 if cat == 250 else 600.0)
		elif cat == 500:
			_waypoints.append(p)
		elif cat >= 141 and cat <= 182 and str(u.get("faction", "")) != player_faction:
			_hostiles.append(p)
	for i in acc.size():
		img.set_pixel(i % MASK_SIZE, i / MASK_SIZE, Color(minf(acc[i], 1.5), 0, 0))
	(_terrain.material as ShaderMaterial).set_shader_parameter("height", ImageTexture.create_from_image(img))
	queue_redraw()


func _splat(acc: PackedFloat32Array, p: Vector2, radius: float) -> void:
	var c := _to_mask(p)
	var r := radius / _bounds.size.x * MASK_SIZE
	var r2 := int(ceil(r * 2.5))
	for y in range(maxi(int(c.y) - r2, 0), mini(int(c.y) + r2, MASK_SIZE)):
		for x in range(maxi(int(c.x) - r2, 0), mini(int(c.x) + r2, MASK_SIZE)):
			var d2 := (Vector2(x, y) - c).length_squared() / (r * r)
			acc[y * MASK_SIZE + x] += exp(-d2) * 0.55


func _to_mask(p: Vector2) -> Vector2:
	return (p - _bounds.position) / _bounds.size * MASK_SIZE


## The map is square and covers the pane (centred, clipped at the long sides).
func _fit() -> void:
	var side := maxf(size.x, size.y)
	_terrain.position = (size - Vector2(side, side)) * 0.5
	_terrain.size = Vector2(side, side)


## Game (x, z) to local pixels: x to the right, -z up.
func _to_local(p: Vector2) -> Vector2:
	var t := (p - _bounds.position) / _bounds.size
	return _terrain.position + t * _terrain.size.x


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	# each marker twice: a dark halo first so it reads on bright terrain and cloud
	for pass_i in 2:
		var halo := pass_i == 0
		var green := Color(0, 0, 0, 0.55) if halo else GREEN
		var yellow := Color(0, 0, 0, 0.55) if halo else YELLOW
		var wide := 3.0 if halo else 0.0
		for i in _waypoints.size():
			var p := _to_local(_waypoints[i])
			draw_arc(p, s * 0.55, 0, TAU, 24, green, 2.0 + wide, true)
			draw_circle(p, s * 0.18 + wide * 0.5, green)
		for h in _hostiles:
			var p := _to_local(h)
			var k := s * 0.5
			draw_line(p + Vector2(-k, -k), p + Vector2(k, k), yellow, 3.5 + wide, true)
			draw_line(p + Vector2(-k, k), p + Vector2(k, -k), yellow, 3.5 + wide, true)
		# player start: a double chevron along the start heading
		var at := _to_local(_start)
		var fwd := Vector2(sin(deg_to_rad(_start_heading)), cos(deg_to_rad(_start_heading))) # local y grows with game z
		var side := Vector2(-fwd.y, fwd.x)
		for k in 2:
			var tip := at + fwd * s * (0.5 + 0.6 * k)
			var pts := PackedVector2Array([tip, tip - fwd * s * 0.7 + side * s * 0.6,
				tip - fwd * s * 0.4, tip - fwd * s * 0.7 - side * s * 0.6])
			if halo:
				pts.append(pts[0])
				draw_polyline(pts, green, 4.0, true)
			else:
				draw_colored_polygon(pts, green)


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()
