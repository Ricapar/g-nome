@tool
class_name PaneFrame
extends Control
## A content pane on the screen: thin phosphor border with brighter corner ticks.

@export var color := Color(0.25, 0.85, 0.4):
	set(v): color = v; queue_redraw()
@export var tick := 14.0:
	set(v): tick = v; queue_redraw()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(color, 0.75), false, 1.5)
	var c := color * 1.3
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := corner * size
		var dx := Vector2(tick if corner.x == 0 else -tick, 0)
		var dy := Vector2(0, tick if corner.y == 0 else -tick)
		draw_polyline(PackedVector2Array([p + dx, p, p + dy]), c, 3.0)
