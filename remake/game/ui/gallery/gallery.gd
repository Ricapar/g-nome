extends Control
## UI kit gallery (R11): every component of the kit in its states, on the screen glass, over
## three pages (CONTROLS, DATA, STAGES). All controls are live; the state samples start in the
## state their caption names. Switch pages with the tabs, PgUp/PgDn or LB/RB.
##
## Run it from the editor (F6), or:
##   godot --path remake/game res://ui/gallery/gallery.tscn -- --shots <outdir> [--size WxH]
##       [--page N|all] [--dialog] [--navtest]
## Shots are saved as gallery_<page>_<name>_<w>x<h>.png. Every run in this mode also prints a
## layout AUDIT (content larger than the screen, controls off screen, clipped labels).
## --navtest walks the arrow/d-pad focus graph from the page's tab and prints which focusable
## controls it can't reach. --dialog adds a shot with the router's modal dialog open.
## --padtest injects gamepad button events (d-pad, A, B, RB) and checks focus, dialog, back
## and page switching react to them through the InputMap.

const GLASS := preload("res://ui/shaders/screen_glass.gdshader")
const SCREEN := preload("res://ui/shaders/screen.gdshader")
const NOISE := preload("res://ui/materials/grime_noise.tres")
const ARROW_L := preload("res://ui/icons/arrow_left.svg")
const ARROW_R := preload("res://ui/icons/arrow_right.svg")
const PAGES := ["CONTROLS", "DATA", "STAGES"]

var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _page := -1
var _margin: SafeArea
var _status: StatusBar
var _result: Label
var _power: ShaderMaterial


