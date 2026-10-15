extends Control
## Main menu (R11/R12): the 3D machinery frame (MenuFrame) with the 2D menu layer pinned to its
## anchors. Menu structure follows the original (array 8611, docs/backlog/R10-menu-decode.md);
## actions are not wired yet. Target look: remake/art/ui/reference/target_briefing.png.
## Screenshot mode: godot --path remake/game res://ui/screens/main_menu.tscn -- \
##   --shots <outdir> [--size <w>x<h>] [--select <key>[,<left>[,<right>]]] [--hover <left>]
##   [--focus <node>]  (keyboard focus on e.g. Key1 or SlotR0, as if a key had been pressed)
##   [--press <key>]   (capture key <key> mid-travel, 40 ms into its press)

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

@onready var _frame: MenuFrame = $FrameViewport
@onready var _frame_view: TextureRect = $FrameView
@onready var _status: StatusBar = %Status
@onready var _screen: Control = %Screen
@onready var _overlay: ColorRect = %ScreenOverlay
@onready var _glass: ColorRect = %Glass
@onready var _idle_page: Control = %IdlePage
@onready var _briefing_page: Control = %BriefingPage
@onready var _left: Array[GlassButton] = [%SlotL0, %SlotL1, %SlotL2, %SlotL3]
@onready var _right: Array[GlassButton] = [%SlotR0, %SlotR1, %SlotR2, %SlotR3]
@onready var _keys: Array[KeyButton] = [%Key0, %Key1, %Key2, %Key3, %Key4]

var _key_index := -1
var _left_index := -1
var _status_base := ""
var _sounds: UiSounds = UiSfx
var _pad := false # last input came from keyboard/gamepad: focus follows selections


func _ready() -> void:
	# HDR 2D lets phosphor text and lamps bloom; per viewport so the 3D viewers are unaffected.
	get_viewport().use_hdr_2d = true
	_sounds.play(&"ambience") # original menu loop (silent without the import)
	_frame_view.texture = _frame.get_texture()
	var key_group := ButtonGroup.new()
	for i in _keys.size():
		var k := _keys[i]
		k.text = MENU[i][0]
		k.status_text = MENU[i][1]
		k.button_group = key_group
		k.pressed.connect(_on_key.bind(i))
		_hook_status(k)
	for column in [_left, _right]:
		var g := ButtonGroup.new()
		for b: GlassButton in column:
			b.button_group = g
			b.set_entry("")
			_hook_status(b)
	for i in 4:
		_left[i].pressed.connect(_on_slot.bind(_select_left, i))
		_right[i].pressed.connect(_on_slot.bind(_select_right, i))
	_wire_focus()
	_overlay.resized.connect(func(): _overlay.material.set_shader_parameter("size", _overlay.size))
	_glass.resized.connect(func(): _glass.material.set_shader_parameter("size", _glass.size))
	_show_page(_idle_page)
	_set_status("")
	_power_on()
	var args := OS.get_cmdline_user_args()
	if args.has("--shots"):
		_run_shots(args)


func _process(_dt: float) -> void:
	_layout()


## Keep the frame rendering at physical resolution and pin each control to its anchor.
func _layout() -> void:
	var px := get_window().size
	if _frame.size != px:
		_frame.size = px
	var k := size / Vector2(px)
	for i in 4:
		_place(_left[i], "slot_L%d" % i, k)
		_place(_right[i], "slot_R%d" % i, k)
	for i in _keys.size():
		_place(_keys[i], "key_%d" % i, k)
		# the splayed key faces are trapezoids on screen; the outline follows them
		var q := _frame.anchor_quad("key_%d" % i)
		for j in q.size():
			q[j] = q[j] * k - _keys[i].position
		_keys[i].face = q
	_place(_status, "status", k)
	_place(_screen, "screen", k)


func _place(c: Control, anchor: String, k: Vector2) -> void:
	var r := _frame.anchor_rect(anchor)
	c.position = r.position * k
	c.size = r.size * k


func _hook_status(b: Control) -> void:
	b.mouse_entered.connect(func(): _hover_status(b.status_text); _sounds.play(&"hover"))
	b.focus_entered.connect(func(): _hover_status(b.status_text); if _pad: _sounds.play(&"hover"))
	b.mouse_exited.connect(_hover_status.bind(""))


## Keyboard / gamepad (ui_* actions): arrows or d-pad move between keys and slot columns,
## accept presses, cancel steps back right column -> left column -> keys. Focus is only shown
## while that input is in use; the mouse hides it again.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		if _pad:
			_pad = false
			var f := get_viewport().gui_get_focus_owner()
			if f:
				f.release_focus()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if not event.is_pressed():
		return
	_pad = true
	if get_viewport().gui_get_focus_owner() == null and _is_nav(event):
		# first key press: land on the current selection instead of moving
		(_keys[_key_index] if _key_index >= 0 else _keys[0]).grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _is_nav(e: InputEvent) -> bool:
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_focus_next", "ui_focus_prev"]:
		if e.is_action(a):
			return true
	return false


func _back() -> void:
	# typed arrays reject lookups of other types, so check the class first
	var f := get_viewport().gui_get_focus_owner() as GlassButton
	# the original has no back sound: stepping back re-selects, so it plays that selection's sound
	if f and _right.has(f) and _left_index >= 0:
		_left[_left_index].grab_focus()
		_sounds.play(&"slot")
	elif f and _key_index >= 0:
		_keys[_key_index].grab_focus()
		_sounds.play(&"key")


func _on_key(i: int) -> void:
	_sounds.play(&"key")
	_frame.press_key(i)
	_select_key(i)
	if _pad:
		_focus_first(_left)


