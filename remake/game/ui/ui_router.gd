extends Node
## Screen stack, transitions, dialogs and the back action (autoload "UiRouter").
##
##   UiRouter.push(scene_or_path, setup := Callable())  -> the new screen
##   UiRouter.pop() / UiRouter.replace(scene_or_path) / UiRouter.back() -> bool
##   var i := await UiRouter.confirm("QUIT G-NOME?", "body", ["QUIT", "CANCEL"])
##   await UiRouter.cover("LOADING"); ...; await UiRouter.reveal()
##
## The scene the game started with (the main menu) is the bottom of the stack. Pushed screens
## go into a layer above it; the screen below is hidden and stops processing until it is on
## top again. A screen can handle back itself with `func ui_back() -> bool` (true = handled).
## ui_cancel that nothing else used goes to back(). `using_pointer` says whether the last UI
## input came from the mouse; screens use it to grab focus hidden (no ring) or visible.

signal screen_changed(screen: Node)

const LAYER := 64

var using_pointer := true
var busy := false

var _layer := CanvasLayer.new()
var _host := Control.new()
var _dialogs := Control.new()
var _overlay := TransitionOverlay.new()
var _stack: Array[Node] = []


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_layer.layer = LAYER
	_layer.name = "UiRouterLayer"
	for c: Control in [_host, _dialogs]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(c)
	_layer.add_child(_overlay)
	_raise.call_deferred() # the root is still busy setting up during autoload _ready


## Watch (never consume) input to know whether the pointer or keys/pad are in use.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_pointer = true
	elif event is InputEventKey or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pointer = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and back():
		get_viewport().set_input_as_handled()


func top() -> Node:
	return _stack.back() if not _stack.is_empty() else get_tree().current_scene


func depth() -> int:
	return _stack.size()


func push(scene: Variant, setup := Callable()) -> Node:
	if busy:
		return null
	busy = true
	await cover()
	var node := _instance(scene)
	if setup.is_valid():
		setup.call(node)
	_set_active(top(), false)
	_stack.append(node)
	_host.add_child(node)
	await reveal()
	busy = false
	screen_changed.emit(node)
	return node


func pop() -> void:
	if busy or _stack.is_empty():
		return
	busy = true
	await cover()
	_stack.pop_back().queue_free()
	_set_active(top(), true)
	await reveal()
	busy = false
	screen_changed.emit(top())


func replace(scene: Variant, setup := Callable()) -> Node:
	if busy:
		return null
	busy = true
	await cover()
	if not _stack.is_empty():
		_stack.pop_back().queue_free()
	var node := _instance(scene)
	if setup.is_valid():
		setup.call(node)
	_set_active(top(), false)
	_stack.append(node)
	_host.add_child(node)
	await reveal()
	busy = false
	screen_changed.emit(node)
	return node


## Close the open dialog, or let the top screen handle back, or pop it. False when there is
## nothing to go back to (the main menu decides what that means, e.g. the quit prompt).
func back() -> bool:
	if busy:
		return true
	var d := _open_dialog()
	if d:
		d.cancel()
		return true
	var t := top()
	if t and t.has_method(&"ui_back") and t.ui_back():
		return true
	if not _stack.is_empty():
		if has_node(^"/root/UiSfx"):
			UiSfx.play(&"back")
		pop()
		return true
	return false


## Modal question; returns the index of the chosen button, or `cancel_index` on cancel
## (default: the last button).
func confirm(title: String, body: String, labels := PackedStringArray(["OK"]), default_index := 0, cancel_index := -1) -> int:
	var d := ScreenDialog.new()
	_dialogs.add_child(d)
	_raise()
	var focus := get_viewport().gui_get_focus_owner()
	d.open(title, body, labels, default_index, cancel_index)
	var i: int = await d.closed
	d.queue_free()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus(using_pointer)
	return i


func cover(loading_text := "") -> void:
	_raise()
	await _overlay.cover()
	if loading_text != "":
		_overlay.show_loading(loading_text)


func reveal() -> void:
	await _overlay.reveal()


func _open_dialog() -> ScreenDialog:
	for c in _dialogs.get_children():
		if c is ScreenDialog and not c.is_queued_for_deletion():
			return c
	return null


## Keep the layer last under the root: input goes to the last node first, so dialogs and the
## overlay see it before the screens do.
func _raise() -> void:
	var root := get_tree().root
	if _layer.get_parent() != root:
		root.add_child(_layer)
	root.move_child(_layer, -1)


func _instance(scene: Variant) -> Node:
	if scene is Node:
		return scene
	var packed: PackedScene = load(scene) if scene is String else scene
	return packed.instantiate()


func _set_active(n: Node, on: bool) -> void:
	if n == null:
		return
	if n is CanvasItem:
		n.visible = on
	n.process_mode = PROCESS_MODE_INHERIT if on else PROCESS_MODE_DISABLED