func _ready() -> void:
	get_viewport().use_hdr_2d = true
	_build()
	_show_page(0, false)
	_status.watch(self)
	var args := OS.get_cmdline_user_args()
	if args.has("--shots") or args.has("--navtest"):
		_run_tests(args)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_page_next"):
		_show_page((_page + 1) % PAGES.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_prev"):
		_show_page((_page + PAGES.size() - 1) % PAGES.size())
		get_viewport().set_input_as_handled()


# --- layout -------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = GLASS
	mat.set_shader_parameter("noise", NOISE)
	mat.set_shader_parameter("cut", Vector2(0.025, 0.015))
	bg.material = mat
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.resized.connect(func(): mat.set_shader_parameter("size", bg.size))
	add_child(bg)

	_margin = SafeArea.new() # content stays within 16:9 on ultrawide; the glass reaches the edges
	add_child(_margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	_margin.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 22)
	v.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"ScreenTitle"
	title.text = "UI KIT"
	head.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"SectionLabel"
	sub.text = "R11 · COMPONENT GALLERY"
	sub.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(sub)
	_result = Label.new()
	_result.theme_type_variation = &"Readout"
	_result.text = "> READY"
	_result.size_flags_horizontal = SIZE_EXPAND_FILL
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result.size_flags_vertical = SIZE_SHRINK_CENTER
	_result.clip_text = true
	head.add_child(_result)
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var t := _screen_button(PAGES[i], "Show the %s page (PgUp/PgDn, LB/RB)" % PAGES[i])
		t.toggle_mode = true
		t.button_group = group
		t.size_flags_vertical = SIZE_SHRINK_CENTER
		t.pressed.connect(_show_page.bind(i))
		head.add_child(t)
		_tabs.append(t)
	v.add_child(HSeparator.new())

	var stack := Control.new()
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(stack)
	for builder: Callable in [_page_controls, _page_data, _page_stages]:
		var page := MarginContainer.new()
		page.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		page.add_theme_constant_override(&"margin_top", 8)
		stack.add_child(page)
		builder.call(page)
		_pages.append(page)

	_status = StatusBar.new()
	_status.custom_minimum_size.y = 46
	_status.base_text = "Hover or focus a control to see its help line here"
	v.add_child(_status)


func _column(parent: Control, min_w := 0.0, expand := true) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override(&"separation", 26)
	c.custom_minimum_size.x = min_w
	if expand:
		c.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


func _section(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	parent.add_child(box)
	var l := Label.new()
	l.theme_type_variation = &"SectionLabel"
	l.text = "// " + title
	box.add_child(l)
	return box


## Adds `c` with a caption under it; returns `c`.
func _sample(parent: Control, c: Control, caption: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	parent.add_child(v)
	v.add_child(c)
	var l := Label.new()
	l.theme_type_variation = &"Caption"
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return c


func _screen_button(text: String, status := "", icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ScreenButton"
	b.text = text
	b.icon = icon
	if status != "":
		b.set_meta(&"status_text", status)
	UiSfx.bind(b, &"toggle")
	return b


## Show a theme-styled button in a fixed state (hover/focus can't be forced in Godot).
func _preview(b: Button, state: String) -> void:
	match state:
		"HOVER":
			b.add_theme_stylebox_override(&"normal", b.get_theme_stylebox(&"hover"))
			b.add_theme_color_override(&"font_color", b.get_theme_color(&"font_hover_color"))
			b.add_theme_color_override(&"icon_normal_color", b.get_theme_color(&"icon_hover_color"))
		"FOCUS":
			var ring := Panel.new()
			ring.mouse_filter = MOUSE_FILTER_IGNORE
			ring.add_theme_stylebox_override(&"panel", b.get_theme_stylebox(&"focus"))
			ring.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			b.add_child(ring)
			b.add_theme_color_override(&"font_color", b.get_theme_color(&"font_focus_color"))
		"PRESSED":
			b.toggle_mode = true
			b.button_pressed = true
		"DISABLED":
			b.disabled = true
			b.focus_mode = FOCUS_NONE


func _say(text: String) -> void:
	_result.text = "> " + text


# --- page 1: controls ---------------------------------------------------------------------

func _page_controls(page: Control) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 56)
	page.add_child(cols)

	var a := _column(cols, 620, false)
	var s := _section(a, "GLASS BUTTON · PILLAR SLOT")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 22)
	grid.add_theme_constant_override(&"v_separation", 12)
	s.add_child(grid)
	for spec in [["", "EMPTY", ""], ["LOAD", "IDLE", ""], ["SAVE", "HOVER / FOCUS", "hover"],
			["NEW", "SELECTED", "pressed"], ["CAMPAIGN", "SELECTED + HOVER", "pressed hover"], ["TRAINING", "LIVE", ""]]:
		var g := GlassButton.new()
		g.custom_minimum_size = Vector2(190, 62)
		_sample(grid, g, spec[1])
		g.set_entry(spec[0], "Glass slot, %s state" % spec[1].to_lower())
		if "pressed" in spec[2]:
			g.button_pressed = true
		if "hover" in spec[2]:
			g.preview_hover = true
		if spec[0] != "":
			UiSfx.bind(g, &"slot")

	s = _section(a, "KEY BUTTON · 2D LAYER (THE KEY ITSELF IS 3D: SEE MAIN MENU)")
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override(&"separation", 22)
	s.add_child(keys)
	for spec in [["GAME", "NORMAL", ""], ["LAB", "HOVER / FOCUS", "hover"], ["OPTIONS", "SELECTED", "pressed"]]:
		var plate := Panel.new()
		plate.custom_minimum_size = Vector2(176, 92)
		plate.add_theme_stylebox_override(&"panel", _key_plate())
		_sample(keys, plate, spec[1])
		var led := ColorRect.new()
		led.color = Color(0.3, 1.0, 0.45) if spec[2] == "pressed" else Color(0.02, 0.025, 0.02)
		led.anchor_left = 0.25
		led.anchor_right = 0.75
		led.offset_top = 14
		led.offset_bottom = 24
		led.mouse_filter = MOUSE_FILTER_IGNORE
		plate.add_child(led)
		var k := KeyButton.new()
		k.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		k.text = spec[0]
		k.status_text = "Bottom-bar key, %s state" % spec[1].to_lower()
		plate.add_child(k)
		if spec[2] == "pressed":
			k.button_pressed = true
		if spec[2] == "hover":
			k.preview_hover = true
		UiSfx.bind(k, &"key")

	s = _section(a, "DIALOG · INLINE PANEL (THE ROUTER'S MODAL USES THE SAME)")
	var panel := ScreenDialog.build_panel("QUIT G-NOME?", "Unsaved progress in the current mission will be lost.",
		PackedStringArray(["QUIT", "CANCEL"]))
	panel.size_flags_horizontal = SIZE_SHRINK_BEGIN
	s.add_child(panel)
	for b: Button in panel.get_meta(&"buttons"):
		# the modal traps focus in its button row; here the panel sits among other controls
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			b.set_focus_neighbor(side, NodePath())
		b.set_meta(&"status_text", "Dialog button")
		b.pressed.connect(_say.bind("inline dialog: " + b.text))
		UiSfx.bind(b, &"toggle")

	var c := _column(cols)
	s = _section(c, "SCREEN BUTTON · STATES")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 18)
	flow.add_theme_constant_override(&"v_separation", 10)
	s.add_child(flow)
	for state in ["NORMAL", "HOVER", "FOCUS", "PRESSED", "DISABLED"]:
		var b := _screen_button("LAUNCH", "Screen button, %s state" % state.to_lower())
		_sample(flow, b, state)
		_preview(b, state)
		b.pressed.connect(_say.bind("LAUNCH pressed"))

	s = _section(c, "ICON BUTTON · SVG ICONS (DPITEXTURE)")
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override(&"separation", 18)
	s.add_child(icons)
	var prev := _screen_button("PREV", "Previous vehicle (Lab)", ARROW_L)
	var next := _screen_button("NEXT", "Next vehicle (Lab)", ARROW_R)
	next.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var only_l := _screen_button("", "Icon only", ARROW_L)
	var only_r := _screen_button("", "Icon only", ARROW_R)
	for b: Button in [prev, next, only_l, only_r]:
		icons.add_child(b)
		b.pressed.connect(_say.bind("icon button: " + (b.text if b.text != "" else "arrow")))
	for b: Button in [only_l, only_r]:
		b.custom_minimum_size.x = 64

	s = _section(c, "CHOICE ROW · TRIANGLE MARKERS (TOGGLE = TWO CHOICES)")
	var diff := _choice(s, "DIFFICULTY", ["EASY", "MEDIUM", "HARD"], 1, "Adjust difficulty")
	var music := _choice(s, "CD MUSIC", ["ON", "OFF"], 0, "Play music during the game")
	var detail := _choice(s, "DETAIL", ["HIGH", "MEDIUM", "LOW"], 0, "Adjust graphic parameters")
	music.buttons[1].preview_hover = true
	detail.disabled = true
	for r in [diff, music]:
		r.changed.connect(func(i): _say("%s = %s" % [r.label, r.options[i]]))

	s = _section(c, "SLIDER ROW")
	_slider(s, "SFX VOLUME", 0, 100, 5, 80, "%d%%", "Sound effects volume")
	_slider(s, "MUSIC VOLUME", 0, 100, 5, 45, "%d%%", "Music volume")
	_slider(s, "MOUSE SPEED", 0.5, 10, 0.5, 3.5, "%.1f", "Mouse sensitivity")
	var dis := _slider(s, "DIALOGUE", 0, 100, 5, 60, "%d%%", "Dialogue volume")
	dis.disabled = true

	s = _section(c, "ROUTER · MODAL DIALOG, SCREEN STACK, LOADING COVER")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	s.add_child(row)
	var open := _screen_button("OPEN DIALOG", "UiRouter.confirm(): a modal question")
	open.pressed.connect(_open_dialog)
	var push := _screen_button("PUSH SCREEN", "UiRouter.push(): open a stub screen; BACK or Escape returns")
	push.pressed.connect(func(): UiRouter.push(StubScreen.make("LOAD GAME",
		"A stub screen pushed by the router. Back, Escape or pad B returns.")))
	var load := _screen_button("LOADING", "UiRouter.cover(\"LOADING\") then reveal()")
	load.pressed.connect(_loading)
	for b in [open, push, load]:
		row.add_child(b)


func _choice(parent: Control, label: String, options: Array, sel: int, status: String) -> ChoiceRow:
	var r := ChoiceRow.new()
	r.label = label
	r.options = PackedStringArray(options)
	r.selected = sel
	r.label_width = 230
	r.status_text = status
	parent.add_child(r)
	return r


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String, status: String) -> SliderRow:
	var r := SliderRow.new()
	r.label = label
	r.min_value = lo
	r.max_value = hi
	r.step = step
	r.format = fmt
	r.value = value
	r.label_width = 230
	r.status_text = status
	parent.add_child(r)
	r.changed.connect(func(v): _say("%s = %s" % [label, fmt % v]))
	return r