func _on_slot(select: Callable, i: int) -> void:
	_sounds.play(&"slot")
	select.call(i)
	if _pad and select == _select_left:
		_focus_first(_right)


func _focus_first(column: Array[GlassButton]) -> void:
	for b in column:
		if not b.disabled:
			b.grab_focus()
			return


## Explicit neighbours, so navigation follows the machine's layout rather than screen geometry:
## keys in a row; each column top to bottom, falling through to the selected key at the bottom.
func _wire_focus() -> void:
	var key_target: Button = _keys[_key_index] if _key_index >= 0 else _keys[0]
	for i in _keys.size():
		var k := _keys[i]
		k.focus_neighbor_left = k.get_path_to(_keys[maxi(i - 1, 0)])
		k.focus_neighbor_right = k.get_path_to(_keys[mini(i + 1, _keys.size() - 1)])
		var up := _first_enabled(_left, _left_index)
		k.focus_neighbor_top = k.get_path_to(up if up else k)
		k.focus_neighbor_bottom = k.get_path_to(k)
	for col in [_left, _right]:
		var other: Array[GlassButton] = _right if col == _left else _left
		var other_sel := _left_index if col == _right else -1
		var enabled: Array[GlassButton] = []
		for b: GlassButton in col:
			if not b.disabled:
				enabled.append(b)
		for j in enabled.size():
			var b := enabled[j]
			b.focus_neighbor_top = b.get_path_to(enabled[maxi(j - 1, 0)])
			b.focus_neighbor_bottom = b.get_path_to(enabled[j + 1] if j + 1 < enabled.size() else key_target)
			var side := _first_enabled(other, other_sel)
			var to_side: NodePath = b.get_path_to(side if side else b)
			if col == _left:
				b.focus_neighbor_right = to_side
				b.focus_neighbor_left = b.get_path_to(b)
			else:
				b.focus_neighbor_left = to_side
				b.focus_neighbor_right = b.get_path_to(b)


func _first_enabled(column: Array[GlassButton], prefer: int) -> GlassButton:
	if prefer >= 0 and not column[prefer].disabled:
		return column[prefer]
	for b in column:
		if not b.disabled:
			return b
	return null


func _select_key(i: int) -> void:
	_key_index = i
	_left_index = -1
	_keys[i].button_pressed = true
	for j in _keys.size():
		_frame.set_led(j, j == i)
	_fill(_left, MENU[i][2])
	_fill(_right, [])
	_status_base = MENU[i][1]
	_set_status(_status_base)
	_show_page(_idle_page)
	_wire_focus()


func _select_left(j: int) -> void:
	_left_index = j
	_left[j].button_pressed = true
	var item: Array = MENU[_key_index][2][j]
	_status_base = item[1]
	_set_status(_status_base)
	_fill(_right, item[2] if item.size() > 2 else [])
	_glow("L", j)
	_wire_focus()


func _select_right(k: int) -> void:
	_right[k].button_pressed = true
	_status_base = _right[k].status_text
	_set_status(_status_base)
	_glow("R", k)
	if _right[k].text == "CAMPAIGN":
		_show_page(_briefing_page)


func _fill(column: Array[GlassButton], entries: Array) -> void:
	for i in column.size():
		var e: Array = entries[i] if i < entries.size() else ["", ""]
		column[i].set_entry(e[0], e[1])
	var pressed := column[0].button_group.get_pressed_button()
	if pressed:
		pressed.button_pressed = false
	_glow("L" if column == _left else "R", -1)


func _glow(side: String, index: int) -> void:
	for i in 4:
		_frame.set_slot_glow(side, i, i == index)


func _show_page(page: Control) -> void:
	for p in [_idle_page, _briefing_page]:
		p.visible = p == page


func _hover_status(text: String) -> void:
	_set_status(text if text != "" else _status_base)


func _set_status(text: String) -> void:
	_status.text = text


func _power_on() -> void:
	var m: ShaderMaterial = _overlay.material
	m.set_shader_parameter("power", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("power", v), 0.0, 1.0, 0.6).set_delay(0.3)


func _arg(args: PackedStringArray, name: String, default: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default


func _run_shots(args: PackedStringArray) -> void:
	var outdir := _arg(args, "--shots", "")
	var size_arg := _arg(args, "--size", "")
	if size_arg != "":
		var wh := size_arg.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	await get_tree().process_frame
	var sel := _arg(args, "--select", "")
	if sel != "":
		var ix := sel.split(",")
		_select_key(int(ix[0]))
		if ix.size() > 1:
			_select_left(int(ix[1]))
		if ix.size() > 2:
			_select_right(int(ix[2]))
	var hover := _arg(args, "--hover", "")
	if hover != "":
		_left[int(hover)].grab_focus()
	var focus := _arg(args, "--focus", "")
	if focus != "":
		_pad = true
		(get_node("%" + focus) as Control).grab_focus()
	await get_tree().create_timer(1.4).timeout
	var press := _arg(args, "--press", "")
	if press != "":
		_frame.press_key(int(press))
		await get_tree().create_timer(0.04).timeout
	else:
		await get_tree().create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(outdir)
	var img := get_viewport().get_texture().get_image()
	print("shot image format: ", img.get_format())
	if get_viewport().use_hdr_2d:
		# HDR 2D viewports store linear colour in a float image; the window shows sRGB
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	img.save_png("%s/main_menu_%dx%d%s.png" % [outdir, img.get_width(), img.get_height(),
		("_" + sel.replace(",", "-")) if sel != "" else ""])
	get_tree().quit()
