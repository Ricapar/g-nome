extends Control
## Main menu style frame (R11/R12): the original's arrangement rebuilt with the UI kit.
## Menu structure follows the original (array 8611, see docs/backlog/R10-menu-decode.md);
## actions are not wired yet.
## Screenshot mode: godot --path remake/game res://ui/screens/main_menu.tscn -- \
##   --shots <outdir> [--size <w>x<h>] [--select <bar>[,<left>[,<right>]]] [--hover <bar>]

const _FACTIONS := [["DARKEN", "Of the Darken"], ["HUMAN", "Of the Humans"], ["MERC", "Of the Mercs"], ["SCORP", "Of the Scorps"]]
# [label, status text, children]. Status texts not yet seen in the original are placeholders
# until R10 extracts the real ones.
const MENU := [
	["GAME", "Start a Game", [
		["NEW", "Start a New Game", [
			["CAMPAIGN", "Begin at the Beginning"], ["TRAINING", "Learn to Pilot a HAWC"],
			["MISSION", "Play a Single Mission"]]],
		["LOAD", "Load a Saved Game"], ["SAVE", "Save the Current Game"], ["CREDITS", "Meet the Team"]]],
	["NETWORK", "Start a Multi-Player Game", [
		["HOST", "Host a Network Game"], ["JOIN", "Join a Network Game"], ["PROTOCOL", "Choose a Connection"]]],
	["LAB", "View HAWCs and Installations", [
		["VEHICLES", "Review Vehicles", _FACTIONS], ["STRUCTURES", "Review Structures", _FACTIONS],
		["PERSONNEL", "Review Personnel", _FACTIONS], ["WEAPONS", "Review Weapons", _FACTIONS]]],
	["OPTIONS", "Change Game Options", [
		["INTERFACE", "Configure Controls"], ["DIFFICULTY", "Adjust Difficulty"],
		["SOUND", "Adjust Sound Parameters"], ["DETAIL", "Adjust Graphic Parameters"]]],
	["EXIT", "Leave G-Nome", []],
]

@onready var _left: Pillar = %LeftPillar
@onready var _right: Pillar = %RightPillar
@onready var _status: Label = %Status
@onready var _bar: HBoxContainer = %BarButtons
@onready var _overlay: ColorRect = %ScreenOverlay

var _bar_index := -1
var _left_index := -1
var _status_base := ""


func _ready() -> void:
	# HDR 2D lets phosphor text and LEDs bloom (colours > 1.0 in the theme). It's enabled per
	# viewport so the 3D viewers keep their plain colour pipeline.
	get_viewport().use_hdr_2d = true
	var group := ButtonGroup.new()
	for i in MENU.size():
		var b := BarButton.new()
		b.text = MENU[i][0]
		b.status_text = MENU[i][1]
		b.button_group = group
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(_select_bar.bind(i))
		b.mouse_entered.connect(_hover_status.bind(MENU[i][1]))
		b.focus_entered.connect(_hover_status.bind(MENU[i][1]))
		b.mouse_exited.connect(_hover_status.bind(""))
		_bar.add_child(b)
	_left.slot_pressed.connect(_select_left)
	_right.slot_pressed.connect(_select_right)
	_left.slot_hovered.connect(func(i): _hover_status(_left.slots[i].status_text))
	_right.slot_hovered.connect(func(i): _hover_status(_right.slots[i].status_text))
	for p in [_left, _right]:
		for s in p.slots:
			s.mouse_exited.connect(_hover_status.bind(""))
	_overlay.resized.connect(func(): _overlay.material.set_shader_parameter("size", _overlay.size))
	_overlay.material.set_shader_parameter("size", _overlay.size)
	_set_status("")
	_power_on()
	var args := OS.get_cmdline_user_args()
	if args.has("--shots"):
		_run_shots(args)


func _select_bar(i: int) -> void:
	_bar_index = i
	_left_index = -1
	_bar.get_child(i).button_pressed = true
	var items: Array = MENU[i][2]
	_left.set_entries(items.map(func(e): return [e[0], e[1]]))
	_right.set_entries([])
	_status_base = MENU[i][1]
	_set_status(_status_base)


func _select_left(j: int) -> void:
	_left_index = j
	_left.select(j)
	var item: Array = MENU[_bar_index][2][j]
	_status_base = item[1]
	_set_status(_status_base)
	var sub: Array = item[2] if item.size() > 2 else []
	_right.set_entries(sub.map(func(e): return [e[0], e[1]]))


func _select_right(k: int) -> void:
	_right.select(k)
	_status_base = _right.slots[k].status_text
	_set_status(_status_base)


func _hover_status(text: String) -> void:
	_set_status(text if text != "" else _status_base)


func _set_status(text: String) -> void:
	_status.text = text


func _power_on() -> void:
	var m: ShaderMaterial = _overlay.material
	m.set_shader_parameter("power", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("power", v), 0.0, 1.0, 0.6).set_delay(0.2)


func _arg(args: PackedStringArray, name: String, default: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default


func _run_shots(args: PackedStringArray) -> void:
	var outdir := _arg(args, "--shots", "")
	var size_arg := _arg(args, "--size", "")
	if size_arg != "":
		var wh := size_arg.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	var sel := _arg(args, "--select", "")
	if sel != "":
		var ix := sel.split(",")
		_select_bar(int(ix[0]))
		if ix.size() > 1:
			_select_left(int(ix[1]))
		if ix.size() > 2:
			_select_right(int(ix[2]))
	var hover := _arg(args, "--hover", "")
	if hover != "":
		_left.slots[int(hover)].grab_focus()
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(outdir)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/main_menu_%dx%d%s.png" % [outdir, img.get_width(), img.get_height(),
		("_" + sel.replace(",", "-")) if sel != "" else ""])
	get_tree().quit()