func _key_plate() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.27, 0.28, 0.28)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.55, 0.56, 0.56)
	sb.set_corner_radius_all(8)
	sb.corner_detail = 1
	return sb


func _open_dialog() -> void:
	var i := await UiRouter.confirm("ABORT MISSION?", "You will return to the main menu. Progress since the last save is lost.",
		PackedStringArray(["ABORT", "CANCEL"]))
	_say("dialog closed with " + (["ABORT", "CANCEL"][i] if i >= 0 else "cancel"))


func _loading() -> void:
	await UiRouter.cover("LOADING")
	await get_tree().create_timer(1.2).timeout
	await UiRouter.reveal()
	_say("loading cover done")


# --- page 2: data -------------------------------------------------------------------------

func _page_data(page: Control) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 48)
	page.add_child(cols)

	var a := _column(cols, 0, false)
	var s := _section(a, "KEY BINDING ROW · THREE MAPPINGS PER FUNCTION")
	s.add_child(KeyBindRow.make_header("FUNCTION", 200, 160))
	var binds := [
		["FORWARD", [_key(KEY_W), _key(KEY_UP), _joy(JOY_BUTTON_DPAD_UP)]],
		["BACKWARD", [_key(KEY_S), _key(KEY_DOWN), null]],
		["TURN LEFT", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]],
		["FIRE", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]],
		["COMMANDEER", [_key(KEY_E), null, _joy(JOY_BUTTON_Y)]],
		["ZOOM", [_key(KEY_Z), null, null]],
	]
	for spec in binds:
		var r := KeyBindRow.new()
		r.label = spec[0]
		r.label_width = 200
		r.cell_width = 160
		r.status_text = "Press a cell, then a key or button. Escape cancels, Delete clears."
		s.add_child(r)
		for i in 3:
			r.set_event(i, spec[1][i])
		r.rebound.connect(func(slot, ev): _say("%s mapping %d = %s" % [r.label, slot + 1, KeyBindRow.event_text(ev)]))
		if spec[0] == "ZOOM":
			r.preview_capture(1)

	s = _section(a, "PANE FRAME · WITH AND WITHOUT CORNER TICKS")
	var panes := HBoxContainer.new()
	panes.add_theme_constant_override(&"separation", 24)
	s.add_child(panes)
	for tick in [14.0, 0.0]:
		var p := PaneFrame.new()
		p.tick = tick
		p.custom_minimum_size = Vector2(240, 120)
		panes.add_child(p)
		var l := Label.new()
		l.theme_type_variation = &"Caption"
		l.text = "TICK %d" % tick
		l.set_anchors_and_offsets_preset(PRESET_CENTER)
		l.grow_horizontal = GROW_DIRECTION_BOTH
		l.grow_vertical = GROW_DIRECTION_BOTH
		p.add_child(l)

	var b := _column(cols, 460, false)
	s = _section(b, "LIST PICKER · SAVE SLOTS")
	var list := ListPicker.new()
	list.custom_minimum_size = Vector2(460, 432)
	list.status_text = "Select a slot; press it again to load"
	s.add_child(list)
	var items := []
	var names := ["1-1 RENEGADE MERCS", "1-2 SUPPLY LINES", "1-3 THE DEPOT", "1-4 NIGHT RAID", "2-1 SCORP TERRITORY",
		"2-2 CANYON RUN", "2-3 OUTPOST", "2-4 THE PROWLER", "", ""]
	for i in names.size():
		items.append(["SLOT %d  %s" % [i + 1, names[i]] if names[i] != "" else "SLOT %d  EMPTY" % (i + 1),
			"10-%02d %02d:%02d" % [14 - i, 21 - i, 7 * i % 60] if names[i] != "" else ""])
	list.set_items(items)
	list.select(2)
	list.item_selected.connect(func(i): _say("slot %d selected" % (i + 1)))
	list.item_activated.connect(func(i): _say("slot %d activated" % (i + 1)))

	var c := _column(cols)
	s = _section(c, "TYPE")
	var t := HBoxContainer.new()
	t.add_theme_constant_override(&"separation", 14)
	s.add_child(t)
	for spec in [["1-1:", &"ScreenTitleWhite"], ["RENEGADE MERCS", &"ScreenTitle"]]:
		var l := Label.new()
		l.theme_type_variation = spec[1]
		l.text = spec[0]
		l.add_theme_font_size_override(&"font_size", 40)
		t.add_child(l)
	var st := Label.new()
	st.theme_type_variation = &"StatusLabel"
	st.text = "Begin at the Beginning"
	s.add_child(st)
	var body := Label.new()
	body.theme_type_variation = &"BodyText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "Mercenaries hold a Union supply depot. Take the Prowler in, recover the cargo and leave nothing standing."
	s.add_child(body)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override(&"h_separation", 18)
	s.add_child(stats)
	for pair in [["CLASS:", "Assault HAWC"], ["NICKNAME:", "Prowler"], ["MAX SPEED:", "42 kph"], ["ARMOUR:", "1200"]]:
		for j in 2:
			var l := Label.new()
			l.theme_type_variation = &"DataLabel" if j == 0 else &"DataValue"
			l.text = pair[j]
			stats.add_child(l)
	var ro := Label.new()
	ro.theme_type_variation = &"Readout"
	ro.text = "AMMO 0120   X +1024   Z -2048"
	s.add_child(ro)
	for obj in ["Head for waypoint one", "Destroy the merc convoy"]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 18)
		var box := PaneFrame.new()
		box.color = Color(1.0, 0.82, 0.18)
		box.tick = 0.0
		box.custom_minimum_size = Vector2(20, 20)
		box.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(box)
		var l := Label.new()
		l.text = obj
		l.add_theme_color_override(&"font_color", Color(0.94, 0.96, 0.96))
		h.add_child(l)
		s.add_child(h)
	var caps := Label.new()
	caps.theme_type_variation = &"Caption"
	caps.text = "CAPTION · SECTIONLABEL ABOVE · TOOLTIPS USE THE MONO FACE"
	s.add_child(caps)


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	return e


func _joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e


func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


# --- page 3: stages -----------------------------------------------------------------------

func _page_stages(page: Control) -> void:
	var screen := Control.new()
	page.add_child(screen)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.add_theme_constant_override(&"separation", 14)
	screen.add_child(v)
	var t := HBoxContainer.new()
	t.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_theme_constant_override(&"separation", 18)
	v.add_child(t)
	for spec in [["LAB:", &"ScreenTitleWhite"], ["UNION PROWLER HAWC", &"ScreenTitle"]]:
		var l := Label.new()
		l.theme_type_variation = spec[1]
		l.text = spec[0]
		t.add_child(l)
	var h := HBoxContainer.new()
	h.size_flags_vertical = SIZE_EXPAND_FILL
	h.add_theme_constant_override(&"separation", 24)
	v.add_child(h)
	for spec in [[ModelStage, "MODEL STAGE · 3D TURNTABLE IN A HANGAR BAY"], [TacticalMap, "TACTICAL MAP · MISSION 1-1 LAYOUT"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(col)
		var pane := PaneFrame.new()
		pane.tick = 0.0
		pane.size_flags_vertical = SIZE_EXPAND_FILL
		col.add_child(pane)
		var stage: Control = spec[0].new()
		stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		stage.offset_left = 2
		stage.offset_top = 2
		stage.offset_right = -2
		stage.offset_bottom = -2
		pane.add_child(stage)
		var cap := Label.new()
		cap.theme_type_variation = &"Caption"
		cap.text = spec[1]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cap)
	# screen ornaments and the power-on sweep, as on the main menu's centre screen
	var chrome := ScreenChrome.new()
	chrome.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen.add_child(chrome)
	t.resized.connect(func(): chrome.rule_y = (t.size.y + 6.0) / maxf(screen.size.y, 1.0))
	screen.resized.connect(func(): chrome.rule_y = (t.size.y + 6.0) / maxf(screen.size.y, 1.0))
	var overlay := ColorRect.new()
	_power = ShaderMaterial.new()
	_power.shader = SCREEN
	_power.set_shader_parameter("scanline_strength", 0.05)
	_power.set_shader_parameter("cut", Vector2(0.0, 0.0))
	overlay.material = _power
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.resized.connect(func(): _power.set_shader_parameter("size", overlay.size))
	screen.add_child(overlay)


# --- pages --------------------------------------------------------------------------------

func _show_page(i: int, animate := true) -> void:
	if i == _page:
		return
	if animate:
		await UiRouter.cover()
	_page = i
	for j in _pages.size():
		_pages[j].visible = j == i
		_tabs[j].set_pressed_no_signal(j == i)
	if i == 2:
		_power.set_shader_parameter("power", 0.0)
		var tw := create_tween()
		tw.tween_method(func(p): _power.set_shader_parameter("power", p), 0.0, 1.0, 0.6).set_delay(0.2)
	if animate:
		await UiRouter.reveal()


# --- test modes ---------------------------------------------------------------------------

func _arg(args: PackedStringArray, name: String, default: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default


func _run_tests(args: PackedStringArray) -> void:
	var size_arg := _arg(args, "--size", "")
	if size_arg != "":
		var wh := size_arg.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	await get_tree().process_frame
	await get_tree().process_frame
	var outdir := _arg(args, "--shots", "")
	var which := _arg(args, "--page", "all")
	var pages: Array = range(PAGES.size()) if which == "all" else [int(which)]
	for p: int in pages:
		_show_page(p, false)
		await get_tree().create_timer(1.3).timeout
		_audit(p)
		if args.has("--navtest"):
			_navtest(p)
		if outdir != "":
			await _shot(outdir, "gallery_%d_%s" % [p, PAGES[p].to_lower()])
	if args.has("--padtest"):
		await _padtest()
	if args.has("--dialog") and outdir != "":
		_show_page(0, false)
		UiRouter.using_pointer = false
		UiRouter.confirm("ABORT MISSION?", "You will return to the main menu. Progress since the last save is lost.",
			PackedStringArray(["ABORT", "CANCEL"]))
		await get_tree().create_timer(0.5).timeout
		await _shot(outdir, "gallery_dialog")
	get_tree().quit()


func _shot(outdir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(outdir)
	var img := get_viewport().get_texture().get_image()
	if get_viewport().use_hdr_2d:
		# HDR 2D viewports store linear colour in a float image; the window shows sRGB
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	var path := "%s/%s_%dx%d.png" % [outdir, name, img.get_width(), img.get_height()]
	img.save_png(path)
	print("shot ", path)


## Layout check: the content's minimum size fits the screen, every visible control lies on
## screen, and no unwrapped label is narrower than its text.
func _audit(p: int) -> void:
	var view := get_viewport_rect().grow(0.5)
	var problems: Array[String] = []
	var need := _margin.get_combined_minimum_size()
	if need.x > size.x + 0.5 or need.y > size.y + 0.5:
		problems.append("content needs %s, screen is %s" % [need, size])
	var controls: Array[Node] = _pages[p].find_children("*", "Control", true, false)
	controls.append_array(_tabs)
	controls.append(_status)
	controls.append(_result)
	for c: Control in controls:
		if not c.is_visible_in_tree() or _clipped(c):
			continue
		var r := c.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if not view.encloses(r):
			problems.append("%s off screen: %s" % [_name(c), r])
		if c is Label and not c.clip_text and c.autowrap_mode == TextServer.AUTOWRAP_OFF \
				and c.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var w := c.get_minimum_size().x
			if c.size.x + 0.5 < w:
				problems.append("%s clipped: %.0f < %.0f" % [_name(c), c.size.x, w])
	print("AUDIT page %d (%s) window %s canvas %s: %s" % [p, PAGES[p], get_window().size, size,
		"ok" if problems.is_empty() else "%d problems\n  %s" % [problems.size(), "\n  ".join(problems)]])


## Inside a scroll view or a control that clips its children (e.g. the tactical map's
## oversized terrain): parts outside the screen are cut off on purpose.
func _clipped(c: Node) -> bool:
	var n := c.get_parent()
	while n and n != self:
		if n is ScrollContainer or (n is Control and n.clip_contents):
			return true
		n = n.get_parent()
	return false


func _name(c: Node) -> String:
	var label := ""
	if "text" in c and c.text is String and c.text != "":
		label = " '%s'" % c.text
	return "%s%s" % [c.get_class() if c.get_script() == null else c.get_script().get_global_name(), label]


## Breadth-first walk of the arrow/d-pad focus graph from the page's tab, using the engine's
## own neighbour search. Sliders keep left/right for their value, so only up/down leave them.
func _navtest(p: int) -> void:
	var focusable: Array[Control] = []
	var nodes: Array[Node] = _pages[p].find_children("*", "Control", true, false)
	nodes.append_array(_tabs)
	for c: Control in nodes:
		if c.is_visible_in_tree() and c.focus_mode == FOCUS_ALL and not (c is BaseButton and c.disabled):
			focusable.append(c)
	var seen := {_tabs[p]: true}
	var queue: Array[Control] = [_tabs[p]]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			if c is Slider and (side == SIDE_LEFT or side == SIDE_RIGHT):
				continue
			var n := c.find_valid_focus_neighbor(side)
			if n and not seen.has(n):
				seen[n] = true
				queue.append(n)
	var missing := focusable.filter(func(c): return not seen.has(c))
	print("NAVTEST page %d (%s): %d/%d focusable controls reachable with arrows/d-pad%s" % [p, PAGES[p],
		focusable.size() - missing.size(), focusable.size(),
		"" if missing.is_empty() else "; missing: " + ", ".join(missing.map(_name))])


func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _check(results: Array[String], name: String, ok: bool) -> void:
	results.append("%s %s" % ["ok  " if ok else "FAIL", name])


func _padtest() -> void:
	var r: Array[String] = []
	_show_page(0, false)
	_tabs[0].grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var f := get_viewport().gui_get_focus_owner()
	_check(r, "d-pad down moves focus off the tab (now %s)" % (_name(f) if f else "none"), f != null and f != _tabs[0])
	var row := _pages[0].find_children("*", "ChoiceRow", true, false)[0] as ChoiceRow
	row.buttons[2].grab_focus()
	await _pad(JOY_BUTTON_A)
	_check(r, "A presses the focused choice (DIFFICULTY = %s)" % row.options[row.selected], row.selected == 2)
	_check(r, "focus from the pad is visible", row.buttons[2].has_focus(true))
	var result := [-2]
	var ask := func(): result[0] = await UiRouter.confirm("TEST", "Pad test", PackedStringArray(["YES", "NO"]))
	ask.call()
	await get_tree().create_timer(0.3).timeout
	await _pad(JOY_BUTTON_B)
	await get_tree().process_frame
	_check(r, "B cancels the dialog (index %d)" % result[0], result[0] == 1)
	UiRouter.push(StubScreen.make("PAD TEST", ""))
	await get_tree().create_timer(0.8).timeout
	_check(r, "push adds a screen (depth %d)" % UiRouter.depth(), UiRouter.depth() == 1)
	await _pad(JOY_BUTTON_B)
	await get_tree().create_timer(0.8).timeout
	_check(r, "B goes back (depth %d)" % UiRouter.depth(), UiRouter.depth() == 0)
	_check(r, "the gallery is active again", visible and process_mode != PROCESS_MODE_DISABLED)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await get_tree().create_timer(0.8).timeout
	_check(r, "RB switches to the next page (page %d)" % _page, _page == 1)
	print("PADTEST
  " + "
  ".join(r))
